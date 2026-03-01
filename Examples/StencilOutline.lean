import Wgpu
import Wgpu.Async
import Glfw

open IO
open Wgpu

set_option linter.unusedVariables false

/-!
  StencilOutline: Demonstrates stencil buffer usage for outline rendering.

  Two-pass technique:
    Pass 1 — Draw a filled hexagon, writing stencil ref=1 everywhere it draws.
    Pass 2 — Draw a scaled-up hexagon (outline), only where stencil != 1.

  This produces a clean colored outline around the shape.
  The shape slowly rotates. Press ESC/Q to quit.
-/

def stencilShaderCode : String :=
"struct Uniforms { angle: f32, scale: f32, aspect: f32, _pad: f32 }; \
@group(0) @binding(0) var<uniform> u: Uniforms; \
struct VertexOutput { @builtin(position) position: vec4f }; \
@vertex fn vs_main(@builtin(vertex_index) idx: u32) -> VertexOutput { \
    let N = 6u; \
    let tri = idx / 3u; \
    let vert = idx % 3u; \
    var p: vec2f; \
    if (vert == 0u) { \
        p = vec2f(0.0, 0.0); \
    } else { \
        let vi = tri + vert - 1u; \
        let a_base = f32(vi) * 6.28318530 / f32(N); \
        p = vec2f(cos(a_base), sin(a_base)); \
    } \
    p = p * u.scale; \
    let ca = cos(u.angle); let sa = sin(u.angle); \
    p = vec2f(p.x*ca - p.y*sa, p.x*sa + p.y*ca); \
    p.x = p.x / u.aspect; \
    var out: VertexOutput; \
    out.position = vec4f(p, 0.5, 1.0); \
    return out; \
} \
struct FragUniforms { color: vec4f }; \
@group(0) @binding(1) var<uniform> frag_u: FragUniforms; \
@fragment fn fs_main() -> @location(0) vec4f { return frag_u.color; }"

def stencilOutline : IO Unit := do
  eprintln "=== StencilOutline (stencil-based outline rendering) ==="
  setLogCallback fun lvl msg => eprintln s!"[{repr lvl}] {msg}"

  let width  : UInt32 := 800
  let height : UInt32 := 600

  let window ← GLFWwindow.mk width height "Stencil Outline"
  let instDesc ← InstanceDescriptor.mk
  let inst ← createInstance instDesc
  let surface ← getSurface inst window
  let adapter ← inst.requestAdapter surface >>= await!
  let ddesc ← DeviceDescriptor.mk "stencil device"
  let device ← adapter.requestDevice ddesc >>= await!
  device.setUncapturedErrorCallback fun t m => eprintln s!"[Device Error] type={t} {m}"
  let queue ← device.getQueue
  let surfFormat ← TextureFormat.get surface adapter
  let config ← SurfaceConfiguration.mk width height device surfFormat
  surface.configure config

  -- Shader
  let sm ← ShaderModule.mk device (← ShaderModuleDescriptor.mk (← ShaderModuleWGSLDescriptor.mk stencilShaderCode))
  let cts ← ColorTargetState.mk surfFormat (← BlendState.mk sm)
  let fs ← FragmentState.mk sm cts

  -- Depth-stencil texture
  let dsTex ← device.createDepthStencilTexture width height
  let dsView ← dsTex.createDepthStencilView

  -- Uniform buffers: vertex uniforms (angle, scale, aspect, pad) + 2 frag uniform buffers (color)
  let vertUnifBuf ← Buffer.mk device (BufferDescriptor.mk "vert uniforms" (BufferUsage.uniform.lor BufferUsage.copyDst) 16 false)
  let fillColorBuf ← Buffer.mk device (BufferDescriptor.mk "fill color" (BufferUsage.uniform.lor BufferUsage.copyDst) 16 false)
  let outlineColorBuf ← Buffer.mk device (BufferDescriptor.mk "outline color" (BufferUsage.uniform.lor BufferUsage.copyDst) 16 false)

  -- Write static fill color (teal) and outline color (orange)
  queue.writeBuffer fillColorBuf (floatsToByteArray #[0.1, 0.6, 0.6, 1.0])
  queue.writeBuffer outlineColorBuf (floatsToByteArray #[1.0, 0.6, 0.1, 1.0])

  -- Bind group layout: @binding(0) vertex uniform, @binding(1) fragment uniform
  let bgLayout ← BindGroupLayout.mkEntries device #[
    (0, ShaderStageFlags.vertex, false, (16 : UInt64)),
    (1, ShaderStageFlags.fragment, false, (16 : UInt64))
  ]
  let pipeLayout ← PipelineLayout.mk device #[bgLayout]

  -- Bind groups: one for fill pass, one for outline pass (different frag color buffer)
  let fillBG ← BindGroup.mkBuffers device bgLayout #[
    (0, vertUnifBuf, (0 : UInt64), (16 : UInt64)),
    (1, fillColorBuf, (0 : UInt64), (16 : UInt64))
  ]
  let outlineBG ← BindGroup.mkBuffers device bgLayout #[
    (0, vertUnifBuf, (0 : UInt64), (16 : UInt64)),
    (1, outlineColorBuf, (0 : UInt64), (16 : UInt64))
  ]

  -- Pipeline for fill pass: stencil Always → Replace with ref=1, write stencil
  let fillStencilFace : StencilFaceState := {
    compare := CompareFunction.Always,
    failOp := StencilOperation.Keep,
    depthFailOp := StencilOperation.Keep,
    passOp := StencilOperation.Replace
  }
  let fillPipeDesc ← RenderPipelineDescriptor.mkWithStencil sm fs #[]
    (depthFormat := TextureFormat.Depth24PlusStencil8)
    (depthCompare := CompareFunction.Always)
    (depthWriteEnabled := false)
    (stencilFront := fillStencilFace)
    (stencilBack := fillStencilFace)
    (stencilReadMask := 0xFF)
    (stencilWriteMask := 0xFF)
  let fillPipeline ← RenderPipeline.mkWithLayout device fillPipeDesc pipeLayout

  -- Pipeline for outline pass: stencil NotEqual with ref=1 → only draw where stencil ≠ 1
  let outlineStencilFace : StencilFaceState := {
    compare := CompareFunction.NotEqual,
    failOp := StencilOperation.Keep,
    depthFailOp := StencilOperation.Keep,
    passOp := StencilOperation.Keep
  }
  let outlinePipeDesc ← RenderPipelineDescriptor.mkWithStencil sm fs #[]
    (depthFormat := TextureFormat.Depth24PlusStencil8)
    (depthCompare := CompareFunction.Always)
    (depthWriteEnabled := false)
    (stencilFront := outlineStencilFace)
    (stencilBack := outlineStencilFace)
    (stencilReadMask := 0xFF)
    (stencilWriteMask := 0x00)  -- don't write stencil in outline pass
  let outlinePipeline ← RenderPipeline.mkWithLayout device outlinePipeDesc pipeLayout

  let aspect := (Float.ofNat width.toNat) / (Float.ofNat height.toNat)
  let clearColor := Color.mk 0.08 0.08 0.12 1.0
  -- hexagon = 6 triangles × 3 verts
  let hexVertCount : UInt32 := 18

  while not (← window.shouldClose) do
    GLFW.pollEvents

    let esc ← window.getKey GLFW.keyEscape
    let q ← window.getKey GLFW.keyQ
    if esc == GLFW.press || q == GLFW.press then
      window.setShouldClose true
      continue

    let time ← GLFW.getTime
    let angle := time * 0.5

    -- Fill pass: scale=0.5
    queue.writeBuffer vertUnifBuf (floatsToByteArray #[angle, 0.5, aspect, 0.0])

    let texture ← surface.getCurrent
    if (← texture.status) != .success then continue
    let surfView ← TextureView.mk texture

    let encoder ← device.createCommandEncoder

    -- Pass 1: fill the hexagon AND write stencil=1
    let rp1 ← RenderPassEncoder.mkWithDepthStencil encoder surfView clearColor dsView
      (stencilClearValue := 0) (stencilLoadOp := 1) (stencilStoreOp := 1)
    rp1.setPipeline fillPipeline
    rp1.setStencilReference 1
    rp1.setBindGroup 0 fillBG
    rp1.draw hexVertCount 1 0 0
    rp1.end
    rp1.release

    -- Update scale for outline (larger)
    queue.writeBuffer vertUnifBuf (floatsToByteArray #[angle, 0.6, aspect, 0.0])

    -- Pass 2: draw outline where stencil != 1 (load stencil from pass 1)
    let rp2 ← RenderPassEncoder.mkWithDepthStencil encoder surfView clearColor dsView
      (depthClearValue := 1.0) (stencilClearValue := 0) (stencilLoadOp := 2) (stencilStoreOp := 2)
    rp2.setPipeline outlinePipeline
    rp2.setStencilReference 1
    rp2.setBindGroup 0 outlineBG
    rp2.draw hexVertCount 1 0 0
    rp2.end
    rp2.release

    let cmd ← encoder.finish
    queue.submit #[cmd]
    surface.present
    device.poll

  eprintln "=== Done ==="

def main : IO Unit := stencilOutline
