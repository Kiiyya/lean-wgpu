import Wgpu
import Wgpu.Async
import Glfw

open IO
open Wgpu

set_option linter.unusedVariables false

def triangle : IO Unit := do
  let window ← GLFWwindow.mk 640 480

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
  let encoder := device.createCommandEncoder
  encoder.insertDebugMarker "rawr"
  let command <- encoder.finish
  queue.submit #[command]

  let surface_config := SurfaceConfiguration.mk 640 480 surface adapter device
  surface.configure surface_config

  println! "a"
  let texture ← surface.getCurrent
  println! "b"
  let view ← TextureView.mk texture
  println! "c"
  let renderPass ← RenderPassDescriptor.mk encoder view
  println! "d"
  while not (← window.shouldClose) do
    device.poll
    GLFW.pollEvents


def main : IO Unit := do
  triangle
  eprintln s!"done"
