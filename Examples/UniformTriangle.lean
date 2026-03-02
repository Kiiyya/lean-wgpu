import Wgpu
import Wgpu.Async
import Glfw
import Wgsl.Syntax

open IO
open Wgpu

set_option linter.unusedVariables false

/--
  UniformTriangle: Renders a triangle that rotates over time using a uniform buffer.
  Tests: bind group layout, bind group, pipeline layout, uniform buffer updates,
  queue.writeBufferOffset, configurable pipeline with layout.
-/

def uniformShaderSource : String := !WGSL{
struct Uniforms {
    time: f32,
    _pad1: f32,
    _pad2: f32,
    _pad3: f32,
};

@group(0) @binding(0) var<uniform> uniforms: Uniforms;

struct VertexInput {
    @location(0) position: vec2f,
    @location(1) color: vec3f,
};

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) color: vec3f,
};

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    let angle = uniforms.time;
    let c = cos(angle);
    let s = sin(angle);
    let rotated = vec2f(
        in.position.x * c - in.position.y * s,
        in.position.x * s + in.position.y * c 
    );
    var out: VertexOutput;
    out.position = vec4f(rotated, 0.0, 1.0);
    out.color = in.color;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4f {
    return vec4f(in.color, 1.0);
}
}

def uniformTriangle : IO Unit := do
  eprintln "=== Uniform Triangle (Animated Rotation) ==="

  setLogCallback fun lvl msg => eprintln s!"[{repr lvl}] {msg}"
  let window ← GLFWwindow.mk 640 480 "Uniform Triangle"

  let desc ← InstanceDescriptor.mk
  let inst ← createInstance desc
  let surface ← getSurface inst window

  let adapter ← inst.requestAdapter surface >>= await!
  adapter.printProperties

  let ddesc ← DeviceDescriptor.mk "uniform triangle device"
  let device ← adapter.requestDevice ddesc >>= await!
  device.setUncapturedErrorCallback fun code msg => do
    eprintln s!"uncaptured error, code {code}: \"{msg}\""

  let queue ← device.getQueue

  let texture_format ← TextureFormat.get surface adapter
  let surface_config ← SurfaceConfiguration.mk 640 480 device texture_format
  surface.configure surface_config

  -- Vertex data: interleaved [x, y, r, g, b]
  let vertexData : Array Float := #[
    -0.5, -0.5,    1.0, 0.2, 0.2,
     0.5, -0.5,    0.2, 1.0, 0.2,
     0.0,  0.5,    0.2, 0.2, 1.0
  ]
  let vertexBytes := floatsToByteArray vertexData
  let vbDesc := BufferDescriptor.mk "vertex buffer"
    (BufferUsage.vertex.lor BufferUsage.copyDst) vertexBytes.size.toUInt32 false
  let vertexBuffer ← Buffer.mk device vbDesc
  queue.writeBuffer vertexBuffer vertexBytes

  -- Uniform buffer: 16 bytes (1 float + 3 padding for alignment)
  let uniformSize : UInt32 := 16
  let ubDesc := BufferDescriptor.mk "uniform buffer"
    (BufferUsage.uniform.lor BufferUsage.copyDst) uniformSize false
  let uniformBuffer ← Buffer.mk device ubDesc

  -- Bind group layout + bind group
  let bindGroupLayout ← BindGroupLayout.mkUniform device 0
    (ShaderStageFlags.vertex.lor ShaderStageFlags.fragment) uniformSize.toUInt64
  let bindGroup ← BindGroup.mk device bindGroupLayout 0 uniformBuffer

  -- Pipeline layout
  let pipelineLayout ← PipelineLayout.mk device #[bindGroupLayout]

  -- Shader
  let shaderWGSL ← ShaderModuleWGSLDescriptor.mk uniformShaderSource
  let shaderDesc ← ShaderModuleDescriptor.mk shaderWGSL
  let shaderModule ← ShaderModule.mk device shaderDesc

  -- Pipeline
  let blendState ← BlendState.mk shaderModule
  let colorTargetState ← ColorTargetState.mk texture_format blendState
  let fragmentState ← FragmentState.mk shaderModule colorTargetState

  let layouts : Array VertexBufferLayoutDesc := #[
    { arrayStride := 5 * 4
      stepMode := .Vertex
      attributes := #[
        { format := .Float32x2, offset := 0,     shaderLocation := 0 },
        { format := .Float32x3, offset := 2 * 4, shaderLocation := 1 }
      ] }
  ]

  let pipelineDesc ← RenderPipelineDescriptor.mkWithLayouts shaderModule fragmentState layouts
  let pipeline ← RenderPipeline.mkWithLayout device pipelineDesc pipelineLayout

  let clearColor := Color.mk 0.1 0.1 0.15 1.0

  eprintln "Entering render loop (press Q or Escape to quit)..."

  let mut frameCount : UInt32 := 0
  while not (← window.shouldClose) do
    GLFW.pollEvents

    let esc ← window.getKey GLFW.keyEscape
    let q ← window.getKey GLFW.keyQ
    if esc == GLFW.press || q == GLFW.press then
      window.setShouldClose true
      continue

    -- Update uniform: time
    let t ← GLFW.getTime
    let uniformData := floatsToByteArray #[t, 0.0, 0.0, 0.0]
    queue.writeBuffer uniformBuffer uniformData

    let texture ← surface.getCurrent
    let status ← texture.status
    if (status != .success) then continue
    let targetView ← TextureView.mk texture
    if !(← targetView.is_valid) then continue

    let encoder ← device.createCommandEncoder
    let renderPassEncoder ← RenderPassEncoder.mkWithColor encoder targetView clearColor
    renderPassEncoder.setPipeline pipeline
    renderPassEncoder.setBindGroup 0 bindGroup
    renderPassEncoder.setVertexBuffer 0 vertexBuffer
    renderPassEncoder.draw 3 1 0 0
    renderPassEncoder.end

    let command ← encoder.finish
    queue.submit #[command]
    surface.present
    device.poll

    frameCount := frameCount + 1
    if frameCount % 300 == 0 then
      window.setTitle s!"Uniform Triangle - {t.toString}s"

  eprintln s!"Rendered {frameCount} frames"
  eprintln "=== Done ==="

def main : IO Unit := uniformTriangle
