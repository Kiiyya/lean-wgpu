import Wgpu
import Wgpu.Async
import Glfw

open IO
open Wgpu

set_option linter.unusedVariables false

/--
  RayTracer: A real-time compute-shader software ray tracer.

  Renders a scene of spheres inside a square room lit by a single ceiling light.
  PBR-inspired shading with roughness and metallic parameters per surface.
  - Room: 8×6×8 box with colored walls (red left, blue right, green back,
    wood-pattern floor, white ceiling)
  - 5 spheres: chrome mirror, matte red, glossy blue, gold metallic, pale pearl
  - Single warm point light near the ceiling
  - Schlick Fresnel, energy-conserving specular, inverse-square falloff
  - Hard shadows, up to 4 bounce reflections, gamma correction

  Controls:
  - Left-click + drag  → look around (yaw / pitch)
  - W / S              → move forward / backward
  - A / D              → strafe left / right
  - Space / LShift     → move up / down
  - Escape             → exit

  Architecture:
  - Compute pipeline: @group(0) = uniform camera, @group(1) = storage pixel buffer
  - Render pipeline: @group(0) = fullscreen quad reading pixel buffer + resolution uniform
-/

-- ═══════════════════════════════════════════════════════════════════
-- Compute shader: ray traces the room scene, writes packed RGBA u32 per pixel
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
const MAX_BOUNCES: i32 = 4; \
const N_SPHERES: i32 = 5; \
 \
struct Sphere { center: vec3f, radius: f32, color: vec3f, roughness: f32, metallic: f32 }; \
struct Hit { t: f32, pos: vec3f, nor: vec3f, col: vec3f, roughness: f32, metallic: f32 }; \
 \
fn getSphere(i: i32) -> Sphere { \
    var s: Sphere; \
    switch(i) { \
        case 0 { s = Sphere(vec3f(-1.8, 1.0, -1.5), 1.0, vec3f(0.95,0.95,0.95), 0.05, 0.95); } \
        case 1 { s = Sphere(vec3f( 2.0, 0.7,  0.5), 0.7, vec3f(0.85,0.15,0.10), 0.85, 0.05); } \
        case 2 { s = Sphere(vec3f( 0.0, 0.5,  1.5), 0.5, vec3f(0.10,0.20,0.90), 0.20, 0.30); } \
        case 3 { s = Sphere(vec3f( 1.5, 1.2, -2.0), 1.2, vec3f(1.00,0.76,0.33), 0.15, 0.90); } \
        default { s = Sphere(vec3f(-2.5, 0.45, 2.0), 0.45,vec3f(0.90,0.92,0.88), 0.08, 0.65); } \
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
fn wallColor(nor: vec3f, pos: vec3f) -> vec3f { \
    if (nor.y > 0.5) { \
        let fx = floor(pos.x); let fz = floor(pos.z); \
        if ((i32(fx) + i32(fz)) % 2 == 0) { return vec3f(0.55,0.35,0.18); } \
        return vec3f(0.42,0.26,0.12); \
    } \
    if (nor.y < -0.5) { return vec3f(0.90,0.88,0.85); } \
    if (nor.x > 0.5)  { return vec3f(0.75,0.15,0.12); } \
    if (nor.x < -0.5) { return vec3f(0.12,0.18,0.75); } \
    if (nor.z > 0.5)  { return vec3f(0.20,0.65,0.25); } \
    return vec3f(0.70,0.70,0.72); \
} \
 \
fn wallProps(nor: vec3f) -> vec2f { \
    if (nor.y > 0.5) { return vec2f(0.35, 0.05); } \
    if (nor.y < -0.5) { return vec2f(0.90, 0.00); } \
    return vec2f(0.80, 0.00); \
} \
 \
fn hitRoom(ro: vec3f, rd: vec3f) -> Hit { \
    var h: Hit; \
    h.t = INF; \
    let rMin = vec3f(-4.0, 0.0, -4.0); \
    let rMax = vec3f( 4.0, 6.0,  4.0); \
    if (abs(rd.x) > EPS) { \
        var t = (rMin.x - ro.x) / rd.x; \
        if (t > EPS && t < h.t) { let p = ro + rd * t; \
            if (p.y >= rMin.y && p.y <= rMax.y && p.z >= rMin.z && p.z <= rMax.z) { \
                h.t = t; h.pos = p; h.nor = vec3f(1.0,0.0,0.0); } } \
        t = (rMax.x - ro.x) / rd.x; \
        if (t > EPS && t < h.t) { let p = ro + rd * t; \
            if (p.y >= rMin.y && p.y <= rMax.y && p.z >= rMin.z && p.z <= rMax.z) { \
                h.t = t; h.pos = p; h.nor = vec3f(-1.0,0.0,0.0); } } \
    } \
    if (abs(rd.y) > EPS) { \
        var t = (rMin.y - ro.y) / rd.y; \
        if (t > EPS && t < h.t) { let p = ro + rd * t; \
            if (p.x >= rMin.x && p.x <= rMax.x && p.z >= rMin.z && p.z <= rMax.z) { \
                h.t = t; h.pos = p; h.nor = vec3f(0.0,1.0,0.0); } } \
        t = (rMax.y - ro.y) / rd.y; \
        if (t > EPS && t < h.t) { let p = ro + rd * t; \
            if (p.x >= rMin.x && p.x <= rMax.x && p.z >= rMin.z && p.z <= rMax.z) { \
                h.t = t; h.pos = p; h.nor = vec3f(0.0,-1.0,0.0); } } \
    } \
    if (abs(rd.z) > EPS) { \
        var t = (rMin.z - ro.z) / rd.z; \
        if (t > EPS && t < h.t) { let p = ro + rd * t; \
            if (p.x >= rMin.x && p.x <= rMax.x && p.y >= rMin.y && p.y <= rMax.y) { \
                h.t = t; h.pos = p; h.nor = vec3f(0.0,0.0,1.0); } } \
        t = (rMax.z - ro.z) / rd.z; \
        if (t > EPS && t < h.t) { let p = ro + rd * t; \
            if (p.x >= rMin.x && p.x <= rMax.x && p.y >= rMin.y && p.y <= rMax.y) { \
                h.t = t; h.pos = p; h.nor = vec3f(0.0,0.0,-1.0); } } \
    } \
    if (h.t < INF) { \
        h.col = wallColor(h.nor, h.pos); \
        let wp = wallProps(h.nor); h.roughness = wp.x; h.metallic = wp.y; \
    } \
    return h; \
} \
 \
fn traceScene(ro: vec3f, rd: vec3f) -> Hit { \
    var h: Hit; \
    h.t = INF; \
    for (var i: i32 = 0; i < N_SPHERES; i++) { \
        let s = getSphere(i); \
        let t = hitSphere(ro, rd, s); \
        if (t < h.t) { \
            h.t = t; h.pos = ro + rd * t; \
            h.nor = normalize(h.pos - s.center); \
            h.col = s.color; h.roughness = s.roughness; h.metallic = s.metallic; \
        } \
    } \
    let rh = hitRoom(ro, rd); \
    if (rh.t < h.t) { h = rh; } \
    return h; \
} \
 \
fn shadowTest(p: vec3f, ld: vec3f, maxD: f32) -> f32 { \
    let o = p + ld * EPS * 2.0; \
    for (var i: i32 = 0; i < N_SPHERES; i++) { \
        let t = hitSphere(o, ld, getSphere(i)); \
        if (t > EPS && t < maxD) { return 0.0; } \
    } \
    return 1.0; \
} \
 \
fn shade(h: Hit, rd: vec3f) -> vec3f { \
    let lp = vec3f(0.0, 5.8, 0.0); \
    let lDir = vec3f(0.0, -1.0, 0.0); \
    let cosInner = 0.85; \
    let cosOuter = 0.55; \
    let lc = vec3f(1.0, 0.95, 0.85); \
    let toL = lp - h.pos; \
    let dist = length(toL); \
    let ld = toL / dist; \
    let spotCos = dot(-ld, lDir); \
    let spotFade = clamp((spotCos - cosOuter) / (cosInner - cosOuter), 0.0, 1.0); \
    let atten = 25.0 / (dist * dist + 1.0) * spotFade; \
    let sh = shadowTest(h.pos, ld, dist); \
    let NdotL = max(dot(h.nor, ld), 0.0); \
    let hv = normalize(ld - rd); \
    let NdotH = max(dot(h.nor, hv), 0.0); \
    let r4 = h.roughness * h.roughness * h.roughness * h.roughness; \
    let specPow = clamp(2.0 / (r4 + 0.001) - 2.0, 1.0, 2048.0); \
    let spec = pow(NdotH, specPow) * (specPow + 2.0) / 8.0; \
    let f0 = mix(vec3f(0.04), h.col, h.metallic); \
    let VdotH = max(dot(-rd, hv), 0.0); \
    let fresnel = f0 + (vec3f(1.0) - f0) * pow(1.0 - VdotH, 5.0); \
    let diffCol = h.col * (1.0 - h.metallic); \
    let ambient = vec3f(0.03, 0.03, 0.04); \
    return ambient + (diffCol * NdotL + fresnel * spec) * lc * atten * sh; \
} \
 \
fn traceRay(ro: vec3f, rd: vec3f) -> vec3f { \
    var color = vec3f(0.0); \
    var throughput = vec3f(1.0); \
    var o = ro; var d = rd; \
    for (var b: i32 = 0; b < MAX_BOUNCES; b++) { \
        let h = traceScene(o, d); \
        if (h.t >= INF) { color += throughput * vec3f(0.01); break; } \
        let f0 = mix(vec3f(0.04), h.col, h.metallic); \
        let cosT = max(dot(-d, h.nor), 0.0); \
        let schlick = f0 + (vec3f(1.0) - f0) * pow(1.0 - cosT, 5.0); \
        let refl = (schlick.x * 0.33 + schlick.y * 0.33 + schlick.z * 0.34) \
                 * (1.0 - h.roughness * 0.85); \
        color += throughput * (1.0 - refl) * shade(h, d); \
        throughput *= refl; \
        if (dot(throughput, vec3f(1.0)) < 0.005) { break; } \
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
    pixels[id.y * w + id.x] = pack(color); \
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
  let window ← GLFWwindow.mkResizable rtWidth rtHeight "Ray Tracer"

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

  -- Initial framebuffer size
  let (initW, initH) ← window.getFramebufferSize
  let surfConfig ← SurfaceConfiguration.mk initW initH device textureFormat
  surface.configure surfConfig

  -- ── Compute uniforms (fixed size, reused across resizes) ──
  let computeUniformSize : UInt32 := 48
  let computeUB ← Buffer.mk device
    (BufferDescriptor.mk "compute uniforms" (BufferUsage.uniform.lor BufferUsage.copyDst) computeUniformSize false)

  -- ── Render uniforms: vec2f (width, height), pad to 16 bytes (fixed size, reused) ──
  let renderUniformSize : UInt32 := 16
  let renderUB ← Buffer.mk device
    (BufferDescriptor.mk "render uniforms" (BufferUsage.uniform.lor BufferUsage.copyDst) renderUniformSize false)

  -- ── Compute pipeline (fixed across resizes) ──
  let compUniBGL ← BindGroupLayout.mkUniform device 0 ShaderStageFlags.compute computeUniformSize.toUInt64
  let compPixBGL ← BindGroupLayout.mkStorage device 0 ShaderStageFlags.compute (readOnly := false)
  let compPL ← PipelineLayout.mk device #[compUniBGL, compPixBGL]

  let compWGSL ← ShaderModuleWGSLDescriptor.mk rtComputeSource
  let compShaderDesc ← ShaderModuleDescriptor.mk compWGSL
  let compShader ← ShaderModule.mk device compShaderDesc
  let computePipeline ← device.createComputePipeline compShader compPL "main"

  -- Compute uniform bind group (fixed — buffer doesn't change)
  let compUniBG ← BindGroup.mk device compUniBGL 0 computeUB

  -- ── Render pipeline (fixed across resizes) ──
  let renderBGL ← BindGroupLayout.mkEntries device #[
    (0, ShaderStageFlags.fragment, true, 0),
    (1, ShaderStageFlags.fragment, false, renderUniformSize.toUInt64)
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

  -- ── Helper: create size-dependent resources ──
  let mkSizeResources (w h : UInt32) : IO (Buffer × BindGroup × BindGroup × UInt32 × UInt32) := do
    let numPx := w * h
    let pxBufSize := numPx * 4
    let pxBuf ← Buffer.mk device
      (BufferDescriptor.mk "pixels" (BufferUsage.storage.lor BufferUsage.copyDst) pxBufSize false)
    -- Compute pixel bind group (group 1)
    let compPixBG ← BindGroup.mk device compPixBGL 0 pxBuf
    -- Render bind group (pixel buffer + resolution uniform)
    let renBG ← BindGroup.mkBuffers device renderBGL #[
      (0, pxBuf, 0, pxBufSize.toUInt64),
      (1, renderUB, 0, renderUniformSize.toUInt64)
    ]
    -- Update render resolution uniform
    queue.writeBuffer renderUB (floatsToByteArray #[w.toFloat, h.toFloat, 0.0, 0.0])
    let wgX := (w + 7) / 8
    let wgY := (h + 7) / 8
    return (pxBuf, compPixBG, renBG, wgX, wgY)

  -- Initial size-dependent resources
  let (initPixBuf, initCompPixBG, initRenBG, initWgX, initWgY) ← mkSizeResources initW initH

  let clearColor := Color.mk 0.0 0.0 0.0 1.0

  eprintln s!"Resolution: {initW}×{initH}, dispatch: {initWgX}×{initWgY} workgroups"
  eprintln "Left-click + drag to look. WASD to move. Space/Shift up/down. Escape to quit."

  -- ── Mutable render-size state ──
  let mut curW := initW
  let mut curH := initH
  let mut pixelBuf := initPixBuf
  let mut compPixBG := initCompPixBG
  let mut renderBG := initRenBG
  let mut wgX := initWgX
  let mut wgY := initWgY

  -- ── Camera state ──
  let mut camX : Float := 0.0
  let mut camY : Float := 2.5
  let mut camZ : Float := 3.5
  let mut yaw  : Float := 3.14159265  -- looking toward -Z (into the room)
  let mut pitch : Float := -0.35    -- slight downward tilt
  let mut prevTime : Float := ← GLFW.getTime
  let mut lastMX : Float := 0.0
  let mut lastMY : Float := 0.0
  let mut wasDragging : Bool := false

  let mut frameCount : UInt32 := 0
  while not (← window.shouldClose) do
    GLFW.pollEvents

    -- ── Time delta ──
    let now ← GLFW.getTime
    let rawDt := now - prevTime
    let dt := if rawDt > 0.1 then 0.1 else rawDt
    prevTime := now

    -- ── Escape to quit ──
    let esc ← window.getKey GLFW.keyEscape
    if esc == GLFW.press then
      window.setShouldClose true
      continue

    -- ── Check for resize ──
    let (fbW, fbH) ← window.getFramebufferSize
    if fbW != curW || fbH != curH then
      if fbW > 0 && fbH > 0 then
        eprintln s!"Resized to {fbW}×{fbH}, recreating pixel buffer..."
        let newConfig ← SurfaceConfiguration.mkWith fbW fbH device textureFormat
        surface.configure newConfig
        pixelBuf.destroy
        let (nb, ncpbg, nrbg, nwx, nwy) ← mkSizeResources fbW fbH
        pixelBuf := nb
        compPixBG := ncpbg
        renderBG := nrbg
        wgX := nwx
        wgY := nwy
        curW := fbW
        curH := fbH

    -- Skip rendering if minimized
    if curW == 0 || curH == 0 then continue

    -- ── Mouse look: right-click + drag ──
    let (mx, my) ← window.getCursorPos
    let rmb ← window.getMouseButton GLFW.mouseButtonLeft
    let dragging := rmb == GLFW.press
    if dragging then
      if wasDragging then
        let dx := mx - lastMX
        let dy := my - lastMY
        let sensitivity : Float := 0.003
        yaw   := yaw   + dx * sensitivity
        let newPitch := pitch - dy * sensitivity
        pitch := if newPitch > 1.5 then 1.5 else if newPitch < -1.5 then -1.5 else newPitch
    lastMX := mx
    lastMY := my
    wasDragging := dragging

    -- ── Forward / right vectors on XZ plane ──
    let fwdX := Float.cos yaw
    let fwdZ := Float.sin yaw
    let rightX := -fwdZ
    let rightZ := fwdX

    -- ── WASD + Space/Shift movement ──
    let speed : Float := 4.0 * dt
    let w ← window.getKey GLFW.keyW
    let s ← window.getKey GLFW.keyS
    let a ← window.getKey GLFW.keyA
    let d ← window.getKey GLFW.keyD
    let sp ← window.getKey GLFW.keySpace
    let sh ← window.getKey GLFW.keyLeftShift
    if w == GLFW.press then  camX := camX + fwdX * speed;  camZ := camZ + fwdZ * speed
    if s == GLFW.press then  camX := camX - fwdX * speed;  camZ := camZ - fwdZ * speed
    if a == GLFW.press then  camX := camX - rightX * speed; camZ := camZ - rightZ * speed
    if d == GLFW.press then  camX := camX + rightX * speed; camZ := camZ + rightZ * speed
    if sp == GLFW.press then camY := camY + speed
    if sh == GLFW.press then camY := camY - speed

    -- ── Compute look-at target from yaw / pitch ──
    let dirX := Float.cos pitch * Float.cos yaw
    let dirY := Float.sin pitch
    let dirZ := Float.cos pitch * Float.sin yaw
    let tgtX := camX + dirX
    let tgtY := camY + dirY
    let tgtZ := camZ + dirZ

    let uniforms := floatsToByteArray #[
      camX, camY, camZ, now,
      tgtX, tgtY, tgtZ, 0.0,
      curW.toFloat, curH.toFloat, 0.0, 0.0
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
      let fps := frameCount.toFloat / now
      window.setTitle s!"Ray Tracer ({curW}×{curH}) - {fps.toString} fps"

  eprintln s!"Rendered {frameCount} frames"
  pixelBuf.destroy
  computeUB.destroy
  renderUB.destroy
  eprintln "=== Done ==="

def main : IO Unit := rayTracer
