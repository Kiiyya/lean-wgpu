import Alloy.C
import Wgpu.Async
open scoped Alloy.C
open IO

namespace Wgpu

alloy c include <stdio.h>
alloy c include <stdlib.h>
alloy c include <string.h>
alloy c include <lean/lean.h>
alloy c include <wgpu.h>
alloy c include <webgpu.h>

alloy c section
  -- Userdata struct for synchronous wgpu callbacks.
  -- wgpu-native v0.19 calls request callbacks synchronously before the request function returns.
  typedef struct {
    lean_object *result;
  } wgpu_callback_data;
end

/- # Instance -/

alloy c opaque_extern_type InstanceDescriptor => WGPUInstanceDescriptor where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUInstanceDescriptor\n");
    -- Free the chained WGPUInstanceExtras if present
    if (ptr->nextInChain != NULL) {
      free((void*)ptr->nextInChain);
    }
    free(ptr);

alloy c opaque_extern_type Instance => WGPUInstance where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUInstance\n");
    wgpuInstanceRelease(*ptr);
    free(ptr);

alloy c extern
def InstanceDescriptor.mk : IO InstanceDescriptor := {
  fprintf(stderr, "mk WGPUInstanceDescriptor\n");
  WGPUInstanceExtras * instanceExtras = calloc(1,sizeof(WGPUInstanceExtras));
  instanceExtras->chain.sType = (WGPUSType)WGPUSType_InstanceExtras;
  instanceExtras->backends = WGPUInstanceBackend_Primary;

  WGPUInstanceDescriptor* desc = calloc(1,sizeof(WGPUInstanceDescriptor));
  desc->nextInChain = &instanceExtras->chain;
  return lean_io_result_mk_ok(to_lean<InstanceDescriptor>(desc));
}

/-- Create an instance descriptor with a specific set of backend flags.
    Use InstanceBackend constants (e.g. `InstanceBackend.vulkan`).
    Combine with `|||`. Pass `InstanceBackend.all` for all backends. -/
alloy c extern
def InstanceDescriptor.mkWithBackends (backends : UInt32) : IO InstanceDescriptor := {
  fprintf(stderr, "mk WGPUInstanceDescriptor (backends=0x%x)\n", backends);
  WGPUInstanceExtras * instanceExtras = calloc(1,sizeof(WGPUInstanceExtras));
  instanceExtras->chain.sType = (WGPUSType)WGPUSType_InstanceExtras;
  instanceExtras->backends = (WGPUInstanceBackendFlags)backends;

  WGPUInstanceDescriptor* desc = calloc(1,sizeof(WGPUInstanceDescriptor));
  desc->nextInChain = &instanceExtras->chain;
  return lean_io_result_mk_ok(to_lean<InstanceDescriptor>(desc));
}

alloy c extern
def createInstance (desc : InstanceDescriptor) : IO Instance := {
  fprintf(stderr, "mk WGPUInstance\n");
  WGPUInstance *inst = calloc(1,sizeof(WGPUInstance));
  *inst = wgpuCreateInstance(of_lean<InstanceDescriptor>(desc));
  if (*inst == NULL) {
    return lean_io_result_mk_error(lean_mk_io_user_error(
      lean_mk_string("wgpuCreateInstance returned NULL")));
  }
  fprintf(stderr, "mk WGPUInstance done!\n");
  return lean_io_result_mk_ok(to_lean<Instance>(inst));
}

/-- Backend flag: all backends (0x0 = default all) -/
def InstanceBackend.all       : UInt32 := 0x00000000
/-- Backend flag: Vulkan -/
def InstanceBackend.vulkan    : UInt32 := 0x00000001
/-- Backend flag: OpenGL -/
def InstanceBackend.gl        : UInt32 := 0x00000002
/-- Backend flag: Metal -/
def InstanceBackend.metal     : UInt32 := 0x00000004
/-- Backend flag: DirectX 12 -/
def InstanceBackend.dx12      : UInt32 := 0x00000008
/-- Backend flag: DirectX 11 -/
def InstanceBackend.dx11      : UInt32 := 0x00000010
/-- Backend flag: Browser WebGPU -/
def InstanceBackend.browserWebGPU : UInt32 := 0x00000020
/-- Backend flags: primary backends (Vulkan | Metal | DX12 | BrowserWebGPU) -/
def InstanceBackend.primary   : UInt32 := InstanceBackend.vulkan ||| InstanceBackend.metal ||| InstanceBackend.dx12 ||| InstanceBackend.browserWebGPU
/-- Backend flags: secondary backends (GL | DX11) -/
def InstanceBackend.secondary : UInt32 := InstanceBackend.gl ||| InstanceBackend.dx11

/- # Surface
  e.g. from GLFW or Instance.createSurface -/

alloy c opaque_extern_type Surface => WGPUSurface where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUSurface\n");
    wgpuSurfaceRelease(*ptr);
    free(ptr);

/-- Create a surface from an Xlib window (X11).
    `display` is the X11 `Display*` as a `USize` (pointer cast),
    `window` is the X11 `Window` (XID) as a `UInt64`. -/
alloy c extern
def Instance.createSurfaceFromXlib (inst : Instance) (display : USize) (window : UInt64) : IO Surface := {
  WGPUInstance *c_inst = of_lean<Instance>(inst);

  WGPUSurfaceDescriptorFromXlibWindow xlibDesc = {};
  xlibDesc.chain.sType = WGPUSType_SurfaceDescriptorFromXlibWindow;
  xlibDesc.chain.next = NULL;
  xlibDesc.display = (void*)(uintptr_t)display;
  xlibDesc.window = window;

  WGPUSurfaceDescriptor desc = {};
  desc.nextInChain = &xlibDesc.chain;
  desc.label = "xlib surface";

  WGPUSurface *surface = calloc(1, sizeof(WGPUSurface));
  *surface = wgpuInstanceCreateSurface(*c_inst, &desc);
  return lean_io_result_mk_ok(to_lean<Surface>(surface));
}

/-- Create a surface from an XCB window.
    `connection` is the `xcb_connection_t*` as a `USize` (pointer cast),
    `window` is the `xcb_window_t` as a `UInt32`. -/
alloy c extern
def Instance.createSurfaceFromXcb (inst : Instance) (connection : USize) (window : UInt32) : IO Surface := {
  WGPUInstance *c_inst = of_lean<Instance>(inst);

  WGPUSurfaceDescriptorFromXcbWindow xcbDesc = {};
  xcbDesc.chain.sType = WGPUSType_SurfaceDescriptorFromXcbWindow;
  xcbDesc.chain.next = NULL;
  xcbDesc.connection = (void*)(uintptr_t)connection;
  xcbDesc.window = window;

  WGPUSurfaceDescriptor desc = {};
  desc.nextInChain = &xcbDesc.chain;
  desc.label = "xcb surface";

  WGPUSurface *surface = calloc(1, sizeof(WGPUSurface));
  *surface = wgpuInstanceCreateSurface(*c_inst, &desc);
  return lean_io_result_mk_ok(to_lean<Surface>(surface));
}

/-- Create a surface from a Wayland surface.
    `display` is the `wl_display*` as a `USize`,
    `wlSurface` is the `wl_surface*` as a `USize`. -/
alloy c extern
def Instance.createSurfaceFromWayland (inst : Instance) (display : USize) (wlSurface : USize) : IO Surface := {
  WGPUInstance *c_inst = of_lean<Instance>(inst);

  WGPUSurfaceDescriptorFromWaylandSurface waylandDesc = {};
  waylandDesc.chain.sType = WGPUSType_SurfaceDescriptorFromWaylandSurface;
  waylandDesc.chain.next = NULL;
  waylandDesc.display = (void*)(uintptr_t)display;
  waylandDesc.surface = (void*)(uintptr_t)wlSurface;

  WGPUSurfaceDescriptor desc = {};
  desc.nextInChain = &waylandDesc.chain;
  desc.label = "wayland surface";

  WGPUSurface *surface = calloc(1, sizeof(WGPUSurface));
  *surface = wgpuInstanceCreateSurface(*c_inst, &desc);
  return lean_io_result_mk_ok(to_lean<Surface>(surface));
}

/-- Create a surface from a Windows HWND.
    `hinstance` is the `HINSTANCE` as a `USize`,
    `hwnd` is the `HWND` as a `USize`. -/
alloy c extern
def Instance.createSurfaceFromWindowsHWND (inst : Instance) (hinstance : USize) (hwnd : USize) : IO Surface := {
  WGPUInstance *c_inst = of_lean<Instance>(inst);

  WGPUSurfaceDescriptorFromWindowsHWND hwndDesc = {};
  hwndDesc.chain.sType = WGPUSType_SurfaceDescriptorFromWindowsHWND;
  hwndDesc.chain.next = NULL;
  hwndDesc.hinstance = (void*)(uintptr_t)hinstance;
  hwndDesc.hwnd = (void*)(uintptr_t)hwnd;

  WGPUSurfaceDescriptor desc = {};
  desc.nextInChain = &hwndDesc.chain;
  desc.label = "win32 surface";

  WGPUSurface *surface = calloc(1, sizeof(WGPUSurface));
  *surface = wgpuInstanceCreateSurface(*c_inst, &desc);
  return lean_io_result_mk_ok(to_lean<Surface>(surface));
}

/-- Create a surface from a Metal layer (macOS/iOS).
    `layer` is the `CAMetalLayer*` as a `USize`. -/
alloy c extern
def Instance.createSurfaceFromMetalLayer (inst : Instance) (layer : USize) : IO Surface := {
  WGPUInstance *c_inst = of_lean<Instance>(inst);

  WGPUSurfaceDescriptorFromMetalLayer metalDesc = {};
  metalDesc.chain.sType = WGPUSType_SurfaceDescriptorFromMetalLayer;
  metalDesc.chain.next = NULL;
  metalDesc.layer = (void*)(uintptr_t)layer;

  WGPUSurfaceDescriptor desc = {};
  desc.nextInChain = &metalDesc.chain;
  desc.label = "metal surface";

  WGPUSurface *surface = calloc(1, sizeof(WGPUSurface));
  *surface = wgpuInstanceCreateSurface(*c_inst, &desc);
  return lean_io_result_mk_ok(to_lean<Surface>(surface));
}

/- # Logging -/

alloy c enum LogLevel => WGPULogLevel
| Off => WGPULogLevel_Off
| Error => WGPULogLevel_Error
| Warn => WGPULogLevel_Warn
| Info => WGPULogLevel_Info
| Debug => WGPULogLevel_Debug
| Trace => WGPULogLevel_Trace
| Force32 => WGPULogLevel_Force32
deriving Repr, BEq, Inhabited

alloy c section
  void onLog(WGPULogLevel level, const char* message, void* closure) {
    lean_closure_object *l_closure = lean_to_closure((lean_object *) closure);
    lean_object *l_message = lean_mk_string(message);
    lean_object *res = lean_apply_3((lean_object *) l_closure, lean_box(to_lean<LogLevel>(level)), l_message, lean_io_mk_world());
    if (!lean_io_result_is_ok(res)) {
      -- TODO: What if the closure itself errors?
      fprintf(stderr, "onLog closure errored out!\n");
      abort();
    }
  }
end

alloy c extern def setLogCallback (logFunction : LogLevel -> String -> IO Unit) : IO Unit := {
  wgpuSetLogLevel(WGPULogLevel_Trace);
  lean_inc(logFunction);
  wgpuSetLogCallback(onLog, (void*)logFunction);
  return lean_io_result_mk_ok(lean_box(0));
}

/- # Wgpu version -/

alloy c extern
def wgpuVersion : IO UInt32 := {
  uint32_t v = wgpuGetVersion();
  return lean_io_result_mk_ok(lean_box(v));
}

/- ################################################################## -/
/- # Instance.processEvents                                           -/
/- ################################################################## -/

/-- Process pending instance events (callbacks). -/
alloy c extern
def Instance.processEvents (inst : Instance) : IO Unit := {
  WGPUInstance *c_inst = of_lean<Instance>(inst);
  wgpuInstanceProcessEvents(*c_inst);
  return lean_io_result_mk_ok(lean_box(0));
}

/- ################################################################## -/
/- # Instance Global Report (wgpu-native extension)                   -/
/- ################################################################## -/

/-- A single backend's resource statistics. -/
structure BackendReport where
  numAdapters : UInt64
  numDevices : UInt64
  numQueues : UInt64
  numPipelineLayouts : UInt64
  numShaderModules : UInt64
  numBindGroupLayouts : UInt64
  numBindGroups : UInt64
  numCommandBuffers : UInt64
  numRenderBundles : UInt64
  numRenderPipelines : UInt64
  numComputePipelines : UInt64
  numBuffers : UInt64
  numTextures : UInt64
  numTextureViews : UInt64
  numSamplers : UInt64
  numQuerySets : UInt64
deriving Repr

/-- Global report across all backends. -/
structure GlobalReport where
  vulkan : BackendReport
  metal  : BackendReport
  dx12   : BackendReport
  gl     : BackendReport
deriving Repr

@[export lean_wgpu_mk_backend_report]
def mkBackendReport (a b c d e f g h i j k l m n o p : UInt64) : BackendReport :=
  { numAdapters := a, numDevices := b, numQueues := c, numPipelineLayouts := d,
    numShaderModules := e, numBindGroupLayouts := f, numBindGroups := g,
    numCommandBuffers := h, numRenderBundles := i, numRenderPipelines := j,
    numComputePipelines := k, numBuffers := l, numTextures := m,
    numTextureViews := n, numSamplers := o, numQuerySets := p }

alloy c section
  extern lean_object* lean_wgpu_mk_backend_report(
    uint64_t, uint64_t, uint64_t, uint64_t,
    uint64_t, uint64_t, uint64_t, uint64_t,
    uint64_t, uint64_t, uint64_t, uint64_t,
    uint64_t, uint64_t, uint64_t, uint64_t);

  static lean_object* hub_report_to_lean(const WGPUHubReport *r) {
    lean_object *result = lean_wgpu_mk_backend_report(
      r->adapters.numAllocated, r->devices.numAllocated, r->queues.numAllocated, r->pipelineLayouts.numAllocated,
      r->shaderModules.numAllocated, r->bindGroupLayouts.numAllocated, r->bindGroups.numAllocated,
      r->commandBuffers.numAllocated, r->renderBundles.numAllocated, r->renderPipelines.numAllocated,
      r->computePipelines.numAllocated, r->buffers.numAllocated, r->textures.numAllocated,
      r->textureViews.numAllocated, r->samplers.numAllocated, r->querySets.numAllocated);
    return result;
  }
end

/-- Generate a global resource report from the wgpu-native instance.
    Returns statistics for Vulkan, Metal, DX12, and GL backends. -/
alloy c extern
def Instance.generateReport (inst : Instance) : IO GlobalReport := {
  WGPUInstance *c_inst = of_lean<Instance>(inst);
  WGPUGlobalReport report = {};
  wgpuGenerateReport(*c_inst, &report);

  lean_object *vk = hub_report_to_lean(&report.vulkan);
  lean_object *mtl = hub_report_to_lean(&report.metal);
  lean_object *dx12 = hub_report_to_lean(&report.dx12);
  lean_object *gl = hub_report_to_lean(&report.gl);

  -- GlobalReport structure: ⟨vulkan, metal, dx12, gl⟩
  lean_object *obj = lean_alloc_ctor(0, 4, 0);
  lean_ctor_set(obj, 0, vk);
  lean_ctor_set(obj, 1, mtl);
  lean_ctor_set(obj, 2, dx12);
  lean_ctor_set(obj, 3, gl);
  return lean_io_result_mk_ok(obj);
}


end Wgpu
