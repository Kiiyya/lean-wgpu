import Wgpu
import Wgpu.Async
import Glfw

open IO
open Wgpu

set_option linter.unusedVariables false

/--
  IndexedQuad: Renders a colored quad using indexed drawing.
  Tests: index buffers, drawIndexed, setIndexBuffer, uint16sToByteArray.
  4 vertices, 6 indices (2 triangles).
-/

def quadShaderSource : String :=
"struct VertexInput { \
    @location(0) position: vec2f, \
    @location(1) color: vec3f, \
}; \
 \
struct VertexOutput { \
    @builtin(position) position: vec4f, \
    @location(0) color: vec3f, \
}; \
 \
@vertex \
fn vs_main(in: VertexInput) -> VertexOutput { \
    var out: VertexOutput; \
    out.position = vec4f(in.position, 0.0, 1.0); \
    out.color = in.color; \
    return out; \
} \
 \
@fragment \
fn fs_main(in: VertexOutput) -> @location(0) vec4f { \
    return vec4f(in.color, 1.0); \
}"

def indexedQuad : IO Unit := do
  eprintln "=== Indexed Quad (Index Buffers) ==="

  setLogCallback fun lvl msg => eprintln s!"[{repr lvl}] {msg}"
  let window ← GLFWwindow.mk 640 480 "Indexed Quad"

  let desc ← InstanceDescriptor.mk
  let inst ← createInstance desc
  let surface ← getSurface inst window

  let adapter ← inst.requestAdapter surface >>= await!
  adapter.printProperties

  let ddesc ← DeviceDescriptor.mk "indexed quad device"
  let device ← adapter.requestDevice ddesc >>= await!
  device.setUncapturedErrorCallback fun code msg => do
    eprintln s!"uncaptured error, code {code}: \"{msg}\""

  let queue ← device.getQueue

  let texture_format ← TextureFormat.get surface adapter
  let surface_config ← SurfaceConfiguration.mk 640 480 device texture_format
  surface.configure surface_config

  -- Quad vertices: 4 corners with position (x,y) and color (r,g,b)
  -- Interleaved: [x, y, r, g, b]
  let vertexData : Array Float := #[
    -- position    -- color
    -0.6, -0.6,    1.0, 0.0, 0.0,  -- bottom-left, red
     0.6, -0.6,    0.0, 1.0, 0.0,  -- bottom-right, green
     0.6,  0.6,    0.0, 0.0, 1.0,  -- top-right, blue
    -0.6,  0.6,    1.0, 1.0, 0.0   -- top-left, yellow
  ]
  let vertexBytes := floatsToByteArray vertexData

  -- Index data: 2 triangles forming a quad (CCW winding)
  let indexData : Array UInt16 := #[0, 1, 2, 0, 2, 3]
  let indexBytes := uint16sToByteArray indexData

  -- Create vertex buffer
  let vbDesc := BufferDescriptor.mk "vertex buffer"
    (BufferUsage.vertex.lor BufferUsage.copyDst) vertexBytes.size.toUInt32 false
  let vertexBuffer ← Buffer.mk device vbDesc
  queue.writeBuffer vertexBuffer vertexBytes

  -- Create index buffer
  let ibDesc := BufferDescriptor.mk "index buffer"
    (BufferUsage.index.lor BufferUsage.copyDst) indexBytes.size.toUInt32 false
  let indexBuffer ← Buffer.mk device ibDesc
  queue.writeBuffer indexBuffer indexBytes

  eprintln s!"Vertex buffer size: {← vertexBuffer.getSize}, Index buffer size: {← indexBuffer.getSize}"

  -- Shader
  let shaderWGSL ← ShaderModuleWGSLDescriptor.mk quadShaderSource
  let shaderDesc ← ShaderModuleDescriptor.mk shaderWGSL
  let shaderModule ← ShaderModule.mk device shaderDesc

  -- Pipeline with vertex buffers
  let blendState ← BlendState.mk shaderModule
  let colorTargetState ← ColorTargetState.mk texture_format blendState
  let fragmentState ← FragmentState.mk shaderModule colorTargetState

  let layouts : Array VertexBufferLayoutDesc := #[
    { arrayStride := 5 * 4  -- 5 floats * 4 bytes
      stepMode := .Vertex
      attributes := #[
        { format := .Float32x2, offset := 0,     shaderLocation := 0 },  -- position
        { format := .Float32x3, offset := 2 * 4, shaderLocation := 1 }   -- color
      ] }
  ]

  let pipelineDesc ← RenderPipelineDescriptor.mkWithLayouts shaderModule fragmentState layouts
  let pipeline ← RenderPipeline.mk device pipelineDesc

  let clearColor := Color.mk 0.08 0.08 0.12 1.0

  eprintln "Entering render loop (press Escape to quit)..."

  let mut frameCount : UInt32 := 0
  while not (← window.shouldClose) do
    GLFW.pollEvents

    let esc ← window.getKey GLFW.keyEscape
    if esc == GLFW.press then
      window.setShouldClose true
      continue

    let texture ← surface.getCurrent
    let status ← texture.status
    if (status != .success) then continue
    let targetView ← TextureView.mk texture
    if !(← targetView.is_valid) then continue

    let encoder ← device.createCommandEncoder
    let renderPassEncoder ← RenderPassEncoder.mkWithColor encoder targetView clearColor
    renderPassEncoder.setPipeline pipeline
    renderPassEncoder.setVertexBuffer 0 vertexBuffer
    renderPassEncoder.setIndexBuffer indexBuffer IndexFormat.Uint16
    renderPassEncoder.drawIndexed 6 1 0  -- 6 indices, 1 instance
    renderPassEncoder.end

    let command ← encoder.finish
    queue.submit #[command]
    surface.present
    device.poll

    frameCount := frameCount + 1
    if frameCount % 300 == 0 then
      let t ← GLFW.getTime
      window.setTitle s!"Indexed Quad - {t.toString}s"

  eprintln s!"Rendered {frameCount} frames"
  eprintln "=== Done ==="

def main : IO Unit := indexedQuad
