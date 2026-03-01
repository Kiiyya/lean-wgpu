import Wgpu
import Wgpu.Async
import Glfw

open IO
open Wgpu

set_option linter.unusedVariables false

/--
  TexturedQuad: Renders a quad with a procedural checkerboard texture.
  Tests: Texture creation, Queue.writeTexture, Texture.createView,
  Sampler creation, texture+sampler bind groups, indexed drawing with UVs.
-/

def texturedShaderSource : String :=
"struct VertexInput { \
    @location(0) position: vec2f, \
    @location(1) uv: vec2f, \
}; \
 \
struct VertexOutput { \
    @builtin(position) position: vec4f, \
    @location(0) uv: vec2f, \
}; \
 \
@group(0) @binding(0) var myTexture: texture_2d<f32>; \
@group(0) @binding(1) var mySampler: sampler; \
 \
@vertex \
fn vs_main(in: VertexInput) -> VertexOutput { \
    var out: VertexOutput; \
    out.position = vec4f(in.position, 0.0, 1.0); \
    out.uv = in.uv; \
    return out; \
} \
 \
@fragment \
fn fs_main(in: VertexOutput) -> @location(0) vec4f { \
    return textureSample(myTexture, mySampler, in.uv); \
}"

def texturedQuad : IO Unit := do
  eprintln "=== Textured Quad (Texture + Sampler) ==="

  setLogCallback fun lvl msg => eprintln s!"[{repr lvl}] {msg}"
  let window ← GLFWwindow.mk 640 480 "Textured Quad"

  let desc ← InstanceDescriptor.mk
  let inst ← createInstance desc
  let surface ← getSurface inst window

  let adapter ← inst.requestAdapter surface >>= await!
  adapter.printProperties

  let ddesc ← DeviceDescriptor.mk "textured quad device"
  let device ← adapter.requestDevice ddesc >>= await!
  device.setUncapturedErrorCallback fun code msg => do
    eprintln s!"uncaptured error, code {code}: \"{msg}\""

  let queue ← device.getQueue

  let texture_format ← TextureFormat.get surface adapter
  let surface_config ← SurfaceConfiguration.mk 640 480 device texture_format
  surface.configure surface_config

  -- Generate checkerboard texture (64x64, 8-pixel tiles)
  let texWidth : UInt32 := 64
  let texHeight : UInt32 := 64
  let tileSize : UInt32 := 8
  let checkerPixels := mkCheckerboard texWidth texHeight tileSize 0xFFFF8844 0xFF442211
  eprintln s!"Checkerboard texture: {texWidth}x{texHeight}, {checkerPixels.size} bytes"

  -- Create GPU texture
  let texture ← device.createTexture texWidth texHeight TextureFormat.RGBA8Unorm
    (TextureUsage.textureBinding.lor TextureUsage.copyDst)
  queue.writeTexture texture checkerPixels texWidth texHeight (texWidth * 4)
  let textureView ← texture.createView TextureFormat.RGBA8Unorm

  -- Create sampler (nearest filtering for pixel-art look)
  let sampler ← device.createSampler FilterMode.Nearest FilterMode.Nearest

  -- Bind group layout and bind group for texture + sampler
  let texBindGroupLayout ← BindGroupLayout.mkTextureSampler device 0 1 ShaderStageFlags.fragment
  let texBindGroup ← BindGroup.mkTextureSampler device texBindGroupLayout 0 textureView 1 sampler

  -- Pipeline layout
  let pipelineLayout ← PipelineLayout.mk device #[texBindGroupLayout]

  -- Quad vertices: position (x,y) + UV (u,v), interleaved
  let vertexData : Array Float := #[
    -- position    -- uv
    -0.7, -0.7,    0.0, 1.0,  -- bottom-left
     0.7, -0.7,    1.0, 1.0,  -- bottom-right
     0.7,  0.7,    1.0, 0.0,  -- top-right
    -0.7,  0.7,    0.0, 0.0   -- top-left
  ]
  let vertexBytes := floatsToByteArray vertexData

  -- Index data
  let indexData : Array UInt16 := #[0, 1, 2, 0, 2, 3]
  let indexBytes := uint16sToByteArray indexData

  -- Create buffers
  let vbDesc := BufferDescriptor.mk "vertex buffer"
    (BufferUsage.vertex.lor BufferUsage.copyDst) vertexBytes.size.toUInt32 false
  let vertexBuffer ← Buffer.mk device vbDesc
  queue.writeBuffer vertexBuffer vertexBytes

  let ibDesc := BufferDescriptor.mk "index buffer"
    (BufferUsage.index.lor BufferUsage.copyDst) indexBytes.size.toUInt32 false
  let indexBuffer ← Buffer.mk device ibDesc
  queue.writeBuffer indexBuffer indexBytes

  -- Shader
  let shaderWGSL ← ShaderModuleWGSLDescriptor.mk texturedShaderSource
  let shaderDesc ← ShaderModuleDescriptor.mk shaderWGSL
  let shaderModule ← ShaderModule.mk device shaderDesc

  -- Pipeline
  let blendState ← BlendState.mk shaderModule
  let colorTargetState ← ColorTargetState.mk texture_format blendState
  let fragmentState ← FragmentState.mk shaderModule colorTargetState

  let layouts : Array VertexBufferLayoutDesc := #[
    { arrayStride := 4 * 4  -- 4 floats * 4 bytes (pos.xy + uv.xy)
      stepMode := .Vertex
      attributes := #[
        { format := .Float32x2, offset := 0,     shaderLocation := 0 },  -- position
        { format := .Float32x2, offset := 2 * 4, shaderLocation := 1 }   -- uv
      ] }
  ]

  let pipelineDesc ← RenderPipelineDescriptor.mkWithLayouts shaderModule fragmentState layouts
  let pipeline ← RenderPipeline.mkWithLayout device pipelineDesc pipelineLayout

  let clearColor := Color.mk 0.15 0.15 0.2 1.0

  eprintln "Entering render loop (press Escape to quit)..."

  let mut frameCount : UInt32 := 0
  while not (← window.shouldClose) do
    GLFW.pollEvents

    let esc ← window.getKey GLFW.keyEscape
    if esc == GLFW.press then
      window.setShouldClose true
      continue

    let surfTex ← surface.getCurrent
    let status ← surfTex.status
    if (status != .success) then continue
    let targetView ← TextureView.mk surfTex
    if !(← targetView.is_valid) then continue

    let encoder ← device.createCommandEncoder
    let renderPassEncoder ← RenderPassEncoder.mkWithColor encoder targetView clearColor
    renderPassEncoder.setPipeline pipeline
    renderPassEncoder.setBindGroup 0 texBindGroup
    renderPassEncoder.setVertexBuffer 0 vertexBuffer
    renderPassEncoder.setIndexBuffer indexBuffer IndexFormat.Uint16
    renderPassEncoder.drawIndexed 6 1 0
    renderPassEncoder.end

    let command ← encoder.finish
    queue.submit #[command]
    surface.present
    device.poll

    frameCount := frameCount + 1
    if frameCount % 300 == 0 then
      let t ← GLFW.getTime
      window.setTitle s!"Textured Quad - {t.toString}s"

  eprintln s!"Rendered {frameCount} frames"
  eprintln "=== Done ==="

def main : IO Unit := texturedQuad
