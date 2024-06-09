import Glfw
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
  #include <GLFW/glfw3.h>
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

alloy c opaque_extern_type InstanceDescriptor => WGPUInstanceDescriptor where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUInstanceDescriptor\n");
    free(ptr);

alloy c opaque_extern_type Instance => WGPUInstance where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUInstance\n");
    wgpuInstanceRelease(*ptr);
    free(ptr);

alloy c opaque_extern_type Adapter => WGPUAdapter where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUAdapter\n");
    wgpuAdapterRelease(*ptr);
    free(ptr);

alloy c extern
def InstanceDescriptor.mk : IO InstanceDescriptor := {
  fprintf(stderr, "mk WGPUInstanceDescriptor\n");
  WGPUInstanceDescriptor* desc = malloc(sizeof(WGPUInstanceDescriptor));
  desc->nextInChain = NULL;
  -- return to_lean<InstanceDescriptor>(desc);
  return lean_io_result_mk_ok(to_lean<InstanceDescriptor>(desc));
}

-- instance : Inhabited InstanceDescriptor where default := .mk

alloy c extern
def createInstance (desc : InstanceDescriptor) : IO Instance := {
  fprintf(stderr, "mk WGPUInstance\n");
  WGPUInstance *inst = malloc(sizeof(WGPUInstance));
  *inst = wgpuCreateInstance(of_lean<InstanceDescriptor>(desc)); -- ! RealWorld
  return lean_io_result_mk_ok(to_lean<Instance>(inst));
}

alloy c section
  void onAdapterRequestEnded(WGPURequestAdapterStatus status, WGPUAdapter adapter, const char* message, void* promise) {
    if (status == WGPURequestAdapterStatus_Success) {
      WGPUAdapter *a = (WGPUAdapter*)malloc(sizeof(WGPUAdapter));
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
-- def WGPUAdapter.mk (l_inst : WGPUInstance) : IO (Promise (EStateM.Result IO.Error IO.RealWorld WGPUAdapter)) := {
def Instance.requestAdapter (l_inst : Instance) : IO (A (Result Adapter)) := {
  WGPUInstance *inst = of_lean<Instance>(l_inst);
  WGPURequestAdapterOptions adapterOpts = {};

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

alloy c extern
def wgpu_playground (l_adapter : WGPUAdapter) : IO Unit := {
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

alloy c extern
def glfw_playground : IO Unit := {
  glfwInit();
  return lean_io_result_mk_ok(lean_box(0));
}

def triangle : IO Unit := do
  let desc <- InstanceDescriptor.mk
  let inst <- createInstance desc
  let adapter <- inst.requestAdapter >>= await!
  wgpu_playground adapter

  -- glfw_playground
  -- let window ← GLFWwindow.mk 640 480
  -- while not (← window.shouldClose) do
  --   println! "polling"
  --   GLFW.pollEvents
  -- return
