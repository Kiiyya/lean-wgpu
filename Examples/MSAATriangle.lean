import Wgpu
import Wgpu.Async
import Glfw

open IO
open Wgpu

set_option linter.unusedVariables false

/-!
  MSAATriangle: Demonstrates multi-sample anti-aliasing (MSAA).

  Renders a rotating triangle with 4x MSAA for smooth edges.
  The MSAA render target is resolved to the swapchain surface each frame.
  Press Space to toggle MSAA on/off to see the difference.
  Press ESC or Q to quit.
-/

def msaaShaderSrc : String :=
"struct Uniforms { angle: f32 }; \
@group(0) @binding(0) var<uniform> u: Uniforms; \
struct VertexOutput { @builtin(position) position: vec4f, @location(0) color: vec3f }; \
@vertex fn vs_main(@builtin(vertex_index) idx: u32) -> VertexOutput { \
    var pos = array<vec2f,3>(vec2f(0.0, 0.6), vec2f(-0.5, -0.3), vec2f(0.5, -0.3)); \
    let ca = cos(u.angle); let sa = sin(u.angle); \
    let p = pos[idx]; \
    let rotated = vec2f(p.x*ca - p.y*sa, p.x*sa + p.y*ca); \
    var colors = array<vec3f,3>(vec3f(1,0.3,0.1), vec3f(0.1,1,0.3), vec3f(0.3,0.1,1)); \
    var out: VertexOutput; \
    out.position = vec4f(rotated, 0.0, 1.0); \
    out.color = colors[idx]; \
    return out; \
} \
@fragment fn fs_main(in: VertexOutput) -> @location(0) vec4f { return vec4f(in.color, 1.0); }"

def msaaTriangle : IO Unit := do
  eprintln "=== MSAATriangle (4x Multi-Sample Anti-Aliasing) ==="
  setLogCallback fun lvl msg => eprintln s!"[{repr lvl}] {msg}"

  let width  : UInt32 := 800
  let height : UInt32 := 600

  let window ← GLFWwindow.mk width height "MSAA Triangle (Space=toggle)"
  let instDesc ← InstanceDescriptor.mk
  let inst ← createInstance instDesc
  let surface ← getSurface inst window
  let adapter ← inst.requestAdapter surface >>= await!
  let ddesc ← DeviceDescriptor.mk "msaa device"
  let device ← adapter.requestDevice ddesc >>= await!
  device.setUncapturedErrorCallback fun t m => eprintln s!"[Device Error] type={t} {m}"
  let queue ← device.getQueue
  let surfFormat ← TextureFormat.get surface adapter
  let config ← SurfaceConfiguration.mk width height device surfFormat
  surface.configure config

  -- Shader + uniform
  let sm ← ShaderModule.mk device (← ShaderModuleDescriptor.mk (← ShaderModuleWGSLDescriptor.mk msaaShaderSrc))
  let unifBuf ← Buffer.mk device (BufferDescriptor.mk "angle" (BufferUsage.uniform.lor BufferUsage.copyDst) 16 false)
  let uLayout ← BindGroupLayout.mkUniform device 0 ShaderStageFlags.vertex 16
  let uBG ← BindGroup.mk device uLayout 0 unifBuf 0 16
  let pipeLayout ← PipelineLayout.mk device #[uLayout]

  -- Two pipelines: 1x (no MSAA) and 4x MSAA
  let cts ← ColorTargetState.mk surfFormat (← BlendState.mk sm)
  let fs ← FragmentState.mk sm cts

  let pipeDesc1 ← RenderPipelineDescriptor.mkSampled sm fs (sampleCount := 1)
  let pipelineNoMSAA ← RenderPipeline.mkWithLayout device pipeDesc1 pipeLayout

  let pipeDesc4 ← RenderPipelineDescriptor.mkSampled sm fs (sampleCount := 4)
  let pipelineMSAA ← RenderPipeline.mkWithLayout device pipeDesc4 pipeLayout

  -- MSAA render target (4x)
  let msaaTex ← device.createMSAATexture width height surfFormat 4
  let msaaView ← msaaTex.createView surfFormat

  let clearColor := Color.mk 0.1 0.1 0.15 1.0

  let mut useMSAA := true
  let mut prevSpace : UInt32 := 0

  eprintln "  Press SPACE to toggle MSAA, ESC/Q to quit"

  while not (← window.shouldClose) do
    GLFW.pollEvents

    let esc ← window.getKey GLFW.keyEscape
    let q ← window.getKey GLFW.keyQ
    if esc == GLFW.press || q == GLFW.press then
      window.setShouldClose true
      continue

    -- Space toggle
    let spaceNow ← window.getKey GLFW.keySpace
    if spaceNow == GLFW.press && prevSpace != GLFW.press then do
      useMSAA := !useMSAA
      if useMSAA then eprintln "  MSAA: ON (4x)"
      else eprintln "  MSAA: OFF"
    prevSpace := spaceNow

    let time ← GLFW.getTime
    let angle := time * 0.8
    queue.writeBuffer unifBuf (floatsToByteArray #[angle, 0, 0, 0])

    let texture ← surface.getCurrent
    if (← texture.status) != .success then continue
    let surfView ← TextureView.mk texture

    let encoder ← device.createCommandEncoder

    if useMSAA then do
      -- Render to MSAA target, resolve to surface
      let rp ← RenderPassEncoder.mkMSAA encoder msaaView surfView clearColor
      rp.setPipeline pipelineMSAA
      rp.setBindGroup 0 uBG
      rp.draw 3 1 0 0
      rp.end
      rp.release
    else do
      -- Render directly to surface (no MSAA)
      let rp ← RenderPassEncoder.mkWithColor encoder surfView clearColor
      rp.setPipeline pipelineNoMSAA
      rp.setBindGroup 0 uBG
      rp.draw 3 1 0 0
      rp.end
      rp.release

    let cmd ← encoder.finish
    queue.submit #[cmd]
    surface.present
    device.poll

  eprintln "=== Done ==="

def main : IO Unit := msaaTriangle
