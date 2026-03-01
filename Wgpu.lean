import Wgpu.Async
import Alloy.C
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
  instanceExtras->backends = WGPUInstanceBackend_GL;

  WGPUInstanceDescriptor* desc = calloc(1,sizeof(WGPUInstanceDescriptor));
  desc->nextInChain = &instanceExtras->chain;
  return lean_io_result_mk_ok(to_lean<InstanceDescriptor>(desc));
}

alloy c extern
def createInstance (desc : InstanceDescriptor) : IO Instance := {
  fprintf(stderr, "mk WGPUInstance\n");
  WGPUInstance *inst = calloc(1,sizeof(WGPUInstance));
  -- *inst = wgpuCreateInstance(of_lean<InstanceDescriptor>(desc)); -- ! RealWorld
  *inst = wgpuCreateInstance(NULL); -- ! RealWorld
  fprintf(stderr, "mk WGPUInstance done!\n");
  return lean_io_result_mk_ok(to_lean<Instance>(inst));
}

/- # Surface
  e.g. from GLFW -/

alloy c opaque_extern_type Surface => WGPUSurface where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUSurface\n");
    wgpuSurfaceRelease(*ptr);
    free(ptr);

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
def Instance.requestAdapter (l_inst : Instance) (surface : Surface): IO (A (Result Adapter)) := {
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
  (onDeviceLost : /- DeviceLostReason -> -/ (message : String) -> IO (A Unit) := fun _ => pure (pure ()))
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
    wgpuDeviceRelease(*ptr);
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

alloy c extern def Adapter.requestDevice (l_adapter : Adapter) (l_ddesc : DeviceDescriptor) : IO (A (Result Device)) := {
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

alloy c extern def Device.features (device : Device) : IO (Array Feature) := {
  WGPUDevice c_device = *of_lean<Device>(device);
  size_t n = wgpuDeviceEnumerateFeatures(c_device, NULL);
  WGPUFeatureName *features = calloc(n, sizeof(WGPUFeatureName));
  wgpuDeviceEnumerateFeatures(c_device, features);
  lean_object *array = lean_mk_array(lean_box(0), lean_box(0));
  for (size_t i = 0; i < n; i++) {
    array = lean_array_push(array, lean_box(to_lean<Feature>(features[i])));
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

/- # Command -/

alloy c opaque_extern_type Command => WGPUCommandBuffer where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUCommandBuffer\n");
    wgpuCommandBufferRelease(*ptr);
    free(ptr);


/- ## CommandEncoder -/

alloy c opaque_extern_type CommandEncoder => WGPUCommandEncoder where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUCommandEncoder\n");
    wgpuCommandEncoderRelease(*ptr);
    free(ptr);

alloy c extern def Device.createCommandEncoder (device : Device) : IO CommandEncoder := {
  WGPUDevice *c_device = of_lean<Device>(device);
  WGPUCommandEncoderDescriptor encoderDesc = {};
  encoderDesc.nextInChain = NULL;
  encoderDesc.label = "My command encoder";
  WGPUCommandEncoder *encoder = calloc(1,sizeof(WGPUCommandEncoder));
  *encoder = wgpuDeviceCreateCommandEncoder(*c_device, &encoderDesc);
  return lean_io_result_mk_ok(to_lean<CommandEncoder>(encoder));
}

alloy c extern def CommandEncoder.insertDebugMarker (encoder : CommandEncoder) (s : @& String) : IO Unit := {
  WGPUCommandEncoder *c_encoder = of_lean<CommandEncoder>(encoder);
  -- wgpu copies the string internally, no need to retain it
  wgpuCommandEncoderInsertDebugMarker(*c_encoder, lean_string_cstr(s));
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern def CommandEncoder.finish (encoder : CommandEncoder) : IO Command := {
  WGPUCommandEncoder *c_encoder = of_lean<CommandEncoder>(encoder);
  WGPUCommandBufferDescriptor cmdBufferDescriptor = {};
  cmdBufferDescriptor.nextInChain = NULL;
  cmdBufferDescriptor.label = "Command buffer";
  WGPUCommandBuffer *command = calloc(1,sizeof(WGPUCommandBuffer));
  *command = wgpuCommandEncoderFinish(*c_encoder, &cmdBufferDescriptor);
  -- wgpuCommandEncoderRelease(*c_encoder); --we shouldn't release it here because it'll get released later via lean's refcounting
  return lean_io_result_mk_ok(to_lean<Command>(command));
}

/- # Queue -/

alloy c opaque_extern_type Queue => WGPUQueue where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUQueue\n");
    wgpuQueueRelease(*ptr);
    free(ptr);

alloy c extern def Device.getQueue (device : Device) : IO Queue := {
  WGPUDevice *c_device = of_lean<Device>(device);
  WGPUQueue *c_queue = calloc(1,sizeof(WGPUQueue));
  *c_queue = wgpuDeviceGetQueue(*c_device);
  lean_object *queue = to_lean<Queue>(c_queue);
  return lean_io_result_mk_ok(queue);
}

alloy c extern def Queue.submit (queue : Queue) (commands : Array Command) : IO Unit := {
  WGPUQueue *c_queue = of_lean<Queue>(queue);
  if (lean_obj_tag(commands) != LeanArray) { -- there are three different kinds of array: LeanArray, LeanScalarArray, LeanStructArray
    fprintf(stderr, "error: commands tag is %d, but expected %d\n", lean_obj_tag(commands), LeanArray);
    abort();
  }
  size_t n = lean_array_size(commands);

  -- Copy each command lean object (they're pointers, so not super heavy) into a continuous C array of wgpu commands.
  WGPUCommandBuffer* arr = calloc(1,sizeof(WGPUCommandBuffer) * n);
  for (size_t i = 0; i < n; i++) {
    lean_object *command = lean_array_uget(commands, i);
    WGPUCommandBuffer *c_command = of_lean<Command>(command);
    arr[i] = *c_command;
  }

  wgpuQueueSubmit(*c_queue, n, arr);
  free(arr);
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c section
  void onSubmittedWorkDoneCallback(WGPUQueueWorkDoneStatus status, void* closure) {
    fprintf(stderr, "onSubmittedWorkDoneCallback\n");
    lean_closure_object *l_closure = lean_to_closure((lean_object *) closure);
    lean_object *res = lean_apply_2((lean_object *) l_closure, lean_box(status), lean_io_mk_world());
    if (!lean_io_result_is_ok(res)) {
      -- TODO: What if the closure itself errors?
      fprintf(stderr, "onSubmittedWorkDoneCallback closure errored out! Tag is %d\n", lean_obj_tag(res));
      abort();
    }
  }
end

alloy c extern def Queue.onSubmittedWorkDone (queue : Queue) (f : UInt32 -> IO Unit) : IO Unit := {
  WGPUQueue *c_queue = of_lean<Queue>(queue);
  lean_inc(f);
  wgpuQueueOnSubmittedWorkDone(*c_queue, onSubmittedWorkDoneCallback, f);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- # TextureFormat -/

alloy c enum TextureFormat  => WGPUTextureFormat
| Undefined => WGPUTextureFormat_Undefined
| R8Unorm => WGPUTextureFormat_R8Unorm
| R8Snorm => WGPUTextureFormat_R8Snorm
| R8Uint => WGPUTextureFormat_R8Uint
| R8Sint => WGPUTextureFormat_R8Sint
| R16Uint => WGPUTextureFormat_R16Uint
| R16Sint => WGPUTextureFormat_R16Sint
| R16Float => WGPUTextureFormat_R16Float
| RG8Unorm => WGPUTextureFormat_RG8Unorm
| RG8Snorm => WGPUTextureFormat_RG8Snorm
| RG8Uint => WGPUTextureFormat_RG8Uint
| RG8Sint => WGPUTextureFormat_RG8Sint
| R32Float => WGPUTextureFormat_R32Float
| R32Uint => WGPUTextureFormat_R32Uint
| R32Sint => WGPUTextureFormat_R32Sint
| RG16Uint => WGPUTextureFormat_RG16Uint
| RG16Sint => WGPUTextureFormat_RG16Sint
| RG16Float => WGPUTextureFormat_RG16Float
| RGBA8Unorm => WGPUTextureFormat_RGBA8Unorm
| RGBA8UnormSrgb => WGPUTextureFormat_RGBA8UnormSrgb
| RGBA8Snorm => WGPUTextureFormat_RGBA8Snorm
| RGBA8Uint => WGPUTextureFormat_RGBA8Uint
| RGBA8Sint => WGPUTextureFormat_RGBA8Sint
| BGRA8Unorm => WGPUTextureFormat_BGRA8Unorm
| BGRA8UnormSrgb => WGPUTextureFormat_BGRA8UnormSrgb
| RGB10A2Uint => WGPUTextureFormat_RGB10A2Uint
| RGB10A2Unorm => WGPUTextureFormat_RGB10A2Unorm
| RG11B10Ufloat => WGPUTextureFormat_RG11B10Ufloat
| RGB9E5Ufloat => WGPUTextureFormat_RGB9E5Ufloat
| RG32Float => WGPUTextureFormat_RG32Float
| RG32Uint => WGPUTextureFormat_RG32Uint
| RG32Sint => WGPUTextureFormat_RG32Sint
| RGBA16Uint => WGPUTextureFormat_RGBA16Uint
| RGBA16Sint => WGPUTextureFormat_RGBA16Sint
| RGBA16Float => WGPUTextureFormat_RGBA16Float
| RGBA32Float => WGPUTextureFormat_RGBA32Float
| RGBA32Uint => WGPUTextureFormat_RGBA32Uint
| RGBA32Sint => WGPUTextureFormat_RGBA32Sint
| Stencil8 => WGPUTextureFormat_Stencil8
| Depth16Unorm => WGPUTextureFormat_Depth16Unorm
| Depth24Plus => WGPUTextureFormat_Depth24Plus
| Depth24PlusStencil8 => WGPUTextureFormat_Depth24PlusStencil8
| Depth32Float => WGPUTextureFormat_Depth32Float
| Depth32FloatStencil8 => WGPUTextureFormat_Depth32FloatStencil8
| BC1RGBAUnorm => WGPUTextureFormat_BC1RGBAUnorm
| BC1RGBAUnormSrgb => WGPUTextureFormat_BC1RGBAUnormSrgb
| BC2RGBAUnorm => WGPUTextureFormat_BC2RGBAUnorm
| BC2RGBAUnormSrgb => WGPUTextureFormat_BC2RGBAUnormSrgb
| BC3RGBAUnorm => WGPUTextureFormat_BC3RGBAUnorm
| BC3RGBAUnormSrgb => WGPUTextureFormat_BC3RGBAUnormSrgb
| BC4RUnorm => WGPUTextureFormat_BC4RUnorm
| BC4RSnorm => WGPUTextureFormat_BC4RSnorm
| BC5RGUnorm => WGPUTextureFormat_BC5RGUnorm
| BC5RGSnorm => WGPUTextureFormat_BC5RGSnorm
| BC6HRGBUfloat => WGPUTextureFormat_BC6HRGBUfloat
| BC6HRGBFloat => WGPUTextureFormat_BC6HRGBFloat
| BC7RGBAUnorm => WGPUTextureFormat_BC7RGBAUnorm
| BC7RGBAUnormSrgb => WGPUTextureFormat_BC7RGBAUnormSrgb
| ETC2RGB8Unorm => WGPUTextureFormat_ETC2RGB8Unorm
| ETC2RGB8UnormSrgb => WGPUTextureFormat_ETC2RGB8UnormSrgb
| ETC2RGB8A1Unorm => WGPUTextureFormat_ETC2RGB8A1Unorm
| ETC2RGB8A1UnormSrgb => WGPUTextureFormat_ETC2RGB8A1UnormSrgb
| ETC2RGBA8Unorm => WGPUTextureFormat_ETC2RGBA8Unorm
| ETC2RGBA8UnormSrgb => WGPUTextureFormat_ETC2RGBA8UnormSrgb
| EACR11Unorm => WGPUTextureFormat_EACR11Unorm
| EACR11Snorm => WGPUTextureFormat_EACR11Snorm
| EACRG11Unorm => WGPUTextureFormat_EACRG11Unorm
| EACRG11Snorm => WGPUTextureFormat_EACRG11Snorm
| ASTC4x4Unorm => WGPUTextureFormat_ASTC4x4Unorm
| ASTC4x4UnormSrgb => WGPUTextureFormat_ASTC4x4UnormSrgb
| ASTC5x4Unorm => WGPUTextureFormat_ASTC5x4Unorm
| ASTC5x4UnormSrgb => WGPUTextureFormat_ASTC5x4UnormSrgb
| ASTC5x5Unorm => WGPUTextureFormat_ASTC5x5Unorm
| ASTC5x5UnormSrgb => WGPUTextureFormat_ASTC5x5UnormSrgb
| ASTC6x5Unorm => WGPUTextureFormat_ASTC6x5Unorm
| ASTC6x5UnormSrgb => WGPUTextureFormat_ASTC6x5UnormSrgb
| ASTC6x6Unorm => WGPUTextureFormat_ASTC6x6Unorm
| ASTC6x6UnormSrgb => WGPUTextureFormat_ASTC6x6UnormSrgb
| ASTC8x5Unorm => WGPUTextureFormat_ASTC8x5Unorm
| ASTC8x5UnormSrgb => WGPUTextureFormat_ASTC8x5UnormSrgb
| ASTC8x6Unorm => WGPUTextureFormat_ASTC8x6Unorm
| ASTC8x6UnormSrgb => WGPUTextureFormat_ASTC8x6UnormSrgb
| ASTC8x8Unorm => WGPUTextureFormat_ASTC8x8Unorm
| ASTC8x8UnormSrgb => WGPUTextureFormat_ASTC8x8UnormSrgb
| ASTC10x5Unorm => WGPUTextureFormat_ASTC10x5Unorm
| ASTC10x5UnormSrgb => WGPUTextureFormat_ASTC10x5UnormSrgb
| ASTC10x6Unorm => WGPUTextureFormat_ASTC10x6Unorm
| ASTC10x6UnormSrgb => WGPUTextureFormat_ASTC10x6UnormSrgb
| ASTC10x8Unorm => WGPUTextureFormat_ASTC10x8Unorm
| ASTC10x8UnormSrgb => WGPUTextureFormat_ASTC10x8UnormSrgb
| ASTC10x10Unorm => WGPUTextureFormat_ASTC10x10Unorm
| ASTC10x10UnormSrgb => WGPUTextureFormat_ASTC10x10UnormSrgb
| ASTC12x10Unorm => WGPUTextureFormat_ASTC12x10Unorm
| ASTC12x10UnormSrgb => WGPUTextureFormat_ASTC12x10UnormSrgb
| ASTC12x12Unorm => WGPUTextureFormat_ASTC12x12Unorm
| ASTC12x12UnormSrgb => WGPUTextureFormat_ASTC12x12UnormSrgb
| Force32 => WGPUTextureFormat_Force32
deriving Inhabited, Repr, BEq


alloy c extern
def TextureFormat.get (surface : Surface) (adapter : Adapter) : IO TextureFormat := {
    WGPUSurface * c_surface = of_lean<Surface>(surface);
    WGPUAdapter * c_adapter = of_lean<Adapter>(adapter);

    WGPUTextureFormat surfaceFormat =  wgpuSurfaceGetPreferredFormat(*c_surface, *c_adapter);
    return lean_io_result_mk_ok(lean_box(to_lean<TextureFormat>(surfaceFormat)));
}

/-- # SurfaceConfiguration -/

alloy c opaque_extern_type SurfaceConfiguration  => WGPUSurfaceConfiguration  where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUSurfaceConfiguration \n");
    free(ptr);

alloy c extern
def SurfaceConfiguration.mk (width height : UInt32) (device : Device) (textureFormat : TextureFormat)
  : IO SurfaceConfiguration := {
  WGPUDevice * c_device = of_lean<Device>(device);
  WGPUTextureFormat surfaceFormat = of_lean<TextureFormat>(textureFormat);
  fprintf(stderr, "surfaceFormat is %d\n", surfaceFormat); -- Kiiya: I get 24.

  WGPUSurfaceConfiguration *config = calloc(1,sizeof(WGPUSurfaceConfiguration))
  config->nextInChain = NULL; --Is this really needed ?
  config->width = width;
  config->height = height;
  config->usage = WGPUTextureUsage_RenderAttachment;
  config->format = surfaceFormat;

  config->viewFormatCount = 0;
  config->viewFormats = NULL;
  config->device = *c_device;
  -- TODO link present mode
  config->presentMode = WGPUPresentMode_Fifo;
  -- TODO link alpha mode enum
  config->alphaMode = WGPUCompositeAlphaMode_Auto;
  fprintf(stderr, "Done generating surface config !\n");

  return lean_io_result_mk_ok(to_lean<SurfaceConfiguration>(config));
}

alloy c extern
def Surface.configure (surface : Surface) (config : SurfaceConfiguration) : IO Unit := {
  WGPUSurface * c_surface = of_lean<Surface>(surface);
  WGPUSurfaceConfiguration * c_config = of_lean<SurfaceConfiguration>(config);
  wgpuSurfaceConfigure(*c_surface,c_config);
  fprintf(stderr, "Done configuring surface !\n");
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern
def Surface.unconfigure (surface : Surface) : IO Unit := {
  WGPUSurface * c_surface = of_lean<Surface>(surface);
  wgpuSurfaceUnconfigure(*c_surface);
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern
def Surface.present (surface : Surface) : IO Unit := {
  WGPUSurface * c_surface = of_lean<Surface>(surface);
  wgpuSurfacePresent(*c_surface);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- # Surface Texture -/

alloy c opaque_extern_type SurfaceTexture => WGPUSurfaceTexture where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUSurfaceTexture \n");
    free(ptr);

alloy c enum SurfaceTextureStatus => WGPUSurfaceGetCurrentTextureStatus
| success => WGPUSurfaceGetCurrentTextureStatus_Success
| timeout => WGPUSurfaceGetCurrentTextureStatus_Timeout
| outdated => WGPUSurfaceGetCurrentTextureStatus_Outdated
| lost => WGPUSurfaceGetCurrentTextureStatus_Lost
| out_of_memory => WGPUSurfaceGetCurrentTextureStatus_OutOfMemory
| device_lost => WGPUSurfaceGetCurrentTextureStatus_DeviceLost
| force32 => WGPUSurfaceGetCurrentTextureStatus_Force32
deriving Inhabited, Repr, BEq

alloy c extern
def SurfaceTexture.mk  : IO SurfaceTexture := {
  WGPUSurfaceTexture * surface_texture = calloc(1,sizeof(WGPUSurfaceTexture));
  return lean_io_result_mk_ok(to_lean<SurfaceTexture>(surface_texture));
}

alloy c extern
def Surface.getCurrent (surface : Surface) : IO SurfaceTexture := {
  WGPUSurfaceTexture * surface_texture = calloc(1,sizeof(WGPUSurfaceTexture));
  WGPUSurface * c_surface = of_lean<Surface>(surface);
  wgpuSurfaceGetCurrentTexture(*c_surface, surface_texture);
  return lean_io_result_mk_ok(to_lean<SurfaceTexture>(surface_texture));
}

alloy c extern
def SurfaceTexture.status (surfaceTexture : SurfaceTexture) : IO SurfaceTextureStatus := {
  WGPUSurfaceGetCurrentTextureStatus status = of_lean<SurfaceTexture>(surfaceTexture)->status;
  return lean_io_result_mk_ok(lean_box(to_lean<SurfaceTextureStatus>(status)));
}

/-- # TextureView -/

alloy c opaque_extern_type TextureView => WGPUTextureView where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUTextureView \n");
    wgpuTextureViewRelease(*ptr);
    free(ptr);

alloy c extern
def TextureView.mk (surfaceTexture : SurfaceTexture): IO TextureView := {
  WGPUSurfaceTexture * surface_texture = of_lean<SurfaceTexture>(surfaceTexture)
  if (surface_texture->status != WGPUSurfaceGetCurrentTextureStatus_Success) {
    return lean_io_result_mk_error(lean_decode_io_error(0,NULL));
  }
  WGPUTextureViewDescriptor * viewDescriptor = calloc(1,sizeof(WGPUTextureViewDescriptor));
  viewDescriptor->nextInChain = NULL;
  viewDescriptor->label = "Surface texture view";
  viewDescriptor->format = wgpuTextureGetFormat(surface_texture->texture);
  viewDescriptor->dimension = WGPUTextureViewDimension_2D;
  viewDescriptor->baseMipLevel = 0;
  viewDescriptor->mipLevelCount = 1;
  viewDescriptor->baseArrayLayer = 0;
  viewDescriptor->arrayLayerCount = 1;
  viewDescriptor->aspect = WGPUTextureAspect_All;

  WGPUTextureView * targetView = calloc(1,sizeof(WGPUTextureView));
  *targetView = wgpuTextureCreateView(surface_texture->texture, viewDescriptor);
  free(viewDescriptor);
  return lean_io_result_mk_ok(to_lean<TextureView>(targetView));
}

alloy c extern
def TextureView.is_valid (t : TextureView) : IO Bool :=
  WGPUTextureView * view = of_lean<TextureView>(t);
  return lean_io_result_mk_ok(lean_box(*view != NULL));


/-- # Color -/
alloy c opaque_extern_type Color => WGPUColor  where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUColor  \n");
    -- TODO call release
    free(ptr);

alloy c section
  WGPUColor color_mk(double r, double g, double b, double a) {
    WGPUColor c = {};
    c.r = r;
    c.g = g;
    c.b = b;
    c.a = a;
    return c
  }
end

alloy c extern
def Color.mk (r g b a : Float) : Color := {
  WGPUColor * c = calloc(1,sizeof(WGPUColor));
  *c = color_mk(r,g,b,a)
  return to_lean<Color>(c);
}


/-- # RenderPassDescriptor  -/

alloy c opaque_extern_type RenderPassEncoder => WGPURenderPassEncoder  where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPURenderPassEncoder  \n");
    -- TODO call release
    wgpuRenderPassEncoderRelease(*ptr);
    free(ptr);

alloy c extern
def RenderPassEncoder.mk (encoder : CommandEncoder) (view : TextureView): IO RenderPassEncoder := {
  WGPUCommandEncoder * c_encoder = of_lean<CommandEncoder>(encoder);
  WGPURenderPassDescriptor * renderPassDesc = calloc(1,sizeof(WGPURenderPassDescriptor));
  renderPassDesc->nextInChain = NULL;

  -- TODO link ColorAttachment
  WGPURenderPassColorAttachment * renderPassColorAttachment = calloc(1,sizeof(WGPURenderPassColorAttachment));
  WGPUTextureView * c_view = of_lean<TextureView>(view)
  renderPassColorAttachment->view = *c_view;
  renderPassColorAttachment->resolveTarget = NULL;
  renderPassColorAttachment->loadOp = WGPULoadOp_Clear;
  renderPassColorAttachment->storeOp = WGPUStoreOp_Store;
  WGPUColor c = color_mk(0.9, 0.3, 0.9, 0.5);
  renderPassColorAttachment->clearValue = c;

  renderPassDesc->colorAttachmentCount = 1;
  renderPassDesc->colorAttachments = renderPassColorAttachment;
  renderPassDesc->depthStencilAttachment = NULL;
  renderPassDesc->timestampWrites = NULL;

  WGPURenderPassEncoder * renderPass = calloc(1,sizeof(WGPURenderPassEncoder));
  *renderPass = wgpuCommandEncoderBeginRenderPass(*c_encoder, renderPassDesc);

  free(renderPassColorAttachment);
  free(renderPassDesc);

  -- ! This was the culprit: wgpuRenderPassEncoderEnd(*renderPass);
  return lean_io_result_mk_ok(to_lean<RenderPassEncoder>(renderPass));
}

/-- Release a render pass encoder.
    NOTE: The finalizer also releases, so this is intentionally a no-op to prevent double-release.
    Kept for API compatibility — call it for readability, but the real release happens via GC. -/
def RenderPassEncoder.release (_ : RenderPassEncoder) : IO Unit := pure ()



def shaderSource : String :=
"@vertex \
  fn vs_main(@builtin(vertex_index) in_vertex_index: u32) -> @builtin(position) vec4f { \
    var p = vec2f(0.0, 0.0); \
    if (in_vertex_index == 0u) { \
        p = vec2f(-0.5, -0.5); \
    } else if (in_vertex_index == 1u) { \
        p = vec2f(0.5, -0.5); \
    } else { \
        p = vec2f(0.0, 0.5); \
    } \
    return vec4f(p, 0.0, 1.0); \
  } \
   \
  @fragment \
  fn fs_main() -> @location(0) vec4f { \
      return vec4f(0.0, 0.4, 1.0, 1.0); \
  }"

/-- # ShaderModuleWGSLDescriptor -/

alloy c opaque_extern_type ShaderModuleWGSLDescriptor => WGPUShaderModuleWGSLDescriptor where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUShaderModuleWGSLDescriptor \n");
    -- wgpuRenderPipelineRelease(*ptr);
    free(ptr);

/-- WARNING: Stores a pointer into the Lean String's buffer for `code`.
    Safe only because `ShaderModuleDescriptor.mk` → `ShaderModule.mk` → `wgpuDeviceCreateShaderModule`
    copies the string. Do NOT store this descriptor long-term. -/
-- TODO put shaderSource as parameter to the function (how to transform String into char* ?)
alloy c extern
def ShaderModuleWGSLDescriptor.mk (shaderSource : String) : IO ShaderModuleWGSLDescriptor := {
  char const * c_shaderSource = lean_string_cstr(shaderSource);
  fprintf(stderr, "uhhh %s \n",c_shaderSource);
  fprintf(stderr, "mk ShaderModuleWGSLDescriptor \n");
  WGPUShaderModuleWGSLDescriptor * shaderCodeDesc = calloc(1,sizeof(WGPUShaderModuleWGSLDescriptor));
  shaderCodeDesc->chain.next = NULL;
  shaderCodeDesc->chain.sType = WGPUSType_ShaderModuleWGSLDescriptor;
  shaderCodeDesc->code = c_shaderSource;
  -- ! shaderDesc.code = &shaderCodeDesc.chain; "connect the chain"
  return lean_io_result_mk_ok(to_lean<ShaderModuleWGSLDescriptor>(shaderCodeDesc));
}

/-- # ShaderModuleDescriptor -/

alloy c opaque_extern_type ShaderModuleDescriptor => WGPUShaderModuleDescriptor where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUShaderModuleDescriptor \n");
    -- wgpuRenderPipelineRelease(*ptr);
    free(ptr);

alloy c extern
def ShaderModuleDescriptor.mk (shaderCodeDesc : ShaderModuleWGSLDescriptor) : IO ShaderModuleDescriptor := {
  fprintf(stderr, "mk ShaderModuleDescriptor \n");
  WGPUShaderModuleWGSLDescriptor * c_shaderCodeDesc = of_lean<ShaderModuleWGSLDescriptor>(shaderCodeDesc);
  WGPUShaderModuleDescriptor * shaderDesc = calloc(1, sizeof(WGPUShaderModuleDescriptor));
  -- shaderDesc->hintCount = 0;
  -- shaderDesc->hints = NULL;
  shaderDesc->nextInChain = &c_shaderCodeDesc->chain;
  return lean_io_result_mk_ok(to_lean<ShaderModuleDescriptor>(shaderDesc));
}

alloy c opaque_extern_type ShaderModule => WGPUShaderModule where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUShaderModule \n");
    -- wgpuRenderPipelineRelease(*ptr);
    free(ptr);

alloy c extern
def ShaderModule.mk (device : Device) (shaderDesc : ShaderModuleDescriptor) : IO ShaderModule := {
  fprintf(stderr, "mk ShaderModule \n");
  WGPUDevice * c_device = of_lean<Device>(device);
  WGPUShaderModuleDescriptor * c_shaderDesc = of_lean<ShaderModuleDescriptor>(shaderDesc);
  WGPUShaderModule * shaderModule = calloc(1,sizeof(WGPUShaderModule));
  *shaderModule = wgpuDeviceCreateShaderModule(*c_device, c_shaderDesc);
  return lean_io_result_mk_ok(to_lean<ShaderModule>(shaderModule));
}

/-- # BlendState -/

alloy c opaque_extern_type BlendState => WGPUBlendState where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUBlendState \n");
    free(ptr);

alloy c extern
def BlendState.mk (shaderModule : ShaderModule) : IO BlendState := {
  fprintf(stderr, "mk BlendState \n");

  WGPUBlendState * blendState = calloc(1,sizeof(WGPUBlendState));
  blendState->color.srcFactor = WGPUBlendFactor_SrcAlpha;
  blendState->color.dstFactor = WGPUBlendFactor_OneMinusSrcAlpha;
  blendState->color.operation = WGPUBlendOperation_Add;
  blendState->alpha.srcFactor = WGPUBlendFactor_Zero;
  blendState->alpha.dstFactor = WGPUBlendFactor_One;
  blendState->alpha.operation = WGPUBlendOperation_Add;

  return lean_io_result_mk_ok(to_lean<BlendState>(blendState));
}

/-- # ColorTargetState -/

alloy c opaque_extern_type ColorTargetState => WGPUColorTargetState where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUColorTargetState \n");
    free(ptr);

alloy c extern
def ColorTargetState.mk (surfaceFormat : TextureFormat) (blendState : BlendState) : IO ColorTargetState := {
  fprintf(stderr, "mk ColorTargetState \n");
  WGPUTextureFormat c_surfaceFormat = of_lean<TextureFormat>(surfaceFormat);
  WGPUBlendState * c_blendState = of_lean<BlendState>(blendState);

  WGPUColorTargetState * colorTarget = calloc(1,sizeof(WGPUColorTargetState));
  colorTarget->format = c_surfaceFormat;
  colorTarget->blend  = c_blendState;
  -- TODO add writeMask param
  colorTarget->writeMask = WGPUColorWriteMask_All; // We could write to only some of the color channels.
  return lean_io_result_mk_ok(to_lean<ColorTargetState>(colorTarget));
}


/-- # FragmentState -/

alloy c opaque_extern_type FragmentState => WGPUFragmentState where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUFragmentState \n");
    free(ptr);

alloy c extern
def FragmentState.mk (shaderModule : ShaderModule) (colorTarget : ColorTargetState) : IO FragmentState := {
  fprintf(stderr, "mk FragmentState \n");
  WGPUShaderModule * c_shaderModule = of_lean<ShaderModule>(shaderModule);
  WGPUColorTargetState * c_colorTarget = of_lean<ColorTargetState>(colorTarget);

  WGPUFragmentState * fragmentState = calloc(1,sizeof(WGPUFragmentState));
  fragmentState->module = *c_shaderModule;
  fragmentState->entryPoint = "fs_main";
  fragmentState->constantCount = 0;
  fragmentState->constants = NULL;
  fragmentState->targetCount = 1;
  fragmentState->targets = c_colorTarget;
  return lean_io_result_mk_ok(to_lean<FragmentState>(fragmentState));
}

/-- # RenderPipelineDescriptor -/

alloy c opaque_extern_type RenderPipelineDescriptor => WGPURenderPipelineDescriptor where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPURenderPipelineDescriptor \n");
    free(ptr);

alloy c extern
def RenderPipelineDescriptor.mk  (shaderModule : ShaderModule) (fState : FragmentState) : IO RenderPipelineDescriptor := {
  WGPUShaderModule * c_shaderModule = of_lean<ShaderModule>(shaderModule);
  WGPUFragmentState * fragmentState = of_lean<FragmentState>(fState);

  WGPURenderPipelineDescriptor * pipelineDesc = calloc(1,sizeof(WGPURenderPipelineDescriptor));
  pipelineDesc->nextInChain = NULL;

  pipelineDesc->vertex.bufferCount = 0;
  pipelineDesc->vertex.buffers = NULL;
  pipelineDesc->vertex.module = *c_shaderModule;
  pipelineDesc->vertex.entryPoint = "vs_main";
  pipelineDesc->vertex.constantCount = 0;
  pipelineDesc->vertex.constants = NULL;

  pipelineDesc->primitive.topology = WGPUPrimitiveTopology_TriangleList;
  pipelineDesc->primitive.stripIndexFormat = WGPUIndexFormat_Undefined;
  pipelineDesc->primitive.frontFace = WGPUFrontFace_CCW;
  pipelineDesc->primitive.cullMode = WGPUCullMode_None;

  pipelineDesc->fragment = fragmentState;
  pipelineDesc->depthStencil = NULL;
  pipelineDesc->multisample.count = 1;
  -- fprintf(stderr, "multisample mask size: %d", sizeof(pipelineDesc->multisample.mask)); -- Kiiya: I get 4, so 0xFFFFFFFF should be okay
  pipelineDesc->multisample.mask = 0xFFFFFFFF;
  pipelineDesc->multisample.alphaToCoverageEnabled = false;
  pipelineDesc->layout = NULL;

  return lean_io_result_mk_ok(to_lean<RenderPipelineDescriptor>(pipelineDesc));
}

/-- Like `mk` but with a configurable multisample count (e.g. 4 for 4x MSAA). -/
alloy c extern
def RenderPipelineDescriptor.mkSampled (shaderModule : ShaderModule) (fState : FragmentState)
    (sampleCount : UInt32 := 1) : IO RenderPipelineDescriptor := {
  WGPUShaderModule *c_shaderModule = of_lean<ShaderModule>(shaderModule);
  WGPUFragmentState *fragmentState = of_lean<FragmentState>(fState);

  WGPURenderPipelineDescriptor *pipelineDesc = calloc(1,sizeof(WGPURenderPipelineDescriptor));
  pipelineDesc->nextInChain = NULL;
  pipelineDesc->vertex.bufferCount = 0;
  pipelineDesc->vertex.buffers = NULL;
  pipelineDesc->vertex.module = *c_shaderModule;
  pipelineDesc->vertex.entryPoint = "vs_main";
  pipelineDesc->vertex.constantCount = 0;
  pipelineDesc->vertex.constants = NULL;
  pipelineDesc->primitive.topology = WGPUPrimitiveTopology_TriangleList;
  pipelineDesc->primitive.stripIndexFormat = WGPUIndexFormat_Undefined;
  pipelineDesc->primitive.frontFace = WGPUFrontFace_CCW;
  pipelineDesc->primitive.cullMode = WGPUCullMode_None;
  pipelineDesc->fragment = fragmentState;
  pipelineDesc->depthStencil = NULL;
  pipelineDesc->multisample.count = sampleCount;
  pipelineDesc->multisample.mask = 0xFFFFFFFF;
  pipelineDesc->multisample.alphaToCoverageEnabled = false;
  pipelineDesc->layout = NULL;
  return lean_io_result_mk_ok(to_lean<RenderPipelineDescriptor>(pipelineDesc));
}

/-- # RenderPipeline -/

alloy c opaque_extern_type RenderPipeline => WGPURenderPipeline where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPURenderPipeline \n");
    wgpuRenderPipelineRelease(*ptr);
    free(ptr);

-- TODO unclog that mess
alloy c extern
def RenderPipeline.mk (device : Device) (pipelineDesc : RenderPipelineDescriptor) : IO RenderPipeline := {
  WGPUDevice * c_device = of_lean<Device>(device);
  WGPURenderPipelineDescriptor * c_pipelineDesc = of_lean<RenderPipelineDescriptor>(pipelineDesc);
  WGPURenderPipeline * pipeline = calloc(1,sizeof(WGPURenderPipeline));
  *pipeline = wgpuDeviceCreateRenderPipeline(*c_device, c_pipelineDesc);
  return lean_io_result_mk_ok(to_lean<RenderPipeline>(pipeline));
}

alloy c extern
def RenderPassEncoder.setPipeline (r : RenderPassEncoder) (p : RenderPipeline) : IO Unit := {
  WGPURenderPassEncoder * renderPass = of_lean<RenderPassEncoder>(r);
  WGPURenderPipeline * pipeline = of_lean<RenderPipeline>(p);
  wgpuRenderPassEncoderSetPipeline(*renderPass, *pipeline);
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern
def RenderPassEncoder.end (r : RenderPassEncoder) : IO Unit := {
  WGPURenderPassEncoder * renderPass = of_lean<RenderPassEncoder>(r);
  wgpuRenderPassEncoderEnd(*renderPass);
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern
def RenderPassEncoder.draw (r : RenderPassEncoder) (vShape n_inst i j : UInt32) : IO Unit := {
  WGPURenderPassEncoder * renderPass = of_lean<RenderPassEncoder>(r);
  wgpuRenderPassEncoderDraw(*renderPass, vShape, n_inst, i, j);
  return lean_io_result_mk_ok(lean_box(0));
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

/- # BufferDescriptor -/

alloy c opaque_extern_type BufferDescriptor => WGPUBufferDescriptor where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUBufferDescriptor \n");
    free(ptr);

abbrev BufferUsage := UInt32
def BufferUsage.none         : BufferUsage := 0x00000000
def BufferUsage.mapRead      : BufferUsage := 0x00000001
def BufferUsage.mapWrite     : BufferUsage := 0x00000002
def BufferUsage.copySrc      : BufferUsage := 0x00000004
def BufferUsage.copyDst      : BufferUsage := 0x00000008
def BufferUsage.index        : BufferUsage := 0x00000010
def BufferUsage.vertex       : BufferUsage := 0x00000020
def BufferUsage.uniform      : BufferUsage := 0x00000040
def BufferUsage.storage      : BufferUsage := 0x00000080
def BufferUsage.indirect     : BufferUsage := 0x00000100
def BufferUsage.queryResolve : BufferUsage := 0x00000200
def BufferUsage.force32      : BufferUsage := 0x7FFFFFFF

/-- WARNING: Stores a raw pointer to the Lean string's internal buffer without retaining
    the Lean string object. Safe only because descriptors are consumed immediately by
    `Buffer.mk` → `wgpuDeviceCreateBuffer`, which copies the label. Do NOT store this
    descriptor long-term without also keeping the label String alive. -/
alloy c extern
def BufferDescriptor.mk (label : String) (usage : BufferUsage)
  (size : UInt32) (mappedAtCreation : Bool) : BufferDescriptor := {
  WGPUBufferDescriptor * bufferDesc = calloc(1,sizeof(WGPUBufferDescriptor));
  bufferDesc->nextInChain = NULL;
  bufferDesc->label = lean_string_cstr(label);
  bufferDesc->usage = usage;
  bufferDesc->size = size;
  bufferDesc->mappedAtCreation = mappedAtCreation;
  return to_lean<BufferDescriptor>(bufferDesc);
  }

/- # Buffer -/

alloy c opaque_extern_type Buffer => WGPUBuffer where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUBuffer \n");
    wgpuBufferRelease(*ptr);
    free(ptr);

alloy c extern
def Buffer.mk (device : Device) (descriptor : BufferDescriptor) : IO Buffer := {
  WGPUDevice c_device = *of_lean<Device>(device);
  WGPUBufferDescriptor * bufferDesc = of_lean<BufferDescriptor>(descriptor);
  WGPUBuffer * buffer = calloc(1,sizeof(WGPUBuffer));
  *buffer = wgpuDeviceCreateBuffer(c_device, bufferDesc);
  return lean_io_result_mk_ok(to_lean<Buffer>(buffer));
}
alloy c extern
def Queue.writeBuffer (queue : Queue) (buffer : Buffer) (bytes : ByteArray) : IO Unit := {
    WGPUQueue c_queue= *of_lean<Queue>(queue);
    WGPUBuffer c_buffer = *of_lean<Buffer>(buffer);
    uint8_t* arr = lean_sarray_cptr(bytes);
    size_t arr_size = lean_sarray_size(bytes);
    wgpuQueueWriteBuffer(c_queue, c_buffer, 0, arr, arr_size);
    return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern
def Queue.writeBufferOffset (queue : Queue) (buffer : Buffer) (offset : UInt64) (bytes : ByteArray) : IO Unit := {
    WGPUQueue c_queue= *of_lean<Queue>(queue);
    WGPUBuffer c_buffer = *of_lean<Buffer>(buffer);
    uint8_t* arr = lean_sarray_cptr(bytes);
    size_t arr_size = lean_sarray_size(bytes);
    wgpuQueueWriteBuffer(c_queue, c_buffer, offset, arr, arr_size);
    return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern
def Buffer.getSize (buffer : Buffer) : IO UInt64 := {
    WGPUBuffer c_buffer = *of_lean<Buffer>(buffer);
    uint64_t sz = wgpuBufferGetSize(c_buffer);
    return lean_io_result_mk_ok(lean_box_uint64(sz));
}

alloy c extern
def Buffer.destroy (buffer : Buffer) : IO Unit := {
    WGPUBuffer c_buffer = *of_lean<Buffer>(buffer);
    wgpuBufferDestroy(c_buffer);
    return lean_io_result_mk_ok(lean_box(0));
}

/- # Vertex Buffer Support -/

alloy c enum VertexFormat => WGPUVertexFormat
| Undefined => WGPUVertexFormat_Undefined
| Uint8x2 => WGPUVertexFormat_Uint8x2
| Uint8x4 => WGPUVertexFormat_Uint8x4
| Sint8x2 => WGPUVertexFormat_Sint8x2
| Sint8x4 => WGPUVertexFormat_Sint8x4
| Unorm8x2 => WGPUVertexFormat_Unorm8x2
| Unorm8x4 => WGPUVertexFormat_Unorm8x4
| Snorm8x2 => WGPUVertexFormat_Snorm8x2
| Snorm8x4 => WGPUVertexFormat_Snorm8x4
| Uint16x2 => WGPUVertexFormat_Uint16x2
| Uint16x4 => WGPUVertexFormat_Uint16x4
| Sint16x2 => WGPUVertexFormat_Sint16x2
| Sint16x4 => WGPUVertexFormat_Sint16x4
| Unorm16x2 => WGPUVertexFormat_Unorm16x2
| Unorm16x4 => WGPUVertexFormat_Unorm16x4
| Snorm16x2 => WGPUVertexFormat_Snorm16x2
| Snorm16x4 => WGPUVertexFormat_Snorm16x4
| Float16x2 => WGPUVertexFormat_Float16x2
| Float16x4 => WGPUVertexFormat_Float16x4
| Float32 => WGPUVertexFormat_Float32
| Float32x2 => WGPUVertexFormat_Float32x2
| Float32x3 => WGPUVertexFormat_Float32x3
| Float32x4 => WGPUVertexFormat_Float32x4
| Uint32 => WGPUVertexFormat_Uint32
| Uint32x2 => WGPUVertexFormat_Uint32x2
| Uint32x3 => WGPUVertexFormat_Uint32x3
| Uint32x4 => WGPUVertexFormat_Uint32x4
| Sint32 => WGPUVertexFormat_Sint32
| Sint32x2 => WGPUVertexFormat_Sint32x2
| Sint32x3 => WGPUVertexFormat_Sint32x3
| Sint32x4 => WGPUVertexFormat_Sint32x4
| Force32 => WGPUVertexFormat_Force32
deriving Inhabited, Repr, BEq

/-- A single vertex attribute description (format, offset, shaderLocation). -/
structure VertexAttributeDesc where
  format : VertexFormat
  offset : UInt64
  shaderLocation : UInt32
deriving Inhabited, Repr

alloy c enum VertexStepMode => WGPUVertexStepMode
| Vertex => WGPUVertexStepMode_Vertex
| Instance => WGPUVertexStepMode_Instance
| VertexBufferNotUsed => WGPUVertexStepMode_VertexBufferNotUsed
| Force32 => WGPUVertexStepMode_Force32
deriving Inhabited, Repr, BEq

/-- Description of a vertex buffer layout (stride, stepMode, attributes). -/
structure VertexBufferLayoutDesc where
  arrayStride : UInt64
  stepMode : VertexStepMode
  attributes : Array VertexAttributeDesc
deriving Inhabited, Repr

alloy c enum IndexFormat => WGPUIndexFormat
| Undefined => WGPUIndexFormat_Undefined
| Uint16 => WGPUIndexFormat_Uint16
| Uint32 => WGPUIndexFormat_Uint32
| Force32 => WGPUIndexFormat_Force32
deriving Inhabited, Repr, BEq

/-- Set a vertex buffer on a render pass encoder. Uses WGPU_WHOLE_SIZE for the buffer. -/
alloy c extern
def RenderPassEncoder.setVertexBuffer (r : RenderPassEncoder) (slot : UInt32) (buffer : Buffer)
    (offset : UInt64 := 0) : IO Unit := {
  WGPURenderPassEncoder *renderPass = of_lean<RenderPassEncoder>(r);
  WGPUBuffer *c_buffer = of_lean<Buffer>(buffer);
  uint64_t size = wgpuBufferGetSize(*c_buffer) - offset;
  wgpuRenderPassEncoderSetVertexBuffer(*renderPass, slot, *c_buffer, offset, size);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set an index buffer on a render pass encoder. -/
alloy c extern
def RenderPassEncoder.setIndexBuffer (r : RenderPassEncoder) (buffer : Buffer) (format : IndexFormat)
    (offset : UInt64 := 0) : IO Unit := {
  WGPURenderPassEncoder *renderPass = of_lean<RenderPassEncoder>(r);
  WGPUBuffer *c_buffer = of_lean<Buffer>(buffer);
  uint64_t size = wgpuBufferGetSize(*c_buffer) - offset;
  wgpuRenderPassEncoderSetIndexBuffer(*renderPass, *c_buffer, of_lean<IndexFormat>(format), offset, size);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Draw indexed primitives. -/
alloy c extern
def RenderPassEncoder.drawIndexed (r : RenderPassEncoder) (indexCount instanceCount firstIndex : UInt32)
    (baseVertex : Int32 := 0) (firstInstance : UInt32 := 0) : IO Unit := {
  WGPURenderPassEncoder *renderPass = of_lean<RenderPassEncoder>(r);
  wgpuRenderPassEncoderDrawIndexed(*renderPass, indexCount, instanceCount, firstIndex, baseVertex, firstInstance);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set the viewport on a render pass encoder. -/
alloy c extern
def RenderPassEncoder.setViewport (r : RenderPassEncoder) (x y width height minDepth maxDepth : Float) : IO Unit := {
  WGPURenderPassEncoder *renderPass = of_lean<RenderPassEncoder>(r);
  wgpuRenderPassEncoderSetViewport(*renderPass, x, y, width, height, minDepth, maxDepth);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set the scissor rect on a render pass encoder. -/
alloy c extern
def RenderPassEncoder.setScissorRect (r : RenderPassEncoder) (x y width height : UInt32) : IO Unit := {
  WGPURenderPassEncoder *renderPass = of_lean<RenderPassEncoder>(r);
  wgpuRenderPassEncoderSetScissorRect(*renderPass, x, y, width, height);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- # RenderPassEncoder with configurable clear color -/

alloy c extern
def RenderPassEncoder.mkWithColor (encoder : CommandEncoder) (view : TextureView) (color : Color) : IO RenderPassEncoder := {
  WGPUCommandEncoder *c_encoder = of_lean<CommandEncoder>(encoder);
  WGPURenderPassDescriptor *renderPassDesc = calloc(1,sizeof(WGPURenderPassDescriptor));
  renderPassDesc->nextInChain = NULL;

  WGPURenderPassColorAttachment *renderPassColorAttachment = calloc(1,sizeof(WGPURenderPassColorAttachment));
  WGPUTextureView *c_view = of_lean<TextureView>(view)
  renderPassColorAttachment->view = *c_view;
  renderPassColorAttachment->resolveTarget = NULL;
  renderPassColorAttachment->loadOp = WGPULoadOp_Clear;
  renderPassColorAttachment->storeOp = WGPUStoreOp_Store;
  WGPUColor *c_color = of_lean<Color>(color);
  renderPassColorAttachment->clearValue = *c_color;

  renderPassDesc->colorAttachmentCount = 1;
  renderPassDesc->colorAttachments = renderPassColorAttachment;
  renderPassDesc->depthStencilAttachment = NULL;
  renderPassDesc->timestampWrites = NULL;

  WGPURenderPassEncoder *renderPass = calloc(1,sizeof(WGPURenderPassEncoder));
  *renderPass = wgpuCommandEncoderBeginRenderPass(*c_encoder, renderPassDesc);

  free(renderPassColorAttachment);
  free(renderPassDesc);

  return lean_io_result_mk_ok(to_lean<RenderPassEncoder>(renderPass));
}

/- # RenderPipeline with Vertex Buffers -/

/--
  Create a render pipeline descriptor with vertex buffer layouts.
  `vertexBufferLayouts` is an array of `(arrayStride, stepMode, Array (format, offset, shaderLocation))`.
-/
alloy c extern
def RenderPipelineDescriptor.mkWithVertexBuffers
    (shaderModule : ShaderModule)
    (fState : FragmentState)
    (vertexEntryPoint : String := "vs_main")
    (strides : @& Array UInt64)
    (stepModes : @& Array UInt32)
    (attrFormats : @& Array UInt32)
    (attrOffsets : @& Array UInt64)
    (attrShaderLocations : @& Array UInt32)
    (attrBufferIndices : @& Array UInt32)
    (bufferCount : UInt32)
    : IO RenderPipelineDescriptor := {
  WGPUShaderModule *c_shaderModule = of_lean<ShaderModule>(shaderModule);
  WGPUFragmentState *fragmentState = of_lean<FragmentState>(fState);

  uint32_t nBuffers = bufferCount;
  size_t nAttrs = lean_array_size(attrFormats);

  -- Allocate vertex buffer layouts
  WGPUVertexBufferLayout *bufferLayouts = calloc(nBuffers, sizeof(WGPUVertexBufferLayout));
  for (uint32_t i = 0; i < nBuffers; i++) {
    bufferLayouts[i].arrayStride = lean_unbox_uint64(lean_array_uget(strides, i));
    bufferLayouts[i].stepMode = (WGPUVertexStepMode)lean_unbox(lean_array_uget(stepModes, i));
    bufferLayouts[i].attributeCount = 0;
    bufferLayouts[i].attributes = NULL;
  }

  -- Count attributes per buffer
  for (size_t i = 0; i < nAttrs; i++) {
    uint32_t bufIdx = lean_unbox(lean_array_uget(attrBufferIndices, i));
    bufferLayouts[bufIdx].attributeCount++;
  }

  -- Allocate attributes per buffer
  WGPUVertexAttribute **attrArrays = calloc(nBuffers, sizeof(WGPUVertexAttribute*));
  uint32_t *attrCounters = calloc(nBuffers, sizeof(uint32_t));
  for (uint32_t i = 0; i < nBuffers; i++) {
    attrArrays[i] = calloc(bufferLayouts[i].attributeCount, sizeof(WGPUVertexAttribute));
    bufferLayouts[i].attributes = attrArrays[i];
  }

  -- Fill in attributes
  for (size_t i = 0; i < nAttrs; i++) {
    uint32_t bufIdx = lean_unbox(lean_array_uget(attrBufferIndices, i));
    uint32_t ai = attrCounters[bufIdx]++;
    attrArrays[bufIdx][ai].format = (WGPUVertexFormat)lean_unbox(lean_array_uget(attrFormats, i));
    attrArrays[bufIdx][ai].offset = lean_unbox_uint64(lean_array_uget(attrOffsets, i));
    attrArrays[bufIdx][ai].shaderLocation = lean_unbox(lean_array_uget(attrShaderLocations, i));
  }
  free(attrCounters);
  free(attrArrays);

  WGPURenderPipelineDescriptor *pipelineDesc = calloc(1,sizeof(WGPURenderPipelineDescriptor));
  pipelineDesc->nextInChain = NULL;

  pipelineDesc->vertex.bufferCount = nBuffers;
  pipelineDesc->vertex.buffers = bufferLayouts;
  pipelineDesc->vertex.module = *c_shaderModule;
  pipelineDesc->vertex.entryPoint = lean_string_cstr(vertexEntryPoint);
  pipelineDesc->vertex.constantCount = 0;
  pipelineDesc->vertex.constants = NULL;

  pipelineDesc->primitive.topology = WGPUPrimitiveTopology_TriangleList;
  pipelineDesc->primitive.stripIndexFormat = WGPUIndexFormat_Undefined;
  pipelineDesc->primitive.frontFace = WGPUFrontFace_CCW;
  pipelineDesc->primitive.cullMode = WGPUCullMode_None;

  pipelineDesc->fragment = fragmentState;
  pipelineDesc->depthStencil = NULL;
  pipelineDesc->multisample.count = 1;
  pipelineDesc->multisample.mask = 0xFFFFFFFF;
  pipelineDesc->multisample.alphaToCoverageEnabled = false;
  pipelineDesc->layout = NULL;

  return lean_io_result_mk_ok(to_lean<RenderPipelineDescriptor>(pipelineDesc));
}

/-- Helper: Build a RenderPipelineDescriptor from pure Lean VertexBufferLayoutDesc array. -/
def RenderPipelineDescriptor.mkWithLayouts
    (shaderModule : ShaderModule)
    (fState : FragmentState)
    (layouts : Array VertexBufferLayoutDesc)
    (vertexEntryPoint : String := "vs_main")
    : IO RenderPipelineDescriptor := do
  let mut strides : Array UInt64 := #[]
  let mut stepModes : Array UInt32 := #[]
  let mut attrFormats : Array UInt32 := #[]
  let mut attrOffsets : Array UInt64 := #[]
  let mut attrShaderLocations : Array UInt32 := #[]
  let mut attrBufferIndices : Array UInt32 := #[]
  for h : i in [:layouts.size] do
    let layout := layouts[i]
    strides := strides.push layout.arrayStride
    stepModes := stepModes.push (match layout.stepMode with
      | .Vertex => 0 | .Instance => 1 | .VertexBufferNotUsed => 2 | .Force32 => 3)
    for attr in layout.attributes do
      attrFormats := attrFormats.push (match attr.format with
        | .Undefined => 0 | .Uint8x2 => 1 | .Uint8x4 => 2 | .Sint8x2 => 3 | .Sint8x4 => 4
        | .Unorm8x2 => 5 | .Unorm8x4 => 6 | .Snorm8x2 => 7 | .Snorm8x4 => 8
        | .Uint16x2 => 9 | .Uint16x4 => 10 | .Sint16x2 => 11 | .Sint16x4 => 12
        | .Unorm16x2 => 13 | .Unorm16x4 => 14 | .Snorm16x2 => 15 | .Snorm16x4 => 16
        | .Float16x2 => 17 | .Float16x4 => 18
        | .Float32 => 19 | .Float32x2 => 20 | .Float32x3 => 21 | .Float32x4 => 22
        | .Uint32 => 23 | .Uint32x2 => 24 | .Uint32x3 => 25 | .Uint32x4 => 26
        | .Sint32 => 27 | .Sint32x2 => 28 | .Sint32x3 => 29 | .Sint32x4 => 30
        | .Force32 => 31)
      attrOffsets := attrOffsets.push attr.offset
      attrShaderLocations := attrShaderLocations.push attr.shaderLocation
      attrBufferIndices := attrBufferIndices.push i.toUInt32
  RenderPipelineDescriptor.mkWithVertexBuffers shaderModule fState vertexEntryPoint
    strides stepModes attrFormats attrOffsets attrShaderLocations attrBufferIndices layouts.size.toUInt32

/- # Bind Group Support -/

alloy c opaque_extern_type BindGroupLayout => WGPUBindGroupLayout where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUBindGroupLayout \n");
    wgpuBindGroupLayoutRelease(*ptr);
    free(ptr);

alloy c opaque_extern_type BindGroup => WGPUBindGroup where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUBindGroup \n");
    wgpuBindGroupRelease(*ptr);
    free(ptr);

alloy c opaque_extern_type PipelineLayout => WGPUPipelineLayout where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUPipelineLayout \n");
    wgpuPipelineLayoutRelease(*ptr);
    free(ptr);

/-- Create a bind group layout with a single uniform buffer binding at the given binding index. -/
alloy c extern
def BindGroupLayout.mkUniform (device : Device) (binding : UInt32) (visibility : UInt32)
    (minBindingSize : UInt64 := 0) : IO BindGroupLayout := {
  WGPUDevice c_device = *of_lean<Device>(device);

  WGPUBindGroupLayoutEntry *entry = calloc(1, sizeof(WGPUBindGroupLayoutEntry));
  entry->binding = binding;
  entry->visibility = visibility;
  entry->buffer.type = WGPUBufferBindingType_Uniform;
  entry->buffer.hasDynamicOffset = false;
  entry->buffer.minBindingSize = minBindingSize;
  -- Zero-init the rest
  entry->sampler.type = WGPUSamplerBindingType_Undefined;
  entry->texture.sampleType = WGPUTextureSampleType_Undefined;
  entry->storageTexture.access = WGPUStorageTextureAccess_Undefined;

  WGPUBindGroupLayoutDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "Uniform bind group layout";
  desc.entryCount = 1;
  desc.entries = entry;

  WGPUBindGroupLayout *layout = calloc(1, sizeof(WGPUBindGroupLayout));
  *layout = wgpuDeviceCreateBindGroupLayout(c_device, &desc);
  free(entry);
  return lean_io_result_mk_ok(to_lean<BindGroupLayout>(layout));
}

/-- Create a bind group that binds a buffer to a layout. -/
alloy c extern
def BindGroup.mk (device : Device) (layout : BindGroupLayout) (binding : UInt32)
    (buffer : Buffer) (offset : UInt64 := 0) (size : UInt64 := 0) : IO BindGroup := {
  WGPUDevice c_device = *of_lean<Device>(device);
  WGPUBindGroupLayout *c_layout = of_lean<BindGroupLayout>(layout);
  WGPUBuffer *c_buffer = of_lean<Buffer>(buffer);

  uint64_t bufSize = size;
  if (bufSize == 0) {
    bufSize = wgpuBufferGetSize(*c_buffer) - offset;
  }

  WGPUBindGroupEntry *entry = calloc(1, sizeof(WGPUBindGroupEntry));
  entry->nextInChain = NULL;
  entry->binding = binding;
  entry->buffer = *c_buffer;
  entry->offset = offset;
  entry->size = bufSize;
  entry->sampler = NULL;
  entry->textureView = NULL;

  WGPUBindGroupDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "Bind group";
  desc.layout = *c_layout;
  desc.entryCount = 1;
  desc.entries = entry;

  WGPUBindGroup *bg = calloc(1, sizeof(WGPUBindGroup));
  *bg = wgpuDeviceCreateBindGroup(c_device, &desc);
  free(entry);
  return lean_io_result_mk_ok(to_lean<BindGroup>(bg));
}

/-- Create a pipeline layout from an array of bind group layouts. -/
alloy c extern
def PipelineLayout.mk (device : Device) (layouts : @& Array BindGroupLayout) : IO PipelineLayout := {
  WGPUDevice c_device = *of_lean<Device>(device);
  size_t n = lean_array_size(layouts);
  WGPUBindGroupLayout *c_layouts = calloc(n, sizeof(WGPUBindGroupLayout));
  for (size_t i = 0; i < n; i++) {
    lean_object *obj = lean_array_uget(layouts, i);
    WGPUBindGroupLayout *l = of_lean<BindGroupLayout>(obj);
    c_layouts[i] = *l;
  }
  WGPUPipelineLayoutDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "Pipeline layout";
  desc.bindGroupLayoutCount = n;
  desc.bindGroupLayouts = c_layouts;

  WGPUPipelineLayout *pl = calloc(1, sizeof(WGPUPipelineLayout));
  *pl = wgpuDeviceCreatePipelineLayout(c_device, &desc);
  free(c_layouts);
  return lean_io_result_mk_ok(to_lean<PipelineLayout>(pl));
}

/-- Set a bind group on a render pass encoder. -/
alloy c extern
def RenderPassEncoder.setBindGroup (r : RenderPassEncoder) (groupIndex : UInt32) (bg : BindGroup) : IO Unit := {
  WGPURenderPassEncoder *renderPass = of_lean<RenderPassEncoder>(r);
  WGPUBindGroup *c_bg = of_lean<BindGroup>(bg);
  wgpuRenderPassEncoderSetBindGroup(*renderPass, groupIndex, *c_bg, 0, NULL);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Create a render pipeline with an explicit pipeline layout. -/
alloy c extern
def RenderPipeline.mkWithLayout (device : Device) (pipelineDesc : RenderPipelineDescriptor) (layout : PipelineLayout) : IO RenderPipeline := {
  WGPUDevice *c_device = of_lean<Device>(device);
  WGPURenderPipelineDescriptor *c_pipelineDesc = of_lean<RenderPipelineDescriptor>(pipelineDesc);
  WGPUPipelineLayout *c_layout = of_lean<PipelineLayout>(layout);
  c_pipelineDesc->layout = *c_layout;
  WGPURenderPipeline *pipeline = calloc(1,sizeof(WGPURenderPipeline));
  *pipeline = wgpuDeviceCreateRenderPipeline(*c_device, c_pipelineDesc);
  return lean_io_result_mk_ok(to_lean<RenderPipeline>(pipeline));
}

/- # Shader Stage Flags -/
abbrev ShaderStageFlags := UInt32
def ShaderStageFlags.none     : ShaderStageFlags := 0x00000000
def ShaderStageFlags.vertex   : ShaderStageFlags := 0x00000001
def ShaderStageFlags.fragment : ShaderStageFlags := 0x00000002
def ShaderStageFlags.compute  : ShaderStageFlags := 0x00000004

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
def Device.getLimits (device : Device) : IO Limits := {
  WGPUDevice *c_device = of_lean<Device>(device);
  WGPUSupportedLimits supported = {};
  supported.nextInChain = NULL;
  wgpuDeviceGetLimits(*c_device, &supported);
  return lean_io_result_mk_ok(limits_to_lean(&supported.limits));
}

alloy c extern
def Adapter.hasFeature (adapter : Adapter) (feature : Feature) : IO Bool := {
  WGPUAdapter *c_adapter = of_lean<Adapter>(adapter);
  WGPUFeatureName fn = of_lean<Feature>(feature);
  WGPUBool has = wgpuAdapterHasFeature(*c_adapter, fn);
  return lean_io_result_mk_ok(lean_box(has));
}

/-- Query all features supported by the adapter. -/
alloy c extern def Adapter.features (adapter : Adapter) : IO (Array Feature) := {
  WGPUAdapter c_adapter = *of_lean<Adapter>(adapter);
  size_t n = wgpuAdapterEnumerateFeatures(c_adapter, NULL);
  WGPUFeatureName *features = calloc(n, sizeof(WGPUFeatureName));
  wgpuAdapterEnumerateFeatures(c_adapter, features);
  lean_object *array = lean_mk_array(lean_box(0), lean_box(0));
  for (size_t i = 0; i < n; i++) {
    array = lean_array_push(array, lean_box(to_lean<Feature>(features[i])));
  }
  free(features);
  return lean_io_result_mk_ok(array);
}

/- # Float-based ByteArray helpers for vertex data -/

/-- Convert an array of floats to a ByteArray (little-endian float32). -/
alloy c extern
def floatsToByteArray (arr : @& Array Float) : ByteArray := {
  size_t n = lean_array_size(arr);
  size_t byte_count = n * sizeof(float);
  lean_object *ba = lean_alloc_sarray(1, byte_count, byte_count);
  uint8_t *ptr = lean_sarray_cptr(ba);
  for (size_t i = 0; i < n; i++) {
    double d = lean_unbox_float(lean_array_uget(arr, i));
    float f = (float)d;
    memcpy(ptr + i * sizeof(float), &f, sizeof(float));
  }
  return ba;
}

/-- Convert an array of UInt16 to a ByteArray (little-endian). -/
alloy c extern
def uint16sToByteArray (arr : @& Array UInt16) : ByteArray := {
  size_t n = lean_array_size(arr);
  size_t byte_count = n * sizeof(uint16_t);
  lean_object *ba = lean_alloc_sarray(1, byte_count, byte_count);
  uint8_t *ptr = lean_sarray_cptr(ba);
  for (size_t i = 0; i < n; i++) {
    uint16_t v = lean_unbox(lean_array_uget(arr, i));
    memcpy(ptr + i * sizeof(uint16_t), &v, sizeof(uint16_t));
  }
  return ba;
}

/-- Convert an array of UInt32 to a ByteArray (little-endian). -/
alloy c extern
def uint32sToByteArray (arr : @& Array UInt32) : ByteArray := {
  size_t n = lean_array_size(arr);
  size_t byte_count = n * sizeof(uint32_t);
  lean_object *ba = lean_alloc_sarray(1, byte_count, byte_count);
  uint8_t *ptr = lean_sarray_cptr(ba);
  for (size_t i = 0; i < n; i++) {
    uint32_t v = lean_unbox(lean_array_uget(arr, i));
    memcpy(ptr + i * sizeof(uint32_t), &v, sizeof(uint32_t));
  }
  return ba;
}

/-- Read UInt32 values from a ByteArray (little-endian). -/
alloy c extern
def byteArrayToUInt32s (arr : @& ByteArray) : Array UInt32 := {
  size_t byte_count = lean_sarray_size(arr);
  size_t n = byte_count / sizeof(uint32_t);
  uint8_t *ptr = lean_sarray_cptr(arr);
  lean_object *array = lean_mk_array(lean_box(0), lean_box(0));
  for (size_t i = 0; i < n; i++) {
    uint32_t v;
    memcpy(&v, ptr + i * sizeof(uint32_t), sizeof(uint32_t));
    array = lean_array_push(array, lean_box(v));
  }
  return array;
}

/-- Read Float values from a ByteArray (little-endian float32). -/
alloy c extern
def byteArrayToFloats (arr : @& ByteArray) : Array Float := {
  size_t byte_count = lean_sarray_size(arr);
  size_t n = byte_count / sizeof(float);
  uint8_t *ptr = lean_sarray_cptr(arr);
  lean_object *array = lean_mk_array(lean_box(0), lean_box(0));
  for (size_t i = 0; i < n; i++) {
    float f;
    memcpy(&f, ptr + i * sizeof(float), sizeof(float));
    array = lean_array_push(array, lean_box_float((double)f));
  }
  return array;
}

/-- Generate RGBA pixel data for a checkerboard pattern. -/
def mkCheckerboard (width height tileSize : UInt32)
    (color1 : UInt32 := 0xFF4488FF) (color2 : UInt32 := 0xFF222222) : ByteArray := Id.run do
  let mut bytes : ByteArray := ByteArray.mk #[]
  for y in [:height.toNat] do
    for x in [:width.toNat] do
      let tileX := x / tileSize.toNat
      let tileY := y / tileSize.toNat
      let color := if (tileX + tileY) % 2 == 0 then color1 else color2
      -- RGBA little-endian
      bytes := bytes.push (color &&& 0xFF).toUInt8
      bytes := bytes.push ((color >>> 8) &&& 0xFF).toUInt8
      bytes := bytes.push ((color >>> 16) &&& 0xFF).toUInt8
      bytes := bytes.push ((color >>> 24) &&& 0xFF).toUInt8
  return bytes

/- # Texture Support -/

abbrev TextureUsage := UInt32
def TextureUsage.none             : TextureUsage := 0x00000000
def TextureUsage.copySrc          : TextureUsage := 0x00000001
def TextureUsage.copyDst          : TextureUsage := 0x00000002
def TextureUsage.textureBinding   : TextureUsage := 0x00000004
def TextureUsage.storageBinding   : TextureUsage := 0x00000008
def TextureUsage.renderAttachment : TextureUsage := 0x00000010

alloy c opaque_extern_type Texture => WGPUTexture where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUTexture\n");
    wgpuTextureRelease(*ptr);
    free(ptr);

/-- Create a 2D texture. -/
alloy c extern
def Device.createTexture (device : Device) (width height : UInt32)
    (format : TextureFormat) (usage : TextureUsage)
    (mipLevelCount : UInt32 := 1) (sampleCount : UInt32 := 1)
    : IO Texture := {
  WGPUDevice c_device = *of_lean<Device>(device);

  WGPUTextureDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "Texture";
  desc.usage = usage;
  desc.dimension = WGPUTextureDimension_2D;
  desc.size.width = width;
  desc.size.height = height;
  desc.size.depthOrArrayLayers = 1;
  desc.format = of_lean<TextureFormat>(format);
  desc.mipLevelCount = mipLevelCount;
  desc.sampleCount = sampleCount;
  desc.viewFormatCount = 0;
  desc.viewFormats = NULL;

  WGPUTexture *tex = calloc(1, sizeof(WGPUTexture));
  *tex = wgpuDeviceCreateTexture(c_device, &desc);
  return lean_io_result_mk_ok(to_lean<Texture>(tex));
}

/-- Create a TextureView from a Texture (2D, all mips, all layers). -/
alloy c extern
def Texture.createView (texture : Texture) (format : TextureFormat) : IO TextureView := {
  WGPUTexture *c_tex = of_lean<Texture>(texture);

  WGPUTextureViewDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "Texture view";
  desc.format = of_lean<TextureFormat>(format);
  desc.dimension = WGPUTextureViewDimension_2D;
  desc.baseMipLevel = 0;
  desc.mipLevelCount = 1;
  desc.baseArrayLayer = 0;
  desc.arrayLayerCount = 1;
  desc.aspect = WGPUTextureAspect_All;

  WGPUTextureView *view = calloc(1, sizeof(WGPUTextureView));
  *view = wgpuTextureCreateView(*c_tex, &desc);
  return lean_io_result_mk_ok(to_lean<TextureView>(view));
}

/-- Write pixel data to a 2D texture. -/
alloy c extern
def Queue.writeTexture (queue : Queue) (texture : Texture) (data : ByteArray)
    (width height : UInt32) (bytesPerRow : UInt32) : IO Unit := {
  WGPUQueue c_queue = *of_lean<Queue>(queue);
  WGPUTexture *c_tex = of_lean<Texture>(texture);

  WGPUImageCopyTexture dest = {};
  dest.texture = *c_tex;
  dest.mipLevel = 0;
  dest.origin = (WGPUOrigin3D){0, 0, 0};
  dest.aspect = WGPUTextureAspect_All;

  WGPUTextureDataLayout layout = {};
  layout.nextInChain = NULL;
  layout.offset = 0;
  layout.bytesPerRow = bytesPerRow;
  layout.rowsPerImage = height;

  WGPUExtent3D extent = {width, height, 1};

  uint8_t *ptr = lean_sarray_cptr(data);
  size_t dataSize = lean_sarray_size(data);
  wgpuQueueWriteTexture(c_queue, &dest, ptr, dataSize, &layout, &extent);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Destroy a texture object. -/
alloy c extern
def Texture.destroy (texture : Texture) : IO Unit := {
  WGPUTexture *c_tex = of_lean<Texture>(texture);
  wgpuTextureDestroy(*c_tex);
  return lean_io_result_mk_ok(lean_box(0));
}

/- # Sampler Support -/

alloy c enum AddressMode => WGPUAddressMode
| Repeat => WGPUAddressMode_Repeat
| MirrorRepeat => WGPUAddressMode_MirrorRepeat
| ClampToEdge => WGPUAddressMode_ClampToEdge
| Force32 => WGPUAddressMode_Force32
deriving Inhabited, Repr, BEq

alloy c enum FilterMode => WGPUFilterMode
| Nearest => WGPUFilterMode_Nearest
| Linear => WGPUFilterMode_Linear
| Force32 => WGPUFilterMode_Force32
deriving Inhabited, Repr, BEq

alloy c opaque_extern_type Sampler => WGPUSampler where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUSampler\n");
    wgpuSamplerRelease(*ptr);
    free(ptr);

/-- Create a sampler with configurable filtering and address modes. -/
alloy c extern
def Device.createSampler (device : Device)
    (magFilter : FilterMode := FilterMode.Linear)
    (minFilter : FilterMode := FilterMode.Linear)
    (addressModeU : AddressMode := AddressMode.ClampToEdge)
    (addressModeV : AddressMode := AddressMode.ClampToEdge)
    : IO Sampler := {
  WGPUDevice c_device = *of_lean<Device>(device);

  WGPUSamplerDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "Sampler";
  desc.addressModeU = of_lean<AddressMode>(addressModeU);
  desc.addressModeV = of_lean<AddressMode>(addressModeV);
  desc.addressModeW = WGPUAddressMode_ClampToEdge;
  desc.magFilter = of_lean<FilterMode>(magFilter);
  desc.minFilter = of_lean<FilterMode>(minFilter);
  desc.mipmapFilter = WGPUMipmapFilterMode_Nearest;
  desc.lodMinClamp = 0.0f;
  desc.lodMaxClamp = 1.0f;
  desc.compare = WGPUCompareFunction_Undefined;
  desc.maxAnisotropy = 1;

  WGPUSampler *sampler = calloc(1, sizeof(WGPUSampler));
  *sampler = wgpuDeviceCreateSampler(c_device, &desc);
  return lean_io_result_mk_ok(to_lean<Sampler>(sampler));
}

/-- Create a bind group layout with a texture + sampler pair. -/
alloy c extern
def BindGroupLayout.mkTextureSampler (device : Device)
    (textureBinding samplerBinding : UInt32) (visibility : UInt32)
    : IO BindGroupLayout := {
  WGPUDevice c_device = *of_lean<Device>(device);

  WGPUBindGroupLayoutEntry *entries = calloc(2, sizeof(WGPUBindGroupLayoutEntry));

  entries[0].binding = textureBinding;
  entries[0].visibility = visibility;
  entries[0].texture.sampleType = WGPUTextureSampleType_Float;
  entries[0].texture.viewDimension = WGPUTextureViewDimension_2D;
  entries[0].texture.multisampled = false;
  entries[0].buffer.type = WGPUBufferBindingType_Undefined;
  entries[0].sampler.type = WGPUSamplerBindingType_Undefined;
  entries[0].storageTexture.access = WGPUStorageTextureAccess_Undefined;

  entries[1].binding = samplerBinding;
  entries[1].visibility = visibility;
  entries[1].sampler.type = WGPUSamplerBindingType_Filtering;
  entries[1].texture.sampleType = WGPUTextureSampleType_Undefined;
  entries[1].buffer.type = WGPUBufferBindingType_Undefined;
  entries[1].storageTexture.access = WGPUStorageTextureAccess_Undefined;

  WGPUBindGroupLayoutDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "Texture+Sampler bind group layout";
  desc.entryCount = 2;
  desc.entries = entries;

  WGPUBindGroupLayout *layout = calloc(1, sizeof(WGPUBindGroupLayout));
  *layout = wgpuDeviceCreateBindGroupLayout(c_device, &desc);
  free(entries);
  return lean_io_result_mk_ok(to_lean<BindGroupLayout>(layout));
}

/-- Create a bind group that binds a texture view and sampler. -/
alloy c extern
def BindGroup.mkTextureSampler (device : Device) (layout : BindGroupLayout)
    (textureBinding : UInt32) (textureView : TextureView)
    (samplerBinding : UInt32) (sampler : Sampler)
    : IO BindGroup := {
  WGPUDevice c_device = *of_lean<Device>(device);
  WGPUBindGroupLayout *c_layout = of_lean<BindGroupLayout>(layout);
  WGPUTextureView *c_view = of_lean<TextureView>(textureView);
  WGPUSampler *c_sampler = of_lean<Sampler>(sampler);

  WGPUBindGroupEntry *entries = calloc(2, sizeof(WGPUBindGroupEntry));

  entries[0].binding = textureBinding;
  entries[0].textureView = *c_view;
  entries[0].sampler = NULL;
  entries[0].buffer = NULL;
  entries[0].offset = 0;
  entries[0].size = 0;

  entries[1].binding = samplerBinding;
  entries[1].sampler = *c_sampler;
  entries[1].textureView = NULL;
  entries[1].buffer = NULL;
  entries[1].offset = 0;
  entries[1].size = 0;

  WGPUBindGroupDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "Texture+Sampler bind group";
  desc.layout = *c_layout;
  desc.entryCount = 2;
  desc.entries = entries;

  WGPUBindGroup *bg = calloc(1, sizeof(WGPUBindGroup));
  *bg = wgpuDeviceCreateBindGroup(c_device, &desc);
  free(entries);
  return lean_io_result_mk_ok(to_lean<BindGroup>(bg));
}

/- # Compute Pipeline Support -/

alloy c opaque_extern_type ComputePipeline => WGPUComputePipeline where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUComputePipeline\n");
    wgpuComputePipelineRelease(*ptr);
    free(ptr);

alloy c opaque_extern_type ComputePassEncoder => WGPUComputePassEncoder where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUComputePassEncoder\n");
    wgpuComputePassEncoderRelease(*ptr);
    free(ptr);

/-- Create a compute pipeline with an explicit layout. -/
alloy c extern
def Device.createComputePipeline (device : Device) (shaderModule : ShaderModule)
    (layout : PipelineLayout) (entryPoint : String := "main") : IO ComputePipeline := {
  WGPUDevice c_device = *of_lean<Device>(device);
  WGPUShaderModule *c_shader = of_lean<ShaderModule>(shaderModule);
  WGPUPipelineLayout *c_layout = of_lean<PipelineLayout>(layout);

  WGPUComputePipelineDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "Compute pipeline";
  desc.layout = *c_layout;
  desc.compute.module = *c_shader;
  desc.compute.entryPoint = lean_string_cstr(entryPoint);
  desc.compute.constantCount = 0;
  desc.compute.constants = NULL;

  WGPUComputePipeline *pipeline = calloc(1, sizeof(WGPUComputePipeline));
  *pipeline = wgpuDeviceCreateComputePipeline(c_device, &desc);
  return lean_io_result_mk_ok(to_lean<ComputePipeline>(pipeline));
}

/-- Begin a compute pass. -/
alloy c extern
def CommandEncoder.beginComputePass (encoder : CommandEncoder) : IO ComputePassEncoder := {
  WGPUCommandEncoder *c_encoder = of_lean<CommandEncoder>(encoder);

  WGPUComputePassDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "Compute pass";
  desc.timestampWrites = NULL;

  WGPUComputePassEncoder *pass = calloc(1, sizeof(WGPUComputePassEncoder));
  *pass = wgpuCommandEncoderBeginComputePass(*c_encoder, &desc);
  return lean_io_result_mk_ok(to_lean<ComputePassEncoder>(pass));
}

alloy c extern
def ComputePassEncoder.setPipeline (pass : ComputePassEncoder) (pipeline : ComputePipeline) : IO Unit := {
  WGPUComputePassEncoder *c_pass = of_lean<ComputePassEncoder>(pass);
  WGPUComputePipeline *c_pipeline = of_lean<ComputePipeline>(pipeline);
  wgpuComputePassEncoderSetPipeline(*c_pass, *c_pipeline);
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern
def ComputePassEncoder.setBindGroup (pass : ComputePassEncoder) (groupIndex : UInt32) (bg : BindGroup) : IO Unit := {
  WGPUComputePassEncoder *c_pass = of_lean<ComputePassEncoder>(pass);
  WGPUBindGroup *c_bg = of_lean<BindGroup>(bg);
  wgpuComputePassEncoderSetBindGroup(*c_pass, groupIndex, *c_bg, 0, NULL);
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern
def ComputePassEncoder.dispatchWorkgroups (pass : ComputePassEncoder) (x : UInt32) (y : UInt32 := 1) (z : UInt32 := 1) : IO Unit := {
  WGPUComputePassEncoder *c_pass = of_lean<ComputePassEncoder>(pass);
  wgpuComputePassEncoderDispatchWorkgroups(*c_pass, x, y, z);
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern
def ComputePassEncoder.end_ (pass : ComputePassEncoder) : IO Unit := {
  WGPUComputePassEncoder *c_pass = of_lean<ComputePassEncoder>(pass);
  wgpuComputePassEncoderEnd(*c_pass);
  return lean_io_result_mk_ok(lean_box(0));
}

/- # Storage Buffer Bind Group Layouts -/

/-- Create a bind group layout for a single storage buffer binding. -/
alloy c extern
def BindGroupLayout.mkStorage (device : Device) (binding : UInt32) (visibility : UInt32)
    (readOnly : Bool := false) (minBindingSize : UInt64 := 0) : IO BindGroupLayout := {
  WGPUDevice c_device = *of_lean<Device>(device);

  WGPUBindGroupLayoutEntry *entry = calloc(1, sizeof(WGPUBindGroupLayoutEntry));
  entry->binding = binding;
  entry->visibility = visibility;
  entry->buffer.type = readOnly ? WGPUBufferBindingType_ReadOnlyStorage : WGPUBufferBindingType_Storage;
  entry->buffer.hasDynamicOffset = false;
  entry->buffer.minBindingSize = minBindingSize;
  entry->sampler.type = WGPUSamplerBindingType_Undefined;
  entry->texture.sampleType = WGPUTextureSampleType_Undefined;
  entry->storageTexture.access = WGPUStorageTextureAccess_Undefined;

  WGPUBindGroupLayoutDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "Storage bind group layout";
  desc.entryCount = 1;
  desc.entries = entry;

  WGPUBindGroupLayout *layout = calloc(1, sizeof(WGPUBindGroupLayout));
  *layout = wgpuDeviceCreateBindGroupLayout(c_device, &desc);
  free(entry);
  return lean_io_result_mk_ok(to_lean<BindGroupLayout>(layout));
}

/-- Create a bind group layout with two storage buffer bindings (e.g., input + output). -/
alloy c extern
def BindGroupLayout.mk2Storage (device : Device)
    (binding0 : UInt32) (visibility0 : UInt32) (readOnly0 : Bool)
    (binding1 : UInt32) (visibility1 : UInt32) (readOnly1 : Bool)
    : IO BindGroupLayout := {
  WGPUDevice c_device = *of_lean<Device>(device);

  WGPUBindGroupLayoutEntry *entries = calloc(2, sizeof(WGPUBindGroupLayoutEntry));

  entries[0].binding = binding0;
  entries[0].visibility = visibility0;
  entries[0].buffer.type = readOnly0 ? WGPUBufferBindingType_ReadOnlyStorage : WGPUBufferBindingType_Storage;
  entries[0].buffer.hasDynamicOffset = false;
  entries[0].buffer.minBindingSize = 0;
  entries[0].sampler.type = WGPUSamplerBindingType_Undefined;
  entries[0].texture.sampleType = WGPUTextureSampleType_Undefined;
  entries[0].storageTexture.access = WGPUStorageTextureAccess_Undefined;

  entries[1].binding = binding1;
  entries[1].visibility = visibility1;
  entries[1].buffer.type = readOnly1 ? WGPUBufferBindingType_ReadOnlyStorage : WGPUBufferBindingType_Storage;
  entries[1].buffer.hasDynamicOffset = false;
  entries[1].buffer.minBindingSize = 0;
  entries[1].sampler.type = WGPUSamplerBindingType_Undefined;
  entries[1].texture.sampleType = WGPUTextureSampleType_Undefined;
  entries[1].storageTexture.access = WGPUStorageTextureAccess_Undefined;

  WGPUBindGroupLayoutDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "2-Storage bind group layout";
  desc.entryCount = 2;
  desc.entries = entries;

  WGPUBindGroupLayout *layout = calloc(1, sizeof(WGPUBindGroupLayout));
  *layout = wgpuDeviceCreateBindGroupLayout(c_device, &desc);
  free(entries);
  return lean_io_result_mk_ok(to_lean<BindGroupLayout>(layout));
}

/-- Create a bind group with two buffer bindings. -/
alloy c extern
def BindGroup.mk2Buffers (device : Device) (layout : BindGroupLayout)
    (binding0 : UInt32) (buffer0 : Buffer)
    (binding1 : UInt32) (buffer1 : Buffer)
    : IO BindGroup := {
  WGPUDevice c_device = *of_lean<Device>(device);
  WGPUBindGroupLayout *c_layout = of_lean<BindGroupLayout>(layout);
  WGPUBuffer *c_buf0 = of_lean<Buffer>(buffer0);
  WGPUBuffer *c_buf1 = of_lean<Buffer>(buffer1);

  WGPUBindGroupEntry *entries = calloc(2, sizeof(WGPUBindGroupEntry));

  entries[0].binding = binding0;
  entries[0].buffer = *c_buf0;
  entries[0].offset = 0;
  entries[0].size = wgpuBufferGetSize(*c_buf0);
  entries[0].sampler = NULL;
  entries[0].textureView = NULL;

  entries[1].binding = binding1;
  entries[1].buffer = *c_buf1;
  entries[1].offset = 0;
  entries[1].size = wgpuBufferGetSize(*c_buf1);
  entries[1].sampler = NULL;
  entries[1].textureView = NULL;

  WGPUBindGroupDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "2-Buffer bind group";
  desc.layout = *c_layout;
  desc.entryCount = 2;
  desc.entries = entries;

  WGPUBindGroup *bg = calloc(1, sizeof(WGPUBindGroup));
  *bg = wgpuDeviceCreateBindGroup(c_device, &desc);
  free(entries);
  return lean_io_result_mk_ok(to_lean<BindGroup>(bg));
}

/- # Buffer Copy & Mapping -/

/-- Copy data between buffers. -/
alloy c extern
def CommandEncoder.copyBufferToBuffer (encoder : CommandEncoder)
    (src : Buffer) (srcOffset : UInt64)
    (dst : Buffer) (dstOffset : UInt64) (size : UInt64) : IO Unit := {
  WGPUCommandEncoder *c_encoder = of_lean<CommandEncoder>(encoder);
  WGPUBuffer *c_src = of_lean<Buffer>(src);
  WGPUBuffer *c_dst = of_lean<Buffer>(dst);
  wgpuCommandEncoderCopyBufferToBuffer(*c_encoder, *c_src, srcOffset, *c_dst, dstOffset, size);
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c section
  void onBufferMappedCallback(WGPUBufferMapAsyncStatus status, void *userdata) {
    wgpu_callback_data *data = (wgpu_callback_data*)userdata;
    if (status == WGPUBufferMapAsyncStatus_Success) {
      data->result = lean_io_result_mk_ok(lean_box(0));
    } else {
      fprintf(stderr, "Buffer map failed with status: %d\n", status);
      data->result = lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string("Buffer mapping failed")));
    }
  }
end

/-- Map a buffer for reading. Blocks until mapping is complete by polling the device. -/
alloy c extern
def Buffer.mapRead (buffer : Buffer) (device : Device) (offset : UInt64 := 0) (size : UInt64 := 0) : IO Unit := {
  WGPUBuffer *c_buffer = of_lean<Buffer>(buffer);
  WGPUDevice *c_device = of_lean<Device>(device);
  uint64_t mapSize = size;
  if (mapSize == 0) {
    mapSize = wgpuBufferGetSize(*c_buffer) - offset;
  }
  wgpu_callback_data cb_data = {0};
  wgpuBufferMapAsync(*c_buffer, WGPUMapMode_Read, offset, mapSize, onBufferMappedCallback, &cb_data);
  -- Poll the device until the callback fires
  while (cb_data.result == NULL) {
    wgpuDevicePoll(*c_device, true, NULL);
  }
  return cb_data.result;
}

/-- Get the mapped range of a buffer as a ByteArray (read-only copy). -/
alloy c extern
def Buffer.getMappedRange (buffer : Buffer) (offset : UInt64 := 0) (size : UInt64 := 0) : IO ByteArray := {
  WGPUBuffer *c_buffer = of_lean<Buffer>(buffer);
  uint64_t mapSize = size;
  if (mapSize == 0) {
    mapSize = wgpuBufferGetSize(*c_buffer) - offset;
  }
  const void *ptr = wgpuBufferGetConstMappedRange(*c_buffer, offset, mapSize);
  if (ptr == NULL) {
    return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string("getMappedRange returned NULL")));
  }
  lean_object *ba = lean_alloc_sarray(1, mapSize, mapSize);
  memcpy(lean_sarray_cptr(ba), ptr, mapSize);
  return lean_io_result_mk_ok(ba);
}

/-- Unmap a previously mapped buffer. -/
alloy c extern
def Buffer.unmap (buffer : Buffer) : IO Unit := {
  WGPUBuffer *c_buffer = of_lean<Buffer>(buffer);
  wgpuBufferUnmap(*c_buffer);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Poll the device and wait until all pending work is complete. -/
alloy c extern
def Device.pollWait (device : Device) : IO Unit := {
  wgpuDevicePoll(*of_lean<Device>(device), true, NULL);
  return lean_io_result_mk_ok(lean_box(0));
}

/- # Primitive Topology & Cull Mode -/

alloy c enum PrimitiveTopology => WGPUPrimitiveTopology
| PointList => WGPUPrimitiveTopology_PointList
| LineList => WGPUPrimitiveTopology_LineList
| LineStrip => WGPUPrimitiveTopology_LineStrip
| TriangleList => WGPUPrimitiveTopology_TriangleList
| TriangleStrip => WGPUPrimitiveTopology_TriangleStrip
| Force32 => WGPUPrimitiveTopology_Force32
deriving Inhabited, Repr, BEq

alloy c enum CullMode => WGPUCullMode
| None => WGPUCullMode_None
| Front => WGPUCullMode_Front
| Back => WGPUCullMode_Back
| Force32 => WGPUCullMode_Force32
deriving Inhabited, Repr, BEq

alloy c enum FrontFace => WGPUFrontFace
| CCW => WGPUFrontFace_CCW
| CW => WGPUFrontFace_CW
| Force32 => WGPUFrontFace_Force32
deriving Inhabited, Repr, BEq

alloy c enum CompareFunction => WGPUCompareFunction
| Undefined => WGPUCompareFunction_Undefined
| Never => WGPUCompareFunction_Never
| Less => WGPUCompareFunction_Less
| LessEqual => WGPUCompareFunction_LessEqual
| Greater => WGPUCompareFunction_Greater
| GreaterEqual => WGPUCompareFunction_GreaterEqual
| Equal => WGPUCompareFunction_Equal
| NotEqual => WGPUCompareFunction_NotEqual
| Always => WGPUCompareFunction_Always
| Force32 => WGPUCompareFunction_Force32
deriving Inhabited, Repr, BEq

/- # Depth / Stencil Support -/

/-- Create a depth texture for use as a depth attachment. -/
alloy c extern
def Device.createDepthTexture (device : Device) (width height : UInt32)
    (format : TextureFormat := TextureFormat.Depth24Plus)
    : IO Texture := {
  WGPUDevice c_device = *of_lean<Device>(device);

  WGPUTextureDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "Depth texture";
  desc.usage = WGPUTextureUsage_RenderAttachment;
  desc.dimension = WGPUTextureDimension_2D;
  desc.size.width = width;
  desc.size.height = height;
  desc.size.depthOrArrayLayers = 1;
  desc.format = of_lean<TextureFormat>(format);
  desc.mipLevelCount = 1;
  desc.sampleCount = 1;
  desc.viewFormatCount = 0;
  desc.viewFormats = NULL;

  WGPUTexture *tex = calloc(1, sizeof(WGPUTexture));
  *tex = wgpuDeviceCreateTexture(c_device, &desc);
  return lean_io_result_mk_ok(to_lean<Texture>(tex));
}

/-- Create a depth TextureView. -/
alloy c extern
def Texture.createDepthView (texture : Texture) (format : TextureFormat := TextureFormat.Depth24Plus) : IO TextureView := {
  WGPUTexture *c_tex = of_lean<Texture>(texture);

  WGPUTextureViewDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "Depth texture view";
  desc.format = of_lean<TextureFormat>(format);
  desc.dimension = WGPUTextureViewDimension_2D;
  desc.baseMipLevel = 0;
  desc.mipLevelCount = 1;
  desc.baseArrayLayer = 0;
  desc.arrayLayerCount = 1;
  desc.aspect = WGPUTextureAspect_DepthOnly;

  WGPUTextureView *view = calloc(1, sizeof(WGPUTextureView));
  *view = wgpuTextureCreateView(*c_tex, &desc);
  return lean_io_result_mk_ok(to_lean<TextureView>(view));
}

/-- Begin a render pass with both color and depth attachments. -/
alloy c extern
def RenderPassEncoder.mkWithDepth (encoder : CommandEncoder)
    (colorView : TextureView) (color : Color)
    (depthView : TextureView)
    : IO RenderPassEncoder := {
  WGPUCommandEncoder *c_encoder = of_lean<CommandEncoder>(encoder);

  WGPURenderPassColorAttachment *colorAttachment = calloc(1, sizeof(WGPURenderPassColorAttachment));
  WGPUTextureView *c_colorView = of_lean<TextureView>(colorView);
  colorAttachment->view = *c_colorView;
  colorAttachment->resolveTarget = NULL;
  colorAttachment->loadOp = WGPULoadOp_Clear;
  colorAttachment->storeOp = WGPUStoreOp_Store;
  WGPUColor *c_color = of_lean<Color>(color);
  colorAttachment->clearValue = *c_color;

  WGPURenderPassDepthStencilAttachment *depthAttachment = calloc(1, sizeof(WGPURenderPassDepthStencilAttachment));
  WGPUTextureView *c_depthView = of_lean<TextureView>(depthView);
  depthAttachment->view = *c_depthView;
  depthAttachment->depthLoadOp = WGPULoadOp_Clear;
  depthAttachment->depthStoreOp = WGPUStoreOp_Store;
  depthAttachment->depthClearValue = 1.0f;
  depthAttachment->depthReadOnly = false;
  depthAttachment->stencilLoadOp = WGPULoadOp_Undefined;
  depthAttachment->stencilStoreOp = WGPUStoreOp_Undefined;
  depthAttachment->stencilClearValue = 0;
  depthAttachment->stencilReadOnly = true;

  WGPURenderPassDescriptor *renderPassDesc = calloc(1, sizeof(WGPURenderPassDescriptor));
  renderPassDesc->nextInChain = NULL;
  renderPassDesc->colorAttachmentCount = 1;
  renderPassDesc->colorAttachments = colorAttachment;
  renderPassDesc->depthStencilAttachment = depthAttachment;
  renderPassDesc->timestampWrites = NULL;

  WGPURenderPassEncoder *renderPass = calloc(1, sizeof(WGPURenderPassEncoder));
  *renderPass = wgpuCommandEncoderBeginRenderPass(*c_encoder, renderPassDesc);

  free(colorAttachment);
  free(depthAttachment);
  free(renderPassDesc);

  return lean_io_result_mk_ok(to_lean<RenderPassEncoder>(renderPass));
}

/-- Set the stencil reference value. -/
alloy c extern
def RenderPassEncoder.setStencilReference (r : RenderPassEncoder) (reference : UInt32) : IO Unit := {
  WGPURenderPassEncoder *renderPass = of_lean<RenderPassEncoder>(r);
  wgpuRenderPassEncoderSetStencilReference(*renderPass, reference);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Create a render pipeline descriptor with vertex buffers, depth test, and configurable primitive state. -/
alloy c extern
def RenderPipelineDescriptor.mkFull
    (shaderModule : ShaderModule)
    (fState : FragmentState)
    (vertexEntryPoint : String := "vs_main")
    (strides : @& Array UInt64)
    (stepModes : @& Array UInt32)
    (attrFormats : @& Array UInt32)
    (attrOffsets : @& Array UInt64)
    (attrShaderLocations : @& Array UInt32)
    (attrBufferIndices : @& Array UInt32)
    (bufferCount : UInt32)
    (topology : PrimitiveTopology := PrimitiveTopology.TriangleList)
    (cullMode : CullMode := CullMode.None)
    (frontFace : FrontFace := FrontFace.CCW)
    (enableDepth : Bool := false)
    (depthFormat : TextureFormat := TextureFormat.Depth24Plus)
    (depthCompare : CompareFunction := CompareFunction.Less)
    (depthWriteEnabled : Bool := true)
    : IO RenderPipelineDescriptor := {
  WGPUShaderModule *c_shaderModule = of_lean<ShaderModule>(shaderModule);
  WGPUFragmentState *fragmentState = of_lean<FragmentState>(fState);

  uint32_t nBuffers = bufferCount;
  size_t nAttrs = lean_array_size(attrFormats);

  WGPUVertexBufferLayout *bufferLayouts = calloc(nBuffers, sizeof(WGPUVertexBufferLayout));
  for (uint32_t i = 0; i < nBuffers; i++) {
    bufferLayouts[i].arrayStride = lean_unbox_uint64(lean_array_uget(strides, i));
    bufferLayouts[i].stepMode = (WGPUVertexStepMode)lean_unbox(lean_array_uget(stepModes, i));
    bufferLayouts[i].attributeCount = 0;
    bufferLayouts[i].attributes = NULL;
  }
  for (size_t i = 0; i < nAttrs; i++) {
    uint32_t bufIdx = lean_unbox(lean_array_uget(attrBufferIndices, i));
    bufferLayouts[bufIdx].attributeCount++;
  }
  WGPUVertexAttribute **attrArrays = calloc(nBuffers, sizeof(WGPUVertexAttribute*));
  uint32_t *attrCounters = calloc(nBuffers, sizeof(uint32_t));
  for (uint32_t i = 0; i < nBuffers; i++) {
    attrArrays[i] = calloc(bufferLayouts[i].attributeCount, sizeof(WGPUVertexAttribute));
    bufferLayouts[i].attributes = attrArrays[i];
  }
  for (size_t i = 0; i < nAttrs; i++) {
    uint32_t bufIdx = lean_unbox(lean_array_uget(attrBufferIndices, i));
    uint32_t ai = attrCounters[bufIdx]++;
    attrArrays[bufIdx][ai].format = (WGPUVertexFormat)lean_unbox(lean_array_uget(attrFormats, i));
    attrArrays[bufIdx][ai].offset = lean_unbox_uint64(lean_array_uget(attrOffsets, i));
    attrArrays[bufIdx][ai].shaderLocation = lean_unbox(lean_array_uget(attrShaderLocations, i));
  }
  free(attrCounters);
  free(attrArrays);

  WGPURenderPipelineDescriptor *pipelineDesc = calloc(1, sizeof(WGPURenderPipelineDescriptor));
  pipelineDesc->nextInChain = NULL;
  pipelineDesc->vertex.bufferCount = nBuffers;
  pipelineDesc->vertex.buffers = bufferLayouts;
  pipelineDesc->vertex.module = *c_shaderModule;
  pipelineDesc->vertex.entryPoint = lean_string_cstr(vertexEntryPoint);
  pipelineDesc->vertex.constantCount = 0;
  pipelineDesc->vertex.constants = NULL;

  pipelineDesc->primitive.topology = of_lean<PrimitiveTopology>(topology);
  pipelineDesc->primitive.stripIndexFormat = WGPUIndexFormat_Undefined;
  pipelineDesc->primitive.frontFace = of_lean<FrontFace>(frontFace);
  pipelineDesc->primitive.cullMode = of_lean<CullMode>(cullMode);

  if (enableDepth) {
    WGPUDepthStencilState *depthState = calloc(1, sizeof(WGPUDepthStencilState));
    depthState->nextInChain = NULL;
    depthState->format = of_lean<TextureFormat>(depthFormat);
    depthState->depthWriteEnabled = depthWriteEnabled;
    depthState->depthCompare = of_lean<CompareFunction>(depthCompare);
    depthState->stencilFront.compare = WGPUCompareFunction_Always;
    depthState->stencilFront.failOp = WGPUStencilOperation_Keep;
    depthState->stencilFront.depthFailOp = WGPUStencilOperation_Keep;
    depthState->stencilFront.passOp = WGPUStencilOperation_Keep;
    depthState->stencilBack = depthState->stencilFront;
    depthState->stencilReadMask = 0xFFFFFFFF;
    depthState->stencilWriteMask = 0xFFFFFFFF;
    depthState->depthBias = 0;
    depthState->depthBiasSlopeScale = 0.0f;
    depthState->depthBiasClamp = 0.0f;
    pipelineDesc->depthStencil = depthState;
  } else {
    pipelineDesc->depthStencil = NULL;
  }

  pipelineDesc->fragment = fragmentState;
  pipelineDesc->multisample.count = 1;
  pipelineDesc->multisample.mask = 0xFFFFFFFF;
  pipelineDesc->multisample.alphaToCoverageEnabled = false;
  pipelineDesc->layout = NULL;

  return lean_io_result_mk_ok(to_lean<RenderPipelineDescriptor>(pipelineDesc));
}

/-- High-level helper: build a pipeline descriptor with depth, topology, and cull mode from Lean data. -/
def RenderPipelineDescriptor.mkFullLayouts
    (shaderModule : ShaderModule)
    (fState : FragmentState)
    (layouts : Array VertexBufferLayoutDesc)
    (vertexEntryPoint : String := "vs_main")
    (topology : PrimitiveTopology := PrimitiveTopology.TriangleList)
    (cullMode : CullMode := CullMode.None)
    (frontFace : FrontFace := FrontFace.CCW)
    (enableDepth : Bool := false)
    (depthFormat : TextureFormat := TextureFormat.Depth24Plus)
    (depthCompare : CompareFunction := CompareFunction.Less)
    (depthWriteEnabled : Bool := true)
    : IO RenderPipelineDescriptor := do
  let mut strides : Array UInt64 := #[]
  let mut stepModes : Array UInt32 := #[]
  let mut attrFormats : Array UInt32 := #[]
  let mut attrOffsets : Array UInt64 := #[]
  let mut attrShaderLocations : Array UInt32 := #[]
  let mut attrBufferIndices : Array UInt32 := #[]
  for h : i in [:layouts.size] do
    let layout := layouts[i]
    strides := strides.push layout.arrayStride
    stepModes := stepModes.push (match layout.stepMode with
      | .Vertex => 0 | .Instance => 1 | .VertexBufferNotUsed => 2 | .Force32 => 3)
    for attr in layout.attributes do
      attrFormats := attrFormats.push (match attr.format with
        | .Undefined => 0 | .Uint8x2 => 1 | .Uint8x4 => 2 | .Sint8x2 => 3 | .Sint8x4 => 4
        | .Unorm8x2 => 5 | .Unorm8x4 => 6 | .Snorm8x2 => 7 | .Snorm8x4 => 8
        | .Uint16x2 => 9 | .Uint16x4 => 10 | .Sint16x2 => 11 | .Sint16x4 => 12
        | .Unorm16x2 => 13 | .Unorm16x4 => 14 | .Snorm16x2 => 15 | .Snorm16x4 => 16
        | .Float16x2 => 17 | .Float16x4 => 18
        | .Float32 => 19 | .Float32x2 => 20 | .Float32x3 => 21 | .Float32x4 => 22
        | .Uint32 => 23 | .Uint32x2 => 24 | .Uint32x3 => 25 | .Uint32x4 => 26
        | .Sint32 => 27 | .Sint32x2 => 28 | .Sint32x3 => 29 | .Sint32x4 => 30
        | .Force32 => 31)
      attrOffsets := attrOffsets.push attr.offset
      attrShaderLocations := attrShaderLocations.push attr.shaderLocation
      attrBufferIndices := attrBufferIndices.push i.toUInt32
  RenderPipelineDescriptor.mkFull shaderModule fState vertexEntryPoint
    strides stepModes attrFormats attrOffsets attrShaderLocations attrBufferIndices
    layouts.size.toUInt32 topology cullMode frontFace enableDepth depthFormat depthCompare depthWriteEnabled

/- # Surface Reconfiguration Helper -/

alloy c extern
def SurfaceConfiguration.mkWith (width height : UInt32) (device : Device) (textureFormat : TextureFormat)
    (presentMode : UInt32 := 2) -- 2 = Fifo
    : IO SurfaceConfiguration := {
  WGPUDevice *c_device = of_lean<Device>(device);
  WGPUTextureFormat surfaceFormat = of_lean<TextureFormat>(textureFormat);

  WGPUSurfaceConfiguration *config = calloc(1, sizeof(WGPUSurfaceConfiguration));
  config->nextInChain = NULL;
  config->width = width;
  config->height = height;
  config->usage = WGPUTextureUsage_RenderAttachment;
  config->format = surfaceFormat;
  config->viewFormatCount = 0;
  config->viewFormats = NULL;
  config->device = *c_device;
  config->presentMode = (WGPUPresentMode)presentMode;
  config->alphaMode = WGPUCompositeAlphaMode_Auto;

  return lean_io_result_mk_ok(to_lean<SurfaceConfiguration>(config));
}

/- # Debug Groups -/

/-- Push a debug group label on a command encoder. -/
alloy c extern
def CommandEncoder.pushDebugGroup (encoder : CommandEncoder) (label : String) : IO Unit := {
  WGPUCommandEncoder *c_encoder = of_lean<CommandEncoder>(encoder);
  wgpuCommandEncoderPushDebugGroup(*c_encoder, lean_string_cstr(label));
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Pop a debug group label from a command encoder. -/
alloy c extern
def CommandEncoder.popDebugGroup (encoder : CommandEncoder) : IO Unit := {
  WGPUCommandEncoder *c_encoder = of_lean<CommandEncoder>(encoder);
  wgpuCommandEncoderPopDebugGroup(*c_encoder);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Push a debug group label on a render pass encoder. -/
alloy c extern
def RenderPassEncoder.pushDebugGroup (r : RenderPassEncoder) (label : String) : IO Unit := {
  WGPURenderPassEncoder *renderPass = of_lean<RenderPassEncoder>(r);
  wgpuRenderPassEncoderPushDebugGroup(*renderPass, lean_string_cstr(label));
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Pop a debug group label from a render pass encoder. -/
alloy c extern
def RenderPassEncoder.popDebugGroup (r : RenderPassEncoder) : IO Unit := {
  WGPURenderPassEncoder *renderPass = of_lean<RenderPassEncoder>(r);
  wgpuRenderPassEncoderPopDebugGroup(*renderPass);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Insert a debug marker on a render pass encoder. -/
alloy c extern
def RenderPassEncoder.insertDebugMarker (r : RenderPassEncoder) (label : String) : IO Unit := {
  WGPURenderPassEncoder *renderPass = of_lean<RenderPassEncoder>(r);
  wgpuRenderPassEncoderInsertDebugMarker(*renderPass, lean_string_cstr(label));
  return lean_io_result_mk_ok(lean_box(0));
}

/- # Render Bundle Support -/

alloy c opaque_extern_type RenderBundle => WGPURenderBundle where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPURenderBundle\n");
    wgpuRenderBundleRelease(*ptr);
    free(ptr);

alloy c opaque_extern_type RenderBundleEncoder => WGPURenderBundleEncoder where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPURenderBundleEncoder\n");
    wgpuRenderBundleEncoderRelease(*ptr);
    free(ptr);

/-- Create a render bundle encoder. colorFormats is an array of TextureFormat values
    (passed as UInt32 since alloy c enum maps to UInt32). -/
alloy c extern
def Device.createRenderBundleEncoder (device : Device)
    (colorFormats : @& Array UInt32)
    (depthStencilFormat : TextureFormat := TextureFormat.Undefined)
    (sampleCount : UInt32 := 1)
    (depthReadOnly : Bool := false)
    (stencilReadOnly : Bool := false)
    : IO RenderBundleEncoder := {
  WGPUDevice c_device = *of_lean<Device>(device);

  size_t nFormats = lean_array_size(colorFormats);
  WGPUTextureFormat *formats = calloc(nFormats, sizeof(WGPUTextureFormat));
  for (size_t i = 0; i < nFormats; i++) {
    formats[i] = (WGPUTextureFormat)lean_unbox(lean_array_uget(colorFormats, i));
  }

  WGPURenderBundleEncoderDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "Render bundle encoder";
  desc.colorFormatCount = nFormats;
  desc.colorFormats = formats;
  desc.depthStencilFormat = of_lean<TextureFormat>(depthStencilFormat);
  desc.sampleCount = sampleCount;
  desc.depthReadOnly = depthReadOnly;
  desc.stencilReadOnly = stencilReadOnly;

  WGPURenderBundleEncoder *enc = calloc(1, sizeof(WGPURenderBundleEncoder));
  *enc = wgpuDeviceCreateRenderBundleEncoder(c_device, &desc);
  free(formats);
  return lean_io_result_mk_ok(to_lean<RenderBundleEncoder>(enc));
}

alloy c extern
def RenderBundleEncoder.setPipeline (enc : RenderBundleEncoder) (pipeline : RenderPipeline) : IO Unit := {
  WGPURenderBundleEncoder *c_enc = of_lean<RenderBundleEncoder>(enc);
  WGPURenderPipeline *c_pipeline = of_lean<RenderPipeline>(pipeline);
  wgpuRenderBundleEncoderSetPipeline(*c_enc, *c_pipeline);
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern
def RenderBundleEncoder.setVertexBuffer (enc : RenderBundleEncoder) (slot : UInt32) (buffer : Buffer)
    (offset : UInt64 := 0) : IO Unit := {
  WGPURenderBundleEncoder *c_enc = of_lean<RenderBundleEncoder>(enc);
  WGPUBuffer *c_buffer = of_lean<Buffer>(buffer);
  uint64_t size = wgpuBufferGetSize(*c_buffer) - offset;
  wgpuRenderBundleEncoderSetVertexBuffer(*c_enc, slot, *c_buffer, offset, size);
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern
def RenderBundleEncoder.setIndexBuffer (enc : RenderBundleEncoder) (buffer : Buffer) (format : IndexFormat)
    (offset : UInt64 := 0) : IO Unit := {
  WGPURenderBundleEncoder *c_enc = of_lean<RenderBundleEncoder>(enc);
  WGPUBuffer *c_buffer = of_lean<Buffer>(buffer);
  uint64_t size = wgpuBufferGetSize(*c_buffer) - offset;
  wgpuRenderBundleEncoderSetIndexBuffer(*c_enc, *c_buffer, of_lean<IndexFormat>(format), offset, size);
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern
def RenderBundleEncoder.setBindGroup (enc : RenderBundleEncoder) (groupIndex : UInt32) (bg : BindGroup) : IO Unit := {
  WGPURenderBundleEncoder *c_enc = of_lean<RenderBundleEncoder>(enc);
  WGPUBindGroup *c_bg = of_lean<BindGroup>(bg);
  wgpuRenderBundleEncoderSetBindGroup(*c_enc, groupIndex, *c_bg, 0, NULL);
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern
def RenderBundleEncoder.draw (enc : RenderBundleEncoder)
    (vertexCount instanceCount firstVertex firstInstance : UInt32) : IO Unit := {
  WGPURenderBundleEncoder *c_enc = of_lean<RenderBundleEncoder>(enc);
  wgpuRenderBundleEncoderDraw(*c_enc, vertexCount, instanceCount, firstVertex, firstInstance);
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern
def RenderBundleEncoder.drawIndexed (enc : RenderBundleEncoder)
    (indexCount instanceCount firstIndex : UInt32)
    (baseVertex : Int32 := 0) (firstInstance : UInt32 := 0) : IO Unit := {
  WGPURenderBundleEncoder *c_enc = of_lean<RenderBundleEncoder>(enc);
  wgpuRenderBundleEncoderDrawIndexed(*c_enc, indexCount, instanceCount, firstIndex, baseVertex, firstInstance);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Finish recording the render bundle. -/
alloy c extern
def RenderBundleEncoder.finish (enc : RenderBundleEncoder) : IO RenderBundle := {
  WGPURenderBundleEncoder *c_enc = of_lean<RenderBundleEncoder>(enc);
  WGPURenderBundleDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "Render bundle";
  WGPURenderBundle *bundle = calloc(1, sizeof(WGPURenderBundle));
  *bundle = wgpuRenderBundleEncoderFinish(*c_enc, &desc);
  return lean_io_result_mk_ok(to_lean<RenderBundle>(bundle));
}

/-- Execute render bundles on a render pass encoder. -/
alloy c extern
def RenderPassEncoder.executeBundles (r : RenderPassEncoder) (bundles : @& Array RenderBundle) : IO Unit := {
  WGPURenderPassEncoder *renderPass = of_lean<RenderPassEncoder>(r);
  size_t n = lean_array_size(bundles);
  WGPURenderBundle *c_bundles = calloc(n, sizeof(WGPURenderBundle));
  for (size_t i = 0; i < n; i++) {
    WGPURenderBundle *b = of_lean<RenderBundle>(lean_array_uget(bundles, i));
    c_bundles[i] = *b;
  }
  wgpuRenderPassEncoderExecuteBundles(*renderPass, n, c_bundles);
  free(c_bundles);
  return lean_io_result_mk_ok(lean_box(0));
}

/- # Multiple Color Targets (MRT) -/

/-- Create a FragmentState with multiple color targets. -/
alloy c extern
def FragmentState.mkMulti (shaderModule : ShaderModule)
    (colorTargets : @& Array ColorTargetState)
    (entryPoint : String := "fs_main")
    : IO FragmentState := {
  WGPUShaderModule *c_shaderModule = of_lean<ShaderModule>(shaderModule);
  size_t n = lean_array_size(colorTargets);
  WGPUColorTargetState *targets = calloc(n, sizeof(WGPUColorTargetState));
  for (size_t i = 0; i < n; i++) {
    WGPUColorTargetState *ct = of_lean<ColorTargetState>(lean_array_uget(colorTargets, i));
    targets[i] = *ct;
  }
  WGPUFragmentState *fragmentState = calloc(1, sizeof(WGPUFragmentState));
  fragmentState->module = *c_shaderModule;
  fragmentState->entryPoint = lean_string_cstr(entryPoint);
  fragmentState->constantCount = 0;
  fragmentState->constants = NULL;
  fragmentState->targetCount = n;
  fragmentState->targets = targets;
  return lean_io_result_mk_ok(to_lean<FragmentState>(fragmentState));
}

/-- Begin a render pass with multiple color attachments. -/
alloy c extern
def RenderPassEncoder.mkMultiColor (encoder : CommandEncoder)
    (views : @& Array TextureView) (colors : @& Array Color)
    : IO RenderPassEncoder := {
  WGPUCommandEncoder *c_encoder = of_lean<CommandEncoder>(encoder);
  size_t n = lean_array_size(views);

  WGPURenderPassColorAttachment *attachments = calloc(n, sizeof(WGPURenderPassColorAttachment));
  for (size_t i = 0; i < n; i++) {
    WGPUTextureView *v = of_lean<TextureView>(lean_array_uget(views, i));
    WGPUColor *c = of_lean<Color>(lean_array_uget(colors, i));
    attachments[i].view = *v;
    attachments[i].resolveTarget = NULL;
    attachments[i].loadOp = WGPULoadOp_Clear;
    attachments[i].storeOp = WGPUStoreOp_Store;
    attachments[i].clearValue = *c;
  }

  WGPURenderPassDescriptor *desc = calloc(1, sizeof(WGPURenderPassDescriptor));
  desc->nextInChain = NULL;
  desc->colorAttachmentCount = n;
  desc->colorAttachments = attachments;
  desc->depthStencilAttachment = NULL;
  desc->timestampWrites = NULL;

  WGPURenderPassEncoder *renderPass = calloc(1, sizeof(WGPURenderPassEncoder));
  *renderPass = wgpuCommandEncoderBeginRenderPass(*c_encoder, desc);

  free(attachments);
  free(desc);

  return lean_io_result_mk_ok(to_lean<RenderPassEncoder>(renderPass));
}

/- # Indirect Drawing -/

/-- Draw indirect — reads draw parameters from a GPU buffer. -/
alloy c extern
def RenderPassEncoder.drawIndirect (r : RenderPassEncoder) (indirectBuffer : Buffer) (indirectOffset : UInt64 := 0) : IO Unit := {
  WGPURenderPassEncoder *renderPass = of_lean<RenderPassEncoder>(r);
  WGPUBuffer *c_buffer = of_lean<Buffer>(indirectBuffer);
  wgpuRenderPassEncoderDrawIndirect(*renderPass, *c_buffer, indirectOffset);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Draw indexed indirect — reads indexed draw parameters from a GPU buffer. -/
alloy c extern
def RenderPassEncoder.drawIndexedIndirect (r : RenderPassEncoder) (indirectBuffer : Buffer) (indirectOffset : UInt64 := 0) : IO Unit := {
  WGPURenderPassEncoder *renderPass = of_lean<RenderPassEncoder>(r);
  WGPUBuffer *c_buffer = of_lean<Buffer>(indirectBuffer);
  wgpuRenderPassEncoderDrawIndexedIndirect(*renderPass, *c_buffer, indirectOffset);
  return lean_io_result_mk_ok(lean_box(0));
}

/- # Texture Copy Operations -/

/-- Copy a texture to a buffer (useful for readback). -/
alloy c extern
def CommandEncoder.copyTextureToBuffer (encoder : CommandEncoder)
    (texture : Texture) (buffer : Buffer)
    (width height : UInt32) (bytesPerRow : UInt32)
    (texMipLevel : UInt32 := 0)
    : IO Unit := {
  WGPUCommandEncoder *c_encoder = of_lean<CommandEncoder>(encoder);
  WGPUTexture *c_tex = of_lean<Texture>(texture);
  WGPUBuffer *c_buf = of_lean<Buffer>(buffer);

  WGPUImageCopyTexture src = {};
  src.texture = *c_tex;
  src.mipLevel = texMipLevel;
  src.origin = (WGPUOrigin3D){0, 0, 0};
  src.aspect = WGPUTextureAspect_All;

  WGPUImageCopyBuffer dst = {};
  dst.nextInChain = NULL;
  dst.buffer = *c_buf;
  dst.layout.offset = 0;
  dst.layout.bytesPerRow = bytesPerRow;
  dst.layout.rowsPerImage = height;

  WGPUExtent3D extent = {width, height, 1};
  wgpuCommandEncoderCopyTextureToBuffer(*c_encoder, &src, &dst, &extent);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Copy a texture to another texture. -/
alloy c extern
def CommandEncoder.copyTextureToTexture (encoder : CommandEncoder)
    (srcTexture : Texture) (dstTexture : Texture)
    (width height : UInt32)
    (srcMipLevel : UInt32 := 0) (dstMipLevel : UInt32 := 0)
    : IO Unit := {
  WGPUCommandEncoder *c_encoder = of_lean<CommandEncoder>(encoder);
  WGPUTexture *c_src = of_lean<Texture>(srcTexture);
  WGPUTexture *c_dst = of_lean<Texture>(dstTexture);

  WGPUImageCopyTexture src = {};
  src.texture = *c_src;
  src.mipLevel = srcMipLevel;
  src.origin = (WGPUOrigin3D){0, 0, 0};
  src.aspect = WGPUTextureAspect_All;

  WGPUImageCopyTexture dst = {};
  dst.texture = *c_dst;
  dst.mipLevel = dstMipLevel;
  dst.origin = (WGPUOrigin3D){0, 0, 0};
  dst.aspect = WGPUTextureAspect_All;

  WGPUExtent3D extent = {width, height, 1};
  wgpuCommandEncoderCopyTextureToTexture(*c_encoder, &src, &dst, &extent);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Clear a GPU buffer (set to zero). -/
alloy c extern
def CommandEncoder.clearBuffer (encoder : CommandEncoder) (buffer : Buffer)
    (offset : UInt64 := 0) (size : UInt64 := 0) : IO Unit := {
  WGPUCommandEncoder *c_encoder = of_lean<CommandEncoder>(encoder);
  WGPUBuffer *c_buffer = of_lean<Buffer>(buffer);
  uint64_t clearSize = size;
  if (clearSize == 0) clearSize = wgpuBufferGetSize(*c_buffer) - offset;
  wgpuCommandEncoderClearBuffer(*c_encoder, *c_buffer, offset, clearSize);
  return lean_io_result_mk_ok(lean_box(0));
}

/- # Texture Introspection -/

/-- Get the width of a texture. -/
alloy c extern
def Texture.getWidth (texture : Texture) : IO UInt32 := {
  WGPUTexture *c_tex = of_lean<Texture>(texture);
  return lean_io_result_mk_ok(lean_box(wgpuTextureGetWidth(*c_tex)));
}

/-- Get the height of a texture. -/
alloy c extern
def Texture.getHeight (texture : Texture) : IO UInt32 := {
  WGPUTexture *c_tex = of_lean<Texture>(texture);
  return lean_io_result_mk_ok(lean_box(wgpuTextureGetHeight(*c_tex)));
}

/-- Get the format of a texture (returned as TextureFormat). -/
alloy c extern
def Texture.getFormat (texture : Texture) : IO TextureFormat := {
  WGPUTexture *c_tex = of_lean<Texture>(texture);
  WGPUTextureFormat fmt = wgpuTextureGetFormat(*c_tex);
  return lean_io_result_mk_ok(lean_box(fmt));
}

/-- Get the mip level count of a texture. -/
alloy c extern
def Texture.getMipLevelCount (texture : Texture) : IO UInt32 := {
  WGPUTexture *c_tex = of_lean<Texture>(texture);
  return lean_io_result_mk_ok(lean_box(wgpuTextureGetMipLevelCount(*c_tex)));
}

/-- Get the sample count of a texture. -/
alloy c extern
def Texture.getSampleCount (texture : Texture) : IO UInt32 := {
  WGPUTexture *c_tex = of_lean<Texture>(texture);
  return lean_io_result_mk_ok(lean_box(wgpuTextureGetSampleCount(*c_tex)));
}

/- # Buffer Introspection -/

/-- Get the size of a buffer in bytes. -/
alloy c extern
def Buffer.getSize_ (buffer : Buffer) : IO UInt64 := {
  WGPUBuffer *c_buf = of_lean<Buffer>(buffer);
  uint64_t size = wgpuBufferGetSize(*c_buf);
  return lean_io_result_mk_ok(lean_box_uint64(size));
}

/-- Get the usage flags of a buffer. -/
alloy c extern
def Buffer.getUsage (buffer : Buffer) : IO BufferUsage := {
  WGPUBuffer *c_buf = of_lean<Buffer>(buffer);
  WGPUBufferUsageFlags usage = wgpuBufferGetUsage(*c_buf);
  return lean_io_result_mk_ok(lean_box((uint32_t)usage));
}

/-- Get the map state of a buffer (0=unmapped, 1=pending, 2=mapped). -/
alloy c extern
def Buffer.getMapState (buffer : Buffer) : IO UInt32 := {
  WGPUBuffer *c_buf = of_lean<Buffer>(buffer);
  return lean_io_result_mk_ok(lean_box((uint32_t)wgpuBufferGetMapState(*c_buf)));
}

/- # Blend Constant -/

/-- Set the blend constant color for the render pass. -/
alloy c extern
def RenderPassEncoder.setBlendConstant (r : RenderPassEncoder) (color : Color) : IO Unit := {
  WGPURenderPassEncoder *renderPass = of_lean<RenderPassEncoder>(r);
  WGPUColor *c_color = of_lean<Color>(color);
  wgpuRenderPassEncoderSetBlendConstant(*renderPass, c_color);
  return lean_io_result_mk_ok(lean_box(0));
}

/- # Indirect Compute Dispatch -/

/-- Dispatch compute workgroups using parameters from a GPU buffer. -/
alloy c extern
def ComputePassEncoder.dispatchWorkgroupsIndirect (enc : ComputePassEncoder)
    (indirectBuffer : Buffer) (indirectOffset : UInt64 := 0) : IO Unit := {
  WGPUComputePassEncoder *c_enc = of_lean<ComputePassEncoder>(enc);
  WGPUBuffer *c_buffer = of_lean<Buffer>(indirectBuffer);
  wgpuComputePassEncoderDispatchWorkgroupsIndirect(*c_enc, *c_buffer, indirectOffset);
  return lean_io_result_mk_ok(lean_box(0));
}

/- # Pipeline Bind Group Layout Introspection -/

/-- Get the bind group layout from a render pipeline at the given group index. -/
alloy c extern
def RenderPipeline.getBindGroupLayout (pipeline : RenderPipeline) (groupIndex : UInt32)
    : IO BindGroupLayout := {
  WGPURenderPipeline *c_pipeline = of_lean<RenderPipeline>(pipeline);
  WGPUBindGroupLayout *layout = calloc(1, sizeof(WGPUBindGroupLayout));
  *layout = wgpuRenderPipelineGetBindGroupLayout(*c_pipeline, groupIndex);
  return lean_io_result_mk_ok(to_lean<BindGroupLayout>(layout));
}

/-- Get the bind group layout from a compute pipeline at the given group index. -/
alloy c extern
def ComputePipeline.getBindGroupLayout (pipeline : ComputePipeline) (groupIndex : UInt32)
    : IO BindGroupLayout := {
  WGPUComputePipeline *c_pipeline = of_lean<ComputePipeline>(pipeline);
  WGPUBindGroupLayout *layout = calloc(1, sizeof(WGPUBindGroupLayout));
  *layout = wgpuComputePipelineGetBindGroupLayout(*c_pipeline, groupIndex);
  return lean_io_result_mk_ok(to_lean<BindGroupLayout>(layout));
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

/-- Destroy a device explicitly. -/
alloy c extern
def Device.destroy (device : Device) : IO Unit := {
  WGPUDevice *c_device = of_lean<Device>(device);
  wgpuDeviceDestroy(*c_device);
  return lean_io_result_mk_ok(lean_box(0));
}

/- # Wgpu version -/

alloy c extern
def wgpuVersion : IO UInt32 := {
  uint32_t v = wgpuGetVersion();
  return lean_io_result_mk_ok(lean_box(v));
}

/- ################################################################## -/
/- # Query Sets & Timestamps (GPU Profiling)                          -/
/- ################################################################## -/

alloy c enum QueryType => WGPUQueryType
| Occlusion  => WGPUQueryType_Occlusion
| Timestamp  => WGPUQueryType_Timestamp
deriving Inhabited, Repr, BEq

alloy c opaque_extern_type QuerySet => WGPUQuerySet where
  finalize(ptr) :=
    wgpuQuerySetRelease(*ptr);
    free(ptr);

/-- Create a query set (Occlusion or Timestamp) with the given count. -/
alloy c extern
def Device.createQuerySet (device : Device) (queryType : QueryType) (count : UInt32) : IO QuerySet := {
  WGPUDevice *c_device = of_lean<Device>(device);
  WGPUQuerySetDescriptor desc = {
    .nextInChain = NULL,
    .label = NULL,
    .type = of_lean<QueryType>(queryType),
    .count = count,
  };
  WGPUQuerySet *qs = calloc(1, sizeof(WGPUQuerySet));
  *qs = wgpuDeviceCreateQuerySet(*c_device, &desc);
  return lean_io_result_mk_ok(to_lean<QuerySet>(qs));
}

/-- Destroy a query set. -/
alloy c extern
def QuerySet.destroy (qs : QuerySet) : IO Unit := {
  WGPUQuerySet *c_qs = of_lean<QuerySet>(qs);
  wgpuQuerySetDestroy(*c_qs);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Get the number of queries in this query set. -/
alloy c extern
def QuerySet.getCount (qs : QuerySet) : IO UInt32 := {
  WGPUQuerySet *c_qs = of_lean<QuerySet>(qs);
  return lean_io_result_mk_ok(lean_box(wgpuQuerySetGetCount(*c_qs)));
}

/-- Get the query type (Occlusion or Timestamp). -/
alloy c extern
def QuerySet.getType (qs : QuerySet) : IO QueryType := {
  WGPUQuerySet *c_qs = of_lean<QuerySet>(qs);
  return lean_io_result_mk_ok(lean_box((uint32_t)wgpuQuerySetGetType(*c_qs)));
}

/-- Write a GPU timestamp into the query set at the given index. -/
alloy c extern
def CommandEncoder.writeTimestamp (encoder : CommandEncoder) (qs : QuerySet) (queryIndex : UInt32) : IO Unit := {
  WGPUCommandEncoder *c_enc = of_lean<CommandEncoder>(encoder);
  WGPUQuerySet *c_qs = of_lean<QuerySet>(qs);
  wgpuCommandEncoderWriteTimestamp(*c_enc, *c_qs, queryIndex);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Resolve query results into a destination buffer.
    Copies `queryCount` queries starting at `firstQuery` into `destination` at `destinationOffset`. -/
alloy c extern
def CommandEncoder.resolveQuerySet (encoder : CommandEncoder) (qs : QuerySet)
    (firstQuery : UInt32) (queryCount : UInt32) (destination : Buffer)
    (destinationOffset : UInt64 := 0) : IO Unit := {
  WGPUCommandEncoder *c_enc = of_lean<CommandEncoder>(encoder);
  WGPUQuerySet *c_qs = of_lean<QuerySet>(qs);
  WGPUBuffer *c_buf = of_lean<Buffer>(destination);
  wgpuCommandEncoderResolveQuerySet(*c_enc, *c_qs, firstQuery, queryCount, *c_buf, destinationOffset);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Begin an occlusion query at the given index in the render pass. -/
alloy c extern
def RenderPassEncoder.beginOcclusionQuery (r : RenderPassEncoder) (queryIndex : UInt32) : IO Unit := {
  WGPURenderPassEncoder *rp = of_lean<RenderPassEncoder>(r);
  wgpuRenderPassEncoderBeginOcclusionQuery(*rp, queryIndex);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- End the current occlusion query in the render pass. -/
alloy c extern
def RenderPassEncoder.endOcclusionQuery (r : RenderPassEncoder) : IO Unit := {
  WGPURenderPassEncoder *rp = of_lean<RenderPassEncoder>(r);
  wgpuRenderPassEncoderEndOcclusionQuery(*rp);
  return lean_io_result_mk_ok(lean_box(0));
}

/- ################################################################## -/
/- # Stencil Operations                                               -/
/- ################################################################## -/

alloy c enum StencilOperation => WGPUStencilOperation
| Keep           => WGPUStencilOperation_Keep
| Zero           => WGPUStencilOperation_Zero
| Replace        => WGPUStencilOperation_Replace
| Invert         => WGPUStencilOperation_Invert
| IncrementClamp => WGPUStencilOperation_IncrementClamp
| DecrementClamp => WGPUStencilOperation_DecrementClamp
| IncrementWrap  => WGPUStencilOperation_IncrementWrap
| DecrementWrap  => WGPUStencilOperation_DecrementWrap
deriving Inhabited, Repr, BEq

/-- A stencil face state descriptor. -/
structure StencilFaceState where
  compare   : CompareFunction := CompareFunction.Always
  failOp    : StencilOperation := StencilOperation.Keep
  depthFailOp : StencilOperation := StencilOperation.Keep
  passOp    : StencilOperation := StencilOperation.Keep
  deriving Inhabited, Repr

/- ################################################################## -/
/- # Texture View Dimension & Aspect Enums                            -/
/- ################################################################## -/

alloy c enum TextureViewDimension => WGPUTextureViewDimension
| Undefined => WGPUTextureViewDimension_Undefined
| D1        => WGPUTextureViewDimension_1D
| D2        => WGPUTextureViewDimension_2D
| D2Array   => WGPUTextureViewDimension_2DArray
| Cube      => WGPUTextureViewDimension_Cube
| CubeArray => WGPUTextureViewDimension_CubeArray
| D3        => WGPUTextureViewDimension_3D
deriving Inhabited, Repr, BEq

alloy c enum TextureAspect => WGPUTextureAspect
| All         => WGPUTextureAspect_All
| StencilOnly => WGPUTextureAspect_StencilOnly
| DepthOnly   => WGPUTextureAspect_DepthOnly
deriving Inhabited, Repr, BEq

/-- Create a texture view with full control over dimension, format, mip range, array layers, and aspect. -/
alloy c extern
def Texture.createViewFull (texture : Texture) (format : TextureFormat)
    (dimension : TextureViewDimension := TextureViewDimension.D2)
    (baseMipLevel : UInt32 := 0) (mipLevelCount : UInt32 := 1)
    (baseArrayLayer : UInt32 := 0) (arrayLayerCount : UInt32 := 1)
    (aspect : TextureAspect := TextureAspect.All) : IO TextureView := {
  WGPUTexture *c_tex = of_lean<Texture>(texture);
  WGPUTextureViewDescriptor desc = {
    .nextInChain = NULL,
    .label = NULL,
    .format = of_lean<TextureFormat>(format),
    .dimension = of_lean<TextureViewDimension>(dimension),
    .baseMipLevel = baseMipLevel,
    .mipLevelCount = mipLevelCount,
    .baseArrayLayer = baseArrayLayer,
    .arrayLayerCount = arrayLayerCount,
    .aspect = of_lean<TextureAspect>(aspect),
  };
  WGPUTextureView *view = calloc(1, sizeof(WGPUTextureView));
  *view = wgpuTextureCreateView(*c_tex, &desc);
  return lean_io_result_mk_ok(to_lean<TextureView>(view));
}

/- ################################################################## -/
/- # CopyBufferToTexture                                              -/
/- ################################################################## -/

/-- Copy data from a buffer to a texture.
    `bytesPerRow` and `rowsPerImage` describe the buffer layout.
    `width`, `height`, `depthOrArrayLayers` describe the copy extent. -/
alloy c extern
def CommandEncoder.copyBufferToTexture (encoder : CommandEncoder)
    (buffer : Buffer) (bytesPerRow : UInt32) (rowsPerImage : UInt32)
    (texture : Texture) (width height : UInt32) (depthOrArrayLayers : UInt32 := 1)
    (mipLevel : UInt32 := 0) : IO Unit := {
  WGPUCommandEncoder *c_enc = of_lean<CommandEncoder>(encoder);
  WGPUBuffer *c_buf = of_lean<Buffer>(buffer);
  WGPUTexture *c_tex = of_lean<Texture>(texture);
  WGPUImageCopyBuffer src = {
    .nextInChain = NULL,
    .layout = { .nextInChain = NULL, .offset = 0, .bytesPerRow = bytesPerRow, .rowsPerImage = rowsPerImage },
    .buffer = *c_buf,
  };
  WGPUImageCopyTexture dst = {
    .nextInChain = NULL,
    .texture = *c_tex,
    .mipLevel = mipLevel,
    .origin = {0, 0, 0},
    .aspect = WGPUTextureAspect_All,
  };
  WGPUExtent3D extent = { .width = width, .height = height, .depthOrArrayLayers = depthOrArrayLayers };
  wgpuCommandEncoderCopyBufferToTexture(*c_enc, &src, &dst, &extent);
  return lean_io_result_mk_ok(lean_box(0));
}

/- ################################################################## -/
/- # Surface Capabilities                                             -/
/- ################################################################## -/

alloy c enum PresentMode => WGPUPresentMode
| Fifo        => WGPUPresentMode_Fifo
| FifoRelaxed => WGPUPresentMode_FifoRelaxed
| Immediate   => WGPUPresentMode_Immediate
| Mailbox     => WGPUPresentMode_Mailbox
deriving Inhabited, Repr, BEq

alloy c enum CompositeAlphaMode => WGPUCompositeAlphaMode
| Auto            => WGPUCompositeAlphaMode_Auto
| Opaque_         => WGPUCompositeAlphaMode_Opaque
| Premultiplied   => WGPUCompositeAlphaMode_Premultiplied
| Unpremultiplied => WGPUCompositeAlphaMode_Unpremultiplied
| Inherit         => WGPUCompositeAlphaMode_Inherit
deriving Inhabited, Repr, BEq

/-- Query surface capabilities: supported formats, present modes, and alpha modes. -/
alloy c extern
def Surface.getCapabilities (surface : Surface) (adapter : Adapter)
    : IO (Array TextureFormat × Array PresentMode × Array CompositeAlphaMode) := {
  WGPUSurface *c_surface = of_lean<Surface>(surface);
  WGPUAdapter *c_adapter = of_lean<Adapter>(adapter);
  WGPUSurfaceCapabilities caps;
  memset(&caps, 0, sizeof(caps));
  wgpuSurfaceGetCapabilities(*c_surface, *c_adapter, &caps);

  // Build format array
  lean_object *fmts = lean_alloc_array(caps.formatCount, caps.formatCount);
  for (size_t i = 0; i < caps.formatCount; i++) {
    lean_array_set_core(fmts, i, lean_box((uint32_t)caps.formats[i]));
  }

  // Build present mode array
  lean_object *pmodes = lean_alloc_array(caps.presentModeCount, caps.presentModeCount);
  for (size_t i = 0; i < caps.presentModeCount; i++) {
    lean_array_set_core(pmodes, i, lean_box((uint32_t)caps.presentModes[i]));
  }

  // Build alpha mode array
  lean_object *amodes = lean_alloc_array(caps.alphaModeCount, caps.alphaModeCount);
  for (size_t i = 0; i < caps.alphaModeCount; i++) {
    lean_array_set_core(amodes, i, lean_box((uint32_t)caps.alphaModes[i]));
  }

  wgpuSurfaceCapabilitiesFreeMembers(caps);

  // Build nested pairs: (fmts, (pmodes, amodes))
  lean_object *inner = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(inner, 0, pmodes);
  lean_ctor_set(inner, 1, amodes);
  lean_object *outer = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(outer, 0, fmts);
  lean_ctor_set(outer, 1, inner);
  return lean_io_result_mk_ok(outer);
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
/- # Texture extra introspection                                      -/
/- ################################################################## -/

/-- Get the depth or array layer count of a texture. -/
alloy c extern
def Texture.getDepthOrArrayLayers (texture : Texture) : IO UInt32 := {
  WGPUTexture *c_tex = of_lean<Texture>(texture);
  return lean_io_result_mk_ok(lean_box(wgpuTextureGetDepthOrArrayLayers(*c_tex)));
}

/-- Get the usage flags of a texture. -/
alloy c extern
def Texture.getUsage (texture : Texture) : IO TextureUsage := {
  WGPUTexture *c_tex = of_lean<Texture>(texture);
  return lean_io_result_mk_ok(lean_box((uint32_t)wgpuTextureGetUsage(*c_tex)));
}

/- ################################################################## -/
/- # Compute pass debug markers                                       -/
/- ################################################################## -/

/-- Push a debug group in a compute pass. -/
alloy c extern
def ComputePassEncoder.pushDebugGroup (enc : ComputePassEncoder) (label : String) : IO Unit := {
  WGPUComputePassEncoder *c_enc = of_lean<ComputePassEncoder>(enc);
  wgpuComputePassEncoderPushDebugGroup(*c_enc, lean_string_cstr(label));
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Pop a debug group in a compute pass. -/
alloy c extern
def ComputePassEncoder.popDebugGroup (enc : ComputePassEncoder) : IO Unit := {
  WGPUComputePassEncoder *c_enc = of_lean<ComputePassEncoder>(enc);
  wgpuComputePassEncoderPopDebugGroup(*c_enc);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Insert a debug marker in a compute pass. -/
alloy c extern
def ComputePassEncoder.insertDebugMarker (enc : ComputePassEncoder) (label : String) : IO Unit := {
  WGPUComputePassEncoder *c_enc = of_lean<ComputePassEncoder>(enc);
  wgpuComputePassEncoderInsertDebugMarker(*c_enc, lean_string_cstr(label));
  return lean_io_result_mk_ok(lean_box(0));
}

/- ################################################################## -/
/- # Pipeline Descriptor with Stencil Configuration                   -/
/- ################################################################## -/

/-- Create a render pipeline descriptor with full depth-stencil configuration including
    custom stencil operations, read/write masks, and depth bias. -/
alloy c extern
def RenderPipelineDescriptor.mkWithStencil
    (shaderModule : ShaderModule) (fState : FragmentState)
    (buffers : @& Array VertexBufferLayoutDesc)
    (topology : PrimitiveTopology := PrimitiveTopology.TriangleList)
    (cullMode : CullMode := CullMode.None)
    (frontFace : FrontFace := FrontFace.CCW)
    (depthFormat : TextureFormat := TextureFormat.Depth24Plus)
    (depthCompare : CompareFunction := CompareFunction.Less)
    (depthWriteEnabled : Bool := true)
    (stencilFront : StencilFaceState := {})
    (stencilBack : StencilFaceState := {})
    (stencilReadMask : UInt32 := 0xFF)
    (stencilWriteMask : UInt32 := 0xFF)
    (sampleCount : UInt32 := 1)
    : IO RenderPipelineDescriptor := {
  WGPUShaderModule *sm = of_lean<ShaderModule>(shaderModule);
  WGPUFragmentState *fs = of_lean<FragmentState>(fState);

  size_t buf_count = lean_array_size(buffers);
  WGPUVertexBufferLayout *c_buffers = NULL;
  WGPUVertexAttribute **attr_arrays = NULL;
  if (buf_count > 0) {
    c_buffers = calloc(buf_count, sizeof(WGPUVertexBufferLayout));
    attr_arrays = calloc(buf_count, sizeof(WGPUVertexAttribute*));
    for (size_t i = 0; i < buf_count; i++) {
      lean_object *vbl_obj = lean_array_get_core(buffers, i);
      uint64_t stride = lean_unbox_uint64(lean_ctor_get(vbl_obj, 0));
      uint8_t step = lean_unbox(lean_ctor_get(vbl_obj, 1));
      lean_object *attrs = lean_ctor_get(vbl_obj, 2);
      size_t attr_count = lean_array_size(attrs);
      WGPUVertexAttribute *c_attrs = calloc(attr_count, sizeof(WGPUVertexAttribute));
      attr_arrays[i] = c_attrs;
      for (size_t j = 0; j < attr_count; j++) {
        lean_object *a = lean_array_get_core(attrs, j);
        c_attrs[j].format = (WGPUVertexFormat)lean_unbox(lean_ctor_get(a, 0));
        c_attrs[j].offset = lean_unbox_uint64(lean_ctor_get(a, 1));
        c_attrs[j].shaderLocation = lean_unbox(lean_ctor_get(a, 2));
      }
      c_buffers[i].arrayStride = stride;
      c_buffers[i].stepMode = (WGPUVertexStepMode)step;
      c_buffers[i].attributeCount = attr_count;
      c_buffers[i].attributes = c_attrs;
    }
    free(attr_arrays);
  }

  // Extract stencil face state fields
  uint8_t sf_compare  = lean_unbox(lean_ctor_get(stencilFront, 0));
  uint8_t sf_fail     = lean_unbox(lean_ctor_get(stencilFront, 1));
  uint8_t sf_depthFail= lean_unbox(lean_ctor_get(stencilFront, 2));
  uint8_t sf_pass     = lean_unbox(lean_ctor_get(stencilFront, 3));

  uint8_t sb_compare  = lean_unbox(lean_ctor_get(stencilBack, 0));
  uint8_t sb_fail     = lean_unbox(lean_ctor_get(stencilBack, 1));
  uint8_t sb_depthFail= lean_unbox(lean_ctor_get(stencilBack, 2));
  uint8_t sb_pass     = lean_unbox(lean_ctor_get(stencilBack, 3));

  WGPURenderPipelineDescriptor *desc = calloc(1, sizeof(WGPURenderPipelineDescriptor));
  desc->nextInChain = NULL;
  desc->label = NULL;
  desc->layout = NULL;

  desc->vertex.module = *sm;
  desc->vertex.entryPoint = "vs_main";
  desc->vertex.constantCount = 0;
  desc->vertex.constants = NULL;
  desc->vertex.bufferCount = buf_count;
  desc->vertex.buffers = c_buffers;

  desc->primitive.topology = of_lean<PrimitiveTopology>(topology);
  desc->primitive.frontFace = of_lean<FrontFace>(frontFace);
  desc->primitive.cullMode = of_lean<CullMode>(cullMode);
  desc->primitive.stripIndexFormat = WGPUIndexFormat_Undefined;

  WGPUDepthStencilState *ds = calloc(1, sizeof(WGPUDepthStencilState));
  ds->format = of_lean<TextureFormat>(depthFormat);
  ds->depthWriteEnabled = depthWriteEnabled ? 1 : 0;
  ds->depthCompare = of_lean<CompareFunction>(depthCompare);
  ds->stencilFront.compare = (WGPUCompareFunction)sf_compare;
  ds->stencilFront.failOp = (WGPUStencilOperation)sf_fail;
  ds->stencilFront.depthFailOp = (WGPUStencilOperation)sf_depthFail;
  ds->stencilFront.passOp = (WGPUStencilOperation)sf_pass;
  ds->stencilBack.compare = (WGPUCompareFunction)sb_compare;
  ds->stencilBack.failOp = (WGPUStencilOperation)sb_fail;
  ds->stencilBack.depthFailOp = (WGPUStencilOperation)sb_depthFail;
  ds->stencilBack.passOp = (WGPUStencilOperation)sb_pass;
  ds->stencilReadMask = stencilReadMask;
  ds->stencilWriteMask = stencilWriteMask;
  ds->depthBias = 0;
  ds->depthBiasSlopeScale = 0.0f;
  ds->depthBiasClamp = 0.0f;
  desc->depthStencil = ds;

  desc->multisample.count = sampleCount;
  desc->multisample.mask = 0xFFFFFFFF;
  desc->multisample.alphaToCoverageEnabled = 0;

  desc->fragment = fs;

  return lean_io_result_mk_ok(to_lean<RenderPipelineDescriptor>(desc));
}

/- ################################################################## -/
/- # Render pass with stencil clear/load/store control                -/
/- ################################################################## -/

/-- Create a render pass with depth+stencil, allowing stencil clear value and
    load/store operation control. -/
alloy c extern
def RenderPassEncoder.mkWithDepthStencil (encoder : CommandEncoder)
    (colorView : TextureView) (clearColor : Color)
    (depthView : TextureView)
    (depthClearValue : Float := 1.0)
    (stencilClearValue : UInt32 := 0)
    (stencilLoadOp : UInt32 := 1)  -- 1=Clear, 2=Load
    (stencilStoreOp : UInt32 := 1) -- 1=Store, 2=Discard
    : IO RenderPassEncoder := {
  WGPUCommandEncoder *c_enc = of_lean<CommandEncoder>(encoder);
  WGPUTextureView *c_view = of_lean<TextureView>(colorView);
  WGPUColor *c_color = of_lean<Color>(clearColor);
  WGPUTextureView *c_depth = of_lean<TextureView>(depthView);

  WGPURenderPassColorAttachment colorAttachment = {
    .nextInChain = NULL,
    .view = *c_view,
    .resolveTarget = NULL,
    .loadOp = WGPULoadOp_Clear,
    .storeOp = WGPUStoreOp_Store,
    .clearValue = *c_color,
  };

  WGPURenderPassDepthStencilAttachment dsAttach = {
    .view = *c_depth,
    .depthLoadOp = WGPULoadOp_Clear,
    .depthStoreOp = WGPUStoreOp_Store,
    .depthClearValue = (float)depthClearValue,
    .depthReadOnly = 0,
    .stencilLoadOp = (WGPULoadOp)stencilLoadOp,
    .stencilStoreOp = (WGPUStoreOp)stencilStoreOp,
    .stencilClearValue = stencilClearValue,
    .stencilReadOnly = 0,
  };

  WGPURenderPassDescriptor desc = {
    .nextInChain = NULL,
    .label = NULL,
    .colorAttachmentCount = 1,
    .colorAttachments = &colorAttachment,
    .depthStencilAttachment = &dsAttach,
    .occlusionQuerySet = NULL,
    .timestampWrites = NULL,
  };

  WGPURenderPassEncoder *rp = calloc(1, sizeof(WGPURenderPassEncoder));
  *rp = wgpuCommandEncoderBeginRenderPass(*c_enc, &desc);
  return lean_io_result_mk_ok(to_lean<RenderPassEncoder>(rp));
}

/- ################################################################## -/
/- # Depth-Stencil texture creation (Depth24PlusStencil8)             -/
/- ################################################################## -/

/-- Create a depth-stencil texture with Depth24PlusStencil8 format. -/
alloy c extern
def Device.createDepthStencilTexture (device : Device) (width height : UInt32)
    : IO Texture := {
  WGPUDevice *c_device = of_lean<Device>(device);
  WGPUTextureDescriptor desc = {
    .nextInChain = NULL,
    .label = NULL,
    .usage = WGPUTextureUsage_RenderAttachment,
    .dimension = WGPUTextureDimension_2D,
    .size = { .width = width, .height = height, .depthOrArrayLayers = 1 },
    .format = WGPUTextureFormat_Depth24PlusStencil8,
    .mipLevelCount = 1,
    .sampleCount = 1,
    .viewFormatCount = 0,
    .viewFormats = NULL,
  };
  WGPUTexture *tex = calloc(1, sizeof(WGPUTexture));
  *tex = wgpuDeviceCreateTexture(*c_device, &desc);
  return lean_io_result_mk_ok(to_lean<Texture>(tex));
}

/-- Create a view for a depth-stencil texture (Depth24PlusStencil8). -/
alloy c extern
def Texture.createDepthStencilView (texture : Texture) : IO TextureView := {
  WGPUTexture *c_tex = of_lean<Texture>(texture);
  WGPUTextureViewDescriptor desc = {
    .nextInChain = NULL,
    .label = NULL,
    .format = WGPUTextureFormat_Depth24PlusStencil8,
    .dimension = WGPUTextureViewDimension_2D,
    .baseMipLevel = 0,
    .mipLevelCount = 1,
    .baseArrayLayer = 0,
    .arrayLayerCount = 1,
    .aspect = WGPUTextureAspect_All,
  };
  WGPUTextureView *view = calloc(1, sizeof(WGPUTextureView));
  *view = wgpuTextureCreateView(*c_tex, &desc);
  return lean_io_result_mk_ok(to_lean<TextureView>(view));
}

/- ################################################################## -/
/- # MSAA texture helpers                                             -/
/- ################################################################## -/

/-- Create an MSAA (multi-sample) render target texture. -/
alloy c extern
def Device.createMSAATexture (device : Device) (width height : UInt32)
    (format : TextureFormat) (sampleCount : UInt32 := 4) : IO Texture := {
  WGPUDevice *c_device = of_lean<Device>(device);
  WGPUTextureDescriptor desc = {
    .nextInChain = NULL,
    .label = NULL,
    .usage = WGPUTextureUsage_RenderAttachment,
    .dimension = WGPUTextureDimension_2D,
    .size = { .width = width, .height = height, .depthOrArrayLayers = 1 },
    .format = of_lean<TextureFormat>(format),
    .mipLevelCount = 1,
    .sampleCount = sampleCount,
    .viewFormatCount = 0,
    .viewFormats = NULL,
  };
  WGPUTexture *tex = calloc(1, sizeof(WGPUTexture));
  *tex = wgpuDeviceCreateTexture(*c_device, &desc);
  return lean_io_result_mk_ok(to_lean<Texture>(tex));
}

/-- Create a render pass that renders to an MSAA texture and resolves to a single-sample target. -/
alloy c extern
def RenderPassEncoder.mkMSAA (encoder : CommandEncoder)
    (msaaView : TextureView) (resolveView : TextureView) (clearColor : Color)
    : IO RenderPassEncoder := {
  WGPUCommandEncoder *c_enc = of_lean<CommandEncoder>(encoder);
  WGPUTextureView *c_msaa = of_lean<TextureView>(msaaView);
  WGPUTextureView *c_resolve = of_lean<TextureView>(resolveView);
  WGPUColor *c_color = of_lean<Color>(clearColor);

  WGPURenderPassColorAttachment colorAttachment = {
    .nextInChain = NULL,
    .view = *c_msaa,
    .resolveTarget = *c_resolve,
    .loadOp = WGPULoadOp_Clear,
    .storeOp = WGPUStoreOp_Store,
    .clearValue = *c_color,
  };

  WGPURenderPassDescriptor desc = {
    .nextInChain = NULL,
    .label = NULL,
    .colorAttachmentCount = 1,
    .colorAttachments = &colorAttachment,
    .depthStencilAttachment = NULL,
    .occlusionQuerySet = NULL,
    .timestampWrites = NULL,
  };

  WGPURenderPassEncoder *rp = calloc(1, sizeof(WGPURenderPassEncoder));
  *rp = wgpuCommandEncoderBeginRenderPass(*c_enc, &desc);
  return lean_io_result_mk_ok(to_lean<RenderPassEncoder>(rp));
}

/- ################################################################## -/
/- # RenderPass with Load (no clear)                                  -/
/- ################################################################## -/

/-- Create a render pass that loads existing content (no clear). -/
alloy c extern
def RenderPassEncoder.mkLoad (encoder : CommandEncoder) (view : TextureView) : IO RenderPassEncoder := {
  WGPUCommandEncoder *c_enc = of_lean<CommandEncoder>(encoder);
  WGPUTextureView *c_view = of_lean<TextureView>(view);

  WGPURenderPassColorAttachment colorAttachment = {
    .nextInChain = NULL,
    .view = *c_view,
    .resolveTarget = NULL,
    .loadOp = WGPULoadOp_Load,
    .storeOp = WGPUStoreOp_Store,
    .clearValue = {0, 0, 0, 0},
  };

  WGPURenderPassDescriptor desc = {
    .nextInChain = NULL,
    .label = NULL,
    .colorAttachmentCount = 1,
    .colorAttachments = &colorAttachment,
    .depthStencilAttachment = NULL,
    .occlusionQuerySet = NULL,
    .timestampWrites = NULL,
  };

  WGPURenderPassEncoder *rp = calloc(1, sizeof(WGPURenderPassEncoder));
  *rp = wgpuCommandEncoderBeginRenderPass(*c_enc, &desc);
  return lean_io_result_mk_ok(to_lean<RenderPassEncoder>(rp));
}

/-- Create a render pass that loads existing color AND depth buffers (no clear). -/
alloy c extern
def RenderPassEncoder.mkLoadWithDepth (encoder : CommandEncoder) (view : TextureView) (depthView : TextureView) : IO RenderPassEncoder := {
  WGPUCommandEncoder *c_enc = of_lean<CommandEncoder>(encoder);
  WGPUTextureView *c_view = of_lean<TextureView>(view);
  WGPUTextureView *c_depth = of_lean<TextureView>(depthView);

  WGPURenderPassColorAttachment colorAttachment = {
    .nextInChain = NULL,
    .view = *c_view,
    .resolveTarget = NULL,
    .loadOp = WGPULoadOp_Load,
    .storeOp = WGPUStoreOp_Store,
    .clearValue = {0, 0, 0, 0},
  };

  WGPURenderPassDepthStencilAttachment dsAttach = {
    .view = *c_depth,
    .depthLoadOp = WGPULoadOp_Load,
    .depthStoreOp = WGPUStoreOp_Store,
    .depthClearValue = 1.0f,
    .depthReadOnly = 0,
    .stencilLoadOp = WGPULoadOp_Undefined,
    .stencilStoreOp = WGPUStoreOp_Undefined,
    .stencilClearValue = 0,
    .stencilReadOnly = 1,
  };

  WGPURenderPassDescriptor desc = {
    .nextInChain = NULL,
    .label = NULL,
    .colorAttachmentCount = 1,
    .colorAttachments = &colorAttachment,
    .depthStencilAttachment = &dsAttach,
    .occlusionQuerySet = NULL,
    .timestampWrites = NULL,
  };

  WGPURenderPassEncoder *rp = calloc(1, sizeof(WGPURenderPassEncoder));
  *rp = wgpuCommandEncoderBeginRenderPass(*c_enc, &desc);
  return lean_io_result_mk_ok(to_lean<RenderPassEncoder>(rp));
}

/- ################################################################## -/
/- # Render pass with color load/store control                        -/
/- ################################################################## -/

/-- Create a render pass with configurable load/store ops.
    loadOp: 1=Clear, 2=Load. storeOp: 1=Store, 2=Discard. -/
alloy c extern
def RenderPassEncoder.mkWithOps (encoder : CommandEncoder) (view : TextureView)
    (clearColor : Color) (loadOp : UInt32 := 1) (storeOp : UInt32 := 1)
    : IO RenderPassEncoder := {
  WGPUCommandEncoder *c_enc = of_lean<CommandEncoder>(encoder);
  WGPUTextureView *c_view = of_lean<TextureView>(view);
  WGPUColor *c_color = of_lean<Color>(clearColor);

  WGPURenderPassColorAttachment colorAttachment = {
    .nextInChain = NULL,
    .view = *c_view,
    .resolveTarget = NULL,
    .loadOp = (WGPULoadOp)loadOp,
    .storeOp = (WGPUStoreOp)storeOp,
    .clearValue = *c_color,
  };

  WGPURenderPassDescriptor desc = {
    .nextInChain = NULL,
    .label = NULL,
    .colorAttachmentCount = 1,
    .colorAttachments = &colorAttachment,
    .depthStencilAttachment = NULL,
    .occlusionQuerySet = NULL,
    .timestampWrites = NULL,
  };

  WGPURenderPassEncoder *rp = calloc(1, sizeof(WGPURenderPassEncoder));
  *rp = wgpuCommandEncoderBeginRenderPass(*c_enc, &desc);
  return lean_io_result_mk_ok(to_lean<RenderPassEncoder>(rp));
}

/- ################################################################## -/
/- # BindGroup with N buffer entries (generic)                        -/
/- ################################################################## -/

/-- Create a bind group with an arbitrary array of buffer bindings.
    Each element of `bindings` is (bindingIndex, buffer, offset, size). -/
alloy c extern
def BindGroup.mkBuffers (device : Device) (layout : BindGroupLayout)
    (bindings : @& Array (UInt32 × Buffer × UInt64 × UInt64)) : IO BindGroup := {
  WGPUDevice *c_device = of_lean<Device>(device);
  WGPUBindGroupLayout *c_layout = of_lean<BindGroupLayout>(layout);
  size_t count = lean_array_size(bindings);
  WGPUBindGroupEntry *entries = calloc(count, sizeof(WGPUBindGroupEntry));
  for (size_t i = 0; i < count; i++) {
    lean_object *tuple = lean_array_get_core(bindings, i);
    uint32_t binding = lean_unbox(lean_ctor_get(tuple, 0));
    lean_object *rest1 = lean_ctor_get(tuple, 1);
    lean_object *buf_obj = lean_ctor_get(rest1, 0);
    lean_object *rest2 = lean_ctor_get(rest1, 1);
    uint64_t offset = lean_unbox_uint64(lean_ctor_get(rest2, 0));
    uint64_t size = lean_unbox_uint64(lean_ctor_get(rest2, 1));
    WGPUBuffer *c_buf = of_lean<Buffer>(buf_obj);
    entries[i].binding = binding;
    entries[i].buffer = *c_buf;
    entries[i].offset = offset;
    entries[i].size = size;
    entries[i].sampler = NULL;
    entries[i].textureView = NULL;
  }
  WGPUBindGroupDescriptor desc = {
    .nextInChain = NULL,
    .label = NULL,
    .layout = *c_layout,
    .entryCount = count,
    .entries = entries,
  };
  WGPUBindGroup *bg = calloc(1, sizeof(WGPUBindGroup));
  *bg = wgpuDeviceCreateBindGroup(*c_device, &desc);
  free(entries);
  return lean_io_result_mk_ok(to_lean<BindGroup>(bg));
}

/- ################################################################## -/
/- # BindGroupLayout with N uniform/storage entries (generic)         -/
/- ################################################################## -/

/-- Create a bind group layout with an arbitrary array of buffer binding entries.
    Each element: (binding, visibility, isStorage : Bool, minBindingSize).
    If isStorage=false, creates a uniform binding. If true, a read-only storage binding. -/
alloy c extern
def BindGroupLayout.mkEntries (device : Device)
    (entries : @& Array (UInt32 × UInt32 × Bool × UInt64)) : IO BindGroupLayout := {
  WGPUDevice *c_device = of_lean<Device>(device);
  size_t count = lean_array_size(entries);
  WGPUBindGroupLayoutEntry *c_entries = calloc(count, sizeof(WGPUBindGroupLayoutEntry));
  for (size_t i = 0; i < count; i++) {
    lean_object *tuple = lean_array_get_core(entries, i);
    uint32_t binding = lean_unbox(lean_ctor_get(tuple, 0));
    lean_object *rest1 = lean_ctor_get(tuple, 1);
    uint32_t visibility = lean_unbox(lean_ctor_get(rest1, 0));
    lean_object *rest2 = lean_ctor_get(rest1, 1);
    uint8_t is_storage = lean_unbox(lean_ctor_get(rest2, 0));
    uint64_t min_size = lean_unbox_uint64(lean_ctor_get(rest2, 1));

    memset(&c_entries[i], 0, sizeof(WGPUBindGroupLayoutEntry));
    c_entries[i].binding = binding;
    c_entries[i].visibility = visibility;
    if (is_storage) {
      c_entries[i].buffer.type = WGPUBufferBindingType_ReadOnlyStorage;
    } else {
      c_entries[i].buffer.type = WGPUBufferBindingType_Uniform;
    }
    c_entries[i].buffer.minBindingSize = min_size;
  }
  WGPUBindGroupLayoutDescriptor desc = {
    .nextInChain = NULL,
    .label = NULL,
    .entryCount = count,
    .entries = c_entries,
  };
  WGPUBindGroupLayout *bgl = calloc(1, sizeof(WGPUBindGroupLayout));
  *bgl = wgpuDeviceCreateBindGroupLayout(*c_device, &desc);
  free(c_entries);
  return lean_io_result_mk_ok(to_lean<BindGroupLayout>(bgl));
}

/- ################################################################## -/
/- # Depth texture + comparison sampler layout/bind group             -/
/- ################################################################## -/

/-- Create a bind group layout for a depth texture (comparison) + comparison sampler.
    This is used for shadow mapping: the texture is sampled with textureSampleCompare. -/
alloy c extern
def BindGroupLayout.mkDepthTextureSampler (device : Device)
    (textureBinding samplerBinding : UInt32) (visibility : UInt32)
    : IO BindGroupLayout := {
  WGPUDevice c_device = *of_lean<Device>(device);

  WGPUBindGroupLayoutEntry *entries = calloc(2, sizeof(WGPUBindGroupLayoutEntry));

  entries[0].binding = textureBinding;
  entries[0].visibility = visibility;
  entries[0].texture.sampleType = WGPUTextureSampleType_Depth;
  entries[0].texture.viewDimension = WGPUTextureViewDimension_2D;
  entries[0].texture.multisampled = false;
  entries[0].buffer.type = WGPUBufferBindingType_Undefined;
  entries[0].sampler.type = WGPUSamplerBindingType_Undefined;
  entries[0].storageTexture.access = WGPUStorageTextureAccess_Undefined;

  entries[1].binding = samplerBinding;
  entries[1].visibility = visibility;
  entries[1].sampler.type = WGPUSamplerBindingType_Comparison;
  entries[1].buffer.type = WGPUBufferBindingType_Undefined;
  entries[1].texture.sampleType = WGPUTextureSampleType_Undefined;
  entries[1].storageTexture.access = WGPUStorageTextureAccess_Undefined;

  WGPUBindGroupLayoutDescriptor desc = {
    .nextInChain = NULL,
    .label = NULL,
    .entryCount = 2,
    .entries = entries,
  };

  WGPUBindGroupLayout *layout = calloc(1, sizeof(WGPUBindGroupLayout));
  *layout = wgpuDeviceCreateBindGroupLayout(c_device, &desc);
  free(entries);
  return lean_io_result_mk_ok(to_lean<BindGroupLayout>(layout));
}

/-- Create a render pass with ONLY depth (no color attachment). For shadow map generation. -/
alloy c extern
def RenderPassEncoder.mkDepthOnly (encoder : CommandEncoder) (depthView : TextureView)
    : IO RenderPassEncoder := {
  WGPUCommandEncoder *c_enc = of_lean<CommandEncoder>(encoder);
  WGPUTextureView *c_depth = of_lean<TextureView>(depthView);

  WGPURenderPassDepthStencilAttachment dsAttach = {
    .view = *c_depth,
    .depthLoadOp = WGPULoadOp_Clear,
    .depthStoreOp = WGPUStoreOp_Store,
    .depthClearValue = 1.0f,
    .depthReadOnly = 0,
    .stencilLoadOp = WGPULoadOp_Undefined,
    .stencilStoreOp = WGPUStoreOp_Undefined,
    .stencilClearValue = 0,
    .stencilReadOnly = 1,
  };

  WGPURenderPassDescriptor desc = {
    .nextInChain = NULL,
    .label = "Shadow pass",
    .colorAttachmentCount = 0,
    .colorAttachments = NULL,
    .depthStencilAttachment = &dsAttach,
    .occlusionQuerySet = NULL,
    .timestampWrites = NULL,
  };

  WGPURenderPassEncoder *rp = calloc(1, sizeof(WGPURenderPassEncoder));
  *rp = wgpuCommandEncoderBeginRenderPass(*c_enc, &desc);
  return lean_io_result_mk_ok(to_lean<RenderPassEncoder>(rp));
}

/-- Create a render pipeline descriptor with depth-only output (no color targets).
    Used for shadow map rendering from the light's perspective. -/
alloy c extern
def RenderPipelineDescriptor.mkDepthOnly
    (shaderModule : ShaderModule)
    (buffers : @& Array VertexBufferLayoutDesc)
    (topology : PrimitiveTopology := PrimitiveTopology.TriangleList)
    (cullMode : CullMode := CullMode.Back)
    (frontFace : FrontFace := FrontFace.CCW)
    (depthFormat : TextureFormat := TextureFormat.Depth24Plus)
    (depthCompare : CompareFunction := CompareFunction.Less)
    : IO RenderPipelineDescriptor := {
  WGPUShaderModule *sm = of_lean<ShaderModule>(shaderModule);

  size_t buf_count = lean_array_size(buffers);
  WGPUVertexBufferLayout *c_buffers = NULL;
  WGPUVertexAttribute **attr_arrays = NULL;
  if (buf_count > 0) {
    c_buffers = calloc(buf_count, sizeof(WGPUVertexBufferLayout));
    attr_arrays = calloc(buf_count, sizeof(WGPUVertexAttribute*));
    for (size_t i = 0; i < buf_count; i++) {
      lean_object *vbl_obj = lean_array_get_core(buffers, i);
      uint64_t stride = lean_unbox_uint64(lean_ctor_get(vbl_obj, 0));
      uint8_t step = lean_unbox(lean_ctor_get(vbl_obj, 1));
      lean_object *attrs = lean_ctor_get(vbl_obj, 2);
      size_t attr_count = lean_array_size(attrs);
      WGPUVertexAttribute *c_attrs = calloc(attr_count, sizeof(WGPUVertexAttribute));
      attr_arrays[i] = c_attrs;
      for (size_t j = 0; j < attr_count; j++) {
        lean_object *a = lean_array_get_core(attrs, j);
        c_attrs[j].format = (WGPUVertexFormat)lean_unbox(lean_ctor_get(a, 0));
        c_attrs[j].offset = lean_unbox_uint64(lean_ctor_get(a, 1));
        c_attrs[j].shaderLocation = lean_unbox(lean_ctor_get(a, 2));
      }
      c_buffers[i].arrayStride = stride;
      c_buffers[i].stepMode = (WGPUVertexStepMode)step;
      c_buffers[i].attributeCount = attr_count;
      c_buffers[i].attributes = c_attrs;
    }
    free(attr_arrays);
  }

  WGPURenderPipelineDescriptor *desc = calloc(1, sizeof(WGPURenderPipelineDescriptor));
  desc->nextInChain = NULL;
  desc->label = NULL;
  desc->layout = NULL;

  desc->vertex.module = *sm;
  desc->vertex.entryPoint = "vs_shadow";
  desc->vertex.constantCount = 0;
  desc->vertex.constants = NULL;
  desc->vertex.bufferCount = buf_count;
  desc->vertex.buffers = c_buffers;

  desc->primitive.topology = of_lean<PrimitiveTopology>(topology);
  desc->primitive.frontFace = of_lean<FrontFace>(frontFace);
  desc->primitive.cullMode = of_lean<CullMode>(cullMode);
  desc->primitive.stripIndexFormat = WGPUIndexFormat_Undefined;

  WGPUDepthStencilState *ds = calloc(1, sizeof(WGPUDepthStencilState));
  ds->format = of_lean<TextureFormat>(depthFormat);
  ds->depthWriteEnabled = 1;
  ds->depthCompare = of_lean<CompareFunction>(depthCompare);
  ds->stencilFront.compare = WGPUCompareFunction_Always;
  ds->stencilFront.failOp = WGPUStencilOperation_Keep;
  ds->stencilFront.depthFailOp = WGPUStencilOperation_Keep;
  ds->stencilFront.passOp = WGPUStencilOperation_Keep;
  ds->stencilBack = ds->stencilFront;
  ds->stencilReadMask = 0xFF;
  ds->stencilWriteMask = 0xFF;
  desc->depthStencil = ds;

  desc->multisample.count = 1;
  desc->multisample.mask = 0xFFFFFFFF;
  desc->multisample.alphaToCoverageEnabled = 0;

  // No fragment state — depth only
  desc->fragment = NULL;

  return lean_io_result_mk_ok(to_lean<RenderPipelineDescriptor>(desc));
}

/- ################################################################## -/
/- # Sampler with comparison function                                 -/
/- ################################################################## -/

/-- Create a comparison sampler (used for shadow mapping PCF). -/
alloy c extern
def Device.createComparisonSampler (device : Device)
    (compare : CompareFunction := CompareFunction.Less)
    (addressMode : AddressMode := AddressMode.ClampToEdge)
    (magFilter : FilterMode := FilterMode.Linear)
    (minFilter : FilterMode := FilterMode.Linear)
    : IO Sampler := {
  WGPUDevice *c_device = of_lean<Device>(device);
  WGPUSamplerDescriptor desc = {
    .nextInChain = NULL,
    .label = NULL,
    .addressModeU = of_lean<AddressMode>(addressMode),
    .addressModeV = of_lean<AddressMode>(addressMode),
    .addressModeW = of_lean<AddressMode>(addressMode),
    .magFilter = of_lean<FilterMode>(magFilter),
    .minFilter = of_lean<FilterMode>(minFilter),
    .mipmapFilter = WGPUMipmapFilterMode_Nearest,
    .lodMinClamp = 0.0f,
    .lodMaxClamp = 1.0f,
    .compare = of_lean<CompareFunction>(compare),
    .maxAnisotropy = 1,
  };
  WGPUSampler *sampler = calloc(1, sizeof(WGPUSampler));
  *sampler = wgpuDeviceCreateSampler(*c_device, &desc);
  return lean_io_result_mk_ok(to_lean<Sampler>(sampler));
}

/- ################################################################## -/
/- # Read bytes from ByteArray as Float / UInt64                      -/
/- ################################################################## -/

/-- Convert a ByteArray to an array of UInt64s (for timestamp readback). -/
alloy c extern
def byteArrayToUInt64s (arr : @& ByteArray) : Array UInt64 := {
  lean_object *ba = arr;
  size_t byte_len = lean_sarray_size(ba);
  size_t count = byte_len / 8;
  uint8_t *data = lean_sarray_cptr(ba);
  lean_object *result = lean_alloc_array(count, count);
  for (size_t i = 0; i < count; i++) {
    uint64_t val;
    memcpy(&val, data + i * 8, 8);
    lean_array_set_core(result, i, lean_box_uint64(val));
  }
  return result;
}

end Wgpu
