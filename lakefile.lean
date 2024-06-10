import Lake
open Lake DSL

package Wgpu

require alloy from git "https://github.com/tydeu/lean4-alloy/" @ "master"

section Platform
  inductive Arch where
  | x86_64
  | arm64
  deriving Inhabited, BEq, Repr

  def systemCommand (cmd : String) (args : Array String): IO String := do
    let out ← IO.Process.output {cmd, args, stdin := .null}
    return out.stdout.trim

  -- Inspired by from https://github.com/lean-dojo/LeanCopilot/blob/main/lakefile.lean
  def getArch? : IO (Option String) := systemCommand "uname" #["-m"]

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

module_data alloy.c.o.export : BuildJob FilePath
module_data alloy.c.o.noexport : BuildJob FilePath

-- TODO: download wgpu automatically.
-- Download manually from: https://github.com/gfx-rs/wgpu-native/releases
def wgpu_native_dir :=
  let s :=
    match (getOS, getArch) with
    | (.macos, .arm64) => "wgpu-macos-aarch64"
    | (.linux, .x86_64) => "wgpu-linux-x86_64"
    | _ => panic! "Unsupported arch/os combination"
  s!"libs/{s}-debug"

/- GLFW is a cross-platform library for opening a window. -/
def glfw_path : String :=
  match (getOS, getArch) with
  | (.macos, _) => (run_io (systemCommand "brew" #["--prefix", "glfw"])) -- returns for example "/opt/homebrew/opt/glfw"
  | _ => panic! "Unsupported arch/os combination"
def glfw_include_path : String := glfw_path ++ "/include"
def glfw_library_path : String := glfw_path ++ "/lib"

-- def buildC

-- Inspiration from Utensil's repo, maybe you can run a script here directly, idk.
target glfw3webgpu pkg : FilePath := do
  compileO
    (pkg.dir / "glfw3webgpu" / "glfw3webgpu.o")
    (pkg.dir / "glfw3webgpu" / "glfw3webgpu.c")
    #["-I",pkg.dir / wgpu_native_dir |>.toString]
  inputFile <| pkg.dir / "glfw3webgpu" / "glfw3webgpu.o"
  -- Package.afterReleaseSync sorry
  -- afterReleaseSync build
  -- sorry

section Glfw
  /-- I guess long-term we'll extract Glfw bindings into its own repo? -/
  lean_lib Glfw where
    moreLeancArgs := Id.run do
      let mut args := #[
        "-I", __dir__ / wgpu_native_dir |>.toString,
        "-I", __dir__ / "glfw3webgpu" |>.toString,
        "-I", glfw_include_path,
        "-fPIC"
      ]
      if getOS == .macos then args := args ++ #["-x", "objective-c"]
      return args

    moreLinkArgs := if getOS == .macos then
    #[
      "-framework", "Cocoa",
      "-framework", "CoreVideo",
      "-framework", "IOKit",
      "-framework", "QuartzCore"
    ] else #[]
    precompileModules := true
    nativeFacets := fun shouldExport =>
      if shouldExport then #[Module.oExportFacet, `alloy.c.o.export]
      else #[Module.oNoExportFacet, `alloy.c.o.noexport]
    extraDepTargets := #[`glfw3webgpu]

end Glfw

-- section GlfwWgpu
--   /- WebGPU and GLFW are not aware of each other.
--     We need to obtain a surface (the glfw window) for webgpu to draw on.
--     This little library helps with that.  -/
--   extern_lib GlfwWgpu :=
--     compileO (__dir__ / "glfw3webgpu" / "glfw3webgpu.o") (__dir__ / "glfw3webgpu" / "glfw3webgpu.c")
--     sorry
-- end GlfwWgpu

section wgpu_native

  extern_lib wgpu_native pkg :=
    inputFile <| pkg.dir / wgpu_native_dir / nameToStaticLib "wgpu_native"
end wgpu_native

lean_lib Wgpu where
  moreLeancArgs := #[
    "-fPIC"
  ]
  weakLeancArgs := #[
    "-I", glfw_include_path,
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
        s!"-L{glfw_library_path}", "-lglfw",
        "-framework", "Metal", -- for wgpu
        "-framework", "QuartzCore", -- for wgpu
        "-framework", "CoreFoundation" -- for wgpu
      ]
      else #["-lglfw"]
  root := `Main
