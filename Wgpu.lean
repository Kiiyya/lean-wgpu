import Wgpu.Async
import Alloy.C
open scoped Alloy.C
open IO

namespace Wgpu

alloy c include <stdio.h>
alloy c include <stdlib.h>
alloy c include <lean/lean.h>
alloy c include <wgpu.h>
alloy c include <webgpu.h>

alloy c section
  -- hacky. Copied from the compiled output from lean runtime
  extern lean_object* lean_io_promise_new(lean_object* seemsNotUsed);
  extern lean_object* lean_io_promise_resolve(lean_object* value, lean_object* promise, lean_object* seemsNotUsed);

  lean_task_object *promise_mk() {
    lean_object *io_res = lean_io_promise_new(lean_io_mk_world());
    if (!lean_io_result_is_ok(io_res)) {
      fprintf(stderr, "Failed to create promise\n");
      abort(); -- In Lean, `Promise.new` is infallible, so we just abort if it ever actually fail (it won't).
    }
    lean_task_object *promise = lean_to_task(lean_io_result_get_value(io_res));
    return promise;
  }

  void promise_resolve(lean_task_object *promise, lean_object *value) {
    lean_io_promise_resolve(value, (lean_object*)promise, lean_io_mk_world());
  }
end

/- # Instance -/

alloy c opaque_extern_type InstanceDescriptor => WGPUInstanceDescriptor where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUInstanceDescriptor\n");
    free(ptr);

alloy c opaque_extern_type Instance => WGPUInstance where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUInstance\n");
    wgpuInstanceRelease(*ptr);
    free(ptr);

alloy c extern
def InstanceDescriptor.mk : IO InstanceDescriptor := {
  fprintf(stderr, "mk WGPUInstanceDescriptor\n");
  WGPUInstanceDescriptor* desc = calloc(1,sizeof(WGPUInstanceDescriptor));
  desc->nextInChain = NULL;
  return lean_io_result_mk_ok(to_lean<InstanceDescriptor>(desc));
}

alloy c extern
def createInstance (desc : InstanceDescriptor) : IO Instance := {
  fprintf(stderr, "mk WGPUInstance\n");
  WGPUInstance *inst = calloc(1,sizeof(WGPUInstance));
  *inst = wgpuCreateInstance(of_lean<InstanceDescriptor>(desc)); -- ! RealWorld
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
  void onAdapterRequestEnded(WGPURequestAdapterStatus status, WGPUAdapter adapter, const char* message, void* promise) {
    if (status == WGPURequestAdapterStatus_Success) {
      WGPUAdapter *a = (WGPUAdapter*)calloc(1,sizeof(WGPUAdapter));
      *a = adapter;

      WGPUAdapterProperties prop = {};
      prop.nextInChain = NULL;
      wgpuAdapterGetProperties(adapter, &prop);
      fprintf(stderr, "Adapter Properties:\n");
      fprintf(stderr, " - Vendor ID: %d\n", prop.vendorID);
      fprintf(stderr, " - Vendor Name: %s\n", prop.vendorName);
      fprintf(stderr, " - Arch: %s\n", prop.architecture);
      fprintf(stderr, " - Device ID: %d\n", prop.deviceID);
      fprintf(stderr, " - Driver Description: %s\n", prop.driverDescription);
      fprintf(stderr, " - Adapter Type: %d\n", prop.adapterType);
      fprintf(stderr, " - Backend Type: %d\n", prop.backendType);

      lean_object* l_adapter = to_lean<Adapter>(a);
      -- Promise type is `Except IO.Error Adapter`
      promise_resolve((lean_task_object*) promise, lean_io_result_mk_ok(l_adapter));
    } else {
      fprintf(stderr, "Could not get WebGPU adapter: %s\n", message);
      promise_resolve((lean_task_object*) promise, lean_io_result_mk_error(lean_box(0)));
    }
  }
end

alloy c extern
def Instance.requestAdapter (l_inst : Instance) (surface : Surface): IO (A (Result Adapter)) := {
  WGPUInstance *inst = of_lean<Instance>(l_inst);
  WGPURequestAdapterOptions adapterOpts = {};
  adapterOpts.nextInChain = NULL;
  lean_inc(surface); -- ! memory leak, need to dec later.
  adapterOpts.compatibleSurface = *of_lean<Surface>(surface);

  lean_task_object *promise = promise_mk();
  -- Note that the adapter maintains an internal (wgpu) reference to the WGPUInstance, according to the C++ guide: "We will no longer need to use the instance once we have selected our adapter, so we can call wgpuInstanceRelease(instance) right after the adapter request instead of at the very end. The underlying instance object will keep on living until the adapter gets released but we do not need to manager this."
  wgpuInstanceRequestAdapter( -- ! RealWorld
      *inst,
      &adapterOpts,
      onAdapterRequestEnded,
      (void*)promise
  );
  return lean_io_result_mk_ok((lean_object*) promise);
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
  desc->desc.defaultQueue.nextInChain = NULL;
  desc->desc.defaultQueue.label = "The default queue";
  lean_inc(onDeviceLost); -- TODO Not sure if we need this, but if yes: When does it get decremented? ==> Memory leak!
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
  void onAdapterRequestDeviceEnded(WGPURequestDeviceStatus status, WGPUDevice device, char const *message, void *promise) {
    if (status == WGPURequestDeviceStatus_Success) {
      WGPUDevice *d = calloc(1,sizeof(WGPUDevice));
      *d = device;
      lean_object* l_device = to_lean<Device>(d);
      promise_resolve((lean_task_object*) promise, lean_io_result_mk_ok(l_device));
    } else {
      fprintf(stderr, "Could not get WebGPU device: %s\n", message);
      promise_resolve((lean_task_object*) promise, lean_io_result_mk_error(lean_box(0)));
    }
  }
end

alloy c extern def Adapter.requestDevice (l_adapter : Adapter) (l_ddesc : DeviceDescriptor) : IO (A (Result Device)) := {
  WGPUAdapter *adapter = of_lean<Adapter>(l_adapter);
  LWGPUDeviceDescriptor *ddesc = of_lean<DeviceDescriptor>(l_ddesc);

  lean_task_object *promise = promise_mk();
  wgpuAdapterRequestDevice( -- ! RealWorld
      *adapter,
      &ddesc->desc,
      onAdapterRequestDeviceEnded,
      (void*)promise
  );
  return lean_io_result_mk_ok((lean_object*) promise);
}

alloy c extern def Device.poll (device : Device) : IO Unit := {
  wgpuDevicePoll(*of_lean<Device>(device), false, NULL);
  return lean_io_result_mk_ok(lean_box(0));
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
  lean_inc(onDeviceError); -- ! Memory leak
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

alloy c extern def CommandEncoder.insertDebugMarker (encoder : CommandEncoder) (s : String) : IO Unit := {
  WGPUCommandEncoder *c_encoder = of_lean<CommandEncoder>(encoder);
  lean_inc(s); -- ! Memory leak
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
def TextureFormat.get (surface : Surface) (adapter : Adapter) : TextureFormat := {
    WGPUSurface * c_surface = of_lean<Surface>(surface);
    WGPUAdapter * c_adapter = of_lean<Adapter>(adapter);

    WGPUTextureFormat surfaceFormat =  wgpuSurfaceGetPreferredFormat(*c_surface, *c_adapter);
    return to_lean<TextureFormat>(surfaceFormat);
}

/-- # SurfaceConfiguration -/

alloy c opaque_extern_type SurfaceConfiguration  => WGPUSurfaceConfiguration  where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUSurfaceConfiguration \n");
    free(ptr);

alloy c extern
def SurfaceConfiguration.mk (width height : UInt32) (device : Device) (textureFormat : TextureFormat)
  : SurfaceConfiguration := {
  WGPUDevice * c_device = of_lean<Device>(device);
  WGPUTextureFormat surfaceFormat = of_lean<TextureFormat>(textureFormat);
  WGPUSurfaceConfiguration *config = calloc(1,sizeof(WGPUSurfaceConfiguration))
  config->format = surfaceFormat;
  config->nextInChain = NULL; --Is this really needed ?
  config->width = width;
  config->height = height;
  config->viewFormatCount = 0;
  config->viewFormats = NULL;
  config->usage = WGPUTextureUsage_RenderAttachment;
  config->device = *c_device;
  -- TODO link present mode
  config->presentMode = WGPUPresentMode_Fifo;
  -- TODO link alpha mode enum
  config->alphaMode = WGPUCompositeAlphaMode_Auto;
  fprintf(stderr, "Done generating config !\n");

  return to_lean<SurfaceConfiguration>(config);
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

  -- ! This was the culprit: wgpuRenderPassEncoderEnd(*renderPass);
  return lean_io_result_mk_ok(to_lean<RenderPassEncoder>(renderPass));
}

alloy c extern
def RenderPassEncoder.release (renderPass : RenderPassEncoder) : IO Unit := {
    WGPURenderPassEncoder * render_pass = of_lean<RenderPassEncoder>(renderPass);
    wgpuRenderPassEncoderRelease(*render_pass);
    return lean_io_result_mk_ok(lean_box(0));
}



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

-- TODO put shaderSource as parameter to the function (how to transform String into char* ?)
alloy c extern
def ShaderModuleWGSLDescriptor.mk (shaderSource : String): ShaderModuleWGSLDescriptor := {
  char const * c_shaderSource = lean_string_cstr(shaderSource);
  fprintf(stderr, "%s \n",c_shaderSource);
  fprintf(stderr, "mk ShaderModuleWGSLDescriptor \n");
  WGPUShaderModuleWGSLDescriptor * shaderCodeDesc = calloc(1,sizeof(WGPUShaderModuleWGSLDescriptor));
  shaderCodeDesc->chain.next = NULL;
  shaderCodeDesc->chain.sType = WGPUSType_ShaderModuleWGSLDescriptor;
  shaderCodeDesc->code = c_shaderSource;
  return to_lean<ShaderModuleWGSLDescriptor>(shaderCodeDesc);
}

/-- # ShaderModuleDescriptor -/

alloy c opaque_extern_type ShaderModuleDescriptor => WGPUShaderModuleDescriptor where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUShaderModuleDescriptor \n");
    -- wgpuRenderPipelineRelease(*ptr);
    free(ptr);

alloy c extern
def ShaderModuleDescriptor.mk (shaderCodeDesc : ShaderModuleWGSLDescriptor) : ShaderModuleDescriptor := {
  fprintf(stderr, "mk ShaderModuleDescriptor \n");
  WGPUShaderModuleWGSLDescriptor * c_shaderCodeDesc = of_lean<ShaderModuleWGSLDescriptor>(shaderCodeDesc);
  WGPUShaderModuleDescriptor * shaderDesc = calloc(1, sizeof(WGPUShaderModuleDescriptor));
  shaderDesc->hintCount = 0;
  shaderDesc->hints = NULL;
  shaderDesc->nextInChain = &c_shaderCodeDesc->chain;
  return to_lean<ShaderModuleDescriptor>(shaderDesc);
}

alloy c opaque_extern_type ShaderModule => WGPUShaderModule where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUShaderModule \n");
    -- wgpuRenderPipelineRelease(*ptr);
    free(ptr);

alloy c extern
def ShaderModule.mk (device : Device) (shaderDesc : ShaderModuleDescriptor) : ShaderModule := {
  fprintf(stderr, "mk ShaderModule \n");
  WGPUDevice * c_device = of_lean<Device>(device);
  WGPUShaderModuleDescriptor * c_shaderDesc = of_lean<ShaderModuleDescriptor>(shaderDesc);
  WGPUShaderModule * shaderModule = calloc(1,sizeof(WGPUShaderModule));
  *shaderModule = wgpuDeviceCreateShaderModule(*c_device, c_shaderDesc);
  return to_lean<ShaderModule>(shaderModule);
}

/-- # BlendState -/

alloy c opaque_extern_type BlendState => WGPUBlendState where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUBlendState \n");
    free(ptr);

alloy c extern
def BlendState.mk (shaderModule : ShaderModule) : BlendState := {
  fprintf(stderr, "mk BlendState \n");

  WGPUBlendState * blendState = calloc(1,sizeof(WGPUBlendState));
  blendState->color.srcFactor = WGPUBlendFactor_SrcAlpha;
  blendState->color.dstFactor = WGPUBlendFactor_OneMinusSrcAlpha;
  blendState->color.operation = WGPUBlendOperation_Add;
  blendState->alpha.srcFactor = WGPUBlendFactor_Zero;
  blendState->alpha.dstFactor = WGPUBlendFactor_One;
  blendState->alpha.operation = WGPUBlendOperation_Add;

  return to_lean<BlendState>(blendState)
}

/-- # ColorTargetState -/

alloy c opaque_extern_type ColorTargetState => WGPUColorTargetState where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUColorTargetState \n");
    free(ptr);

alloy c extern
def ColorTargetState.mk (surfaceFormat : TextureFormat) (blendState : BlendState) :  ColorTargetState := {
  fprintf(stderr, "mk ColorTargetState \n");

  WGPUTextureFormat c_surfaceFormat = of_lean<TextureFormat>(surfaceFormat);
  WGPUBlendState * c_blendState = of_lean<BlendState>(blendState);
  WGPUColorTargetState * colorTarget = calloc(1,sizeof(WGPUColorTargetState));
  colorTarget->format = surfaceFormat;
  colorTarget->blend  = c_blendState;
  -- TODO add writeMask param
  colorTarget->writeMask = WGPUColorWriteMask_All; // We could write to only some of the color channels.
  return to_lean<ColorTargetState>(colorTarget)
}


/-- # FragmentState -/

alloy c opaque_extern_type FragmentState => WGPUFragmentState where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUFragmentState \n");
    free(ptr);

alloy c extern
def FragmentState.mk (shaderModule : ShaderModule) (colorTarget : ColorTargetState): FragmentState := {
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
  return to_lean<FragmentState>(fragmentState);
}

/-- # RenderPipelineDescriptor -/

alloy c opaque_extern_type RenderPipelineDescriptor => WGPURenderPipelineDescriptor where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPURenderPipelineDescriptor \n");
    free(ptr);

alloy c extern
def RenderPipelineDescriptor.mk  (shaderModule : ShaderModule) (fState : FragmentState) : RenderPipelineDescriptor := {
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
  pipelineDesc->layout = NULL;
  pipelineDesc->fragment = fragmentState;
  pipelineDesc->depthStencil = NULL;
  pipelineDesc->multisample.count = 1;
  pipelineDesc->multisample.mask = 0xFFFFFFFF;
  pipelineDesc->multisample.alphaToCoverageEnabled = false;

  return to_lean<RenderPipelineDescriptor>(pipelineDesc);
}

/-- # RenderPipeline -/

alloy c opaque_extern_type RenderPipeline => WGPURenderPipeline where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPURenderPipeline \n");
    wgpuRenderPipelineRelease(*ptr);
    free(ptr);

-- TODO unclog that mess
alloy c extern
def RenderPipeline.mk (device : Device) (pipelineDesc : RenderPipelineDescriptor): RenderPipeline := {
  WGPUDevice * c_device = of_lean<Device>(device);
  WGPURenderPipelineDescriptor * c_pipelineDesc = of_lean<RenderPipelineDescriptor>(pipelineDesc);
  WGPURenderPipeline * pipeline = calloc(1,sizeof(WGPURenderPipeline));
  *pipeline = wgpuDeviceCreateRenderPipeline(*c_device, c_pipelineDesc);
  return to_lean<RenderPipeline>(pipeline);
}

alloy c extern
def RenderPassEncoder.setPipeline (r : RenderPassEncoder) (p : RenderPipeline) : IO Unit := {
  WGPURenderPassEncoder * renderPass = of_lean<RenderPassEncoder>(r);
  WGPURenderPipeline * pipeline = of_lean<RenderPipeline>(r);
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
