import Wgpu.Async
import Alloy.C
open scoped Alloy.C
open IO

namespace Wgpu

alloy c section
  #include <stdio.h>
  #include <stdlib.h>
  #include <lean/lean.h>
  #include <wgpu.h>
  #include <webgpu.h>
end

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
  -- return to_lean<InstanceDescriptor>(desc);
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

/-- # SurfaceConfiguration -/


alloy c opaque_extern_type SurfaceConfiguration  => WGPUSurfaceConfiguration  where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUSurfaceConfiguration \n");
    free(ptr);

alloy c extern
def SurfaceConfiguration.mk (width height : UInt32) (surface : Surface) (adapter : Adapter)
  (device : Device)
  : SurfaceConfiguration := {
  WGPUSurface * c_surface = of_lean<Surface>(surface);
  WGPUAdapter * c_adapter = of_lean<Adapter>(adapter);
  WGPUDevice * c_device = of_lean<Device>(device);
  WGPUTextureFormat surfaceFormat = wgpuSurfaceGetPreferredFormat(*c_surface, *c_adapter);
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
def RenderPassDescriptor.mk (encoder : CommandEncoder) (view : TextureView): IO RenderPassEncoder := {
  lean_inc(encoder);
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

  wgpuRenderPassEncoderEnd(*renderPass);
  lean_obj_res res = lean_io_result_mk_ok(to_lean<RenderPassEncoder>(renderPass));
  return res
}

alloy c extern
def RenderPassEncoder.release (renderPass : RenderPassEncoder) : IO Unit := {
    WGPURenderPassEncoder * render_pass = of_lean<RenderPassEncoder>(renderPass);
    wgpuRenderPassEncoderRelease(*render_pass);
    return lean_io_result_mk_ok(lean_box(0));
}


alloy c extern
def wgpu_playground (l_adapter : WGPUAdapter) : IO Unit := {
  fprintf(stderr, "sizeof command: %lu\n", sizeof(WGPUCommandBuffer));
  WGPUSupportedLimits supportedLimits = {};
  supportedLimits.nextInChain = NULL;
  bool success = wgpuAdapterGetLimits(*of_lean<Adapter>(l_adapter), &supportedLimits);
  if (success) {
      fprintf(stderr, "Adapter limits:\n");
      fprintf(stderr, "  maxTextureDimension1D: %d\n", supportedLimits.limits.maxTextureDimension1D);
      fprintf(stderr, "  maxTextureDimension2D: %d\n", supportedLimits.limits.maxTextureDimension2D);
  }
  return lean_io_result_mk_ok(lean_box(0));
}
