import Alloy.C
import Wgpu.Command
import Wgpu.Pipeline
import Wgpu.Buffer
import Wgpu.Device
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
  static inline WGPUDevice* _alloy_of_l_Wgpu_Device(b_lean_obj_arg o) { return (WGPUDevice*)lean_get_external_data(o); }
  static inline WGPUShaderModule* _alloy_of_l_Wgpu_ShaderModule(b_lean_obj_arg o) { return (WGPUShaderModule*)lean_get_external_data(o); }
  static inline WGPUPipelineLayout* _alloy_of_l_Wgpu_PipelineLayout(b_lean_obj_arg o) { return (WGPUPipelineLayout*)lean_get_external_data(o); }
  static inline WGPUCommandEncoder* _alloy_of_l_Wgpu_CommandEncoder(b_lean_obj_arg o) { return (WGPUCommandEncoder*)lean_get_external_data(o); }
  static inline WGPUBindGroup* _alloy_of_l_Wgpu_BindGroup(b_lean_obj_arg o) { return (WGPUBindGroup*)lean_get_external_data(o); }
  static inline WGPUBuffer* _alloy_of_l_Wgpu_Buffer(b_lean_obj_arg o) { return (WGPUBuffer*)lean_get_external_data(o); }
  static inline WGPUQuerySet* _alloy_of_l_Wgpu_QuerySet(b_lean_obj_arg o) { return (WGPUQuerySet*)lean_get_external_data(o); }
  typedef struct {
    lean_object *result;
  } wgpu_callback_data;
  static lean_external_class* _xfile_class_bindgrouplayout = NULL;
  static void _xfile_finalize_bindgrouplayout(void* ptr) { WGPUBindGroupLayout* p = (WGPUBindGroupLayout*)ptr; wgpuBindGroupLayoutRelease(*p); free(p); }
  static void _xfile_foreach_bindgrouplayout(void* ptr, b_lean_obj_arg f) { }
  static inline lean_obj_res _alloy_to_l_Wgpu_BindGroupLayout(WGPUBindGroupLayout* o) {
    if (_xfile_class_bindgrouplayout == NULL) {
      _xfile_class_bindgrouplayout = lean_register_external_class(
        (void(*)(void*))_xfile_finalize_bindgrouplayout,
        (void(*)(void*, b_lean_obj_arg))_xfile_foreach_bindgrouplayout);
    }
    return lean_alloc_external(_xfile_class_bindgrouplayout, o);
  }
end

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

alloy c extern
def ComputePipeline.getBindGroupLayout (pipeline : ComputePipeline) (groupIndex : UInt32)
    : IO BindGroupLayout := {
  WGPUComputePipeline *c_pipeline = of_lean<ComputePipeline>(pipeline);
  WGPUBindGroupLayout *layout = calloc(1, sizeof(WGPUBindGroupLayout));
  *layout = wgpuComputePipelineGetBindGroupLayout(*c_pipeline, groupIndex);
  return lean_io_result_mk_ok(to_lean<BindGroupLayout>(layout));
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

alloy c extern
def ComputePipeline.setLabel (pipeline : ComputePipeline) (label : @& String) : IO Unit := {
  WGPUComputePipeline *c_pipeline = of_lean<ComputePipeline>(pipeline);
  wgpuComputePipelineSetLabel(*c_pipeline, lean_string_cstr(label));
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set the debug label of a command encoder. -/
alloy c extern
def ComputePassEncoder.setLabel (enc : ComputePassEncoder) (label : @& String) : IO Unit := {
  WGPUComputePassEncoder *c_enc = of_lean<ComputePassEncoder>(enc);
  wgpuComputePassEncoderSetLabel(*c_enc, lean_string_cstr(label));
  return lean_io_result_mk_ok(lean_box(0));
}

/- ################################################################## -/
/- # Pipeline Statistics Queries (wgpu-native extension)              -/
/- ################################################################## -/

/-- Begin a pipeline statistics query in a compute pass. -/
alloy c extern
def ComputePassEncoder.beginPipelineStatisticsQuery (enc : ComputePassEncoder) (qs : QuerySet) (queryIndex : UInt32) : IO Unit := {
  WGPUComputePassEncoder *c_enc = of_lean<ComputePassEncoder>(enc);
  WGPUQuerySet *c_qs = of_lean<QuerySet>(qs);
  wgpuComputePassEncoderBeginPipelineStatisticsQuery(*c_enc, *c_qs, queryIndex);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- End a pipeline statistics query in a compute pass. -/
alloy c extern
def ComputePassEncoder.endPipelineStatisticsQuery (enc : ComputePassEncoder) : IO Unit := {
  WGPUComputePassEncoder *c_enc = of_lean<ComputePassEncoder>(enc);
  wgpuComputePassEncoderEndPipelineStatisticsQuery(*c_enc);
  return lean_io_result_mk_ok(lean_box(0));
}

/- ################################################################## -/
/- # Async Pipeline Creation                                          -/
/- ################################################################## -/

alloy c section
  static void create_compute_pipeline_async_cb(
      WGPUCreatePipelineAsyncStatus status, WGPUComputePipeline pipeline,
      const char *message, void *userdata) {
    wgpu_callback_data *data = (wgpu_callback_data*)userdata;
    if (status == WGPUCreatePipelineAsyncStatus_Success) {
      WGPUComputePipeline *p = calloc(1, sizeof(WGPUComputePipeline));
      *p = pipeline;
      data->result = lean_io_result_mk_ok(to_lean<ComputePipeline>(p));
    } else {
      lean_object *errMsg = lean_mk_string(message ? message : "async compute pipeline creation failed");
      data->result = lean_io_result_mk_error(lean_mk_io_user_error(errMsg));
    }
  }

  -- Note: wgpuDeviceCreateRenderPipelineAsync requires a complex descriptor
  -- that is constructed by existing high-level helpers (e.g. createRenderPipeline).
  -- The async render pipeline callback is omitted here for now.
end

/-- Create a compute pipeline asynchronously. Returns a Task result. -/
alloy c extern
def Device.createComputePipelineAsync (device : Device)
    (shaderModule : ShaderModule) (pipelineLayout : PipelineLayout)
    (entryPoint : @& String) : IO (Task (Result ComputePipeline)) := {
  WGPUDevice *c_device = of_lean<Device>(device);
  WGPUShaderModule *c_sm = of_lean<ShaderModule>(shaderModule);
  WGPUPipelineLayout *c_layout = of_lean<PipelineLayout>(pipelineLayout);

  WGPUComputePipelineDescriptor desc = {};
  desc.compute.module = *c_sm;
  desc.compute.entryPoint = lean_string_cstr(entryPoint);
  desc.layout = *c_layout;

  wgpu_callback_data cb_data = {0};
  wgpuDeviceCreateComputePipelineAsync(*c_device, &desc, create_compute_pipeline_async_cb, &cb_data);

  -- wgpu-native calls this synchronously, so cb_data.result is already set
  if (cb_data.result == NULL) {
    -- Poll until complete
    for (int i = 0; i < 1000 && cb_data.result == NULL; i++) {
      wgpuDevicePoll(*c_device, false, NULL);
    }
    if (cb_data.result == NULL) {
      cb_data.result = lean_io_result_mk_error(lean_mk_io_user_error(
        lean_mk_string("createComputePipelineAsync: timed out")));
    }
  }
  lean_object *task = lean_task_pure(cb_data.result);
  return lean_io_result_mk_ok(task);
}

/- ################################################################## -/
/- # Instance.createSurface (headless / non-GLFW surface creation)    -/
/- ################################################################## -/


end Wgpu
