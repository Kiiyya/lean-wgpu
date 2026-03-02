import Wgpu
import Wgpu.Async
import Glfw
import Wgsl.Syntax

open IO
open Wgpu

set_option linter.unusedVariables false

/-!
  PostProcessBlur: Multi-pass post-processing example.

  1. Renders spinning colored triangles to an offscreen texture (Pass 1)
  2. Applies horizontal Gaussian blur: offscreen → pingA (Pass 2)
  3. Applies vertical Gaussian blur: pingA → pingB (Pass 3)
  4. Blits the blurred result to the screen (Pass 4)

  Demonstrates: offscreen rendering, multi-pass post-processing,
  texture sampling, fullscreen quads, ping-pong textures.
  Uses @group(0) for texture+sampler, @group(1) for blur uniforms.
-/

def sceneShaderSrc : String := !WGSL{
struct Uniforms { time: f32 };
@group(0) @binding(0) var<uniform> u: Uniforms;
struct VertexOutput { @builtin(position) position: vec4f, @location(0) color: vec3f };
@vertex fn vs_main(@builtin(vertex_index) idx: u32, @builtin(instance_index) inst: u32) -> VertexOutput {
    let angle = u.time * 2.0 + f32(inst) * 2.094;
    let ca = cos(angle); let sa = sin(angle);
    var base = array<vec2f,3>(vec2f(0.0,0.3),vec2f(-0.25,-0.15),vec2f(0.25,-0.15));
    let p = base[idx];
    let rot = vec2f(p.x*ca - p.y*sa, p.x*sa + p.y*ca);
    let off = vec2f(cos(f32(inst)*2.094)*0.4, sin(f32(inst)*2.094)*0.4);
    var out: VertexOutput;
    out.position = vec4f(rot + off, 0.0, 1.0);
    var colors = array<vec3f,3>(vec3f(1.0,0.2,0.2),vec3f(0.2,1.0,0.2),vec3f(0.2,0.2,1.0));
    out.color = colors[inst];
    return out;
}
@fragment fn fs_main(in: VertexOutput) -> @location(0) vec4f { return vec4f(in.color, 1.0); }
}

def blurShaderSrc : String := !WGSL{
@group(0) @binding(0) var input_tex: texture_2d<f32>;
@group(0) @binding(1) var input_samp: sampler;
struct BlurParams { direction: vec2f, texel_size: vec2f };
@group(1) @binding(0) var<uniform> blur: BlurParams;
struct VertexOutput { @builtin(position) position: vec4f, @location(0) uv: vec2f };
@vertex fn vs_main(@builtin(vertex_index) idx: u32) -> VertexOutput {
    var pos = array<vec2f,6>(vec2f(-1,-1),vec2f(1,-1),vec2f(-1,1),vec2f(-1,1),vec2f(1,-1),vec2f(1,1));
    var uv = array<vec2f,6>(vec2f(0,1),vec2f(1,1),vec2f(0,0),vec2f(0,0),vec2f(1,1),vec2f(1,0));
    var out: VertexOutput; out.position = vec4f(pos[idx], 0.0, 1.0); out.uv = uv[idx]; return out;
}
@fragment fn fs_main(in: VertexOutput) -> @location(0) vec4f {
    var w = array<f32,5>(0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);
    let step = blur.direction * blur.texel_size;
    var color = textureSample(input_tex, input_samp, in.uv) * w[0];
    for (var i = 1; i < 5; i++) {
        let off = step * f32(i);
        color += textureSample(input_tex, input_samp, in.uv + off) * w[i];
        color += textureSample(input_tex, input_samp, in.uv - off) * w[i];
    }
    return color;
}
}

def blitShaderSrc : String := !WGSL{
@group(0) @binding(0) var blit_tex: texture_2d<f32>;
@group(0) @binding(1) var blit_samp: sampler;
struct VertexOutput { @builtin(position) position: vec4f, @location(0) uv: vec2f };
@vertex fn vs_main(@builtin(vertex_index) idx: u32) -> VertexOutput {
    var pos = array<vec2f,6>(vec2f(-1,-1),vec2f(1,-1),vec2f(-1,1),vec2f(-1,1),vec2f(1,-1),vec2f(1,1));
    var uv = array<vec2f,6>(vec2f(0,1),vec2f(1,1),vec2f(0,0),vec2f(0,0),vec2f(1,1),vec2f(1,0));
    var out: VertexOutput; out.position = vec4f(pos[idx], 0.0, 1.0); out.uv = uv[idx]; return out;
}
@fragment fn fs_main(in: VertexOutput) -> @location(0) vec4f {
    return textureSample(blit_tex, blit_samp, in.uv);
}
}

def postProcessBlur : IO Unit := do
  eprintln "=== PostProcessBlur (Multi-Pass Gaussian Blur) ==="
  setLogCallback fun lvl msg => eprintln s!"[{repr lvl}] {msg}"

  let width  : UInt32 := 800
  let height : UInt32 := 600

  let window ← GLFWwindow.mk width height "Post-Process Blur"
  let instDesc ← InstanceDescriptor.mk
  let inst ← createInstance instDesc
  let surface ← getSurface inst window
  let adapter ← inst.requestAdapter surface >>= await!
  let ddesc ← DeviceDescriptor.mk "blur device"
  let device ← adapter.requestDevice ddesc >>= await!
  device.setUncapturedErrorCallback fun t m => eprintln s!"[Device Error] type={t} {m}"
  let queue ← device.getQueue
  let surfFormat ← TextureFormat.get surface adapter
  let config ← SurfaceConfiguration.mk width height device surfFormat
  surface.configure config

  let offFmt := TextureFormat.RGBA8Unorm
  let texUsage := TextureUsage.renderAttachment.lor TextureUsage.textureBinding

  -- Offscreen textures for multi-pass
  let sceneTex ← device.createTexture width height offFmt texUsage
  let sceneView ← sceneTex.createView offFmt
  let pingA ← device.createTexture width height offFmt texUsage
  let pingAView ← pingA.createView offFmt
  let pingB ← device.createTexture width height offFmt texUsage
  let pingBView ← pingB.createView offFmt

  let sampler ← device.createSampler

  -- Scene pipeline
  let sceneSm ← ShaderModule.mk device (← ShaderModuleDescriptor.mk (← ShaderModuleWGSLDescriptor.mk sceneShaderSrc))
  let sceneUnifBuf ← Buffer.mk device (BufferDescriptor.mk "time" (BufferUsage.uniform.lor BufferUsage.copyDst) 16 false)
  let sceneUBGL ← BindGroupLayout.mkUniform device 0 ShaderStageFlags.vertex 16
  let sceneUBG ← BindGroup.mk device sceneUBGL 0 sceneUnifBuf 0 16
  let scenePL ← PipelineLayout.mk device #[sceneUBGL]
  let sceneCTS ← ColorTargetState.mk offFmt (← BlendState.mk sceneSm)
  let sceneFS ← FragmentState.mk sceneSm sceneCTS
  let scenePipeDesc ← RenderPipelineDescriptor.mk sceneSm sceneFS
  let scenePipeline ← RenderPipeline.mkWithLayout device scenePipeDesc scenePL

  -- Blur pipeline: group0=texture+sampler, group1=uniform(direction)
  let blurSm ← ShaderModule.mk device (← ShaderModuleDescriptor.mk (← ShaderModuleWGSLDescriptor.mk blurShaderSrc))
  let blurTexLayout ← BindGroupLayout.mkTextureSampler device 0 1 ShaderStageFlags.fragment
  let blurUnifLayout ← BindGroupLayout.mkUniform device 0 ShaderStageFlags.fragment 16
  let blurPL ← PipelineLayout.mk device #[blurTexLayout, blurUnifLayout]
  let blurCTS ← ColorTargetState.mk offFmt (← BlendState.mk blurSm)
  let blurFS ← FragmentState.mk blurSm blurCTS
  let blurPipeDesc ← RenderPipelineDescriptor.mk blurSm blurFS
  let blurPipeline ← RenderPipeline.mkWithLayout device blurPipeDesc blurPL

  let texelW := 1.0 / width.toFloat
  let texelH := 1.0 / height.toFloat

  -- H-blur uniform
  let hDirBuf ← Buffer.mk device (BufferDescriptor.mk "hdir" (BufferUsage.uniform.lor BufferUsage.copyDst) 16 false)
  queue.writeBuffer hDirBuf (floatsToByteArray #[1.0, 0.0, texelW, texelH])
  let hDirBG ← BindGroup.mk device blurUnifLayout 0 hDirBuf 0 16

  -- V-blur uniform
  let vDirBuf ← Buffer.mk device (BufferDescriptor.mk "vdir" (BufferUsage.uniform.lor BufferUsage.copyDst) 16 false)
  queue.writeBuffer vDirBuf (floatsToByteArray #[0.0, 1.0, texelW, texelH])
  let vDirBG ← BindGroup.mk device blurUnifLayout 0 vDirBuf 0 16

  -- Blur texture+sampler bind groups
  let hBlurTexBG ← BindGroup.mkTextureSampler device blurTexLayout 0 sceneView 1 sampler
  let vBlurTexBG ← BindGroup.mkTextureSampler device blurTexLayout 0 pingAView 1 sampler

  -- Blit pipeline: reads pingB, draws to screen
  let blitSm ← ShaderModule.mk device (← ShaderModuleDescriptor.mk (← ShaderModuleWGSLDescriptor.mk blitShaderSrc))
  let blitTexLayout ← BindGroupLayout.mkTextureSampler device 0 1 ShaderStageFlags.fragment
  let blitPL ← PipelineLayout.mk device #[blitTexLayout]
  let blitCTS ← ColorTargetState.mk surfFormat (← BlendState.mk blitSm)
  let blitFS ← FragmentState.mk blitSm blitCTS
  let blitPipeDesc ← RenderPipelineDescriptor.mk blitSm blitFS
  let blitPipeline ← RenderPipeline.mkWithLayout device blitPipeDesc blitPL
  let blitBG ← BindGroup.mkTextureSampler device blitTexLayout 0 pingBView 1 sampler

  let black := Color.mk 0.0 0.0 0.0 1.0

  eprintln "  Rendering: spinning triangles → H-blur → V-blur → screen"
  eprintln "  Press ESC or Q to quit"

  while not (← window.shouldClose) do
    GLFW.pollEvents

    let esc ← window.getKey GLFW.keyEscape
    let q ← window.getKey GLFW.keyQ
    if esc == GLFW.press || q == GLFW.press then
      window.setShouldClose true
      continue

    let time ← GLFW.getTime
    queue.writeBuffer sceneUnifBuf (floatsToByteArray #[time, 0.0, 0.0, 0.0])

    let texture ← surface.getCurrent
    let status ← texture.status
    if status != .success then continue
    let surfView ← TextureView.mk texture

    let encoder ← device.createCommandEncoder

    -- Pass 1: Scene → offscreen
    do
      let rp ← RenderPassEncoder.mkWithColor encoder sceneView (Color.mk 0.05 0.05 0.1 1.0)
      rp.setPipeline scenePipeline
      rp.setBindGroup 0 sceneUBG
      rp.draw 3 3 0 0  -- 3 vertices, 3 instances (3 spinning triangles)
      rp.end
      rp.release

    -- Pass 2: H-blur (scene → pingA)
    do
      let rp ← RenderPassEncoder.mkWithColor encoder pingAView black
      rp.setPipeline blurPipeline
      rp.setBindGroup 0 hBlurTexBG
      rp.setBindGroup 1 hDirBG
      rp.draw 6 1 0 0
      rp.end
      rp.release

    -- Pass 3: V-blur (pingA → pingB)
    do
      let rp ← RenderPassEncoder.mkWithColor encoder pingBView black
      rp.setPipeline blurPipeline
      rp.setBindGroup 0 vBlurTexBG
      rp.setBindGroup 1 vDirBG
      rp.draw 6 1 0 0
      rp.end
      rp.release

    -- Pass 4: Blit (pingB → screen)
    do
      let rp ← RenderPassEncoder.mkWithColor encoder surfView black
      rp.setPipeline blitPipeline
      rp.setBindGroup 0 blitBG
      rp.draw 6 1 0 0
      rp.end
      rp.release

    let cmd ← encoder.finish
    queue.submit #[cmd]
    surface.present
    device.poll

  eprintln "=== Done ==="

def main : IO Unit := postProcessBlur
