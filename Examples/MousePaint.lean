import Wgpu
import Wgpu.Async
import Glfw
import Wgsl.Syntax

open IO
open Wgpu

set_option linter.unusedVariables false

/--
  MousePaint: Interactive painting with the mouse. Click and drag to paint colored dots.
  Tests: dynamic vertex buffer updates, mouse input (getCursorPos, getMouseButton),
  keyboard input (C to clear, 1-5 for colors), PointList topology (drawn as triangles).
-/

def paintShaderSource : String := !WGSL{
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
    var out: VertexOutput;
    out.position = vec4f(in.position, 0.0, 1.0);
    out.color = in.color;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4f {
    return vec4f(in.color, 1.0);
}
}

-- Each brush stamp creates a small quad (2 triangles = 6 vertices)
-- at the cursor position with the current color.
-- vertex: pos2 + color3 = 5 floats
structure BrushState where
  vertices : Array Float  -- accumulator for all painted quads
  colorR : Float
  colorG : Float
  colorB : Float
  prevDown : Bool         -- was mouse pressed last frame?
  deriving Inhabited

def maxVertices : Nat := 60000 -- 10000 quads * 6 verts

/-- Add a small quad at (cx, cy) in NDC space. -/
def addBrushQuad (state : BrushState) (cx cy : Float) (brushSize : Float := 0.015) : BrushState :=
  if state.vertices.size / 5 + 6 > maxVertices then state
  else
    let r := state.colorR
    let g := state.colorG
    let b := state.colorB
    let s := brushSize
    let v := state.vertices
    -- Two triangles forming a quad centered at (cx, cy)
    let v := v ++ #[cx - s, cy - s, r, g, b,
                     cx + s, cy - s, r, g, b,
                     cx + s, cy + s, r, g, b,
                     cx - s, cy - s, r, g, b,
                     cx + s, cy + s, r, g, b,
                     cx - s, cy + s, r, g, b]
    { state with vertices := v }

def mousePaint : IO Unit := do
  eprintln "=== MousePaint (Interactive Painting) ==="
  eprintln "  Left-click to paint. Keys: C=clear, 1=red, 2=green, 3=blue, 4=yellow, 5=white"

  setLogCallback fun lvl msg => eprintln s!"[{repr lvl}] {msg}"
  let window ← GLFWwindow.mk 640 480 "MousePaint"

  let desc ← InstanceDescriptor.mk
  let inst ← createInstance desc
  let surface ← getSurface inst window

  let adapter ← inst.requestAdapter surface >>= await!
  let ddesc ← DeviceDescriptor.mk "paint device"
  let device ← adapter.requestDevice ddesc >>= await!
  device.setUncapturedErrorCallback fun code msg => do
    eprintln s!"uncaptured error, code {code}: \"{msg}\""

  let queue ← device.getQueue
  let texture_format ← TextureFormat.get surface adapter
  let surface_config ← SurfaceConfiguration.mk 640 480 device texture_format
  surface.configure surface_config

  -- Shader
  let shaderWGSL ← ShaderModuleWGSLDescriptor.mk paintShaderSource
  let shaderDesc ← ShaderModuleDescriptor.mk shaderWGSL
  let shaderModule ← ShaderModule.mk device shaderDesc

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

  let pipelineDesc ← RenderPipelineDescriptor.mkFullLayouts shaderModule fragmentState layouts
    (topology := .TriangleList)
    (cullMode := .None)
  let pipeline ← RenderPipeline.mk device pipelineDesc

  -- Large vertex buffer for all painted quads
  let bufSize : UInt32 := (maxVertices * 5 * 4).toUInt32  -- 5 floats * 4 bytes each
  let vbDesc := BufferDescriptor.mk "paint vertex buffer"
    (BufferUsage.vertex.lor BufferUsage.copyDst) bufSize false
  let vertexBuffer ← Buffer.mk device vbDesc

  let clearColor := Color.mk 0.95 0.95 0.92 1.0

  let mut state : BrushState := { vertices := #[], colorR := 0.9, colorG := 0.2, colorB := 0.2, prevDown := false }

  eprintln "Entering render loop (press Q or Escape to quit)..."

  let mut frameCount : UInt32 := 0
  while not (← window.shouldClose) do
    GLFW.pollEvents

    let esc ← window.getKey GLFW.keyEscape
    let q ← window.getKey GLFW.keyQ
    if esc == GLFW.press || q == GLFW.press then
      window.setShouldClose true
      continue

    -- Color selection via number keys (key codes for '1'..'5' are 49..53)
    let k1 ← window.getKey 49
    let k2 ← window.getKey 50
    let k3 ← window.getKey 51
    let k4 ← window.getKey 52
    let k5 ← window.getKey 53
    if k1 == GLFW.press then state := { state with colorR := 0.9, colorG := 0.2, colorB := 0.2 }
    if k2 == GLFW.press then state := { state with colorR := 0.2, colorG := 0.9, colorB := 0.2 }
    if k3 == GLFW.press then state := { state with colorR := 0.2, colorG := 0.2, colorB := 0.9 }
    if k4 == GLFW.press then state := { state with colorR := 0.9, colorG := 0.9, colorB := 0.2 }
    if k5 == GLFW.press then state := { state with colorR := 1.0, colorG := 1.0, colorB := 1.0 }

    -- Clear on C key (key code 67)
    let kC ← window.getKey 67
    if kC == GLFW.press then state := { state with vertices := #[] }

    -- Mouse painting
    let mouseBtn ← window.getMouseButton GLFW.mouseButtonLeft
    let mouseDown := mouseBtn == GLFW.press
    if mouseDown then
      let (mx, my) ← window.getCursorPos
      -- Convert pixel coords to NDC [-1, 1]
      let ndcX := mx / 640.0 * 2.0 - 1.0
      let ndcY := -(my / 480.0 * 2.0 - 1.0)  -- flip Y
      state := addBrushQuad state ndcX ndcY
    state := { state with prevDown := mouseDown }

    -- Upload vertices if any
    let numVerts := state.vertices.size / 5
    if numVerts > 0 then
      let vertBytes := floatsToByteArray state.vertices
      queue.writeBuffer vertexBuffer vertBytes

    let texture ← surface.getCurrent
    let status ← texture.status
    if (status != .success) then continue
    let targetView ← TextureView.mk texture
    if !(← targetView.is_valid) then continue

    let encoder ← device.createCommandEncoder
    let renderPassEncoder ← RenderPassEncoder.mkWithColor encoder targetView clearColor
    renderPassEncoder.setPipeline pipeline
    if numVerts > 0 then
      renderPassEncoder.setVertexBuffer 0 vertexBuffer
      renderPassEncoder.draw numVerts.toUInt32 1 0 0
    renderPassEncoder.end

    let command ← encoder.finish
    queue.submit #[command]
    surface.present
    device.poll

    frameCount := frameCount + 1
    if frameCount % 300 == 0 then
      window.setTitle s!"MousePaint - {numVerts / 6} dots"

  eprintln s!"Rendered {frameCount} frames, {state.vertices.size / 5 / 6} dots painted"
  eprintln "=== Done ==="

def main : IO Unit := mousePaint
