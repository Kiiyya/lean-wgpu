import Wgpu
import Wgpu.Async
import Glfw
import Wgsl.Syntax

open IO
open Wgpu

set_option linter.unusedVariables false

/--
  ResizableWindow: Renders a triangle in a resizable window.
  Tests: GLFWwindow.mkResizable, dynamic surface reconfiguration on
  framebuffer size change, SurfaceConfiguration.mkWith.
-/

def resizeShaderSource : String := !WGSL{
struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) color: vec3f,
};

@vertex
fn vs_main(@builtin(vertex_index) idx: u32) -> VertexOutput {
    var positions = array<vec2f, 3>(
        vec2f( 0.0,  0.6),
        vec2f(-0.5, -0.4),
        vec2f( 0.5, -0.4) 
    );
    var colors = array<vec3f, 3>(
        vec3f(1.0, 0.4, 0.4),
        vec3f(0.4, 1.0, 0.4),
        vec3f(0.4, 0.4, 1.0) 
    );
    var out: VertexOutput;
    out.position = vec4f(positions[idx], 0.0, 1.0);
    out.color = colors[idx];
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4f {
    return vec4f(in.color, 1.0);
}
}

def resizableWindow : IO Unit := do
  eprintln "=== Resizable Window (Dynamic Surface Reconfiguration) ==="

  setLogCallback fun lvl msg => eprintln s!"[{repr lvl}] {msg}"
  let window ← GLFWwindow.mkResizable 640 480 "Resizable Window (try resizing!)"

  let desc ← InstanceDescriptor.mk
  let inst ← createInstance desc
  let surface ← getSurface inst window

  let adapter ← inst.requestAdapter surface >>= await!
  adapter.printProperties

  let ddesc ← DeviceDescriptor.mk "resizable window device"
  let device ← adapter.requestDevice ddesc >>= await!
  device.setUncapturedErrorCallback fun code msg => do
    eprintln s!"uncaptured error, code {code}: \"{msg}\""

  let queue ← device.getQueue

  let texture_format ← TextureFormat.get surface adapter

  -- Initial configuration
  let (initW, initH) ← window.getFramebufferSize
  let surface_config ← SurfaceConfiguration.mk initW initH device texture_format
  surface.configure surface_config

  -- Shader
  let shaderWGSL ← ShaderModuleWGSLDescriptor.mk resizeShaderSource
  let shaderDesc ← ShaderModuleDescriptor.mk shaderWGSL
  let shaderModule ← ShaderModule.mk device shaderDesc

  -- Pipeline: simple, no vertex buffer (using @builtin(vertex_index))
  let blendState ← BlendState.mk shaderModule
  let colorTargetState ← ColorTargetState.mk texture_format blendState
  let fragmentState ← FragmentState.mk shaderModule colorTargetState
  let pipelineDesc ← RenderPipelineDescriptor.mk shaderModule fragmentState
  let pipeline ← RenderPipeline.mk device pipelineDesc

  let clearColor := Color.mk 0.12 0.12 0.18 1.0

  eprintln "Entering render loop (press Q or Escape to quit, try resizing the window!)..."

  let mut frameCount : UInt32 := 0
  let mut lastW := initW
  let mut lastH := initH

  while not (← window.shouldClose) do
    GLFW.pollEvents

    let esc ← window.getKey GLFW.keyEscape
    let q ← window.getKey GLFW.keyQ
    if esc == GLFW.press || q == GLFW.press then
      window.setShouldClose true
      continue

    -- Check for resize
    let (curW, curH) ← window.getFramebufferSize
    if curW != lastW || curH != lastH then
      if curW > 0 && curH > 0 then
        eprintln s!"Window resized to {curW}x{curH}, reconfiguring surface..."
        let newConfig ← SurfaceConfiguration.mkWith curW curH device texture_format
        surface.configure newConfig
        lastW := curW
        lastH := curH

    -- Skip rendering if window is minimized
    if lastW == 0 || lastH == 0 then
      continue

    let texture ← surface.getCurrent
    let status ← texture.status
    if (status != .success) then continue
    let targetView ← TextureView.mk texture
    if !(← targetView.is_valid) then continue

    let encoder ← device.createCommandEncoder
    let renderPassEncoder ← RenderPassEncoder.mkWithColor encoder targetView clearColor
    renderPassEncoder.setPipeline pipeline
    renderPassEncoder.draw 3 1 0 0
    renderPassEncoder.end

    let command ← encoder.finish
    queue.submit #[command]
    surface.present
    device.poll

    frameCount := frameCount + 1
    if frameCount % 300 == 0 then
      let t ← GLFW.getTime
      window.setTitle s!"Resizable Window ({lastW}x{lastH}) - {t.toString}s"

  eprintln s!"Rendered {frameCount} frames"
  eprintln "=== Done ==="

def main : IO Unit := resizableWindow
