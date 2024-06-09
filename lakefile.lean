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

-- # glfw
-- We need this for opening a window
-- Download manually from: https://www.glfw.org/download.html
-- ! The GLFW binaries come with `libglfw3.a` and `libglfw.3.dylib`, note the extra `.` here. This confuses lake.
-- ! You need to rename (symlink is insufficient) it to `libglfw3.dylib`. Might differ for linux/windows.
def glfw_dir := "libs/glfw-3.4.bin.MACOS"
run_cmd do
  if getOS != .linux then
    let stx ← `(
      extern_lib glfw pkg := do
        -- ! Okay, no clue why glfw works with the shared lib, but not static lib /shrug.
          inputFile <| pkg.dir / glfw_dir / "lib-arm64" / nameToSharedLib "glfw.3"
    )
    Lean.Elab.Command.elabCommand stx

module_data alloy.c.o.export : BuildJob FilePath
module_data alloy.c.o.noexport : BuildJob FilePath

@[default_target]
lean_lib Wgpu where
  moreLeancArgs := #[
    "-fPIC"
  ]
  weakLeancArgs := #[
    -- These three commented-out lines don't seem necessary for some reason?
    -- s!"-L{__dir__ / wgpu_native_dir |>.toString}",
    -- "-lwgpu_native",
    -- s!"--load-dynlib={__dir__ / wgpu_native_dir / nameToSharedLib "wgpu_native" |>.toString}",
    "-I", __dir__ / wgpu_native_dir |>.toString
  ]
  precompileModules := true
  nativeFacets := fun shouldExport =>
    if shouldExport then #[Module.oExportFacet, `alloy.c.o.export]
    else #[Module.oNoExportFacet, `alloy.c.o.noexport]

lean_exe helloworld where
  moreLinkArgs :=
    if getOS == .macos
      then #[
        "-framework", "AppKit",
        "-framework", "Metal",
        "-framework", "QuartzCore",
        "-framework", "CoreFoundation"]
      else #["-lglfw"]
  root := `Main
