import Lake
open Lake DSL
open System

package Wgpu

require alloy from git "https://github.com/sio-funmatsu/lean4-alloy/" @ "master"

section Platform
  inductive Arch where
  | x86_64
  | arm64
  deriving Inhabited, BEq, Repr

  def systemCommand (cmd : String) (args : Array String): IO String := do
    let out ← IO.Process.output {cmd, args, stdin := .null}
    return out.stdout.trimAscii.toString

  -- Inspired by from https://github.com/lean-dojo/LeanCopilot/blob/main/lakefile.lean
  def getArch? : IO String := systemCommand "uname" #["-m"]

  def getArch : Arch :=
    match run_io getArch? with
    | "arm64" => Arch.arm64
    | "aarch64" => Arch.arm64
    | "x86_64" => Arch.x86_64
    | _ => panic! "Unable to determine architecture (you might not have the command `uname` installed or in PATH.)"

  inductive OS where | windows | linux | macos
  deriving Inhabited, BEq, Repr

  def getOS : OS :=
    if Platform.isWindows then .windows
    else if Platform.isOSX then .macos
    else .linux
end Platform

module_data alloy.c.o.export : FilePath
module_data alloy.c.o.noexport : FilePath

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
def glfw_path : Option String :=
  match (getOS, getArch) with
  | (.macos, _) => pure (run_io (systemCommand "brew" #["--prefix", "glfw"])) -- returns for example "/opt/homebrew/opt/glfw"
  | (.linux,_) => none
  | _ => panic! "Unsupported arch/os combination"

def glfw_include_path : Option String := do
  let path ← glfw_path
  return path ++ "/include"

def glfw_library_path : Option String := do
  let path ← glfw_path
  return path ++ "/lib"

target glfw3webgpu pkg : FilePath := do
  proc {
    cmd := "clang",
    args :=
      let args := if getOS == .macos then #["-x", "objective-c","-I", glfw_include_path.get!] else #[]
      args ++ #[
        "-o", pkg.dir / "glfw3webgpu" / "glfw3webgpu.o" |>.toString,
        "-c", pkg.dir / "glfw3webgpu" / "glfw3webgpu.c" |>.toString,
        "-I", pkg.dir / wgpu_native_dir |>.toString
      ]
  }
  inputBinFile <| pkg.dir / "glfw3webgpu" / "glfw3webgpu.o"

section Glfw
  /-- I guess long-term we'll extract Glfw bindings into its own repo? -/
  lean_lib Glfw where
    moreLeancArgs :=
      let args := if getOS == .macos then #["-I", glfw_include_path.get!] else #[]
      args ++ #[
        "-I", __dir__ / wgpu_native_dir |>.toString,
        "-I", __dir__ / "glfw3webgpu" |>.toString,
        "-fPIC",
        "-Wall"
      ]

    moreLinkArgs := if getOS == .macos
      then #[
        "-framework", "Cocoa",
        "-framework", "CoreVideo",
        "-framework", "IOKit",
        "-framework", "QuartzCore" ]
      else #[]
    precompileModules := true
    nativeFacets := fun shouldExport =>
      if shouldExport then #[Module.oExportFacet, `module.alloy.c.o.export]
      else #[Module.oNoExportFacet, `module.alloy.c.o.noexport]
    extraDepTargets := #[`glfw3webgpu]
end Glfw

section wgpu_native
  extern_lib wgpu_native pkg :=
    inputBinFile <| pkg.dir / wgpu_native_dir / nameToStaticLib "wgpu_native"
end wgpu_native


lean_lib Wgpu where
  moreLeancArgs := #[
    "-Wall",
    "-fPIC"
  ]
  weakLeancArgs :=
    let args := if getOS == .macos then #["-I", glfw_include_path.get!] else #[]
    args ++ #[
    "-I", __dir__ / wgpu_native_dir |>.toString
  ]
  precompileModules := true
  nativeFacets := fun shouldExport =>
    if shouldExport then #[Module.oExportFacet, `module.alloy.c.o.export]
    else #[Module.oNoExportFacet, `module.alloy.c.o.noexport]
  extraDepTargets := #[`glfw3webgpu]

@[default_target]
lean_exe helloworld where
  moreLinkArgs :=
    if getOS == .macos
      then #[
        "./glfw3webgpu/glfw3webgpu.o",
        s!"-L{glfw_library_path.get!}", "-lglfw",
        "-framework", "Metal", -- for wgpu
        "-framework", "QuartzCore", -- for wgpu
        "-framework", "CoreFoundation" -- for wgpu
      ]
      else #[
        "./glfw3webgpu/glfw3webgpu.o",
        "-L/usr/lib/x86_64-linux-gnu", "-lglfw"
      ]
  root := `Examples.Main
  extraDepTargets := #[`glfw3webgpu]
  nativeFacets := fun shouldExport =>
    if shouldExport then #[Module.oExportFacet, `module.alloy.c.o.export]
    else #[Module.oNoExportFacet, `module.alloy.c.o.noexport]

def exeLinkArgs :=
  if getOS == .macos
    then #[
      "./glfw3webgpu/glfw3webgpu.o",
      s!"-L{glfw_library_path.get!}", "-lglfw",
      "-framework", "Metal",
      "-framework", "QuartzCore",
      "-framework", "CoreFoundation"
    ]
    else #[
      "./glfw3webgpu/glfw3webgpu.o",
      "-L/usr/lib/x86_64-linux-gnu", "-lglfw"
    ]

def exeNativeFacets : Bool → Array (ModuleFacet FilePath) := fun shouldExport =>
  if shouldExport then #[Module.oExportFacet, `module.alloy.c.o.export]
  else #[Module.oNoExportFacet, `module.alloy.c.o.noexport]

lean_exe deviceinfo where
  moreLinkArgs := exeLinkArgs
  root := `Examples.DeviceInfo
  extraDepTargets := #[`glfw3webgpu]
  nativeFacets := exeNativeFacets

lean_exe coloredtriangle where
  moreLinkArgs := exeLinkArgs
  root := `Examples.ColoredTriangle
  extraDepTargets := #[`glfw3webgpu]
  nativeFacets := exeNativeFacets

lean_exe uniformtriangle where
  moreLinkArgs := exeLinkArgs
  root := `Examples.UniformTriangle
  extraDepTargets := #[`glfw3webgpu]
  nativeFacets := exeNativeFacets

lean_exe indexedquad where
  moreLinkArgs := exeLinkArgs
  root := `Examples.IndexedQuad
  extraDepTargets := #[`glfw3webgpu]
  nativeFacets := exeNativeFacets

lean_exe texturedquad where
  moreLinkArgs := exeLinkArgs
  root := `Examples.TexturedQuad
  extraDepTargets := #[`glfw3webgpu]
  nativeFacets := exeNativeFacets

lean_exe computedouble where
  moreLinkArgs := exeLinkArgs
  root := `Examples.ComputeDouble
  extraDepTargets := #[`glfw3webgpu]
  nativeFacets := exeNativeFacets

lean_exe depthcube where
  moreLinkArgs := exeLinkArgs
  root := `Examples.DepthCube
  extraDepTargets := #[`glfw3webgpu]
  nativeFacets := exeNativeFacets

lean_exe instancing where
  moreLinkArgs := exeLinkArgs
  root := `Examples.Instancing
  extraDepTargets := #[`glfw3webgpu]
  nativeFacets := exeNativeFacets

lean_exe resizablewindow where
  moreLinkArgs := exeLinkArgs
  root := `Examples.ResizableWindow
  extraDepTargets := #[`glfw3webgpu]
  nativeFacets := exeNativeFacets

lean_exe linegrid where
  moreLinkArgs := exeLinkArgs
  root := `Examples.LineGrid
  extraDepTargets := #[`glfw3webgpu]
  nativeFacets := exeNativeFacets

lean_exe mousepaint where
  moreLinkArgs := exeLinkArgs
  root := `Examples.MousePaint
  extraDepTargets := #[`glfw3webgpu]
  nativeFacets := exeNativeFacets

lean_exe rendertotexture where
  moreLinkArgs := exeLinkArgs
  root := `Examples.RenderToTexture
  extraDepTargets := #[`glfw3webgpu]
  nativeFacets := exeNativeFacets

lean_exe gameoflife where
  moreLinkArgs := exeLinkArgs
  root := `Examples.GameOfLife
  extraDepTargets := #[`glfw3webgpu]
  nativeFacets := exeNativeFacets

lean_exe bouncingballs where
  moreLinkArgs := exeLinkArgs
  root := `Examples.BouncingBalls
  extraDepTargets := #[`glfw3webgpu]
  nativeFacets := exeNativeFacets

lean_exe particles where
  moreLinkArgs := exeLinkArgs
  root := `Examples.Particles
  extraDepTargets := #[`glfw3webgpu]
  nativeFacets := exeNativeFacets

lean_exe postprocessblur where
  moreLinkArgs := exeLinkArgs
  root := `Examples.PostProcessBlur
  extraDepTargets := #[`glfw3webgpu]
  nativeFacets := exeNativeFacets

lean_exe msaatriangle where
  moreLinkArgs := exeLinkArgs
  root := `Examples.MSAATriangle
  extraDepTargets := #[`glfw3webgpu]
  nativeFacets := exeNativeFacets

lean_exe stenciloutline where
  moreLinkArgs := exeLinkArgs
  root := `Examples.StencilOutline
  extraDepTargets := #[`glfw3webgpu]
  nativeFacets := exeNativeFacets

lean_exe wireframe where
  moreLinkArgs := exeLinkArgs
  root := `Examples.Wireframe
  extraDepTargets := #[`glfw3webgpu]
  nativeFacets := exeNativeFacets

lean_exe shadowmap where
  moreLinkArgs := exeLinkArgs
  root := `Examples.ShadowMap
  extraDepTargets := #[`glfw3webgpu]
  nativeFacets := exeNativeFacets

lean_exe keyboardcallback where
  moreLinkArgs := exeLinkArgs
  root := `Examples.KeyboardCallback
  extraDepTargets := #[`glfw3webgpu]
  nativeFacets := exeNativeFacets

lean_exe bufferreadwrite where
  moreLinkArgs := exeLinkArgs
  root := `Examples.BufferReadWrite
  extraDepTargets := #[`glfw3webgpu]
  nativeFacets := exeNativeFacets

lean_exe adapterenum where
  moreLinkArgs := exeLinkArgs
  root := `Examples.AdapterEnum
  extraDepTargets := #[`glfw3webgpu]
  nativeFacets := exeNativeFacets

lean_exe glfwinfo where
  moreLinkArgs := exeLinkArgs
  root := `Examples.GlfwInfo
  extraDepTargets := #[`glfw3webgpu]
  nativeFacets := exeNativeFacets

lean_exe instancereport where
  moreLinkArgs := exeLinkArgs
  root := `Examples.InstanceReport
  extraDepTargets := #[`glfw3webgpu]
  nativeFacets := exeNativeFacets

lean_exe raytracer where
  moreLinkArgs := exeLinkArgs
  root := `Examples.RayTracer
  extraDepTargets := #[`glfw3webgpu]
  nativeFacets := exeNativeFacets
