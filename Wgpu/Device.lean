import Alloy.C
import Wgpu.Core
import Wgpu.Adapter
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
  static inline WGPUAdapter* _alloy_of_l_Wgpu_Adapter(b_lean_obj_arg o) { return (WGPUAdapter*)lean_get_external_data(o); }
  static inline WGPUFeatureName _alloy_of_l_Feature(uint8_t v) { return (WGPUFeatureName)v; }
  static inline uint8_t _alloy_to_l_Feature(WGPUFeatureName v) { return (uint8_t)v; }
  typedef struct { lean_object *result; } wgpu_callback_data;
  extern lean_object* limits_to_lean(WGPULimits *l);
end

/- # Device
  https://eliemichel.github.io/LearnWebGPU/getting-started/adapter-and-device/the-device.html#the-device
-/

-- /- ## Device Descriptor -/

alloy c section
  typedef struct {
    WGPUDeviceDescriptor desc;
    lean_string_object *l_label; -- need this to decrement the refcount on finalize
  } LWGPUDeviceDescriptor;
end

/--
```c
  typedef struct WGPUDeviceDescriptor {
    WGPUChainedStruct const * nextInChain;
    WGPU_NULLABLE char const * label;
    size_t requiredFeatureCount;
    WGPUFeatureName const * requiredFeatures;
    WGPU_NULLABLE WGPURequiredLimits const * requiredLimits;
    WGPUQueueDescriptor defaultQueue;
    WGPUDeviceLostCallback deviceLostCallback;
    void * deviceLostUserdata;
  } WGPUDeviceDescriptor;
```
-/
alloy c opaque_extern_type DeviceDescriptor => LWGPUDeviceDescriptor where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUDeviceDescriptor\n");
    lean_dec((lean_object*) ptr->l_label);
    free(ptr);

-- alloy c enum DeviceLostReason => int
-- | undefined => WGPUDeviceLostReason_Undefined
-- | destroyed => WGPUDeviceLostReason_Destroyed
-- | force32 => WGPUDeviceLostReason_Force32

alloy c section
  void onDeviceLostCallback(WGPUDeviceLostReason reason, char const* message, void* closure) {
    fprintf(stderr, "onDeviceLostCallback\n");
    lean_closure_object *l_closure = lean_to_closure((lean_object *) closure);
    -- lean_object *l_reason = to_lean<DeviceLostReason>(reason);
    lean_object *l_message = lean_mk_string(message);
    lean_object *res = lean_apply_2((lean_object *) l_closure, /- l_reason, -/ l_message, lean_io_mk_world());
    if (!lean_io_result_is_ok(res)) {
      -- TODO: What if the closure itself errors?
      fprintf(stderr, "onDeviceLost closure errored out!\n");
      abort();
    }
  }
end

alloy c extern def DeviceDescriptor.mk
  (l_label : String := "The default device")
  (onDeviceLost : /- DeviceLostReason -> -/ (message : String) -> IO (Task Unit) := fun _ => pure (pure ()))
  : IO DeviceDescriptor :=
{
  fprintf(stderr, "mk WGPUDeviceDescriptor\n");
  LWGPUDeviceDescriptor *desc = calloc(1,sizeof(LWGPUDeviceDescriptor));
  desc->desc.nextInChain = NULL;
  lean_inc(l_label); -- * increase refcount of string ==> need to dec in finalizer
  desc->desc.label = lean_string_cstr(l_label);
  desc->desc.requiredFeatureCount = 0;
  desc->desc.requiredLimits = NULL;
  desc->desc.defaultQueue.nextInChain = NULL;
  desc->desc.defaultQueue.label = "The default queue";
  lean_inc(onDeviceLost); -- Leaks: wgpu stores this forever; we'd need a custom destructor hook to dec it.
  desc->desc.deviceLostCallback = onDeviceLostCallback; -- the C function, which then actually...
  desc->desc.deviceLostUserdata = onDeviceLost;         -- ...invokes this Lean closure :D
  desc->l_label = (lean_string_object *) l_label;

  return lean_io_result_mk_ok(to_lean<DeviceDescriptor>(desc));
}

/- ## Device itself -/

alloy c opaque_extern_type Device => WGPUDevice where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUDevice\n");
    if (*ptr) {
      wgpuDeviceDestroy(*ptr);
      wgpuDeviceRelease(*ptr);
    }
    free(ptr);

alloy c section
  void onAdapterRequestDeviceEnded(WGPURequestDeviceStatus status, WGPUDevice device, char const *message, void *userdata) {
    wgpu_callback_data *data = (wgpu_callback_data*)userdata;
    if (status == WGPURequestDeviceStatus_Success) {
      WGPUDevice *d = calloc(1,sizeof(WGPUDevice));
      *d = device;
      lean_object* l_device = to_lean<Device>(d);
      data->result = lean_io_result_mk_ok(l_device);
    } else {
      fprintf(stderr, "Could not get WebGPU device: %s\n", message);
      data->result = lean_io_result_mk_error(lean_box(0));
    }
  }
end

alloy c extern def Adapter.requestDevice (l_adapter : Adapter) (l_ddesc : DeviceDescriptor) : IO (Task (Result Device)) := {
  WGPUAdapter *adapter = of_lean<Adapter>(l_adapter);
  LWGPUDeviceDescriptor *ddesc = of_lean<DeviceDescriptor>(l_ddesc);

  wgpu_callback_data cb_data = {0};
  wgpuAdapterRequestDevice( -- ! RealWorld
      *adapter,
      &ddesc->desc,
      onAdapterRequestDeviceEnded,
      (void*)&cb_data
  );
  lean_object *task = lean_task_pure(cb_data.result);
  return lean_io_result_mk_ok(task);
}

alloy c extern def Device.poll (device : Device) : IO Unit := {
  wgpuDevicePoll(*of_lean<Device>(device), false, NULL);
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern def Device.features (device : Device) : IO (Array Feature) := {
  WGPUDevice c_device = *of_lean<Device>(device);
  size_t n = wgpuDeviceEnumerateFeatures(c_device, NULL);
  WGPUFeatureName *features = calloc(n, sizeof(WGPUFeatureName));
  wgpuDeviceEnumerateFeatures(c_device, features);
  lean_object *array = lean_mk_array(lean_box(0), lean_box(0));
  for (size_t i = 0; i < n; i++) {
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
        break;
    }
  }
  free(features);
  return lean_io_result_mk_ok(array);
}

/- ## Uncaptured Error Callback -/
alloy c section
  void onDeviceUncapturedErrorCallback(WGPUErrorType type, char const* message, void* closure) {
    fprintf(stderr, "onDeviceUncapturedErrorCallback\n");
    lean_closure_object *l_closure = lean_to_closure((lean_object *) closure);
    lean_object *l_message = lean_mk_string(message);
    lean_object *res = lean_apply_3((lean_object *) l_closure, lean_box(type), l_message, lean_io_mk_world());
    if (!lean_io_result_is_ok(res)) {
      -- TODO: What if the closure itself errors?
      fprintf(stderr, "onDeviceUncapturedErrorCallback closure errored out!\n");
      abort();
    }
  }
end

alloy c extern def Device.setUncapturedErrorCallback
  (l_device : Device)
  (onDeviceError : UInt32 -> String -> IO Unit)
  : IO Unit :=
{
  WGPUDevice *device = of_lean<Device>(l_device);
  lean_inc(onDeviceError); -- Leaks: wgpu stores callback forever. One per device lifetime, acceptable.
  wgpuDeviceSetUncapturedErrorCallback(*device, onDeviceUncapturedErrorCallback, onDeviceError);
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern
def Device.getLimits (device : Device) : IO Limits := {
  WGPUDevice *c_device = of_lean<Device>(device);
  WGPUSupportedLimits supported = {};
  supported.nextInChain = NULL;
  wgpuDeviceGetLimits(*c_device, &supported);
  return lean_io_result_mk_ok(limits_to_lean(&supported.limits));
}

alloy c extern
def Device.pollWait (device : Device) : IO Unit := {
  wgpuDevicePoll(*of_lean<Device>(device), true, NULL);
  return lean_io_result_mk_ok(lean_box(0));
}

/- # Error Scoping -/

alloy c enum ErrorFilter => WGPUErrorFilter
| Validation => WGPUErrorFilter_Validation
| OutOfMemory => WGPUErrorFilter_OutOfMemory
| Internal => WGPUErrorFilter_Internal
deriving Inhabited, Repr, BEq

/-- Push an error scope on the device. Captures errors of the given filter type. -/
alloy c extern
def Device.pushErrorScope (device : Device) (filter : ErrorFilter) : IO Unit := {
  WGPUDevice *c_device = of_lean<Device>(device);
  wgpuDevicePushErrorScope(*c_device, of_lean<ErrorFilter>(filter));
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c section
  static uint32_t g_pop_error_type = 0;
  static char g_pop_error_msg[1024];
  static int g_pop_error_done = 0;
  static void pop_error_scope_cb(WGPUErrorType type, char const *message, void *userdata) {
    (void)userdata;
    g_pop_error_type = (uint32_t)type;
    if (message) {
      strncpy(g_pop_error_msg, message, sizeof(g_pop_error_msg) - 1);
      g_pop_error_msg[sizeof(g_pop_error_msg) - 1] = 0;
    } else {
      g_pop_error_msg[0] = 0;
    }
    g_pop_error_done = 1;
  }
end

/-- Pop an error scope and return (errorType, message). Polls the device until ready.
    errorType: 0 = no error, 1 = validation, 2 = out-of-memory. -/
alloy c extern
def Device.popErrorScope (device : Device) : IO (UInt32 × String) := {
  WGPUDevice *c_device = of_lean<Device>(device);

  g_pop_error_done = 0;
  g_pop_error_type = 0;
  g_pop_error_msg[0] = 0;
  wgpuDevicePopErrorScope(*c_device, pop_error_scope_cb, NULL);

  // Poll until the callback fires
  for (int i = 0; i < 1000 && !g_pop_error_done; i++) {
    wgpuDevicePoll(*c_device, false, NULL);
  }

  lean_object *pair = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(pair, 0, lean_box(g_pop_error_type));
  lean_ctor_set(pair, 1, lean_mk_string(g_pop_error_msg));
  return lean_io_result_mk_ok(pair);
}

/- # Device Destroy -/

/-- Destroy a device's GPU resources immediately.
    NOTE: The finalizer also calls destroy+release, so this is optional.
    Use it to shut down the device earlier than GC would. -/
alloy c extern
def Device.destroy (device : Device) : IO Unit := {
  WGPUDevice *c_device = of_lean<Device>(device);
  if (*c_device) {
    wgpuDeviceDestroy(*c_device);
    *c_device = NULL;
  }
  return lean_io_result_mk_ok(lean_box(0));
}

/- ################################################################## -/
/- # Device.hasFeature                                                -/
/- ################################################################## -/

/-- Check if the device supports a specific feature. -/
alloy c extern
def Device.hasFeature (device : Device) (feature : Feature) : IO Bool := {
  WGPUDevice *c_device = of_lean<Device>(device);
  WGPUBool has = wgpuDeviceHasFeature(*c_device, of_lean<Feature>(feature));
  return lean_io_result_mk_ok(lean_box(has ? 1 : 0));
}

/- ################################################################## -/
/- # Device.setLabel                                                  -/
/- ################################################################## -/

/-- Set the debug label of a device. -/
alloy c extern
def Device.setLabel (device : Device) (label : @& String) : IO Unit := {
  WGPUDevice *c_dev = of_lean<Device>(device);
  wgpuDeviceSetLabel(*c_dev, lean_string_cstr(label));
  return lean_io_result_mk_ok(lean_box(0));
}


end Wgpu
