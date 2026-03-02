import Wgpu
import Wgpu.Async
import Glfw
import Wgsl.Syntax

open IO
open Wgpu

set_option linter.unusedVariables false

/--
  Particles: A GPU compute particle system. Particles are simulated in a compute
  shader (gravity + wind + bounce) and rendered as colored points (small quads).
  Tests: compute→render pipeline, storage buffer as vertex source, GPU-only simulation,
  no CPU readback of particle state.
-/

def particleComputeSource : String := !WGSL{
struct Particle {
    pos: vec2f,
    vel: vec2f,
    color: vec4f,
    life: f32,
    _pad: f32,
    _pad2: vec2f,
};

struct SimParams {
    deltaTime: f32,
    time: f32,
    gravity: f32,
    wind: f32,
};

@group(0) @binding(0) var<storage, read_write> particles: array<Particle>;
@group(1) @binding(0) var<uniform> params: SimParams;

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let idx = id.x;
    if (idx >= arrayLength(&particles)) { return; }
    var p = particles[idx];
    p.vel.y += params.gravity * params.deltaTime;
    p.vel.x += params.wind * sin(params.time + f32(idx) * 0.1) * params.deltaTime;
    p.pos += p.vel * params.deltaTime;
    p.life -= params.deltaTime * 0.2;
    if (p.pos.y > 1.0) { p.pos.y = 1.0; p.vel.y = -abs(p.vel.y) * 0.6; }
    if (p.pos.y < -1.0) { p.pos.y = -1.0; p.vel.y = abs(p.vel.y) * 0.6; }
    if (p.pos.x > 1.0) { p.pos.x = 1.0; p.vel.x = -abs(p.vel.x) * 0.6; }
    if (p.pos.x < -1.0) { p.pos.x = -1.0; p.vel.x = abs(p.vel.x) * 0.6; }
    if (p.life <= 0.0) {
        let seed = f32(idx) * 1.618 + params.time;
        p.pos = vec2f(sin(seed * 3.7) * 0.1, -0.8 + sin(seed * 2.3) * 0.1);
        p.vel = vec2f(sin(seed * 5.1) * 0.5, -(0.5 + fract(seed * 1.3) * 1.5));
        p.life = 0.5 + fract(seed * 0.7) * 1.5;
        p.color = vec4f(
            0.5 + fract(seed * 1.1) * 0.5,
            0.3 + fract(seed * 2.3) * 0.4,
            0.2 + fract(seed * 3.7) * 0.3,
            1.0
        );
    }
    particles[idx] = p;
}
}

def particleRenderSource : String := !WGSL{
struct Particle {
    pos: vec2f,
    vel: vec2f,
    color: vec4f,
    life: f32,
    _pad: f32,
    _pad2: vec2f,
};

@group(0) @binding(0) var<storage, read> particles: array<Particle>;

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) color: vec4f,
    @location(1) localUV: vec2f,
};

@vertex
fn vs_main(@builtin(vertex_index) vIdx: u32, @builtin(instance_index) iIdx: u32) -> VertexOutput {
    let p = particles[iIdx];
    var quad = array<vec2f, 6>(
        vec2f(-1.0, -1.0), vec2f(1.0, -1.0), vec2f(1.0, 1.0),
        vec2f(-1.0, -1.0), vec2f(1.0, 1.0), vec2f(-1.0, 1.0) 
    );
    let size = 0.008 * (0.5 + p.life * 0.5);
    let worldPos = p.pos + quad[vIdx] * size;
    var out: VertexOutput;
    out.position = vec4f(worldPos, 0.0, 1.0);
    out.color = vec4f(p.color.rgb * p.life, p.life);
    out.localUV = quad[vIdx];
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4f {
    let dist = length(in.localUV);
    if (dist > 1.0) { discard; }
    let alpha = (1.0 - dist) * in.color.a;
    return vec4f(in.color.rgb, alpha);
}
}

def numParticles : Nat := 4096

def fmod (a b : Float) : Float :=
  a - Float.floor (a / b) * b

def mkInitialParticles : Array Float := Id.run do
  let mut data : Array Float := #[]
  let pi := 3.14159265
  for i in [:numParticles] do
    let fi := i.toFloat
    let angle := 2.0 * pi * fi / numParticles.toFloat
    let speed := 0.5 + fmod (fi * 0.37) 1.5
    -- pos (2), vel (2), color (4), life (1), pad (1), pad2 (2) = 12 floats
    data := data.push (Float.sin angle * 0.1)  -- pos.x
    data := data.push (-0.5)                     -- pos.y
    data := data.push (Float.cos (fi * 0.7) * speed * 0.5) -- vel.x
    data := data.push (-speed)                   -- vel.y (upward)
    -- color
    data := data.push (0.8 + fmod (fi * 0.003) 0.2)
    data := data.push (0.4 + fmod (fi * 0.007) 0.4)
    data := data.push (0.1 + fmod (fi * 0.011) 0.3)
    data := data.push 1.0  -- alpha
    -- life + padding
    data := data.push (0.5 + fmod (fi * 0.0013) 2.0) -- life
    data := data.push 0.0  -- pad
    data := data.push 0.0  -- pad2.x
    data := data.push 0.0  -- pad2.y
  return data

def particles : IO Unit := do
  eprintln "=== Particles (GPU Compute Particle System) ==="

  setLogCallback fun lvl msg => eprintln s!"[{repr lvl}] {msg}"
  let window ← GLFWwindow.mk 640 480 "Particles"

  let desc ← InstanceDescriptor.mk
  let inst ← createInstance desc
  let surface ← getSurface inst window

  let adapter ← inst.requestAdapter surface >>= await!
  let ddesc ← DeviceDescriptor.mk "particles device"
  let device ← adapter.requestDevice ddesc >>= await!
  device.setUncapturedErrorCallback fun code msg => do
    eprintln s!"uncaptured error, code {code}: \"{msg}\""

  let queue ← device.getQueue
  let texture_format ← TextureFormat.get surface adapter
  let surface_config ← SurfaceConfiguration.mk 640 480 device texture_format
  surface.configure surface_config

  -- Particle buffer: 12 floats * 4 bytes * numParticles
  let particleBufSize : UInt32 := (numParticles * 12 * 4).toUInt32
  let pbDesc := BufferDescriptor.mk "particle buffer"
    (BufferUsage.storage.lor BufferUsage.copyDst) particleBufSize false
  let particleBuf ← Buffer.mk device pbDesc

  -- Initialize particle data
  let initData := mkInitialParticles
  let initBytes := floatsToByteArray initData
  queue.writeBuffer particleBuf initBytes
  eprintln s!"Particles: {numParticles}, buffer: {particleBufSize} bytes"

  -- Sim params uniform: deltaTime(f32) + time(f32) + gravity(f32) + wind(f32) = 16 bytes
  let paramSize : UInt32 := 16
  let paramDesc := BufferDescriptor.mk "sim params"
    (BufferUsage.uniform.lor BufferUsage.copyDst) paramSize false
  let paramBuf ← Buffer.mk device paramDesc

  -- Compute pipeline: group(0) = particles storage, group(1) = params uniform
  let compWGSL ← ShaderModuleWGSLDescriptor.mk particleComputeSource
  let compShaderDesc ← ShaderModuleDescriptor.mk compWGSL
  let compShader ← ShaderModule.mk device compShaderDesc

  let particleBGL ← BindGroupLayout.mkStorage device 0 ShaderStageFlags.compute false
  let paramBGL ← BindGroupLayout.mkUniform device 0 ShaderStageFlags.compute paramSize.toUInt64

  let compPL ← PipelineLayout.mk device #[particleBGL, paramBGL]
  let compPipeline ← device.createComputePipeline compShader compPL "main"

  let compParticleBG ← BindGroup.mk device particleBGL 0 particleBuf
  let compParamBG ← BindGroup.mk device paramBGL 0 paramBuf

  -- Render pipeline: uses particle buffer for per-instance data via storage buffer
  let rendWGSL ← ShaderModuleWGSLDescriptor.mk particleRenderSource
  let rendShaderDesc ← ShaderModuleDescriptor.mk rendWGSL
  let rendShader ← ShaderModule.mk device rendShaderDesc

  let rendBGL ← BindGroupLayout.mkStorage device 0 ShaderStageFlags.vertex true
  let rendPL ← PipelineLayout.mk device #[rendBGL]

  let blendState ← BlendState.mk rendShader
  let cts ← ColorTargetState.mk texture_format blendState
  let fragState ← FragmentState.mk rendShader cts

  -- No vertex buffers! We read position data from the storage buffer in the vertex shader.
  let pipeDesc ← RenderPipelineDescriptor.mk rendShader fragState
  let renderPipeline ← RenderPipeline.mkWithLayout device pipeDesc rendPL

  let rendParticleBG ← BindGroup.mk device rendBGL 0 particleBuf

  let clearColor := Color.mk 0.02 0.02 0.04 1.0

  eprintln "Entering render loop (press Q or Escape to quit)..."

  let mut prevTime ← GLFW.getTime
  let mut frameCount : UInt32 := 0

  while not (← window.shouldClose) do
    GLFW.pollEvents

    let esc ← window.getKey GLFW.keyEscape
    let q ← window.getKey GLFW.keyQ
    if esc == GLFW.press || q == GLFW.press then
      window.setShouldClose true
      continue

    let now ← GLFW.getTime
    let dt := if now - prevTime > 0.05 then 0.05 else now - prevTime
    prevTime := now

    -- Upload sim params
    let paramData := floatsToByteArray #[dt, now, 1.5, 0.3]
    queue.writeBuffer paramBuf paramData

    let texture ← surface.getCurrent
    let status ← texture.status
    if (status != .success) then continue
    let targetView ← TextureView.mk texture
    if !(← targetView.is_valid) then continue

    let encoder ← device.createCommandEncoder

    -- Compute pass: simulate particles
    let computePass ← encoder.beginComputePass
    computePass.setPipeline compPipeline
    computePass.setBindGroup 0 compParticleBG
    computePass.setBindGroup 1 compParamBG
    let wgCount := ((numParticles + 63) / 64).toUInt32
    computePass.dispatchWorkgroups wgCount
    computePass.end_

    -- Render pass: draw particles as instanced quads
    let renderPass ← RenderPassEncoder.mkWithColor encoder targetView clearColor
    renderPass.setPipeline renderPipeline
    renderPass.setBindGroup 0 rendParticleBG
    renderPass.draw 6 numParticles.toUInt32 0 0  -- 6 verts per quad, one instance per particle
    renderPass.end

    let command ← encoder.finish
    queue.submit #[command]
    surface.present
    device.poll

    frameCount := frameCount + 1
    if frameCount % 300 == 0 then
      window.setTitle s!"Particles ({numParticles}) - {now.toString}s"

  eprintln s!"Rendered {frameCount} frames"
  particleBuf.destroy
  paramBuf.destroy
  eprintln "=== Done ==="

def main : IO Unit := particles
