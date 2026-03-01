import Wgpu
import Wgpu.Async
import Glfw

open IO
open Wgpu

set_option linter.unusedVariables false

/--
  AdapterEnum: A headless test that exercises:
  - Instance.enumerateAdapters (wgpu-native extension)
  - Adapter.getProperties (structured return)
  - Adapter features & limits for each adapter
  - Surface capabilities
  - wgpuVersion
-/
def adapterEnum : IO Unit := do
  eprintln "=== Adapter Enumeration Test ==="

  setLogCallback fun lvl msg => eprintln s!"[{repr lvl}] {msg}"

  -- Print wgpu-native version
  let ver ← wgpuVersion
  eprintln s!"wgpu-native version: {ver}"

  let window ← GLFWwindow.mk 320 240 "Adapter Enum"
  let desc ← InstanceDescriptor.mk
  let inst ← createInstance desc
  let surface ← getSurface inst window

  -- ── Enumerate all adapters ──
  let adapters ← inst.enumerateAdapters
  eprintln s!"\nFound {adapters.size} adapter(s):"

  for h : i in [:adapters.size] do
    let a := adapters[i]
    let (vendorID, deviceID, vendorName, driverDesc, adapterType, backendType) ← a.getProperties
    let typeName := match adapterType with
      | 0 => "DiscreteGPU"
      | 1 => "IntegratedGPU"
      | 2 => "CPU"
      | _ => s!"Unknown({adapterType})"
    let backendName := match backendType with
      | 0 => "Undefined"
      | 1 => "Null"
      | 2 => "WebGPU"
      | 3 => "D3D11"
      | 4 => "D3D12"
      | 5 => "Metal"
      | 6 => "Vulkan"
      | 7 => "OpenGL"
      | 8 => "OpenGLES"
      | _ => s!"Unknown({backendType})"

    eprintln s!"\n--- Adapter [{i}] ---"
    eprintln s!"  Vendor: {vendorName} (ID: {vendorID})"
    eprintln s!"  Device ID: {deviceID}"
    eprintln s!"  Driver: {driverDesc}"
    eprintln s!"  Type: {typeName}"
    eprintln s!"  Backend: {backendName}"

    -- Features (known enum values)
    let feats ← a.features
    eprintln s!"  Standard Features ({feats.size}):"
    for f in feats do
      eprintln s!"    {f}"

    -- All features including native extensions (as raw IDs)
    let rawFeats ← a.featuresRaw
    eprintln s!"  All Feature IDs ({rawFeats.size}):"
    for f in rawFeats do
      eprintln s!"    0x{String.ofList (Nat.toDigits 16 f.toNat)}"

    -- Limits
    let lim ← a.getLimits
    eprintln s!"  Key limits:"
    eprintln s!"    maxTextureDimension2D: {lim.maxTextureDimension2D}"
    eprintln s!"    maxBindGroups: {lim.maxBindGroups}"
    eprintln s!"    maxVertexBuffers: {lim.maxVertexBuffers}"
    eprintln s!"    maxStorageBufferBindingSize: {lim.maxStorageBufferBindingSize}"
    eprintln s!"    maxComputeWorkgroupSizeX: {lim.maxComputeWorkgroupSizeX}"
    eprintln s!"    maxComputeWorkgroupsPerDimension: {lim.maxComputeWorkgroupsPerDimension}"

    -- Check specific features
    let hasTimestamp ← a.hasFeature Feature.TimestampQuery
    eprintln s!"    TimestampQuery supported: {hasTimestamp}"

  -- ── Surface Capabilities (using the default adapter) ──
  eprintln "\n--- Surface Capabilities ---"
  let defaultAdapter ← inst.requestAdapter surface >>= await!
  let (formats, presentModes, alphaModes) ← surface.getCapabilities defaultAdapter

  eprintln s!"  Supported formats ({formats.size}):"
  for f in formats do
    eprintln s!"    {repr f}"

  eprintln s!"  Present modes ({presentModes.size}):"
  for pm in presentModes do
    eprintln s!"    {repr pm}"

  eprintln s!"  Alpha modes ({alphaModes.size}):"
  for am in alphaModes do
    eprintln s!"    {repr am}"

  -- Close
  window.setShouldClose true
  eprintln "\n=== Adapter Enumeration Test Done ==="

def main : IO Unit := adapterEnum
