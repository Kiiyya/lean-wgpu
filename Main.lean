import Wgpu

-- #check Task
-- #check IO.Promise

def main : IO Unit := do
  let res <- triangle 0
  IO.eprintln s!"result: {res}"

-- #eval test 0 -- this works, prints `8`.
-- #eval main -- works in LSP, but not via `lake build helloworld`.
