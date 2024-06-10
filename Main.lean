import Wgpu
import Wgpu.Async
import Glfw

open IO
open Wgpu

set_option linter.unusedVariables false

def triangle : IO Unit := do
  let desc <- InstanceDescriptor.mk
  let inst <- createInstance desc
  let adapter <- inst.requestAdapter >>= await!
  let ddesc <- DeviceDescriptor.mk "default device" fun msg => do
    eprintln s!"device was lost: {msg}"
    return pure ()
  let device : Device <- adapter.requestDevice ddesc >>= await!
  device.setUncapturedErrorCallback fun code msg => do
    eprintln s!"uncaptured error, code{code}, message is \"{msg}\""
  let queue : Queue <- device.getQueue
  queue.onSubmittedWorkDone fun status => do
    eprintln s!"queue work done! status {status}"
  let encoder <- device.createCommandEncoder
  encoder.insertDebugMarker "rawr"
  let command <- encoder.finish
  queue.submit #[command]

  wgpu_playground adapter
  sleep 10

def main : IO Unit := do
  triangle

  glfw_playground
  let window ← GLFWwindow.mk 640 480
  while not (← window.shouldClose) do
    -- println! "polling"
    GLFW.pollEvents

  eprintln s!"done"

-- #eval main -- works in LSP, but not via `lake build helloworld`.
