import Wgpu
import Wgpu.Async
import Glfw

open IO
open Wgpu

set_option linter.unusedVariables false

/--
  RayTracer: A real-time compute-shader software ray tracer.

  Renders a scene with reflective spheres on a checkerboard ground plane.
  The camera orbits the scene over time. Features:
  - Per-pixel ray casting from a perspective camera
  - 5 spheres with different colors, specularity, and reflectivity
  - Infinite checkerboard ground plane
  - Phong shading with a point light
  - Hard shadows (shadow rays)
  - Up to 3 bounces of mirror-like reflections
  - Gamma correction
  - Sky gradient background

  Architecture:
  - Compute pipeline: @group(0) = uniform camera, @group(1) = storage pixel buffer
  - Render pipeline: @group(0) = fullscreen quad reading pixel buffer + resolution uniform
  Press Q or Escape to exit.
-/

-- ═══════════════════════════════════════════════════════════════════
-- Compute shader: ray traces the scene, writes packed RGBA u32 per pixel
-- ═══════════════════════════════════════════════════════════════════
def rtComputeSource : String :=
"struct Uniforms { \
    eyeX: f32, eyeY: f32, eyeZ: f32, time: f32, \
    targetX: f32, targetY: f32, targetZ: f32, _pad: f32, \
    width: f32, height: f32, _p2: f32, _p3: f32, \
}; \
 \
@group(0) @binding(0) var<uniform> u: Uniforms; \
@group(1) @binding(0) var<storage, read_write> pixels: array<u32>; \
 \
const INF: f32 = 1e20; \
const EPS: f32 = 0.001; \
const MAX_BOUNCES: i32 = 3; \
const N_SPHERES: i32 = 5; \
 \
struct Sphere { center: vec3f, radius: f32, color: vec3f, spec: f32, refl: f32 }; \
struct Hit { t: f32, pos: vec3f, nor: vec3f, col: vec3f, spec: f32, refl: f32 }; \
 \
fn sphere(i: i32) -> Sphere { \
    var s: Sphere; \
    switch(i) { \
        case 0 { s = Sphere(vec3f( 0.0, 1.0,  0.0), 1.0,  vec3f(0.9,0.2,0.2),  64.0, 0.4); } \
        case 1 { s = Sphere(vec3f( 2.5, 0.6,  1.5), 0.6,  vec3f(0.2,0.9,0.3),  32.0, 0.3); } \
        case 2 { s = Sphere(vec3f(-2.0, 0.8,  1.0), 0.8,  vec3f(0.2,0.3,0.95), 128.0,0.5); } \
        case 3 { s = Sphere(vec3f( 1.0, 0.4, -2.0), 0.4,  vec3f(0.95,0.85,0.2), 16.0,0.2); } \
        default { s = Sphere(vec3f(-1.5, 0.35,-1.5), 0.35, vec3f(0.9,0.5,0.95), 48.0,0.6); } \
    } \
    return s; \
} \
 \
fn hitSphere(ro: vec3f, rd: vec3f, s: Sphere) -> f32 { \
    let oc = ro - s.center; \
    let b = dot(oc, rd); \
    let c = dot(oc, oc) - s.radius * s.radius; \
    let d = b * b - c; \
    if (d < 0.0) { return INF; } \
    let sq = sqrt(d); \
    let t0 = -b - sq; \
    if (t0 > EPS) { return t0; } \
    let t1 = -b + sq; \
    if (t1 > EPS) { return t1; } \
    return INF; \
} \
 \
fn hitPlane(ro: vec3f, rd: vec3f) -> f32 { \
    if (abs(rd.y) < EPS) { return INF; } \
    let t = -ro.y / rd.y; \
    if (t > EPS) { return t; } \
    return INF; \
} \
 \
fn checker(p: vec3f) -> vec3f { \
    if ((i32(floor(p.x)) + i32(floor(p.z))) % 2 == 0) { \
        return vec3f(0.92, 0.92, 0.92); \
    } \
    return vec3f(0.18, 0.18, 0.18); \
} \
 \
fn traceScene(ro: vec3f, rd: vec3f) -> Hit { \
    var h: Hit; \
    h.t = INF; \
    for (var i: i32 = 0; i < N_SPHERES; i++) { \
        let s = sphere(i); \
        let t = hitSphere(ro, rd, s); \
        if (t < h.t) { \
            h.t = t; \
            h.pos = ro + rd * t; \
            h.nor = normalize(h.pos - s.center); \
            h.col = s.color; h.spec = s.spec; h.refl = s.refl; \
        } \
    } \
    let tP = hitPlane(ro, rd); \
    if (tP < h.t) { \
        h.t = tP; \
        h.pos = ro + rd * tP; \
        h.nor = vec3f(0.0, 1.0, 0.0); \
        h.col = checker(h.pos); \
        h.spec = 16.0; h.refl = 0.15; \
    } \
    return h; \
} \
 \
fn shadow(p: vec3f, ld: vec3f) -> f32 { \
    let o = p + ld * EPS * 2.0; \
    for (var i: i32 = 0; i < N_SPHERES; i++) { \
        if (hitSphere(o, ld, sphere(i)) < INF) { return 0.2; } \
    } \
    return 1.0; \
} \
 \
fn shade(h: Hit, rd: vec3f) -> vec3f { \
    let lp = vec3f(5.0, 8.0, -3.0); \
    let ld = normalize(lp - h.pos); \
    let sh = shadow(h.pos, ld); \
    let diff = max(dot(h.nor, ld), 0.0) * sh; \
    let hv = normalize(ld - rd); \
    let sp = pow(max(dot(h.nor, hv), 0.0), h.spec) * sh; \
    return vec3f(0.08, 0.08, 0.12) + h.col * diff * 0.9 + vec3f(1.0) * sp * 0.6; \
} \
 \
fn traceRay(ro: vec3f, rd: vec3f) -> vec3f { \
    var color = vec3f(0.0); \
    var throughput = vec3f(1.0); \
    var o = ro; var d = rd; \
    for (var b: i32 = 0; b < MAX_BOUNCES; b++) { \
        let h = traceScene(o, d); \
        if (h.t >= INF) { \
            color += throughput * mix(vec3f(0.6,0.75,1.0), vec3f(0.15,0.3,0.8), max(d.y,0.0)); \
            break; \
        } \
        color += throughput * (1.0 - h.refl) * shade(h, d); \
        throughput *= h.refl; \
        if (dot(throughput, vec3f(1.0)) < 0.01) { break; } \
        o = h.pos + h.nor * EPS * 2.0; \
        d = reflect(d, h.nor); \
    } \
    return color; \
} \
 \
fn pack(c: vec3f) -> u32 { \
    let r = u32(clamp(c.x, 0.0, 1.0) * 255.0); \
    let g = u32(clamp(c.y, 0.0, 1.0) * 255.0); \
    let b = u32(clamp(c.z, 0.0, 1.0) * 255.0); \
    return r | (g << 8u) | (b << 16u) | (255u << 24u); \
} \
 \
@compute @workgroup_size(8, 8) \
fn main(@builtin(global_invocation_id) id: vec3<u32>) { \
    let w = u32(u.width); \
    let h = u32(u.height); \
    if (id.x >= w || id.y >= h) { return; } \
    let uv = vec2f( \
        (f32(id.x) + 0.5) / u.width * 2.0 - 1.0, \
        1.0 - (f32(id.y) + 0.5) / u.height * 2.0 \
    ); \
    let aspect = u.width / u.height; \
    let eye = vec3f(u.eyeX, u.eyeY, u.eyeZ); \
    let lookAt = vec3f(u.targetX, u.targetY, u.targetZ); \
    let fwd = normalize(lookAt - eye); \
    let right = normalize(cross(fwd, vec3f(0.0, 1.0, 0.0))); \
    let up = cross(right, fwd); \
    let fov = 1.2; \
    let rd = normalize(fwd + right * uv.x * aspect * fov + up * uv.y * fov); \
    let color = traceRay(eye, rd); \
    pixels[id.y * w + id.x] = pack(pow(color, vec3f(1.0 / 2.2))); \
}"

-- ═══════════════════════════════════════════════════════════════════
-- Render shader: fullscreen quad, reads pixel buffer for display
-- ═══════════════════════════════════════════════════════════════════
def rtRenderSource : String :=
"@group(0) @binding(0) var<storage, read> pixels: array<u32>; \
@group(0) @binding(1) var<uniform> res: vec2f; \
 \
struct VOut { @builtin(position) pos: vec4f, @location(0) uv: vec2f }; \
 \
@vertex \
fn vs_main(@builtin(vertex_index) i: u32) -> VOut { \
    var p = array<vec2f,6>( \
        vec2f(-1,-1), vec2f(1,-1), vec2f(1,1), \
        vec2f(-1,-1), vec2f(1,1),  vec2f(-1,1) \
    ); \
    var t = array<vec2f,6>( \
        vec2f(0,1), vec2f(1,1), vec2f(1,0), \
        vec2f(0,1), vec2f(1,0), vec2f(0,0) \
    ); \
    var o: VOut; \
    o.pos = vec4f(p[i], 0.0, 1.0); \
    o.uv = t[i]; \
    return o; \
} \
 \
@fragment \
fn fs_main(v: VOut) -> @location(0) vec4f { \
    let w = u32(res.x); let h = u32(res.y); \
    let x = min(u32(v.uv.x * f32(w)), w - 1u); \
    let y = min(u32(v.uv.y * f32(h)), h - 1u); \
    let c = pixels[y * w + x]; \
    return vec4f( \
        f32(c & 0xFFu) / 255.0, \
        f32((c >> 8u) & 0xFFu) / 255.0, \
        f32((c >> 16u) & 0xFFu) / 255.0, \
        1.0 \
    ); \
}"

-- ═══════════════════════════════════════════════════════════════════
-- Lean host code
-- ═══════════════════════════════════════════════════════════════════
def rtWidth  : UInt32 := 640
def rtHeight : UInt32 := 480

def rayTracer : IO Unit := do
  eprintln "=== Ray Tracer (Compute Shader) ==="

  setLogCallback fun lvl msg => eprintln s!"[{repr lvl}] {msg}"
  let window ← GLFWwindow.mk rtWidth rtHeight "Ray Tracer"

  let desc ← InstanceDescriptor.mk
  let inst ← createInstance desc
  let surface ← getSurface inst window

  let adapter ← inst.requestAdapter surface >>= await!
  adapter.printProperties

  let ddesc ← DeviceDescriptor.mk "raytracer device"
  let device ← adapter.requestDevice ddesc >>= await!
  device.setUncapturedErrorCallback fun code msg => do
    eprintln s!"uncaptured error, code {code}: \"{msg}\""

  let queue ← device.getQueue
  let textureFormat ← TextureFormat.get surface adapter
  let surfConfig ← SurfaceConfiguration.mk rtWidth rtHeight device textureFormat
  surface.configure surfConfig

  -- ── Buffers ──
  let numPixels := rtWidth * rtHeight
  let pixelBufSize : UInt32 := numPixels * 4

  let pixelBuf ← Buffer.mk device
    (BufferDescriptor.mk "pixels" (BufferUsage.storage.lor BufferUsage.copyDst) pixelBufSize false)

  -- Compute uniforms: eye(3) + time(1) + target(3) + pad(1) + w + h + pad(2) = 48 bytes = 12 floats
  let computeUniformSize : UInt32 := 48
  let computeUB ← Buffer.mk device
    (BufferDescriptor.mk "compute uniforms" (BufferUsage.uniform.lor BufferUsage.copyDst) computeUniformSize false)

  -- Render uniforms: vec2f (width, height) = 8 bytes (pad to 16)
  let renderUniformSize : UInt32 := 16
  let renderUB ← Buffer.mk device
    (BufferDescriptor.mk "render uniforms" (BufferUsage.uniform.lor BufferUsage.copyDst) renderUniformSize false)
  queue.writeBuffer renderUB (floatsToByteArray #[rtWidth.toFloat, rtHeight.toFloat, 0.0, 0.0])

  -- ── Compute pipeline ──
  -- group 0: binding 0 = uniform (camera)
  -- group 1: binding 0 = storage (pixels, read_write)
  let compUniBGL ← BindGroupLayout.mkUniform device 0 ShaderStageFlags.compute computeUniformSize.toUInt64
  let compPixBGL ← BindGroupLayout.mkStorage device 0 ShaderStageFlags.compute (readOnly := false)
  let compPL ← PipelineLayout.mk device #[compUniBGL, compPixBGL]

  let compWGSL ← ShaderModuleWGSLDescriptor.mk rtComputeSource
  let compShaderDesc ← ShaderModuleDescriptor.mk compWGSL
  let compShader ← ShaderModule.mk device compShaderDesc
  let computePipeline ← device.createComputePipeline compShader compPL "main"

  let compUniBG ← BindGroup.mk device compUniBGL 0 computeUB
  let compPixBG ← BindGroup.mk device compPixBGL 0 pixelBuf

  -- ── Render pipeline ──
  -- group 0: binding 0 = storage (pixels, read), binding 1 = uniform (resolution)
  -- Use mkEntries: (binding, visibility, isStorage, minBindingSize)
  --   binding 0: isStorage=true → ReadOnlyStorage
  --   binding 1: isStorage=false → Uniform
  let renderBGL ← BindGroupLayout.mkEntries device #[
    (0, ShaderStageFlags.fragment, true, 0),  -- storage read-only
    (1, ShaderStageFlags.fragment, false, renderUniformSize.toUInt64)  -- uniform
  ]
  let renderPL ← PipelineLayout.mk device #[renderBGL]

  let renWGSL ← ShaderModuleWGSLDescriptor.mk rtRenderSource
  let renShaderDesc ← ShaderModuleDescriptor.mk renWGSL
  let renShader ← ShaderModule.mk device renShaderDesc

  let blendState ← BlendState.mk renShader
  let cts ← ColorTargetState.mk textureFormat blendState
  let fragState ← FragmentState.mk renShader cts
  let pipeDesc ← RenderPipelineDescriptor.mk renShader fragState
  let renderPipeline ← RenderPipeline.mkWithLayout device pipeDesc renderPL

  -- Render bind group: pixel buffer + resolution uniform
  let renderBG ← BindGroup.mkBuffers device renderBGL #[
    (0, pixelBuf, 0, pixelBufSize.toUInt64),
    (1, renderUB, 0, renderUniformSize.toUInt64)
  ]

  let clearColor := Color.mk 0.0 0.0 0.0 1.0
  let wgX := (rtWidth + 7) / 8
  let wgY := (rtHeight + 7) / 8

  eprintln s!"Resolution: {rtWidth}×{rtHeight}, dispatch: {wgX}×{wgY} workgroups"
  eprintln "Entering render loop (press Q or Escape to quit)..."

  let mut frameCount : UInt32 := 0
  while not (← window.shouldClose) do
    GLFW.pollEvents

    let esc ← window.getKey GLFW.keyEscape
    let q ← window.getKey GLFW.keyQ
    if esc == GLFW.press || q == GLFW.press then
      window.setShouldClose true
      continue

    -- Update camera: orbit around the scene
    let t ← GLFW.getTime
    let angle := t * 0.3
    let radius := 6.0
    let eyeX := Float.cos angle * radius
    let eyeY := 3.0 + Float.sin (t * 0.15) * 0.8
    let eyeZ := Float.sin angle * radius
    let uniforms := floatsToByteArray #[
      eyeX, eyeY, eyeZ, t,       -- eye + time
      0.0, 0.5, 0.0, 0.0,        -- target + pad
      rtWidth.toFloat, rtHeight.toFloat, 0.0, 0.0  -- resolution + pad
    ]
    queue.writeBuffer computeUB uniforms

    let encoder ← device.createCommandEncoder

    -- Compute pass: ray trace
    let computePass ← encoder.beginComputePass
    computePass.setPipeline computePipeline
    computePass.setBindGroup 0 compUniBG
    computePass.setBindGroup 1 compPixBG
    computePass.dispatchWorkgroups wgX wgY 1
    computePass.end_

    -- Render pass: blit pixel buffer to screen
    let texture ← surface.getCurrent
    let status ← texture.status
    if (status != .success) then continue
    let targetView ← TextureView.mk texture
    if !(← targetView.is_valid) then continue

    let renderPass ← RenderPassEncoder.mkWithColor encoder targetView clearColor
    renderPass.setPipeline renderPipeline
    renderPass.setBindGroup 0 renderBG
    renderPass.draw 6 1 0 0
    renderPass.end

    let command ← encoder.finish
    queue.submit #[command]
    surface.present
    device.poll

    frameCount := frameCount + 1
    if frameCount % 120 == 0 then
      let fps := frameCount.toFloat / t
      window.setTitle s!"Ray Tracer - {fps.toString} fps"

  eprintln s!"Rendered {frameCount} frames"
  pixelBuf.destroy
  computeUB.destroy
  renderUB.destroy
  eprintln "=== Done ==="

def main : IO Unit := rayTracer
