import Wgpu
import Glfw

open IO
open Wgpu

set_option linter.unusedVariables false

/--
  InstanceReport: Tests wgpu-native extension bindings:
  - wgpuGetVersion
  - Instance.generateReport (GlobalReport / BackendReport)
  - Enumerates resources per backend after creating some GPU objects
-/
def printBackend (name : String) (br : BackendReport) : IO Unit := do
  let a := br.numAdapters
  let d := br.numDevices
  let q := br.numQueues
  let pl := br.numPipelineLayouts
  let sm := br.numShaderModules
  let bgl := br.numBindGroupLayouts
  let bg := br.numBindGroups
  let cb := br.numCommandBuffers
  let rb := br.numRenderBundles
  let rp := br.numRenderPipelines
  let cp := br.numComputePipelines
  let bu := br.numBuffers
  let tx := br.numTextures
  let tv := br.numTextureViews
  let sa := br.numSamplers
  let qs := br.numQuerySets
  let total := a + d + q + pl + sm + bgl + bg + cb + rb + rp + cp + bu + tx + tv + sa + qs
  if total > 0 then
    eprintln s!"  {name}:"
    eprintln s!"    Adapters={a} Devices={d} Queues={q}"
    eprintln s!"    PipelineLayouts={pl} ShaderModules={sm}"
    eprintln s!"    BindGroupLayouts={bgl} BindGroups={bg}"
    eprintln s!"    CmdBuffers={cb} RenderBundles={rb}"
    eprintln s!"    RenderPipelines={rp} ComputePipelines={cp}"
    eprintln s!"    Buffers={bu} Textures={tx} TextureViews={tv}"
    eprintln s!"    Samplers={sa} QuerySets={qs}"
  else
    eprintln s!"  {name}: (no resources)"

def printReport (label : String) (r : GlobalReport) : IO Unit := do
  eprintln s!"--- {label} ---"
  printBackend "Vulkan" r.vulkan
  printBackend "Metal" r.metal
  printBackend "DX12" r.dx12
  printBackend "GL" r.gl

def doReport (label : String) (inst : Instance) : IO GlobalReport := do
  let r ← Instance.generateReport inst
  printReport label r
  return r

def instanceReport : IO Unit := do
  eprintln "=== Instance Report Test ==="

  -- wgpu-native version
  let ver ← wgpuVersion
  eprintln s!"wgpu-native version: {ver}"

  -- Create instance and hidden window for surface
  let desc ← InstanceDescriptor.mk
  let inst ← createInstance desc
  GLFW.windowHint GLFW.hintVisible 0
  GLFW.windowHint GLFW.hintClientAPI GLFW.hintNoAPI
  let window ← GLFWwindow.mk 64 64 "instancereport"
  let surface ← getSurface inst window

  eprintln ""
  let _ ← doReport "After createInstance" inst

  -- Request adapter
  let adapter ← inst.requestAdapter surface >>= await!
  eprintln ""
  let _ ← doReport "After requestAdapter" inst

  -- Request device
  let ddesc ← DeviceDescriptor.mk "report-device"
  let device ← adapter.requestDevice ddesc >>= await!
  let _queue ← device.getQueue

  eprintln ""
  let r3 : GlobalReport ← doReport "After requestDevice" inst

  -- Create some resources
  let buf1 ← Buffer.mk device (BufferDescriptor.mk "" BufferUsage.copyDst 256 false)
  let buf2 ← Buffer.mk device (BufferDescriptor.mk "" BufferUsage.copySrc 256 false)
  let buf3 ← Buffer.mk device (BufferDescriptor.mk "" (BufferUsage.mapRead.lor BufferUsage.copyDst) 128 false)

  eprintln ""
  let r4 : GlobalReport ← doReport "After creating 3 buffers" inst

  -- Check buffer count change
  let vkBefore := r3.vulkan.numBuffers
  let vkAfter := r4.vulkan.numBuffers
  let glBefore := r3.gl.numBuffers
  let glAfter := r4.gl.numBuffers
  if vkAfter > vkBefore then
    eprintln s!"✓ Vulkan buffer count: {vkBefore} → {vkAfter}"
  else if glAfter > glBefore then
    eprintln s!"✓ GL buffer count: {glBefore} → {glAfter}"
  else
    eprintln s!"? No buffer count change detected"

  -- Destroy buffers
  Buffer.destroy buf1
  Buffer.destroy buf2
  Buffer.destroy buf3

  eprintln ""
  let _ ← doReport "After destroying 3 buffers" inst

  window.setShouldClose true
  eprintln ""
  eprintln "=== Instance Report Test Done ==="

def main : IO Unit := instanceReport
