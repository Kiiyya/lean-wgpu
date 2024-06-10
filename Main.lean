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

  wgpu_playground adapter
  sleep 100

def main : IO Unit := do
  triangle
  eprintln s!"done"

  -- glfw_playground
  -- let window ← GLFWwindow.mk 640 480
  -- while not (← window.shouldClose) do
  --   println! "polling"
  --   GLFW.pollEvents
  -- return

-- #eval main -- works in LSP, but not via `lake build helloworld`.
