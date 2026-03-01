import Wgpu
import Wgpu.Async
import Glfw

open IO
open Wgpu

set_option linter.unusedVariables false

/-!
  Wireframe: Renders a spinning icosahedron with solid fill + wireframe overlay.

  Two render passes per frame:
    Pass 1 — Solid triangles with per-face colors + depth
    Pass 2 — Wireframe edges in white, drawn on top with depth bias

  Demonstrates: dual-pipeline rendering, LineList topology, depth buffer,
  vertex buffers with custom layouts, MVP matrices.
  Press ESC/Q to quit.
-/

def solidShader : String :=
"struct Uniforms { mvp: mat4x4<f32> }; \
@group(0) @binding(0) var<uniform> u: Uniforms; \
struct VIn { @location(0) pos: vec3f, @location(1) color: vec3f }; \
struct VOut { @builtin(position) position: vec4f, @location(0) color: vec3f }; \
@vertex fn vs_main(in: VIn) -> VOut { \
    var out: VOut; out.position = u.mvp * vec4f(in.pos, 1.0); out.color = in.color; return out; \
} \
@fragment fn fs_main(in: VOut) -> @location(0) vec4f { return vec4f(in.color, 1.0); }"

def wireShader : String :=
"struct Uniforms { mvp: mat4x4<f32> }; \
@group(0) @binding(0) var<uniform> u: Uniforms; \
struct VIn { @location(0) pos: vec3f }; \
struct VOut { @builtin(position) position: vec4f }; \
@vertex fn vs_main(in: VIn) -> VOut { \
    var out: VOut; out.position = u.mvp * vec4f(in.pos, 1.0); \
    out.position.z = out.position.z - 0.0005; \
    return out; \
} \
@fragment fn fs_main() -> @location(0) vec4f { return vec4f(1.0, 1.0, 1.0, 1.0); }"

-- Simple math helpers
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

def mat4RotY (angle : Float) : Array Float :=
  let c := Float.cos angle; let s := Float.sin angle
  -- Column-major
  #[c, 0, -s, 0,  0, 1, 0, 0,  s, 0, c, 0,  0, 0, 0, 1]

def mat4RotX (angle : Float) : Array Float :=
  let c := Float.cos angle; let s := Float.sin angle
  -- Column-major
  #[1, 0, 0, 0,  0, c, s, 0,  0, -s, c, 0,  0, 0, 0, 1]

def mat4Translate (_x _y _z : Float) : Array Float :=
  #[1,0,0,0, 0,1,0,0, 0,0,1,0, _x,_y,_z,1]

def mat4Perspective (fovy aspect near far : Float) : Array Float :=
  let f := 1.0 / Float.tan (fovy / 2.0)
  let nf := 1.0 / (near - far)
  #[f/aspect,0,0,0, 0,f,0,0, 0,0,far*nf,-1, 0,0,near*far*nf,0]


-- Icosahedron: 12 vertices, 20 triangles
-- Golden ratio
def phi : Float := 1.6180339887

def icoVertices : Array Float :=
  let n := Float.sqrt (1.0 + phi * phi) -- normalize factor
  let a := 1.0 / n
  let b := phi / n
  -- 12 verts: permutations of (0, ±a, ±b)
  #[ -a, b, 0,   a, b, 0,   -a,-b, 0,    a,-b, 0,
      0,-a, b,   0, a, b,    0,-a,-b,     0, a,-b,
      b, 0,-a,   b, 0, a,   -b, 0,-a,    -b, 0, a ]

def icoTriangles : Array UInt32 :=
  #[0,11,5, 0,5,1, 0,1,7, 0,7,10, 0,10,11,
    1,5,9, 5,11,4, 11,10,2, 10,7,6, 7,1,8,
    3,9,4, 3,4,2, 3,2,6, 3,6,8, 3,8,9,
    4,9,5, 2,4,11, 6,2,10, 8,6,7, 9,8,1]

-- Build solid vertex buffer: pos3 + color3 per vertex (using triangle index)
def buildSolidVertexData : Array Float := Id.run do
  let mut data : Array Float := #[]
  let faceColors : Array (Float × Float × Float) := #[
    (0.9,0.3,0.2),(0.2,0.9,0.3),(0.3,0.2,0.9),(0.9,0.9,0.2),(0.9,0.2,0.9),
    (0.2,0.9,0.9),(0.7,0.5,0.2),(0.2,0.5,0.7),(0.7,0.2,0.5),(0.5,0.7,0.2),
    (0.8,0.4,0.6),(0.6,0.8,0.4),(0.4,0.6,0.8),(0.9,0.6,0.3),(0.3,0.9,0.6),
    (0.6,0.3,0.9),(0.8,0.8,0.5),(0.5,0.8,0.8),(0.8,0.5,0.8),(0.7,0.7,0.7)
  ]
  for face in [:20] do
    let (cr, cg, cb) := faceColors[face]!
    for vert in [:3] do
      let idx := icoTriangles[face * 3 + vert]!.toNat
      data := data.push icoVertices[idx*3]!
      data := data.push icoVertices[idx*3+1]!
      data := data.push icoVertices[idx*3+2]!
      data := data.push cr
      data := data.push cg
      data := data.push cb
  data

-- Build wireframe edge list (line-list): 3 edges per face, deduplicated
def buildWireVertexData : Array Float := Id.run do
  let mut edges : Array (UInt32 × UInt32) := #[]
  for face in [:20] do
    for e in [:3] do
      let a := icoTriangles[face * 3 + e]!
      let b := icoTriangles[face * 3 + (e + 1) % 3]!
      let lo := if a < b then a else b
      let hi := if a < b then b else a
      -- Check for duplicate
      let mut found := false
      for existing in edges do
        if existing.1 == lo && existing.2 == hi then
          found := true
      if !found then
        edges := edges.push (lo, hi)
  -- Now build vertex data: 2 vertices per edge, pos only
  let mut data : Array Float := #[]
  for (a, b) in edges do
    let ai := a.toNat
    let bi := b.toNat
    data := data.push icoVertices[ai*3]!
    data := data.push icoVertices[ai*3+1]!
    data := data.push icoVertices[ai*3+2]!
    data := data.push icoVertices[bi*3]!
    data := data.push icoVertices[bi*3+1]!
    data := data.push icoVertices[bi*3+2]!
  data

def wireframe : IO Unit := do
  eprintln "=== Wireframe (Solid + Wire overlay on Icosahedron) ==="
  setLogCallback fun lvl msg => eprintln s!"[{repr lvl}] {msg}"

  let width  : UInt32 := 800
  let height : UInt32 := 600

  let window ← GLFWwindow.mk width height "Wireframe Icosahedron"
  let instDesc ← InstanceDescriptor.mk
  let inst ← createInstance instDesc
  let surface ← getSurface inst window
  let adapter ← inst.requestAdapter surface >>= await!
  let ddesc ← DeviceDescriptor.mk "wire device"
  let device ← adapter.requestDevice ddesc >>= await!
  device.setUncapturedErrorCallback fun t m => eprintln s!"[Device Error] type={t} {m}"
  let queue ← device.getQueue
  let surfFormat ← TextureFormat.get surface adapter
  let config ← SurfaceConfiguration.mk width height device surfFormat
  surface.configure config

  -- MVP uniform
  let unifBuf ← Buffer.mk device (BufferDescriptor.mk "mvp" (BufferUsage.uniform.lor BufferUsage.copyDst) 64 false)
  let uLayout ← BindGroupLayout.mkUniform device 0 ShaderStageFlags.vertex 64
  let uBG ← BindGroup.mk device uLayout 0 unifBuf 0 64
  let pipeLayout ← PipelineLayout.mk device #[uLayout]

  -- Solid pipeline (TriangleList, pos3+color3)
  let solidSm ← ShaderModule.mk device (← ShaderModuleDescriptor.mk (← ShaderModuleWGSLDescriptor.mk solidShader))
  let solidCTS ← ColorTargetState.mk surfFormat (← BlendState.mk solidSm)
  let solidFS ← FragmentState.mk solidSm solidCTS
  let solidLayouts : Array VertexBufferLayoutDesc := #[
    { arrayStride := 6 * 4
      stepMode := .Vertex
      attributes := #[
        { format := .Float32x3, offset := 0,     shaderLocation := 0 },
        { format := .Float32x3, offset := 3 * 4, shaderLocation := 1 }
      ] }
  ]
  let solidPipeDesc ← RenderPipelineDescriptor.mkFullLayouts solidSm solidFS solidLayouts
    (topology := .TriangleList) (cullMode := .Back) (frontFace := .CCW) (enableDepth := true)
  let solidPipeline ← RenderPipeline.mkWithLayout device solidPipeDesc pipeLayout

  -- Wireframe pipeline (LineList, pos3 only, depth-tested with z-bias in shader)
  let wireSm ← ShaderModule.mk device (← ShaderModuleDescriptor.mk (← ShaderModuleWGSLDescriptor.mk wireShader))
  let wireCTS ← ColorTargetState.mk surfFormat (← BlendState.mk wireSm)
  let wireFS ← FragmentState.mk wireSm wireCTS
  let wireLayouts : Array VertexBufferLayoutDesc := #[
    { arrayStride := 3 * 4
      stepMode := .Vertex
      attributes := #[
        { format := .Float32x3, offset := 0, shaderLocation := 0 }
      ] }
  ]
  let wirePipeDesc ← RenderPipelineDescriptor.mkFullLayouts wireSm wireFS wireLayouts
    (topology := .LineList) (enableDepth := true)
  let wirePipeline ← RenderPipeline.mkWithLayout device wirePipeDesc pipeLayout

  -- Vertex buffers
  let solidVerts := buildSolidVertexData
  let solidVertBuf ← Buffer.mk device (BufferDescriptor.mk "solid verts" (BufferUsage.vertex.lor BufferUsage.copyDst) (solidVerts.size.toUInt32 * 4) false)
  queue.writeBuffer solidVertBuf (floatsToByteArray solidVerts)
  let solidVertCount : UInt32 := 60  -- 20 faces × 3 verts

  let wireVerts := buildWireVertexData
  let wireVertBuf ← Buffer.mk device (BufferDescriptor.mk "wire verts" (BufferUsage.vertex.lor BufferUsage.copyDst) (wireVerts.size.toUInt32 * 4) false)
  queue.writeBuffer wireVertBuf (floatsToByteArray wireVerts)
  let wireVertCount : UInt32 := wireVerts.size.toUInt32 / 3  -- 2 verts per edge, 3 floats per vert

  -- Depth buffer
  let depthTex ← Device.createDepthTexture device width height
  let depthView ← depthTex.createDepthView

  let proj := mat4Perspective (3.14159265 / 4.0) (800.0 / 600.0) 0.1 100.0
  let clearColor := Color.mk 0.06 0.06 0.1 1.0

  eprintln "  Press ESC or Q to quit"

  while not (← window.shouldClose) do
    GLFW.pollEvents

    let esc ← window.getKey GLFW.keyEscape
    let q ← window.getKey GLFW.keyQ
    if esc == GLFW.press || q == GLFW.press then
      window.setShouldClose true
      continue

    let time ← GLFW.getTime

    let model := mat4Mul (mat4RotY (time * 0.7)) (mat4RotX (time * 0.5))
    let view := mat4Translate 0 0 (-3.0)
    let mvp := mat4Mul proj (mat4Mul view model)
    queue.writeBuffer unifBuf (floatsToByteArray mvp)

    let texture ← surface.getCurrent
    if (← texture.status) != .success then continue
    let surfView ← TextureView.mk texture

    let encoder ← device.createCommandEncoder

    -- Pass 1: solid triangles (clear + draw)
    do
      let rp ← RenderPassEncoder.mkWithDepth encoder surfView clearColor depthView
      rp.setPipeline solidPipeline
      rp.setBindGroup 0 uBG
      rp.setVertexBuffer 0 solidVertBuf
      rp.draw solidVertCount 1 0 0
      rp.end
      rp.release

    -- Pass 2: wireframe overlay (load color+depth from pass 1, z-bias in shader)
    do
      let rp ← RenderPassEncoder.mkLoadWithDepth encoder surfView depthView
      rp.setPipeline wirePipeline
      rp.setBindGroup 0 uBG
      rp.setVertexBuffer 0 wireVertBuf
      rp.draw wireVertCount 1 0 0
      rp.end
      rp.release

    let cmd ← encoder.finish
    queue.submit #[cmd]
    surface.present
    device.poll

  eprintln "=== Done ==="

def main : IO Unit := wireframe
