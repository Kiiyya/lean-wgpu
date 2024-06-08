import Alloy.C
open scoped Alloy.C
open IO

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
  -- hacky. Copied from the compiled output from lean runtime
  extern lean_object* lean_io_promise_new(lean_object* seemsNotUsed);
  extern lean_object* lean_io_promise_resolve(lean_object* value, lean_object* promise, lean_object* seemsNotUsed);

  -- void log_obj_(lean_object *obj) {
  --   fprintf(stderr, "tag is %s\n", obj->m_tag);
  -- }
end

alloy c section
  void onAdapterRequestEnded(WGPURequestAdapterStatus status, WGPUAdapter adapter, const char* message, void* l_promise) {
    fprintf(stderr, "onAdapterRequestEnded 0\n");
    lean_task_object *promise = lean_to_task((lean_object*) l_promise); -- lean_to_task downcasts with assert
    fprintf(stderr, "onAdapterRequestEnded 1\n");
    if (status == WGPURequestAdapterStatus_Success) {
      fprintf(stderr, "onAdapterRequestEnded 2\n");

      WGPUAdapter *a = (WGPUAdapter*)malloc(sizeof(WGPUAdapter));
      *a = adapter;
      lean_object* l_adapter = to_lean<WGPUAdapter>(a);
      fprintf(stderr, "onAdapterRequestEnded 3\n");

      lean_io_promise_resolve(l_adapter, (lean_object*)promise, NULL);
      fprintf(stderr, "onAdapterRequestEnded 4\n");
    } else {
      fprintf(stderr, "Could not get WebGPU adapter: %s\n", message);
    }
  }
end

alloy c extern "WGPUAdapter_mk"
def WGPUAdapter.mk (l_inst : WGPUInstance) : IO (Promise WGPUAdapter) := {
  WGPUInstance *inst = of_lean<WGPUInstance>(l_inst);
  WGPURequestAdapterOptions adapterOpts = {};

  fprintf(stderr, "WGPUAdapter_mk 1\n");
  lean_task_object *promise = lean_to_task(lean_io_promise_new(NULL)); -- promise : `Promise WGPUAdapter`
  fprintf(stderr, "promise tag is %d\n", lean_ptr_tag((lean_object*) promise)); -- prints 0, but the assert above passes? wtf?
  fprintf(stderr, "WGPUAdapter_mk 2\n");

  -- Note that the adapter maintains an internal (wgpu) reference to the WGPUInstance, according to the C++ guide: "We will no longer need to use the instance once we have selected our adapter, so we can call wgpuInstanceRelease(instance) right after the adapter request instead of at the very end. The underlying instance object will keep on living until the adapter gets released but we do not need to manager this."
  wgpuInstanceRequestAdapter(
      *inst,
      &adapterOpts,
      onAdapterRequestEnded,
      (void*)&promise
  );
  fprintf(stderr, "WGPUAdapter_mk 3\n");

  return lean_io_result_mk_ok((lean_object*) promise);
  -- assert(req.requestEnded); -- wgpu_native wgpuInstanceRequestAdapter is guaranteed to call its callback before it returns. Not the case for emscripten tho.
  -- WGPUAdapter *a = (WGPUAdapter*)malloc(sizeof(WGPUAdapter));
  -- *a = req.adapter;
  -- return lean_io_result_mk_ok(to_lean<WGPUAdapter>(a));
}

alloy c extern
def rawr (l_adapter : WGPUAdapter) : IO Unit := {
  WGPUSupportedLimits supportedLimits = {};
  supportedLimits.nextInChain = NULL;
  bool success = wgpuAdapterGetLimits(*of_lean<WGPUAdapter>(l_adapter), &supportedLimits);
  if (success) {
      fprintf(stderr, "Adapter limits:\n");
      fprintf(stderr, "  maxTextureDimension1D: %d\n", supportedLimits.limits.maxTextureDimension1D);
      fprintf(stderr, "  maxTextureDimension2D: %d\n", supportedLimits.limits.maxTextureDimension2D);
  }
  return lean_io_result_mk_ok(lean_box(0));
}

set_option linter.unusedVariables false in
def triangle : IO Unit := do
  let desc <- WGPUInstanceDescriptor.mk
  let inst <- WGPUInstance.mk desc
  let adapter : Promise WGPUAdapter <- WGPUAdapter.mk inst
  eprintln "created adapter promise!"
  rawr adapter.result.get
