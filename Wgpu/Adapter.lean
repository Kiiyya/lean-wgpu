import Alloy.C
import Wgpu.Core
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
  static inline WGPUInstance* _alloy_of_l_Wgpu_Instance(b_lean_obj_arg o) { return (WGPUInstance*)lean_get_external_data(o); }
  static inline WGPUSurface* _alloy_of_l_Wgpu_Surface(b_lean_obj_arg o) { return (WGPUSurface*)lean_get_external_data(o); }
  typedef struct {
    lean_object *result;
  } wgpu_callback_data;
end

/- # Adapter -/

alloy c opaque_extern_type Adapter => WGPUAdapter where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUAdapter\n");
    wgpuAdapterRelease(*ptr);
    free(ptr);

alloy c section
  void onAdapterRequestEnded(WGPURequestAdapterStatus status, WGPUAdapter adapter, const char* message, void* userdata) {
    wgpu_callback_data *data = (wgpu_callback_data*)userdata;
    if (status == WGPURequestAdapterStatus_Success) {
      WGPUAdapter *a = (WGPUAdapter*)calloc(1,sizeof(WGPUAdapter));
      *a = adapter;
      fprintf(stderr, "Got adapter: %p\n", a);

      lean_object* l_adapter = to_lean<Adapter>(a);
      data->result = lean_io_result_mk_ok(l_adapter);
    } else {
      fprintf(stderr, "Could not get WebGPU adapter: %s\n", message);
      data->result = lean_io_result_mk_error(lean_box(0));
    }
  }
end

alloy c extern
def Instance.requestAdapter (l_inst : Instance) (surface : Surface): IO (Task (Result Adapter)) := {
  WGPUInstance *inst = of_lean<Instance>(l_inst);
  WGPURequestAdapterOptions *adapterOpts = calloc(1, sizeof(WGPURequestAdapterOptions));
  adapterOpts->nextInChain = NULL;
  -- Surface handle is copied by value; wgpu internally references the surface.
  -- No need to lean_inc — we just read the WGPUSurface handle.
  adapterOpts->compatibleSurface = *of_lean<Surface>(surface);
  -- adapterOpts.backendType = WGPUBackendType_OpenGLES;

  wgpu_callback_data cb_data = {0};
  -- Note that the adapter maintains an internal (wgpu) reference to the WGPUInstance, according to the C++ guide: "We will no longer need to use the instance once we have selected our adapter, so we can call wgpuInstanceRelease(instance) right after the adapter request instead of at the very end. The underlying instance object will keep on living until the adapter gets released but we do not need to manager this."
  wgpuInstanceRequestAdapter( -- ! RealWorld
      *inst,
      adapterOpts,
      onAdapterRequestEnded,
      (void*)&cb_data
  );
  free(adapterOpts);
  lean_object *task = lean_task_pure(cb_data.result);
  return lean_io_result_mk_ok(task);
}

alloy c extern
def Adapter.printProperties (a : Adapter) : IO Unit := {
  WGPUAdapter *adapter = of_lean<Adapter>(a);
  WGPUAdapterProperties prop = {};
  prop.nextInChain = NULL;
  wgpuAdapterGetProperties(*adapter, &prop);
  fprintf(stderr, "Adapter Properties:\n");
  fprintf(stderr, " - Vendor ID: %d\n", prop.vendorID);
  fprintf(stderr, " - Vendor Name: %s\n", prop.vendorName);
  fprintf(stderr, " - Arch: %s\n", prop.architecture);
  fprintf(stderr, " - Device ID: %d\n", prop.deviceID);
  fprintf(stderr, " - Driver Description: %s\n", prop.driverDescription);
  fprintf(stderr, " - Adapter Type: %d\n", prop.adapterType);
  fprintf(stderr, " - Backend Type: %d\n", prop.backendType);

  return lean_io_result_mk_ok(lean_box(0));
}

alloy c enum Feature => WGPUFeatureName
| Undefined => WGPUFeatureName_Undefined
| DepthClipControl => WGPUFeatureName_DepthClipControl
| Depth32FloatStencil8 => WGPUFeatureName_Depth32FloatStencil8
| TimestampQuery => WGPUFeatureName_TimestampQuery
| TextureCompressionBC => WGPUFeatureName_TextureCompressionBC
| TextureCompressionETC2 => WGPUFeatureName_TextureCompressionETC2
| TextureCompressionASTC => WGPUFeatureName_TextureCompressionASTC
| IndirectFirstInstance => WGPUFeatureName_IndirectFirstInstance
| ShaderF16 => WGPUFeatureName_ShaderF16
| RG11B10UfloatRenderable => WGPUFeatureName_RG11B10UfloatRenderable
| BGRA8UnormStorage => WGPUFeatureName_BGRA8UnormStorage
| Float32Filterable => WGPUFeatureName_Float32Filterable
| Force32 => WGPUFeatureName_Force32
deriving Inhabited, Repr, BEq

instance : ToString Feature where
  toString f := s!"{repr f}"
alloy c extern def Adapter.featuresRaw (adapter : Adapter) : IO (Array UInt32) := {
  WGPUAdapter c_adapter = *of_lean<Adapter>(adapter);
  size_t n = wgpuAdapterEnumerateFeatures(c_adapter, NULL);
  WGPUFeatureName *features = calloc(n, sizeof(WGPUFeatureName));
  wgpuAdapterEnumerateFeatures(c_adapter, features);
  lean_object *array = lean_mk_array(lean_box(0), lean_box(0));
  for (size_t i = 0; i < n; i++) {
    array = lean_array_push(array, lean_box((uint32_t)features[i]));
  }
  free(features);
  return lean_io_result_mk_ok(array);
}


/- # Adapter / Device Limits -/

structure Limits where
  maxTextureDimension1D : UInt32
  maxTextureDimension2D : UInt32
  maxTextureDimension3D : UInt32
  maxTextureArrayLayers : UInt32
  maxBindGroups : UInt32
  maxDynamicUniformBuffersPerPipelineLayout : UInt32
  maxDynamicStorageBuffersPerPipelineLayout : UInt32
  maxSampledTexturesPerShaderStage : UInt32
  maxSamplersPerShaderStage : UInt32
  maxStorageBuffersPerShaderStage : UInt32
  maxStorageTexturesPerShaderStage : UInt32
  maxUniformBuffersPerShaderStage : UInt32
  maxUniformBufferBindingSize : UInt64
  maxStorageBufferBindingSize : UInt64
  maxVertexBuffers : UInt32
  maxVertexAttributes : UInt32
  maxVertexBufferArrayStride : UInt32
  maxComputeWorkgroupSizeX : UInt32
  maxComputeWorkgroupSizeY : UInt32
  maxComputeWorkgroupSizeZ : UInt32
  maxComputeWorkgroupsPerDimension : UInt32
deriving Repr

/-- Helper to construct Limits — this ensures the ABI matches between Lean and C. -/
@[export lean_wgpu_mk_limits]
def mkLimits
    (f0 f1 f2 f3 f4 f5 f6 f7 f8 f9 f10 f11 : UInt32)
    (f12 f13 : UInt64)
    (f14 f15 f16 f17 f18 f19 f20 : UInt32)
    : Limits :=
  { maxTextureDimension1D := f0
    maxTextureDimension2D := f1
    maxTextureDimension3D := f2
    maxTextureArrayLayers := f3
    maxBindGroups := f4
    maxDynamicUniformBuffersPerPipelineLayout := f5
    maxDynamicStorageBuffersPerPipelineLayout := f6
    maxSampledTexturesPerShaderStage := f7
    maxSamplersPerShaderStage := f8
    maxStorageBuffersPerShaderStage := f9
    maxStorageTexturesPerShaderStage := f10
    maxUniformBuffersPerShaderStage := f11
    maxUniformBufferBindingSize := f12
    maxStorageBufferBindingSize := f13
    maxVertexBuffers := f14
    maxVertexAttributes := f15
    maxVertexBufferArrayStride := f16
    maxComputeWorkgroupSizeX := f17
    maxComputeWorkgroupSizeY := f18
    maxComputeWorkgroupSizeZ := f19
    maxComputeWorkgroupsPerDimension := f20 }

alloy c section
  extern lean_object* lean_wgpu_mk_limits(
    uint32_t f0, uint32_t f1, uint32_t f2, uint32_t f3,
    uint32_t f4, uint32_t f5, uint32_t f6, uint32_t f7,
    uint32_t f8, uint32_t f9, uint32_t f10, uint32_t f11,
    uint64_t f12, uint64_t f13,
    uint32_t f14, uint32_t f15, uint32_t f16, uint32_t f17,
    uint32_t f18, uint32_t f19, uint32_t f20);

  lean_object* limits_to_lean(WGPULimits *l) {
    return lean_wgpu_mk_limits(
      l->maxTextureDimension1D,
      l->maxTextureDimension2D,
      l->maxTextureDimension3D,
      l->maxTextureArrayLayers,
      l->maxBindGroups,
      l->maxDynamicUniformBuffersPerPipelineLayout,
      l->maxDynamicStorageBuffersPerPipelineLayout,
      l->maxSampledTexturesPerShaderStage,
      l->maxSamplersPerShaderStage,
      l->maxStorageBuffersPerShaderStage,
      l->maxStorageTexturesPerShaderStage,
      l->maxUniformBuffersPerShaderStage,
      l->maxUniformBufferBindingSize,
      l->maxStorageBufferBindingSize,
      l->maxVertexBuffers,
      l->maxVertexAttributes,
      l->maxVertexBufferArrayStride,
      l->maxComputeWorkgroupSizeX,
      l->maxComputeWorkgroupSizeY,
      l->maxComputeWorkgroupSizeZ,
      l->maxComputeWorkgroupsPerDimension
    );
  }
end

alloy c extern
def Adapter.getLimits (adapter : Adapter) : IO Limits := {
  WGPUAdapter *c_adapter = of_lean<Adapter>(adapter);
  WGPUSupportedLimits supported = {};
  supported.nextInChain = NULL;
  wgpuAdapterGetLimits(*c_adapter, &supported);
  return lean_io_result_mk_ok(limits_to_lean(&supported.limits));
}

alloy c extern
def Adapter.hasFeature (adapter : Adapter) (feature : Feature) : IO Bool := {
  WGPUAdapter *c_adapter = of_lean<Adapter>(adapter);
  WGPUFeatureName fn = of_lean<Feature>(feature);
  WGPUBool has = wgpuAdapterHasFeature(*c_adapter, fn);
  return lean_io_result_mk_ok(lean_box(has));
}

/-- Query all features supported by the adapter.
    Note: features not in the Feature enum are silently skipped. -/
alloy c extern def Adapter.features (adapter : Adapter) : IO (Array Feature) := {
  WGPUAdapter c_adapter = *of_lean<Adapter>(adapter);
  size_t n = wgpuAdapterEnumerateFeatures(c_adapter, NULL);
  WGPUFeatureName *features = calloc(n, sizeof(WGPUFeatureName));
  wgpuAdapterEnumerateFeatures(c_adapter, features);
  lean_object *array = lean_mk_array(lean_box(0), lean_box(0));
  for (size_t i = 0; i < n; i++) {
    -- Only include features that map to known enum variants
    switch (features[i]) {
      case WGPUFeatureName_Undefined:
      case WGPUFeatureName_DepthClipControl:
      case WGPUFeatureName_Depth32FloatStencil8:
      case WGPUFeatureName_TimestampQuery:
      case WGPUFeatureName_TextureCompressionBC:
      case WGPUFeatureName_TextureCompressionETC2:
      case WGPUFeatureName_TextureCompressionASTC:
      case WGPUFeatureName_IndirectFirstInstance:
      case WGPUFeatureName_ShaderF16:
      case WGPUFeatureName_RG11B10UfloatRenderable:
      case WGPUFeatureName_BGRA8UnormStorage:
      case WGPUFeatureName_Float32Filterable:
        array = lean_array_push(array, lean_box(to_lean<Feature>(features[i])));
        break;
      default:
        break;  -- skip native/unknown features
    }
  }
  free(features);
  return lean_io_result_mk_ok(array);
}
alloy c extern
def Adapter.getProperties (adapter : Adapter)
    : IO (UInt32 × UInt32 × String × String × UInt32 × UInt32) := {
  WGPUAdapter *c_adapter = of_lean<Adapter>(adapter);
  WGPUAdapterProperties prop = {};
  prop.nextInChain = NULL;
  wgpuAdapterGetProperties(*c_adapter, &prop);

  lean_object *vendorName = lean_mk_string(prop.vendorName ? prop.vendorName : "");
  lean_object *driverDesc = lean_mk_string(prop.driverDescription ? prop.driverDescription : "");

  -- Build nested pairs: (vendorID, (deviceID, (vendorName, (driverDesc, (adapterType, backendType)))))
  lean_object *p5 = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(p5, 0, lean_box(prop.adapterType));
  lean_ctor_set(p5, 1, lean_box(prop.backendType));

  lean_object *p4 = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(p4, 0, driverDesc);
  lean_ctor_set(p4, 1, p5);

  lean_object *p3 = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(p3, 0, vendorName);
  lean_ctor_set(p3, 1, p4);

  lean_object *p2 = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(p2, 0, lean_box(prop.deviceID));
  lean_ctor_set(p2, 1, p3);

  lean_object *p1 = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(p1, 0, lean_box(prop.vendorID));
  lean_ctor_set(p1, 1, p2);

  return lean_io_result_mk_ok(p1);
}

/- ################################################################## -/
/- # Adapter Enumeration (wgpu-native extension)                      -/
/- ################################################################## -/

/-- Enumerate all available adapters. Returns an array of Adapter objects. -/
alloy c extern
def Instance.enumerateAdapters (inst : Instance) : IO (Array Adapter) := {
  WGPUInstance *c_inst = of_lean<Instance>(inst);
  size_t n = wgpuInstanceEnumerateAdapters(*c_inst, NULL, NULL);
  if (n == 0) {
    return lean_io_result_mk_ok(lean_mk_array(lean_box(0), lean_box(0)));
  }
  WGPUAdapter *adapters = calloc(n, sizeof(WGPUAdapter));
  wgpuInstanceEnumerateAdapters(*c_inst, NULL, adapters);
  lean_object *array = lean_mk_array(lean_box(0), lean_box(0));
  for (size_t i = 0; i < n; i++) {
    WGPUAdapter *a = calloc(1, sizeof(WGPUAdapter));
    *a = adapters[i];
    array = lean_array_push(array, to_lean<Adapter>(a));
  }
  free(adapters);
  return lean_io_result_mk_ok(array);
}

end Wgpu
