import Lake
open Lake DSL

package Wgpu

require alloy from git "https://github.com/tydeu/lean4-alloy/" @ "master"

section Platform
  inductive Arch where
  | x86_64
  | arm64
  deriving Inhabited, BEq, Repr

  -- Inspired by from https://github.com/lean-dojo/LeanCopilot/blob/main/lakefile.lean
  def getArch? : IO (Option String) := do
    let out ← IO.Process.output {cmd := "uname", args := #["-m"], stdin := .null}
    return out.stdout.trim

  def getArch : Arch :=
    match run_io getArch? with
    | "arm64" => Arch.arm64
    | "aarch64" => Arch.arm64
    | "x86_64" => Arch.x86_64
    | _ => panic! "Unable to determine architecture (you might not have the command `uname` installed or in PATH.)"

  inductive OS where | windows | linux | macos
  deriving Inhabited, BEq, Repr

  open System in
  def getOS : OS :=
    if Platform.isWindows then .windows
    else if Platform.isOSX then .macos
    else .linux
end Platform

-- TODO: download wgpu and glfw automatically.
-- # wgpu_native
-- Download manually from: https://github.com/gfx-rs/wgpu-native/releases
def wgpu_native_dir :=
  let s :=
    match (getOS, getArch) with
    | (.macos, .arm64) => "wgpu-macos-aarch64"
    | (.linux, .x86_64) => "wgpu-linux-x86_64"
    | _ => panic! "Unsupported arch/os combination"
  s!"libs/{s}-debug"

extern_lib wgpu_native pkg :=
   inputFile <| pkg.dir / wgpu_native_dir / nameToStaticLib "wgpu_native"
  --  inputFile <| pkg.dir / wgpu_native_dir / nameToSharedLib "wgpu_native"

module_data alloy.c.o.export : BuildJob FilePath
module_data alloy.c.o.noexport : BuildJob FilePath

lean_lib Glfw where
  moreLeancArgs := #[
    "-I", "/opt/homebrew/Cellar/glfw/3.4/include/",
    "-fPIC"
  ]
  precompileModules := true
  nativeFacets := fun shouldExport =>
    if shouldExport then #[Module.oExportFacet, `alloy.c.o.export]
    else #[Module.oNoExportFacet, `alloy.c.o.noexport]

lean_lib Wgpu where
  moreLeancArgs := #[
    "-fPIC"
  ]
  weakLeancArgs := #[
    "-I", __dir__ / wgpu_native_dir |>.toString
  ]
  precompileModules := true
  nativeFacets := fun shouldExport =>
    if shouldExport then #[Module.oExportFacet, `alloy.c.o.export]
    else #[Module.oNoExportFacet, `alloy.c.o.noexport]

@[default_target]
lean_exe helloworld where
  moreLinkArgs :=
    if getOS == .macos
      then #[
        "-L/opt/homebrew/Cellar/glfw/3.4/lib/", "-lglfw", -- for glfw
        "-framework", "Metal", -- for wgpu
        "-framework", "QuartzCore", -- for wgpu
        "-framework", "CoreFoundation" -- for wgpu
      ]
      else #["-lglfw"]
  root := `Main
