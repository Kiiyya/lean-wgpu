import Alloy.C
open scoped Alloy.C

alloy c section
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
  finalize(ptr) := free(ptr);

alloy c opaque_extern_type WGPUInstance => WGPUInstance where
  finalize(ptr) := free(ptr);

alloy c opaque_extern_type WGPUAdapter => WGPUAdapter where
  finalize(ptr) := free(ptr);

alloy c extern "WGPUInstanceDescriptor_mk"
def WGPUInstanceDescriptor.mk: IO WGPUInstanceDescriptor:= {
  WGPUInstanceDescriptor* desc = malloc(sizeof(WGPUInstanceDescriptor));
  desc->nextInChain = NULL;
  return to_lean<WGPUInstanceDescriptor>(desc);
}

alloy c extern "WGPUInstance_mk"
def WGPUInstance.mk (desc : WGPUInstanceDescriptor): WGPUInstance:= {
  WGPUInstance *inst = malloc(sizeof(WGPUInstance));
  *inst = wgpuCreateInstance(of_lean<WGPUInstanceDescriptor>(desc));
  return to_lean<WGPUInstance>(inst)
}

alloy c section
  int add(int a, int b) {
    return a + b;
  }
end


-- alloy c section
--    struct UserData {
--         WGPUAdapter adapter;
--         bool requestEnded;
--     };

--   void onAdapterRequestEnded(WGPURequestAdapterStatus status, WGPUAdapter adapter, const char* message, void* pUserData) {
--       UserData* userData = (UserData*)pUserData;
--       if (status == WGPURequestAdapterStatus_Success) {
--           userData->adapter = adapter;
--       } else {
--           printf("Could not get WebGPU adapter: %s\n", message);
--       }
--       userData->requestEnded = true;
--   }
-- end

-- alloy c extern
-- def requestAdapterSync (inst: WGPUInstance) : WGPUAdapter := {

--     UserData userData;
--     userData.adapter = nullptr;
--     userData.requestEnded = false;

--     wgpuInstanceRequestAdapter(
--         inst,
--         nullptr,
--         onAdapterRequestEnded,
--         (void*)&userData
--     );

--     assert(userData.requestEnded);

--     return userData.adapter;
-- }

alloy c extern
def helloworld (n : UInt32) : IO UInt32 := {
  -- We create a descriptor
  WGPUInstanceDescriptor * desc = of_lean<WGPUInstanceDescriptor>(WGPUInstanceDescriptor_mk(NULL));
  int res = add(1, 3);
  return lean_io_result_mk_ok(lean_box(1));

  -- Comment the following three lines out to make it build just fine:
  -- WGPUInstance inst = l_WGPUInstance_mk(desc);
  -- if (!inst) { return lean_io_result_mk_error(lean_box(1)); }
  -- wgpuInstanceRelease(inst);

  -- uint32_t p = (uint32_t) inst;
  -- return lean_io_result_mk_ok(lean_box(p));
}
