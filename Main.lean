import Wgpu
import Wgpu.Async
import Glfw

open IO
open Wgpu

set_option linter.unusedVariables false

def triangle : IO Unit := do
  let window ← GLFWwindow.mk 1366 768

  let desc <- InstanceDescriptor.mk
  let inst <- createInstance desc

  let surface <- getSurface inst window

  let adapter <- inst.requestAdapter surface >>= await!

  let ddesc <- DeviceDescriptor.mk "default device" fun msg => do
    eprintln s!"device was lost: {msg}"
    return pure ()
  let device : Device <- adapter.requestDevice ddesc >>= await!
  device.setUncapturedErrorCallback fun code msg => do
    eprintln s!"uncaptured error, code{code}, message is \"{msg}\""
  let queue : Queue <- device.getQueue
  queue.onSubmittedWorkDone fun status => do
    eprintln s!"queue work done! status {status}"
  let encoder ← device.createCommandEncoder
  encoder.insertDebugMarker "rawr"

  let surface_config := SurfaceConfiguration.mk 1366 768 surface adapter device
  surface.configure surface_config

  let pipeline ← RenderPipeline.mk device

  println! "prout"
  while not (← window.shouldClose) do
    println! "prout1"
    GLFW.pollEvents
    println! "glfw poll"
    let texture ← surface.getCurrent
    let status ← texture.status
    println! "texture status: {repr status}"
    if (status != .success) then continue
    let targetView ← TextureView.mk texture
    println! "view"
    if !(←  targetView.is_valid) then
      println! "invalid"
      continue
    println! "valid texture"
    let encoder ← device.createCommandEncoder
    let renderPass ← RenderPassEncoder.mk encoder targetView
    renderPass.setPipeline pipeline
    renderPass.draw 3 1 0 0
    println! "foo"
    let command <- encoder.finish
    queue.submit #[command]
    surface.present
    -- renderPass.release
    device.poll




    -- pure ()
    -- println! "polling !"
    -- println! (repr <| texture.status)
    -- surface.present
    -- device.poll
    -- GLFW.pollEvents


def main : IO Unit := do
  triangle
  eprintln s!"done"
