import Wgpu
import Wgpu.Async
import Glfw

open IO
open Wgpu

set_option linter.unusedVariables false

/--
  LineGrid: Renders a spinning 3D wireframe grid using line primitives and depth testing.
  Tests: PrimitiveTopology.LineList, depth buffer, 3D perspective, MVP uniform.
-/

def gridShaderSource : String :=
"struct Uniforms { \
    mvp: mat4x4<f32>, \
}; \
 \
@group(0) @binding(0) var<uniform> uniforms: Uniforms; \
 \
struct VertexInput { \
    @location(0) position: vec3f, \
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
    out.position = uniforms.mvp * vec4f(in.position, 1.0); \
    out.color = in.color; \
    return out; \
} \
 \
@fragment \
fn fs_main(in: VertexOutput) -> @location(0) vec4f { \
    return vec4f(in.color, 1.0); \
}"

-- Matrix math (column-major, same as DepthCube)
def mat4Mul (a b : Array Float) : Array Float := Id.run do
  let get (m : Array Float) (row col : Nat) : Float := m[col * 4 + row]!
  let mut result : Array Float := #[0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0]
  for col in [:4] do
    for row in [:4] do
      let mut s : Float := 0.0
      for k in [:4] do
        s := s + get a row k * get b k col
      result := result.set! (col * 4 + row) s
  return result

def mat4Perspective (fovY aspect near far : Float) : Array Float :=
  let f := 1.0 / Float.tan (fovY / 2.0)
  let rangeInv := 1.0 / (near - far)
  #[f / aspect, 0, 0, 0,
    0, f, 0, 0,
    0, 0, far * rangeInv, -1,
    0, 0, near * far * rangeInv, 0]

def mat4LookAt (eyeX eyeY eyeZ targetX targetY targetZ upX upY upZ : Float) : Array Float :=
  let fx := targetX - eyeX
  let fy := targetY - eyeY
  let fz := targetZ - eyeZ
  let fLen := Float.sqrt (fx*fx + fy*fy + fz*fz)
  let fx := fx / fLen; let fy := fy / fLen; let fz := fz / fLen
  let sx := fy * upZ - fz * upY
  let sy := fz * upX - fx * upZ
  let sz := fx * upY - fy * upX
  let sLen := Float.sqrt (sx*sx + sy*sy + sz*sz)
  let sx := sx / sLen; let sy := sy / sLen; let sz := sz / sLen
  let ux := sy * fz - sz * fy
  let uy := sz * fx - sx * fz
  let uz := sx * fy - sy * fx
  #[sx, ux, -fx, 0,
    sy, uy, -fy, 0,
    sz, uz, -fz, 0,
    -(sx*eyeX + sy*eyeY + sz*eyeZ),
    -(ux*eyeX + uy*eyeY + uz*eyeZ),
    (fx*eyeX + fy*eyeY + fz*eyeZ),
    1]

def mat4RotateY (angle : Float) : Array Float :=
  let c := Float.cos angle
  let s := Float.sin angle
  #[c, 0, -s, 0,  0, 1, 0, 0,  s, 0, c, 0,  0, 0, 0, 1]

def mat4RotateX (angle : Float) : Array Float :=
  let c := Float.cos angle
  let s := Float.sin angle
  #[1, 0, 0, 0,  0, c, s, 0,  0, -s, c, 0,  0, 0, 0, 1]

-- Generate grid lines: a flat grid of lines in the XZ plane
def mkGridVertices (gridSize : Nat) : Array Float := Id.run do
  let half := gridSize.toFloat / 2.0
  let mut verts : Array Float := #[]
  -- Lines along X axis (varying Z)
  for i in [:gridSize + 1] do
    let z := i.toFloat - half
    let intensity := if i == gridSize / 2 then 0.9 else 0.3
    -- Line from (-half, 0, z) to (half, 0, z)
    -- vertex 1: position + color
    verts := verts.push (-half); verts := verts.push 0; verts := verts.push z
    verts := verts.push intensity; verts := verts.push intensity; verts := verts.push 0.4
    -- vertex 2
    verts := verts.push half; verts := verts.push 0; verts := verts.push z
    verts := verts.push intensity; verts := verts.push intensity; verts := verts.push 0.4
  -- Lines along Z axis (varying X)
  for i in [:gridSize + 1] do
    let x := i.toFloat - half
    let intensity := if i == gridSize / 2 then 0.9 else 0.3
    verts := verts.push x; verts := verts.push 0; verts := verts.push (-half)
    verts := verts.push 0.4; verts := verts.push intensity; verts := verts.push intensity
    verts := verts.push x; verts := verts.push 0; verts := verts.push half
    verts := verts.push 0.4; verts := verts.push intensity; verts := verts.push intensity
  -- Add axis highlight lines (colored)
  -- X axis (red): from (-half, 0.01, 0) to (half, 0.01, 0)
  verts := verts.push (-half); verts := verts.push 0.01; verts := verts.push 0
  verts := verts.push 1.0; verts := verts.push 0.2; verts := verts.push 0.2
  verts := verts.push half; verts := verts.push 0.01; verts := verts.push 0
  verts := verts.push 1.0; verts := verts.push 0.2; verts := verts.push 0.2
  -- Z axis (blue): from (0, 0.01, -half) to (0, 0.01, half)
  verts := verts.push 0; verts := verts.push 0.01; verts := verts.push (-half)
  verts := verts.push 0.2; verts := verts.push 0.2; verts := verts.push 1.0
  verts := verts.push 0; verts := verts.push 0.01; verts := verts.push half
  verts := verts.push 0.2; verts := verts.push 0.2; verts := verts.push 1.0
  -- Y axis (green): small vertical line from (0,0,0) to (0,1,0)
  verts := verts.push 0; verts := verts.push 0; verts := verts.push 0
  verts := verts.push 0.2; verts := verts.push 1.0; verts := verts.push 0.2
  verts := verts.push 0; verts := verts.push 1; verts := verts.push 0
  verts := verts.push 0.2; verts := verts.push 1.0; verts := verts.push 0.2
  return verts

def lineGrid : IO Unit := do
  eprintln "=== LineGrid (3D Wireframe Grid) ==="

  setLogCallback fun lvl msg => eprintln s!"[{repr lvl}] {msg}"
  let window ← GLFWwindow.mk 640 480 "LineGrid"

  let desc ← InstanceDescriptor.mk
  let inst ← createInstance desc
  let surface ← getSurface inst window

  let adapter ← inst.requestAdapter surface >>= await!
  adapter.printProperties

  let ddesc ← DeviceDescriptor.mk "linegrid device"
  let device ← adapter.requestDevice ddesc >>= await!
  device.setUncapturedErrorCallback fun code msg => do
    eprintln s!"uncaptured error, code {code}: \"{msg}\""

  let queue ← device.getQueue

  let texture_format ← TextureFormat.get surface adapter
  let surface_config ← SurfaceConfiguration.mk 640 480 device texture_format
  surface.configure surface_config

  -- Grid vertices
  let gridSize := 10
  let gridVerts := mkGridVertices gridSize
  let numVerts := gridVerts.size / 6  -- 6 floats per vertex
  let vertexBytes := floatsToByteArray gridVerts
  eprintln s!"Grid: {gridSize}×{gridSize}, {numVerts} line vertices, {vertexBytes.size} bytes"

  let vbDesc := BufferDescriptor.mk "grid vertex buffer"
    (BufferUsage.vertex.lor BufferUsage.copyDst) vertexBytes.size.toUInt32 false
  let vertexBuffer ← Buffer.mk device vbDesc
  queue.writeBuffer vertexBuffer vertexBytes

  -- Uniform buffer (4x4 matrix = 64 bytes)
  let uniformSize : UInt32 := 64
  let ubDesc := BufferDescriptor.mk "mvp uniform"
    (BufferUsage.uniform.lor BufferUsage.copyDst) uniformSize false
  let uniformBuffer ← Buffer.mk device ubDesc

  let bindGroupLayout ← BindGroupLayout.mkUniform device 0
    ShaderStageFlags.vertex uniformSize.toUInt64
  let bindGroup ← BindGroup.mk device bindGroupLayout 0 uniformBuffer
  let pipelineLayout ← PipelineLayout.mk device #[bindGroupLayout]

  -- Shader
  let shaderWGSL ← ShaderModuleWGSLDescriptor.mk gridShaderSource
  let shaderDesc ← ShaderModuleDescriptor.mk shaderWGSL
  let shaderModule ← ShaderModule.mk device shaderDesc

  -- Pipeline with LineList topology
  let blendState ← BlendState.mk shaderModule
  let colorTargetState ← ColorTargetState.mk texture_format blendState
  let fragmentState ← FragmentState.mk shaderModule colorTargetState

  let layouts : Array VertexBufferLayoutDesc := #[
    { arrayStride := 6 * 4
      stepMode := .Vertex
      attributes := #[
        { format := .Float32x3, offset := 0,     shaderLocation := 0 },
        { format := .Float32x3, offset := 3 * 4, shaderLocation := 1 }
      ] }
  ]

  let pipelineDesc ← RenderPipelineDescriptor.mkFullLayouts shaderModule fragmentState layouts
    (topology := .LineList)
    (cullMode := .None)
    (enableDepth := true)
  let pipeline ← RenderPipeline.mkWithLayout device pipelineDesc pipelineLayout

  let depthTexture ← Device.createDepthTexture device 640 480
  let depthView ← depthTexture.createDepthView

  let clearColor := Color.mk 0.02 0.02 0.05 1.0
  let proj := mat4Perspective (3.14159265 / 4.0) (640.0 / 480.0) 0.1 100.0

  eprintln "Entering render loop (press Q or Escape to quit)..."

  let mut frameCount : UInt32 := 0
  while not (← window.shouldClose) do
    GLFW.pollEvents

    let esc ← window.getKey GLFW.keyEscape
    let q ← window.getKey GLFW.keyQ
    if esc == GLFW.press || q == GLFW.press then
      window.setShouldClose true
      continue

    let t ← GLFW.getTime
    -- Camera orbits around the grid
    let camX := 8.0 * Float.cos (t * 0.3)
    let camZ := 8.0 * Float.sin (t * 0.3)
    let camY := 4.0 + 1.0 * Float.sin (t * 0.2)
    let view := mat4LookAt camX camY camZ 0 0 0 0 1 0
    let mvp := mat4Mul proj view
    let mvpBytes := floatsToByteArray mvp
    queue.writeBuffer uniformBuffer mvpBytes

    let texture ← surface.getCurrent
    let status ← texture.status
    if (status != .success) then continue
    let targetView ← TextureView.mk texture
    if !(← targetView.is_valid) then continue

    let encoder ← device.createCommandEncoder
    let renderPassEncoder ← RenderPassEncoder.mkWithDepth encoder targetView clearColor depthView
    renderPassEncoder.setPipeline pipeline
    renderPassEncoder.setBindGroup 0 bindGroup
    renderPassEncoder.setVertexBuffer 0 vertexBuffer
    renderPassEncoder.draw numVerts.toUInt32 1 0 0
    renderPassEncoder.end

    let command ← encoder.finish
    queue.submit #[command]
    surface.present
    device.poll

    frameCount := frameCount + 1
    if frameCount % 300 == 0 then
      window.setTitle s!"LineGrid - {t.toString}s"

  eprintln s!"Rendered {frameCount} frames"
  eprintln "=== Done ==="

def main : IO Unit := lineGrid
