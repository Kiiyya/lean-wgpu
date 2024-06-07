import Wgpu

def main : IO Unit := do
  let res <- test 0
  IO.println s!"{res}"

#eval main
