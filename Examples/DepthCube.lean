import Wgpu
import Wgpu.Async
import Glfw

open IO
open Wgpu

set_option linter.unusedVariables false

/--
  DepthCube: Renders a spinning 3D cube with per-face colors and depth testing.
  Tests: depth buffer, 3D vertex data, MVP matrix uniform,
  back-face culling, RenderPipelineDescriptor.mkFullLayouts.
-/

def cubeShaderSource : String :=
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

-- Simple mat4 operations in pure Lean for the MVP
-- Row-major 4x4 matrix as Array Float (16 elements)

def mat4Identity : Array Float :=
  #[1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]

def mat4Mul (a b : Array Float) : Array Float := Id.run do
  -- Column-major: element at (row, col) is stored at index col*4 + row
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
  -- Column-major, WebGPU z-range [0, 1]
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
  -- side = f × up
  let sx := fy * upZ - fz * upY
  let sy := fz * upX - fx * upZ
  let sz := fx * upY - fy * upX
  let sLen := Float.sqrt (sx*sx + sy*sy + sz*sz)
  let sx := sx / sLen; let sy := sy / sLen; let sz := sz / sLen
  -- u = s × f
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
  -- Column-major
  #[c, 0, -s, 0,
    0, 1, 0, 0,
    s, 0, c, 0,
    0, 0, 0, 1]

def mat4RotateX (angle : Float) : Array Float :=
  let c := Float.cos angle
  let s := Float.sin angle
  -- Column-major
  #[1, 0, 0, 0,
    0, c, s, 0,
    0, -s, c, 0,
    0, 0, 0, 1]

-- Cube mesh: 36 vertices (6 faces * 2 triangles * 3 vertices)
-- Each vertex: position (x,y,z) + color (r,g,b) = 6 floats
def cubeVertices : Array Float :=
  -- Front face (red)
  let r := 0.9; let g := 0.2; let b := 0.2
  let front := #[
    -0.5, -0.5,  0.5,  r, g, b,
     0.5, -0.5,  0.5,  r, g, b,
     0.5,  0.5,  0.5,  r, g, b,
    -0.5, -0.5,  0.5,  r, g, b,
     0.5,  0.5,  0.5,  r, g, b,
    -0.5,  0.5,  0.5,  r, g, b
  ]
  -- Back face (green)
  let r := 0.2; let g := 0.9; let b := 0.2
  let back := #[
     0.5, -0.5, -0.5,  r, g, b,
    -0.5, -0.5, -0.5,  r, g, b,
    -0.5,  0.5, -0.5,  r, g, b,
     0.5, -0.5, -0.5,  r, g, b,
    -0.5,  0.5, -0.5,  r, g, b,
     0.5,  0.5, -0.5,  r, g, b
  ]
  -- Right face (blue)
  let r := 0.2; let g := 0.2; let b := 0.9
  let right := #[
     0.5, -0.5,  0.5,  r, g, b,
     0.5, -0.5, -0.5,  r, g, b,
     0.5,  0.5, -0.5,  r, g, b,
     0.5, -0.5,  0.5,  r, g, b,
     0.5,  0.5, -0.5,  r, g, b,
     0.5,  0.5,  0.5,  r, g, b
  ]
  -- Left face (yellow)
  let r := 0.9; let g := 0.9; let b := 0.2
  let left := #[
    -0.5, -0.5, -0.5,  r, g, b,
    -0.5, -0.5,  0.5,  r, g, b,
    -0.5,  0.5,  0.5,  r, g, b,
    -0.5, -0.5, -0.5,  r, g, b,
    -0.5,  0.5,  0.5,  r, g, b,
    -0.5,  0.5, -0.5,  r, g, b
  ]
  -- Top face (cyan)
  let r := 0.2; let g := 0.9; let b := 0.9
  let top := #[
    -0.5,  0.5,  0.5,  r, g, b,
     0.5,  0.5,  0.5,  r, g, b,
     0.5,  0.5, -0.5,  r, g, b,
    -0.5,  0.5,  0.5,  r, g, b,
     0.5,  0.5, -0.5,  r, g, b,
    -0.5,  0.5, -0.5,  r, g, b
  ]
  -- Bottom face (magenta)
  let r := 0.9; let g := 0.2; let b := 0.9
  let bottom := #[
    -0.5, -0.5, -0.5,  r, g, b,
     0.5, -0.5, -0.5,  r, g, b,
     0.5, -0.5,  0.5,  r, g, b,
    -0.5, -0.5, -0.5,  r, g, b,
     0.5, -0.5,  0.5,  r, g, b,
    -0.5, -0.5,  0.5,  r, g, b
  ]
  front ++ back ++ right ++ left ++ top ++ bottom

def depthCube : IO Unit := do
  eprintln "=== Depth Cube (3D Spinning Cube with Depth Test) ==="

  setLogCallback fun lvl msg => eprintln s!"[{repr lvl}] {msg}"
  let window ← GLFWwindow.mk 640 480 "Depth Cube"

  let desc ← InstanceDescriptor.mk
  let inst ← createInstance desc
  let surface ← getSurface inst window

  let adapter ← inst.requestAdapter surface >>= await!
  adapter.printProperties

  let ddesc ← DeviceDescriptor.mk "depth cube device"
  let device ← adapter.requestDevice ddesc >>= await!
  device.setUncapturedErrorCallback fun code msg => do
    eprintln s!"uncaptured error, code {code}: \"{msg}\""

  let queue ← device.getQueue

  let texture_format ← TextureFormat.get surface adapter
  let surface_config ← SurfaceConfiguration.mk 640 480 device texture_format
  surface.configure surface_config

  -- Vertex buffer
  let vertexBytes := floatsToByteArray cubeVertices
  let vbDesc := BufferDescriptor.mk "cube vertex buffer"
    (BufferUsage.vertex.lor BufferUsage.copyDst) vertexBytes.size.toUInt32 false
  let vertexBuffer ← Buffer.mk device vbDesc
  queue.writeBuffer vertexBuffer vertexBytes

  -- Uniform buffer: 4x4 matrix = 64 bytes
  let uniformSize : UInt32 := 64
  let ubDesc := BufferDescriptor.mk "mvp uniform"
    (BufferUsage.uniform.lor BufferUsage.copyDst) uniformSize false
  let uniformBuffer ← Buffer.mk device ubDesc

  -- Bind group layout + bind group
  let bindGroupLayout ← BindGroupLayout.mkUniform device 0
    (ShaderStageFlags.vertex) uniformSize.toUInt64
  let bindGroup ← BindGroup.mk device bindGroupLayout 0 uniformBuffer

  -- Pipeline layout
  let pipelineLayout ← PipelineLayout.mk device #[bindGroupLayout]

  -- Shader
  let shaderWGSL ← ShaderModuleWGSLDescriptor.mk cubeShaderSource
  let shaderDesc ← ShaderModuleDescriptor.mk shaderWGSL
  let shaderModule ← ShaderModule.mk device shaderDesc

  -- Pipeline with depth + back-face culling
  let blendState ← BlendState.mk shaderModule
  let colorTargetState ← ColorTargetState.mk texture_format blendState
  let fragmentState ← FragmentState.mk shaderModule colorTargetState

  let layouts : Array VertexBufferLayoutDesc := #[
    { arrayStride := 6 * 4  -- 6 floats: xyz + rgb
      stepMode := .Vertex
      attributes := #[
        { format := .Float32x3, offset := 0,     shaderLocation := 0 },  -- position
        { format := .Float32x3, offset := 3 * 4, shaderLocation := 1 }   -- color
      ] }
  ]

  let pipelineDesc ← RenderPipelineDescriptor.mkFullLayouts shaderModule fragmentState layouts
    (topology := .TriangleList)
    (cullMode := .Back)
    (frontFace := .CCW)
    (enableDepth := true)
  let pipeline ← RenderPipeline.mkWithLayout device pipelineDesc pipelineLayout

  -- Create depth texture + view
  let depthTexture ← Device.createDepthTexture device 640 480
  let depthView ← depthTexture.createDepthView

  let clearColor := Color.mk 0.05 0.05 0.1 1.0

  -- Projection matrix (perspective)
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

    -- Compute MVP
    let t ← GLFW.getTime
    let model := mat4Mul (mat4RotateY (t * 1.5)) (mat4RotateX (t * 0.7))
    let view := mat4LookAt 0 0 3 0 0 0 0 1 0
    let mvp := mat4Mul proj (mat4Mul view model)
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
    renderPassEncoder.draw 36 1 0 0
    renderPassEncoder.end

    let command ← encoder.finish
    queue.submit #[command]
    surface.present
    device.poll

    frameCount := frameCount + 1
    if frameCount % 300 == 0 then
      window.setTitle s!"Depth Cube - {t.toString}s"

  eprintln s!"Rendered {frameCount} frames"
  eprintln "=== Done ==="

def main : IO Unit := depthCube
