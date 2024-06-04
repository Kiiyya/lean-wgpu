import Lake
open Lake DSL

require batteries from git "https://github.com/leanprover-community/batteries" @ "main"
require socket from git "https://github.com/hargoniX/socket.lean.git" @ "main"
require alloy from git "https://github.com/tydeu/lean4-alloy/" @ "master"

package Wgpu where
  -- add package configuration options here

lean_lib Wgpu where
  -- add library configuration options here

@[default_target]
lean_exe wgpu where
  root := `Main
