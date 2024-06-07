import Wgpu

def main : IO Unit := do
  let res <- helloworld 0
  IO.println s!"{res}"

#eval test 0 -- this works, prints `8`.
#eval main -- works in LSP, but not via `lake build helloworld`.
