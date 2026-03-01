import Wgpu
import Wgpu.Async
import Glfw

open IO
open Wgpu

set_option linter.unusedVariables false

/--
  ColoredTriangle: Renders a triangle with per-vertex colors using vertex buffers.
  Tests: vertex buffer creation, vertex buffer layouts, setVertexBuffer,
  floatsToByteArray, custom clear color, configurable RenderPipelineDescriptor.
-/

def coloredShaderSource : String :=
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

def coloredTriangle : IO Unit := do
  eprintln "=== Colored Triangle (Vertex Buffers) ==="

  setLogCallback fun lvl msg => eprintln s!"[{repr lvl}] {msg}"
  let window ← GLFWwindow.mk 640 480 "Colored Triangle"

  let desc ← InstanceDescriptor.mk
  let inst ← createInstance desc
  let surface ← getSurface inst window

  let adapter ← inst.requestAdapter surface >>= await!
  adapter.printProperties

  let ddesc ← DeviceDescriptor.mk "colored triangle device"
  let device ← adapter.requestDevice ddesc >>= await!
  device.setUncapturedErrorCallback fun code msg => do
    eprintln s!"uncaptured error, code {code}: \"{msg}\""

  let queue ← device.getQueue

  let texture_format ← TextureFormat.get surface adapter
  let surface_config ← SurfaceConfiguration.mk 640 480 device texture_format
  surface.configure surface_config

  -- Vertex data: 3 vertices with position (x,y) and color (r,g,b)
  -- Interleaved: [x, y, r, g, b] per vertex
  let vertexData : Array Float := #[
    -- position    -- color
    -0.5, -0.5,    1.0, 0.0, 0.0,  -- bottom-left, red
     0.5, -0.5,    0.0, 1.0, 0.0,  -- bottom-right, green
     0.0,  0.5,    0.0, 0.0, 1.0   -- top-center, blue
  ]
  let vertexBytes := floatsToByteArray vertexData

  -- Create vertex buffer
  let vbDesc := BufferDescriptor.mk "vertex buffer"
    (BufferUsage.vertex.lor BufferUsage.copyDst) vertexBytes.size.toUInt32 false
  let vertexBuffer ← Buffer.mk device vbDesc
  queue.writeBuffer vertexBuffer vertexBytes
  eprintln s!"Vertex buffer size: {← vertexBuffer.getSize}"

  -- Shader
  let shaderWGSL ← ShaderModuleWGSLDescriptor.mk coloredShaderSource
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

  -- Dark background color
  let clearColor := Color.mk 0.05 0.05 0.05 1.0

  eprintln "Entering render loop..."

  let mut frameCount : UInt32 := 0
  while not (← window.shouldClose) do
    GLFW.pollEvents

    -- Check escape to close
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
    renderPassEncoder.draw 3 1 0 0
    renderPassEncoder.end

    let command ← encoder.finish
    queue.submit #[command]
    surface.present
    device.poll

    frameCount := frameCount + 1
    if frameCount % 300 == 0 then
      let t ← GLFW.getTime
      window.setTitle s!"Colored Triangle - {t.toString}s"

  eprintln s!"Rendered {frameCount} frames"
  eprintln "=== Done ==="

def main : IO Unit := coloredTriangle
