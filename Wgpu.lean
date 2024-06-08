import Alloy.C
open scoped Alloy.C

alloy c section
  #include <stdio.h>
  #include <lean/lean.h>
  #include <wgpu.h>
  #include <webgpu.h>
end

alloy c extern
def test (x : UInt32) : IO UInt32 := {
  WGPUInstance *inst = NULL;
  return lean_io_result_mk_ok(lean_box(sizeof(WGPUInstance)));
}

alloy c opaque_extern_type WGPUInstanceDescriptor => WGPUInstanceDescriptor where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUInstanceDescriptor\n");
    free(ptr);

alloy c opaque_extern_type WGPUInstance => WGPUInstance where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUInstance\n");
    wgpuInstanceRelease(*ptr);
    free(ptr);

alloy c opaque_extern_type WGPUAdapter => WGPUAdapter where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUAdapter\n");
    wgpuAdapterRelease(*ptr);
    free(ptr);

alloy c opaque_extern_type WGPUDevice => WGPUDevice where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUDevice\n");
    wgpuDeviceRelease(*ptr);
    free(ptr);

alloy c extern "WGPUInstanceDescriptor_mk"
def WGPUInstanceDescriptor.mk : IO WGPUInstanceDescriptor := {
  fprintf(stderr, "mk WGPUInstanceDescriptor\n");
  WGPUInstanceDescriptor* desc = malloc(sizeof(WGPUInstanceDescriptor));
  desc->nextInChain = NULL;
  return lean_io_result_mk_ok(to_lean<WGPUInstanceDescriptor>(desc));
}

alloy c extern "WGPUInstance_mk"
def WGPUInstance.mk (desc : WGPUInstanceDescriptor) : IO WGPUInstance := {
  fprintf(stderr, "mk WGPUInstance\n");
  WGPUInstance *inst = malloc(sizeof(WGPUInstance));
  *inst = wgpuCreateInstance(of_lean<WGPUInstanceDescriptor>(desc));
  return lean_io_result_mk_ok(to_lean<WGPUInstance>(inst));
}

alloy c section
  typedef struct {
    WGPUAdapter adapter;
    bool requestEnded;
  } AdapterRequest;

  void onAdapterRequestEnded(WGPURequestAdapterStatus status, WGPUAdapter adapter, const char* message, void* pUserData) {
    AdapterRequest* req = (AdapterRequest*)pUserData;
    if (status == WGPURequestAdapterStatus_Success) {
        req->adapter = adapter;
    } else {
        fprintf(stderr, "Could not get WebGPU adapter: %s\n", message);
    }
    req->requestEnded = true;
  }
end

alloy c extern
def WGPUAdapter.mk (l_inst : WGPUInstance) : IO WGPUAdapter := {
  WGPUInstance *inst = of_lean<WGPUInstance>(l_inst);
  WGPURequestAdapterOptions adapterOpts = {};
  AdapterRequest req = {};

  -- Note that the adapter maintains an internal (wgpu) reference to the WGPUInstance, according to the C++ guide: "We will no longer need to use the instance once we have selected our adapter, so we can call wgpuInstanceRelease(instance) right after the adapter request instead of at the very end. The underlying instance object will keep on living until the adapter gets released but we do not need to manager this."
  wgpuInstanceRequestAdapter(
      *inst,
      &adapterOpts,
      onAdapterRequestEnded,
      (void*)&req
  );

  assert(req.requestEnded); -- wgpu_native wgpuInstanceRequestAdapter is guaranteed to call its callback before it returns. Not the case for emscripten tho.
  WGPUAdapter *a = (WGPUAdapter*)malloc(sizeof(WGPUAdapter));
  *a = req.adapter;
  return lean_io_result_mk_ok(to_lean<WGPUAdapter>(a));
}

alloy c section
    typedef struct  {
        WGPUDevice device;
        bool requestEnded;
    } DeviceRequest ;

  void onDeviceRequestEnded (WGPURequestDeviceStatus  status, WGPUDevice device, const char* message, void* pUserData) {
    DeviceRequest* userData = (DeviceRequest*)(pUserData);
        if (status == WGPURequestDeviceStatus_Success) {
            userData->device = device;
        } else {
            fprintf(stderr, "Could not get WebGPU device:  %s\n",message);
        }
        userData->requestEnded = true;
  }

  void onDeviceLostCallback(WGPUDeviceLostReason reason, char const* message, void* pUserData) {
      fprintf(stderr, "Device lost: reason %d\n",reason);
      if (message) fprintf(stderr, "%s", message);
      fprintf(stderr, "\n");
  }

  void onDeviceError(WGPUErrorType type, char const* message, void* pUserData) {
    fprintf(stderr, "Uncaptured device error: type %d\n",type);
    if (message) fprintf(stderr, " (%s) ", message);
    fprintf(stderr, "\n");
  }



end

alloy c extern
def WGPUDevice.mk (l_adapter : WGPUAdapter) : IO WGPUDevice := {
  WGPUAdapter *adapter = of_lean<WGPUAdapter>(l_adapter);
  WGPUDeviceDescriptor  deviceOpts = {};
  deviceOpts.deviceLostCallback = onDeviceLostCallback;
  DeviceRequest req = {};

  -- Note that the adapter maintains an internal (wgpu) reference to the WGPUInstance, according to the C++ guide: "We will no longer need to use the instance once we have selected our adapter, so we can call wgpuInstanceRelease(instance) right after the adapter request instead of at the very end. The underlying instance object will keep on living until the adapter gets released but we do not need to manager this."
  wgpuAdapterRequestDevice(
      *adapter,
      &deviceOpts,
      onDeviceRequestEnded,
      (void*)&req
  );

  assert(req.requestEnded); -- wgpu_native wgpuInstanceRequestAdapter is guaranteed to call its callback before it returns. Not the case for emscripten tho.
  WGPUDevice *device = (WGPUDevice*)malloc(sizeof(WGPUDevice));
  *device = req.device;
  wgpuDeviceSetUncapturedErrorCallback(*device, onDeviceError, NULL);
  return lean_io_result_mk_ok(to_lean<WGPUDevice>(device));
}

alloy c extern
def WGPUDevice.inspect(l_device : WGPUDevice): IO Unit := {
    WGPUDevice *device = of_lean<WGPUDevice>(l_device);
    -- std::vector<WGPUFeatureName> features;
    -- size_t featureCount = wgpuDeviceEnumerateFeatures(device, nullptr);
    -- features.resize(featureCount);
    -- wgpuDeviceEnumerateFeatures(device, features.data());

    -- std::cout << "Device features:" << std::endl;
    -- std::cout << std::hex;
    -- for (auto f : features) {
    --     std::cout << " - 0x" << f << std::endl;
    -- }
    -- std::cout << std::dec;

    WGPUSupportedLimits limits = {};
    limits.nextInChain = NULL;
    bool success = wgpuDeviceGetLimits(*device, &limits);
    if (success) {
        fprintf(stderr, "Device limits:\n");
        fprintf(stderr, "- maxTextureDimension1D: %i\n",limits.limits.maxTextureDimension1D);
        fprintf(stderr, "- maxTextureDimension2D: %i\n",limits.limits.maxTextureDimension2D);
        fprintf(stderr, "- maxTextureDimension3D: %i\n",limits.limits.maxTextureDimension3D);
        fprintf(stderr, "- maxTextureArrayLayers: %i\n",limits.limits.maxTextureArrayLayers);
        {{}}
    }
}

set_option linter.unusedVariables false in
def triangle (_ : UInt32) : IO UInt32 := do
  let desc <- WGPUInstanceDescriptor.mk
  let inst <- WGPUInstance.mk desc
  let adapter <- WGPUAdapter.mk inst -- releasing the adapter as soon as the device is constructed is good convention, TODO add FFI to release and use it
  let device ← WGPUDevice.mk adapter
  device.inspect
  return 0
