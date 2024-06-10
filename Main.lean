import Wgpu
import Glfw

open Wgpu

def triangle : IO Unit := do
  let desc <- InstanceDescriptor.mk
  let inst <- createInstance desc
  let adapter <- inst.requestAdapter >>= await!
  let ddesc <- DeviceDescriptor.mk "asdf"
  let device : Device <- adapter.requestDevice ddesc >>= await!
  wgpu_playground adapter

def main : IO Unit := do
  triangle
  IO.eprintln s!"done"

  -- glfw_playground
  -- let window ← GLFWwindow.mk 640 480
  -- while not (← window.shouldClose) do
  --   println! "polling"
  --   GLFW.pollEvents
  -- return

-- #eval main -- works in LSP, but not via `lake build helloworld`.
