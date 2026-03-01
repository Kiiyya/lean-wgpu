import Wgpu
import Wgpu.Async
import Glfw

open IO
open Wgpu

set_option linter.unusedVariables false

/--
  Instancing: Renders many small triangles in a single draw call using instancing.
  Tests: VertexStepMode.Instance, multiple vertex buffers (per-vertex + per-instance),
  RenderPipelineDescriptor.mkFullLayouts with 2 buffer layouts, draw with instanceCount > 1.
-/

def instanceShaderSource : String :=
"struct VertexInput { \
    @location(0) position: vec2f, \
    @location(1) color: vec3f, \
    @location(2) offset: vec2f, \
    @location(3) scale: f32, \
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
    out.position = vec4f(in.position * in.scale + in.offset, 0.0, 1.0); \
    out.color = in.color; \
    return out; \
} \
 \
@fragment \
fn fs_main(in: VertexOutput) -> @location(0) vec4f { \
    return vec4f(in.color, 1.0); \
}"

-- Generate a grid of instances with varying colors
def mkInstanceData (rows cols : Nat) : Array Float := Id.run do
  let mut data : Array Float := #[]
  for r in [:rows] do
    for c in [:cols] do
      let x : Float := -0.8 + 1.6 * (c.toFloat / (cols - 1).toFloat)
      let y : Float := -0.8 + 1.6 * (r.toFloat / (rows - 1).toFloat)
      let scale : Float := 0.08
      data := data.push x
      data := data.push y
      data := data.push scale
  return data

def instancing : IO Unit := do
  eprintln "=== Instancing (Many Triangles, One Draw Call) ==="

  setLogCallback fun lvl msg => eprintln s!"[{repr lvl}] {msg}"
  let window ← GLFWwindow.mk 640 480 "Instancing"

  let desc ← InstanceDescriptor.mk
  let inst ← createInstance desc
  let surface ← getSurface inst window

  let adapter ← inst.requestAdapter surface >>= await!
  adapter.printProperties

  let ddesc ← DeviceDescriptor.mk "instancing device"
  let device ← adapter.requestDevice ddesc >>= await!
  device.setUncapturedErrorCallback fun code msg => do
    eprintln s!"uncaptured error, code {code}: \"{msg}\""

  let queue ← device.getQueue

  let texture_format ← TextureFormat.get surface adapter
  let surface_config ← SurfaceConfiguration.mk 640 480 device texture_format
  surface.configure surface_config

  -- Per-vertex data: small triangle, 3 vertices × (pos2 + color3) = 5 floats each
  let vertexData : Array Float := #[
     0.0,  0.5,    1.0, 0.3, 0.3,   -- top
    -0.5, -0.5,    0.3, 1.0, 0.3,   -- bottom-left
     0.5, -0.5,    0.3, 0.3, 1.0    -- bottom-right
  ]
  let vertexBytes := floatsToByteArray vertexData

  -- Per-instance data: 8×8 grid = 64 instances, each has offset(2) + scale(1) = 3 floats
  let numRows := 8
  let numCols := 8
  let numInstances := numRows * numCols
  let instanceData := mkInstanceData numRows numCols
  let instanceBytes := floatsToByteArray instanceData

  eprintln s!"Instances: {numInstances}, vertex bytes: {vertexBytes.size}, instance bytes: {instanceBytes.size}"

  -- Create vertex buffer
  let vbDesc := BufferDescriptor.mk "vertex buffer"
    (BufferUsage.vertex.lor BufferUsage.copyDst) vertexBytes.size.toUInt32 false
  let vertexBuffer ← Buffer.mk device vbDesc
  queue.writeBuffer vertexBuffer vertexBytes

  -- Create instance buffer
  let ibDesc := BufferDescriptor.mk "instance buffer"
    (BufferUsage.vertex.lor BufferUsage.copyDst) instanceBytes.size.toUInt32 false
  let instanceBuffer ← Buffer.mk device ibDesc
  queue.writeBuffer instanceBuffer instanceBytes

  -- Shader
  let shaderWGSL ← ShaderModuleWGSLDescriptor.mk instanceShaderSource
  let shaderDesc ← ShaderModuleDescriptor.mk shaderWGSL
  let shaderModule ← ShaderModule.mk device shaderDesc

  -- Pipeline with 2 vertex buffers: per-vertex + per-instance
  let blendState ← BlendState.mk shaderModule
  let colorTargetState ← ColorTargetState.mk texture_format blendState
  let fragmentState ← FragmentState.mk shaderModule colorTargetState

  let layouts : Array VertexBufferLayoutDesc := #[
    -- Buffer 0: per-vertex (position + color)
    { arrayStride := 5 * 4  -- 5 floats
      stepMode := .Vertex
      attributes := #[
        { format := .Float32x2, offset := 0,     shaderLocation := 0 },  -- position
        { format := .Float32x3, offset := 2 * 4, shaderLocation := 1 }   -- color
      ] },
    -- Buffer 1: per-instance (offset + scale)
    { arrayStride := 3 * 4  -- 3 floats
      stepMode := .Instance
      attributes := #[
        { format := .Float32x2, offset := 0,     shaderLocation := 2 },  -- offset
        { format := .Float32,   offset := 2 * 4, shaderLocation := 3 }   -- scale
      ] }
  ]

  let pipelineDesc ← RenderPipelineDescriptor.mkFullLayouts shaderModule fragmentState layouts
  let pipeline ← RenderPipeline.mk device pipelineDesc

  let clearColor := Color.mk 0.08 0.08 0.12 1.0

  eprintln "Entering render loop (press Q or Escape to quit)..."

  let mut frameCount : UInt32 := 0
  while not (← window.shouldClose) do
    GLFW.pollEvents

    let esc ← window.getKey GLFW.keyEscape
    let q ← window.getKey GLFW.keyQ
    if esc == GLFW.press || q == GLFW.press then
      window.setShouldClose true
      continue

    -- Animate: update instance offsets to make them wobble
    let t ← GLFW.getTime
    let mut animData : Array Float := #[]
    for r in [:numRows] do
      for c in [:numCols] do
        let baseX : Float := -0.8 + 1.6 * (c.toFloat / (numCols - 1).toFloat)
        let baseY : Float := -0.8 + 1.6 * (r.toFloat / (numRows - 1).toFloat)
        let wobbleX := baseX + 0.02 * Float.sin (t * 3.0 + r.toFloat * 0.5 + c.toFloat * 0.3)
        let wobbleY := baseY + 0.02 * Float.cos (t * 2.5 + r.toFloat * 0.3 + c.toFloat * 0.5)
        let scale : Float := 0.08 + 0.02 * Float.sin (t * 2.0 + (r * numCols + c).toFloat * 0.1)
        animData := animData.push wobbleX
        animData := animData.push wobbleY
        animData := animData.push scale
    let animBytes := floatsToByteArray animData
    queue.writeBuffer instanceBuffer animBytes

    let texture ← surface.getCurrent
    let status ← texture.status
    if (status != .success) then continue
    let targetView ← TextureView.mk texture
    if !(← targetView.is_valid) then continue

    let encoder ← device.createCommandEncoder
    let renderPassEncoder ← RenderPassEncoder.mkWithColor encoder targetView clearColor
    renderPassEncoder.setPipeline pipeline
    renderPassEncoder.setVertexBuffer 0 vertexBuffer
    renderPassEncoder.setVertexBuffer 1 instanceBuffer
    renderPassEncoder.draw 3 numInstances.toUInt32 0 0
    renderPassEncoder.end

    let command ← encoder.finish
    queue.submit #[command]
    surface.present
    device.poll

    frameCount := frameCount + 1
    if frameCount % 300 == 0 then
      window.setTitle s!"Instancing ({numInstances} instances) - {t.toString}s"

  eprintln s!"Rendered {frameCount} frames"
  eprintln "=== Done ==="

def main : IO Unit := instancing
