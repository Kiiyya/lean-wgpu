import Wgpu
import Wgpu.Async
import Glfw

open IO
open Wgpu

set_option linter.unusedVariables false

/--
  BouncingBalls: Animated bouncing balls with simple physics (gravity + wall bouncing).
  Updated on CPU each frame and rendered with instancing.
  Tests: per-frame CPU physics, dynamic buffer update, instancing, TriangleStrip
  (for circle approximation), and keyboard interactivity (Space to add balls).
-/

def ballShaderSource : String :=
"struct Uniforms { \
    screenSize: vec2f, \
    _pad: vec2f, \
}; \
 \
@group(0) @binding(0) var<uniform> uniforms: Uniforms; \
 \
struct VertexInput { \
    @location(0) localPos: vec2f, \
    @location(1) center: vec2f, \
    @location(2) radius: f32, \
    @location(3) color: vec3f, \
}; \
 \
struct VertexOutput { \
    @builtin(position) position: vec4f, \
    @location(0) color: vec3f, \
    @location(1) localUV: vec2f, \
}; \
 \
@vertex \
fn vs_main(in: VertexInput) -> VertexOutput { \
    let worldPos = in.center + in.localPos * in.radius; \
    let ndc = worldPos / uniforms.screenSize * 2.0 - 1.0; \
    var out: VertexOutput; \
    out.position = vec4f(ndc.x, -ndc.y, 0.0, 1.0); \
    out.color = in.color; \
    out.localUV = in.localPos; \
    return out; \
} \
 \
@fragment \
fn fs_main(in: VertexOutput) -> @location(0) vec4f { \
    let dist = length(in.localUV); \
    if (dist > 1.0) { discard; } \
    let edge = smoothstep(0.9, 1.0, dist); \
    let brightness = 1.0 - edge * 0.5; \
    return vec4f(in.color * brightness, 1.0); \
}"

-- Circle mesh: a triangle fan as triangle list (N triangles)
def mkCircleVertices (segments : Nat) : Array Float := Id.run do
  let mut verts : Array Float := #[]
  let pi := 3.14159265
  for i in [:segments] do
    let a0 := 2.0 * pi * i.toFloat / segments.toFloat
    let a1 := 2.0 * pi * (i + 1).toFloat / segments.toFloat
    -- Center
    verts := verts.push 0.0; verts := verts.push 0.0
    -- Point 1
    verts := verts.push (Float.cos a0); verts := verts.push (Float.sin a0)
    -- Point 2
    verts := verts.push (Float.cos a1); verts := verts.push (Float.sin a1)
  return verts

structure Ball where
  x : Float
  y : Float
  vx : Float
  vy : Float
  radius : Float
  r : Float
  g : Float
  b : Float
  deriving Inhabited

def screenW : Float := 640.0
def screenH : Float := 480.0
def gravity : Float := 300.0
def damping : Float := 0.85
def maxBalls : Nat := 200

-- Helper: float modulo
def fmod (a b : Float) : Float :=
  a - Float.floor (a / b) * b

-- Generate initial balls
def mkInitialBalls (n : Nat) : Array Ball := Id.run do
  let mut balls : Array Ball := #[]
  for i in [:n] do
    let fi := i.toFloat
    let ball : Ball := {
      x := 50.0 + fmod (fi * 73.0) (screenW - 100.0)
      y := 50.0 + fmod (fi * 47.0) (screenH / 2.0)
      vx := fmod (fi * 31.0) 200.0 - 100.0
      vy := fmod (fi * 17.0) 100.0 - 50.0
      radius := 10.0 + fmod (fi * 7.0) 15.0
      r := 0.3 + fmod (fi * 0.13) 0.7
      g := 0.3 + fmod (fi * 0.17) 0.7
      b := 0.3 + fmod (fi * 0.23) 0.7
    }
    balls := balls.push ball
  return balls

-- Physics step
def stepBall (b : Ball) (dt : Float) : Ball :=
  let vy := b.vy + gravity * dt
  let x := b.x + b.vx * dt
  let y := b.y + vy * dt
  -- Bounce off walls
  let (x, vx) :=
    if x - b.radius < 0 then (b.radius, Float.abs b.vx * damping)
    else if x + b.radius > screenW then (screenW - b.radius, -(Float.abs b.vx) * damping)
    else (x, b.vx)
  -- Bounce off floor/ceiling
  let (y, vy) :=
    if y + b.radius > screenH then (screenH - b.radius, -(Float.abs vy) * damping)
    else if y - b.radius < 0 then (b.radius, Float.abs vy * damping)
    else (y, vy)
  { b with x, y, vx, vy }

-- Pack per-instance data: center(2) + radius(1) + color(3) = 6 floats per ball
def packBallInstances (balls : Array Ball) : Array Float := Id.run do
  let mut data : Array Float := #[]
  for b in balls do
    data := data.push b.x; data := data.push b.y
    data := data.push b.radius
    data := data.push b.r; data := data.push b.g; data := data.push b.b
  return data

def bouncingBalls : IO Unit := do
  eprintln "=== BouncingBalls (Physics + Instancing) ==="
  eprintln "  Space = add ball, R = reset, Q/Escape = quit"

  setLogCallback fun lvl msg => eprintln s!"[{repr lvl}] {msg}"
  let window ← GLFWwindow.mk 640 480 "Bouncing Balls"

  let desc ← InstanceDescriptor.mk
  let inst ← createInstance desc
  let surface ← getSurface inst window

  let adapter ← inst.requestAdapter surface >>= await!
  let ddesc ← DeviceDescriptor.mk "balls device"
  let device ← adapter.requestDevice ddesc >>= await!
  device.setUncapturedErrorCallback fun code msg => do
    eprintln s!"uncaptured error, code {code}: \"{msg}\""

  let queue ← device.getQueue
  let texture_format ← TextureFormat.get surface adapter
  let surface_config ← SurfaceConfiguration.mk 640 480 device texture_format
  surface.configure surface_config

  -- Circle mesh (per-vertex): 24 segments * 3 verts * 2 floats
  let circleSegs := 24
  let circleVerts := mkCircleVertices circleSegs
  let circleVertCount := circleSegs * 3
  let circleBytes := floatsToByteArray circleVerts

  let vbDesc := BufferDescriptor.mk "circle vertex buffer"
    (BufferUsage.vertex.lor BufferUsage.copyDst) circleBytes.size.toUInt32 false
  let circleVB ← Buffer.mk device vbDesc
  queue.writeBuffer circleVB circleBytes

  -- Instance buffer (dynamic, max balls * 6 floats * 4 bytes)
  let instanceBufSize : UInt32 := (maxBalls * 6 * 4).toUInt32
  let ibDesc := BufferDescriptor.mk "instance buffer"
    (BufferUsage.vertex.lor BufferUsage.copyDst) instanceBufSize false
  let instanceVB ← Buffer.mk device ibDesc

  -- Uniform buffer: screen size (vec2) + padding = 16 bytes
  let uniformSize : UInt32 := 16
  let ubDesc := BufferDescriptor.mk "screen uniform"
    (BufferUsage.uniform.lor BufferUsage.copyDst) uniformSize false
  let uniformBuf ← Buffer.mk device ubDesc
  let uniformData := floatsToByteArray #[screenW, screenH, 0, 0]
  queue.writeBuffer uniformBuf uniformData

  let bindGroupLayout ← BindGroupLayout.mkUniform device 0
    ShaderStageFlags.vertex uniformSize.toUInt64
  let bindGroup ← BindGroup.mk device bindGroupLayout 0 uniformBuf
  let pipelineLayout ← PipelineLayout.mk device #[bindGroupLayout]

  -- Shader + pipeline
  let shaderWGSL ← ShaderModuleWGSLDescriptor.mk ballShaderSource
  let shaderDesc ← ShaderModuleDescriptor.mk shaderWGSL
  let shaderModule ← ShaderModule.mk device shaderDesc

  let blendState ← BlendState.mk shaderModule
  let cts ← ColorTargetState.mk texture_format blendState
  let fragState ← FragmentState.mk shaderModule cts

  let layouts : Array VertexBufferLayoutDesc := #[
    -- Buffer 0: per-vertex circle mesh
    { arrayStride := 2 * 4
      stepMode := .Vertex
      attributes := #[
        { format := .Float32x2, offset := 0, shaderLocation := 0 }  -- localPos
      ] },
    -- Buffer 1: per-instance ball data
    { arrayStride := 6 * 4
      stepMode := .Instance
      attributes := #[
        { format := .Float32x2, offset := 0,     shaderLocation := 1 },  -- center
        { format := .Float32,   offset := 2 * 4, shaderLocation := 2 },  -- radius
        { format := .Float32x3, offset := 3 * 4, shaderLocation := 3 }   -- color
      ] }
  ]

  let pipeDesc ← RenderPipelineDescriptor.mkFullLayouts shaderModule fragState layouts
    (topology := .TriangleList)
    (cullMode := .None)
  let pipeline ← RenderPipeline.mkWithLayout device pipeDesc pipelineLayout

  let clearColor := Color.mk 0.12 0.12 0.18 1.0

  let mut balls := mkInitialBalls 20
  let mut prevTime ← GLFW.getTime
  let mut spaceWasPressed := false

  eprintln "Entering render loop..."

  let mut frameCount : UInt32 := 0
  while not (← window.shouldClose) do
    GLFW.pollEvents

    let esc ← window.getKey GLFW.keyEscape
    let q ← window.getKey GLFW.keyQ
    if esc == GLFW.press || q == GLFW.press then
      window.setShouldClose true
      continue

    -- Add ball on Space press (edge-triggered)
    let spaceKey ← window.getKey GLFW.keySpace
    let spacePressed := spaceKey == GLFW.press
    if spacePressed && !spaceWasPressed && balls.size < maxBalls then
      let (mx, my) ← window.getCursorPos
      let newBall : Ball := {
        x := mx, y := my
        vx := 0.0, vy := -200.0
        radius := 12.0 + fmod (balls.size.toFloat * 3.0) 10.0
        r := 0.9, g := 0.9, b := 0.3
      }
      balls := balls.push newBall
    spaceWasPressed := spacePressed

    -- Reset on R
    let rKey ← window.getKey GLFW.keyR
    if rKey == GLFW.press then
      balls := mkInitialBalls 20

    -- Physics
    let now ← GLFW.getTime
    let dt := if now - prevTime > 0.05 then 0.05 else now - prevTime  -- cap dt
    prevTime := now

    balls := balls.map (stepBall · dt)

    -- Upload instance data
    let instanceData := packBallInstances balls
    let instanceBytes := floatsToByteArray instanceData
    queue.writeBuffer instanceVB instanceBytes

    let texture ← surface.getCurrent
    let status ← texture.status
    if (status != .success) then continue
    let targetView ← TextureView.mk texture
    if !(← targetView.is_valid) then continue

    let encoder ← device.createCommandEncoder
    let renderPass ← RenderPassEncoder.mkWithColor encoder targetView clearColor
    renderPass.setPipeline pipeline
    renderPass.setBindGroup 0 bindGroup
    renderPass.setVertexBuffer 0 circleVB
    renderPass.setVertexBuffer 1 instanceVB
    renderPass.draw circleVertCount.toUInt32 balls.size.toUInt32 0 0
    renderPass.end

    let command ← encoder.finish
    queue.submit #[command]
    surface.present
    device.poll

    frameCount := frameCount + 1
    if frameCount % 300 == 0 then
      window.setTitle s!"Bouncing Balls ({balls.size}) - {now.toString}s"

  eprintln s!"Rendered {frameCount} frames, {balls.size} balls"
  eprintln "=== Done ==="

def main : IO Unit := bouncingBalls
