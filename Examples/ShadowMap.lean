import Wgpu
import Wgpu.Async
import Glfw

open IO
open Wgpu

set_option linter.unusedVariables false

/-!
  ShadowMap: Basic shadow mapping with a directional light.

  Two-pass rendering:
    Pass 1 — Render scene from light's perspective into a depth-only shadow map.
    Pass 2 — Render scene from camera, sampling the shadow map to determine
              which fragments are in shadow.

  Demonstrates: depth-only render pass, comparison sampler, textureSampleCompare,
  depth texture bind group layout, multi-pipeline rendering, MVP matrices.
  Press ESC/Q to quit.
-/

-- Shadow map resolution
def shadowSize : UInt32 := 512

-- Simple mat4 helpers
def mat4Mul (a b : Array Float) : Array Float := Id.run do
  let mut r := Array.replicate 16 0.0
  for i in [:4] do
    for j in [:4] do
      let mut s := 0.0
      for k in [:4] do
        s := s + a[i*4+k]! * b[k*4+j]!
      r := r.set! (i*4+j) s
  r

def mat4Transpose (m : Array Float) : Array Float := Id.run do
  let mut r := Array.replicate 16 0.0
  for i in [:4] do
    for j in [:4] do
      r := r.set! (i*4+j) m[j*4+i]!
  r

def mat4Perspective (fovy aspect near far : Float) : Array Float :=
  let f := 1.0 / Float.tan (fovy / 2.0)
  let nf := 1.0 / (near - far)
  #[f/aspect,0,0,0, 0,f,0,0, 0,0,far*nf,-1, 0,0,near*far*nf,0]

def mat4Ortho (l r b t n f : Float) : Array Float :=
  let w := r - l; let h := t - b; let d := f - n
  #[2/w,0,0,0, 0,2/h,0,0, 0,0,-1/d,0, -(r+l)/w,-(t+b)/h,-n/d,1]

def mat4LookAt (eye center up : Array Float) : Array Float :=
  let fx := center[0]! - eye[0]!
  let fy := center[1]! - eye[1]!
  let fz := center[2]! - eye[2]!
  let flen := Float.sqrt (fx*fx + fy*fy + fz*fz)
  let fx := fx/flen; let fy := fy/flen; let fz := fz/flen
  let sx := fy*up[2]! - fz*up[1]!
  let sy := fz*up[0]! - fx*up[2]!
  let sz := fx*up[1]! - fy*up[0]!
  let slen := Float.sqrt (sx*sx + sy*sy + sz*sz)
  let sx := sx/slen; let sy := sy/slen; let sz := sz/slen
  let ux := sy*fz - sz*fy
  let uy := sz*fx - sx*fz
  let uz := sx*fy - sy*fx
  #[sx,ux,-fx,0, sy,uy,-fy,0, sz,uz,-fz,0,
    -(sx*eye[0]!+sy*eye[1]!+sz*eye[2]!),
    -(ux*eye[0]!+uy*eye[1]!+uz*eye[2]!),
    -(-fx*eye[0]! + -fy*eye[1]! + -fz*eye[2]!),
    1]

def mat4RotY (angle : Float) : Array Float :=
  let c := Float.cos angle; let s := Float.sin angle
  #[c,0,s,0, 0,1,0,0, -s,0,c,0, 0,0,0,1]

-- Scene geometry: a ground plane + 3 vertical pillars
-- Ground: 4 verts, 2 triangles. Pillars: 8 verts each, 12 tris each (box)
-- Format: position(3) + normal(3) per vertex

def groundVerts : Array Float :=
  -- Two triangles forming a 4x4 ground plane at y=0
  #[ -2,0,-2,  0,1,0,
      2,0,-2,  0,1,0,
      2,0, 2,  0,1,0,
     -2,0,-2,  0,1,0,
      2,0, 2,  0,1,0,
     -2,0, 2,  0,1,0 ]

-- Emit 6 transformed vertices (2 tris) with a shared normal into a Float array.
private def pushFace (d : Array Float) (cx cy cz hx hy hz : Float)
    (v0 v1 v2 v3 v4 v5 : Float × Float × Float) (nx ny nz : Float) : Array Float := Id.run do
  let mut d := d
  for (vx, vy, vz) in [v0, v1, v2, v3, v4, v5] do
    d := d.push (cx + vx * hx)
    d := d.push (cy + vy * hy)
    d := d.push (cz + vz * hz)
    d := d.push nx; d := d.push ny; d := d.push nz
  d

-- Build a box: center (cx,cy,cz), half-extents (hx,hy,hz)
def boxVerts (cx cy cz hx hy hz : Float) : Array Float := Id.run do
  let mut d : Array Float := #[]
  -- front (z+)
  d := pushFace d cx cy cz hx hy hz (-1,-1,1) (1,-1,1) (1,1,1) (-1,-1,1) (1,1,1) (-1,1,1) 0 0 1
  -- back (z-)
  d := pushFace d cx cy cz hx hy hz (1,-1,-1) (-1,-1,-1) (-1,1,-1) (1,-1,-1) (-1,1,-1) (1,1,-1) 0 0 (-1)
  -- right (x+)
  d := pushFace d cx cy cz hx hy hz (1,-1,1) (1,-1,-1) (1,1,-1) (1,-1,1) (1,1,-1) (1,1,1) 1 0 0
  -- left (x-)
  d := pushFace d cx cy cz hx hy hz (-1,-1,-1) (-1,-1,1) (-1,1,1) (-1,-1,-1) (-1,1,1) (-1,1,-1) (-1) 0 0
  -- top (y+)
  d := pushFace d cx cy cz hx hy hz (-1,1,1) (1,1,1) (1,1,-1) (-1,1,1) (1,1,-1) (-1,1,-1) 0 1 0
  -- bottom (y-)
  d := pushFace d cx cy cz hx hy hz (-1,-1,-1) (1,-1,-1) (1,-1,1) (-1,-1,-1) (1,-1,1) (-1,-1,1) 0 (-1) 0
  d

def sceneVertexData : Array Float := Id.run do
  let mut d := groundVerts
  d := d ++ boxVerts (-0.8) 0.5 (-0.3)  0.2 0.5 0.2  -- pillar 1
  d := d ++ boxVerts  0.5  0.35 0.4     0.15 0.35 0.15  -- pillar 2
  d := d ++ boxVerts  0.0  0.7  (-0.8)  0.18 0.7 0.18  -- pillar 3
  d

-- Shadow pass shader: just output depth from light MVP
def shadowShaderSrc : String :=
"struct LightUniforms { light_mvp: mat4x4<f32> }; \
@group(0) @binding(0) var<uniform> light_u: LightUniforms; \
struct VIn { @location(0) pos: vec3f, @location(1) normal: vec3f }; \
@vertex fn vs_shadow(in: VIn) -> @builtin(position) vec4f { \
    return light_u.light_mvp * vec4f(in.pos, 1.0); \
}"

-- Scene pass shader: lit with shadow lookup
def sceneShaderSrc : String :=
"struct SceneUniforms { \
    mvp: mat4x4<f32>, \
    light_mvp: mat4x4<f32>, \
    light_dir: vec3f, \
    _pad: f32, \
}; \
@group(0) @binding(0) var<uniform> scene_u: SceneUniforms; \
@group(1) @binding(0) var shadow_map: texture_depth_2d; \
@group(1) @binding(1) var shadow_sampler: sampler_comparison; \
struct VIn { @location(0) pos: vec3f, @location(1) normal: vec3f }; \
struct VOut { @builtin(position) position: vec4f, @location(0) normal: vec3f, @location(1) shadow_pos: vec3f }; \
@vertex fn vs_main(in: VIn) -> VOut { \
    var out: VOut; \
    out.position = scene_u.mvp * vec4f(in.pos, 1.0); \
    out.normal = in.normal; \
    let light_clip = scene_u.light_mvp * vec4f(in.pos, 1.0); \
    let light_ndc = light_clip.xyz / light_clip.w; \
    out.shadow_pos = vec3f(light_ndc.x * 0.5 + 0.5, 1.0 - (light_ndc.y * 0.5 + 0.5), light_ndc.z); \
    return out; \
} \
@fragment fn fs_main(in: VOut) -> @location(0) vec4f { \
    let n = normalize(in.normal); \
    let ndotl = max(dot(n, -scene_u.light_dir), 0.0); \
    let shadow = textureSampleCompare(shadow_map, shadow_sampler, in.shadow_pos.xy, in.shadow_pos.z - 0.005); \
    let ambient = 0.15; \
    let diffuse = ndotl * shadow; \
    let brightness = ambient + diffuse * 0.85; \
    let ground_color = vec3f(0.6, 0.7, 0.5); \
    let pillar_color = vec3f(0.8, 0.5, 0.3); \
    var color = ground_color; \
    if (abs(n.y) < 0.5) { color = pillar_color; } \
    return vec4f(color * brightness, 1.0); \
}"

def shadowMap : IO Unit := do
  eprintln "=== ShadowMap (directional light shadow mapping) ==="
  setLogCallback fun lvl msg => eprintln s!"[{repr lvl}] {msg}"

  let width  : UInt32 := 800
  let height : UInt32 := 600

  let window ← GLFWwindow.mk width height "Shadow Map"
  let instDesc ← InstanceDescriptor.mk
  let inst ← createInstance instDesc
  let surface ← getSurface inst window
  let adapter ← inst.requestAdapter surface >>= await!
  let ddesc ← DeviceDescriptor.mk "shadow device"
  let device ← adapter.requestDevice ddesc >>= await!
  device.setUncapturedErrorCallback fun t m => eprintln s!"[Device Error] type={t} {m}"
  let queue ← device.getQueue
  let surfFormat ← TextureFormat.get surface adapter
  let config ← SurfaceConfiguration.mk width height device surfFormat
  surface.configure config

  -- Vertex buffer (shared between shadow and scene passes)
  let vertData := sceneVertexData
  let vertCount := vertData.size / 6  -- 6 floats per vert
  let vertBuf ← Buffer.mk device (BufferDescriptor.mk "scene verts" (BufferUsage.vertex.lor BufferUsage.copyDst) (vertData.size.toUInt32 * 4) false)
  queue.writeBuffer vertBuf (floatsToByteArray vertData)

  let vertLayout : Array VertexBufferLayoutDesc := #[
    { arrayStride := 6 * 4
      stepMode := .Vertex
      attributes := #[
        { format := .Float32x3, offset := 0,     shaderLocation := 0 },
        { format := .Float32x3, offset := 3 * 4, shaderLocation := 1 }
      ] }
  ]

  -- === Shadow pass pipeline ===
  let shadowSm ← ShaderModule.mk device (← ShaderModuleDescriptor.mk (← ShaderModuleWGSLDescriptor.mk shadowShaderSrc))
  let lightUnifBuf ← Buffer.mk device (BufferDescriptor.mk "light mvp" (BufferUsage.uniform.lor BufferUsage.copyDst) 64 false)
  let shadowLayout ← BindGroupLayout.mkUniform device 0 ShaderStageFlags.vertex 64
  let shadowBG ← BindGroup.mk device shadowLayout 0 lightUnifBuf 0 64
  let shadowPipeLayout ← PipelineLayout.mk device #[shadowLayout]
  let shadowPipeDesc ← RenderPipelineDescriptor.mkDepthOnly shadowSm vertLayout (cullMode := .Front)
  let shadowPipeline ← RenderPipeline.mkWithLayout device shadowPipeDesc shadowPipeLayout

  -- Shadow map texture (depth only)
  let shadowTex ← Device.createDepthTexture device shadowSize shadowSize
  let shadowView ← shadowTex.createDepthView

  -- === Scene pass pipeline ===
  let sceneSm ← ShaderModule.mk device (← ShaderModuleDescriptor.mk (← ShaderModuleWGSLDescriptor.mk sceneShaderSrc))
  -- group 0: scene uniforms (mvp + light_mvp + light_dir = 128+16=144 bytes, pad to 160)
  let sceneUnifSize : UInt32 := 160
  let sceneUnifBuf ← Buffer.mk device (BufferDescriptor.mk "scene uniforms" (BufferUsage.uniform.lor BufferUsage.copyDst) sceneUnifSize false)
  let sceneUBGL ← BindGroupLayout.mkUniform device 0 ShaderStageFlags.vertex 160
  let sceneUBG ← BindGroup.mk device sceneUBGL 0 sceneUnifBuf 0 160

  -- group 1: shadow map texture + comparison sampler
  let shadowTexLayout ← BindGroupLayout.mkDepthTextureSampler device 0 1 ShaderStageFlags.fragment
  let compSampler ← device.createComparisonSampler
  let shadowTexBG ← BindGroup.mkTextureSampler device shadowTexLayout 0 shadowView 1 compSampler

  let scenePipeLayout ← PipelineLayout.mk device #[sceneUBGL, shadowTexLayout]
  let sceneCTS ← ColorTargetState.mk surfFormat (← BlendState.mk sceneSm)
  let sceneFS ← FragmentState.mk sceneSm sceneCTS
  let scenePipeDesc ← RenderPipelineDescriptor.mkFullLayouts sceneSm sceneFS vertLayout
    (enableDepth := true) (cullMode := .Back)
  let scenePipeline ← RenderPipeline.mkWithLayout device scenePipeDesc scenePipeLayout

  -- Camera depth buffer
  let cameraDepthTex ← Device.createDepthTexture device width height
  let cameraDepthView ← cameraDepthTex.createDepthView

  let clearColor := Color.mk 0.5 0.7 0.9 1.0

  -- Light direction (normalized, pointing down-left-forward)
  let lx := 0.5; let ly := -1.0; let lz := 0.5
  let llen := Float.sqrt (lx*lx + ly*ly + lz*lz)
  let lightDir := #[lx/llen, ly/llen, lz/llen]

  let proj := mat4Perspective (3.14159265 / 4.0) (800.0 / 600.0) 0.1 50.0

  eprintln "  Press ESC or Q to quit"

  while not (← window.shouldClose) do
    GLFW.pollEvents

    let esc ← window.getKey GLFW.keyEscape
    let q ← window.getKey GLFW.keyQ
    if esc == GLFW.press || q == GLFW.press then
      window.setShouldClose true
      continue

    let time ← GLFW.getTime
    let camAngle := time * 0.3

    -- Camera
    let camDist := 5.0
    let camX := Float.cos camAngle * camDist
    let camZ := Float.sin camAngle * camDist
    let view := mat4LookAt #[camX, 3.0, camZ] #[0,0.5,0] #[0,1,0]
    let mvp := mat4Mul proj view

    -- Light view-projection (orthographic, looking down from light direction)
    let lightPos := #[-lightDir[0]! * 4.0, -lightDir[1]! * 4.0, -lightDir[2]! * 4.0]
    let lightView := mat4LookAt lightPos #[0,0,0] #[0,1,0]
    let lightProj := mat4Ortho (-3) 3 (-3) 3 0.1 10.0
    let lightMVP := mat4Mul lightProj lightView

    -- Upload light uniform
    queue.writeBuffer lightUnifBuf (floatsToByteArray (mat4Transpose lightMVP))

    -- Upload scene uniforms: mvp(64) + lightMVP(64) + lightDir(12) + pad(4) = 144, pad to 160
    let sceneData := (mat4Transpose mvp) ++ (mat4Transpose lightMVP) ++
      #[lightDir[0]!, lightDir[1]!, lightDir[2]!, 0.0] ++
      #[0,0,0,0] -- padding to 160 bytes = 40 floats total? No: 16+16+4+4=40 floats = 160 bytes ✓
    queue.writeBuffer sceneUnifBuf (floatsToByteArray sceneData)

    let encoder ← device.createCommandEncoder

    -- Pass 1: Shadow map (depth only from light)
    do
      let rp ← RenderPassEncoder.mkDepthOnly encoder shadowView
      rp.setPipeline shadowPipeline
      rp.setBindGroup 0 shadowBG
      rp.setVertexBuffer 0 vertBuf
      rp.draw vertCount.toUInt32 1 0 0
      rp.end
      rp.release

    -- Pass 2: Scene with shadow lookup
    do
      let texture ← surface.getCurrent
      if (← texture.status) != .success then continue
      let surfView ← TextureView.mk texture

      let rp ← RenderPassEncoder.mkWithDepth encoder surfView clearColor cameraDepthView
      rp.setPipeline scenePipeline
      rp.setBindGroup 0 sceneUBG
      rp.setBindGroup 1 shadowTexBG
      rp.setVertexBuffer 0 vertBuf
      rp.draw vertCount.toUInt32 1 0 0
      rp.end
      rp.release

      let cmd ← encoder.finish
      queue.submit #[cmd]
      surface.present
    device.poll

  eprintln "=== Done ==="

def main : IO Unit := shadowMap
