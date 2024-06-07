import Lake
open Lake DSL

package Wgpu

require alloy from git "https://github.com/tydeu/lean4-alloy/" @ "master"

-- TODO: download from github releases automatically.
def wgpu_native_dir := "wgpu-macos-aarch64-debug"

extern_lib wgpu_native pkg :=
   inputFile <| pkg.dir / wgpu_native_dir / nameToStaticLib "wgpu_native"
  --  inputFile <| pkg.dir / wgpu_native_dir / nameToSharedLib "wgpu_native"

module_data alloy.c.o.export : BuildJob FilePath
module_data alloy.c.o.noexport : BuildJob FilePath

@[default_target]
lean_lib Wgpu where
  weakLeancArgs := #[
    -- These three commented-out lines don't seem necessary for some reason?
    -- s!"-L{__dir__ / wgpu_native_dir |>.toString}",
    -- "-lwgpu_native",
    -- s!"--load-dynlib={__dir__ / wgpu_native_dir / nameToSharedLib "wgpu_native" |>.toString}",
    "-I", __dir__ / wgpu_native_dir |>.toString -- but this one is necessary, I assume because of alloy
  ]
  precompileModules := true
  nativeFacets := fun shouldExport =>
    if shouldExport then #[Module.oExportFacet, `alloy.c.o.export]
    else #[Module.oNoExportFacet, `alloy.c.o.noexport]

lean_exe helloworld where
  root := `Main
