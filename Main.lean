import Wgpu
import Glfw

def main : IO Unit := do
  triangle
  IO.eprintln s!"done"

-- #eval main -- works in LSP, but not via `lake build helloworld`.
