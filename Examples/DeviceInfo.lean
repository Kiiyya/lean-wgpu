import Wgpu
import Wgpu.Async
import Glfw

open IO
open Wgpu

set_option linter.unusedVariables false

/--
  DeviceInfo: A headless test that initializes WGPU, creates a window,
  requests an adapter and device, and prints detailed info about them.
  Tests: adapter properties, adapter/device limits, adapter/device features,
  GLFW window utilities (getWindowSize, getFramebufferSize, getTime).
-/
def deviceInfo : IO Unit := do
  eprintln "=== Device Info Test ==="

  setLogCallback fun lvl msg => eprintln s!"[{repr lvl}] {msg}"

  let window ← GLFWwindow.mk 320 240 "Device Info"

  -- Test GLFW utilities
  let (ww, wh) ← window.getWindowSize
  eprintln s!"Window size: {ww} x {wh}"
  let (fw, fh) ← window.getFramebufferSize
  eprintln s!"Framebuffer size: {fw} x {fh}"
  let t ← GLFW.getTime
  eprintln s!"GLFW time: {t}"

  -- Set title
  window.setTitle "Device Info (updated title)"

  let desc ← InstanceDescriptor.mk
  let inst ← createInstance desc
  let surface ← getSurface inst window

  let adapter ← inst.requestAdapter surface >>= await!
  eprintln ""
  eprintln "--- Adapter Properties ---"
  adapter.printProperties

  eprintln ""
  eprintln "--- Adapter Features ---"
  let adapterFeats ← adapter.features
  for f in adapterFeats do
    eprintln s!"  {f}"

  eprintln ""
  eprintln "--- Adapter Limits ---"
  let aLimits ← adapter.getLimits
  eprintln s!"  maxTextureDimension2D: {aLimits.maxTextureDimension2D}"
  eprintln s!"  maxBindGroups: {aLimits.maxBindGroups}"
  eprintln s!"  maxVertexBuffers: {aLimits.maxVertexBuffers}"
  eprintln s!"  maxVertexAttributes: {aLimits.maxVertexAttributes}"
  eprintln s!"  maxUniformBufferBindingSize: {aLimits.maxUniformBufferBindingSize}"
  eprintln s!"  maxStorageBufferBindingSize: {aLimits.maxStorageBufferBindingSize}"
  eprintln s!"  maxComputeWorkgroupSizeX: {aLimits.maxComputeWorkgroupSizeX}"

  let ddesc ← DeviceDescriptor.mk "info device"
  let device ← adapter.requestDevice ddesc >>= await!

  eprintln ""
  eprintln "--- Device Features ---"
  let deviceFeats ← device.features
  for f in deviceFeats do
    eprintln s!"  {f}"

  eprintln ""
  eprintln "--- Device Limits ---"
  let dLimits ← device.getLimits
  eprintln s!"  maxTextureDimension2D: {dLimits.maxTextureDimension2D}"
  eprintln s!"  maxBindGroups: {dLimits.maxBindGroups}"
  eprintln s!"  maxVertexBuffers: {dLimits.maxVertexBuffers}"
  eprintln s!"  maxVertexAttributes: {dLimits.maxVertexAttributes}"
  eprintln s!"  maxUniformBufferBindingSize: {dLimits.maxUniformBufferBindingSize}"
  eprintln s!"  maxStorageBufferBindingSize: {dLimits.maxStorageBufferBindingSize}"
  eprintln s!"  maxComputeWorkgroupSizeX: {dLimits.maxComputeWorkgroupSizeX}"

  -- Quick key poll test (window is briefly open)
  let escState ← window.getKey GLFW.keyEscape
  eprintln s!"Escape key state: {escState}"
  let (mx, my) ← window.getCursorPos
  eprintln s!"Cursor position: ({mx}, {my})"

  -- Close immediately
  window.setShouldClose true

  let t2 ← GLFW.getTime
  eprintln s!"GLFW time at end: {t2}"
  eprintln "=== Done ==="

def main : IO Unit := deviceInfo
