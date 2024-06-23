import Wgpu
import Wgpu.Async
import Glfw

open IO
open Wgpu

set_option linter.unusedVariables false

def triangle : IO Unit := do
  let window ← GLFWwindow.mk 640 480 "T R I A N G L E"

  setLogLevel .warn
  setLogCallback fun lvl msg => eprintln s!"[{repr lvl}] {msg}"

  let inst <- createInstance

  let surface <- getSurface inst window

  let adapter <- inst.requestAdapter surface >>= await!
  adapter.printProperties
  let texture_format <- surface.getPreferredFormat adapter

  let ddesc <- DeviceDescriptor.mk "default device" fun msg => do
    eprintln s!"device was lost: {msg}"

  let device : Device <- adapter.requestDevice ddesc >>= await!
  device.setUncapturedErrorCallback fun code msg => do
    eprintln s!"uncaptured error, code{code}, message is \"{msg}\""

  eprintln s!"Have features: {<- device.features}"

  surface.configure device texture_format

  -- BEGIN "InitializePipeline"
  let shaderModule : ShaderModule <- device.createShaderModule shaderSource
  let pipeline <- device.createRenderPipeline texture_format shaderModule
  -- END "InitializePipeline"

  let queue : Queue <- device.getQueue
  queue.onSubmittedWorkDone fun status => do
    eprintln s!"queue work done! status {status}"
  -- * Pretty sure until this point, we are doing exactly what the tutorial is doing.

  while not (← window.shouldClose) do
    GLFW.pollEvents
    let texture : SurfaceTexture ← surface.getCurrent
    let status : SurfaceTextureStatus ← texture.status
    if (status != .success) then continue
    let targetView ← TextureView.mk texture
    if !(←  targetView.is_valid) then
      -- println! "invalid"
      continue

    let encoder : CommandEncoder ← device.createCommandEncoder
    let renderPassEncoder : RenderPassEncoder ← RenderPassEncoder.mk encoder targetView
    renderPassEncoder.setPipeline pipeline
    renderPassEncoder.draw 3 1 0 0
    renderPassEncoder.end
    let command <- encoder.finish
    renderPassEncoder.release

    queue.submit #[command]
    surface.present
    device.poll

def main : IO Unit := do
  triangle
  eprintln s!"done"
