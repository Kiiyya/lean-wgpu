import Alloy.C
import Wgpu.Device
import Wgpu.Buffer
import Wgpu.Texture
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
  static inline WGPUBuffer* _alloy_of_l_Wgpu_Buffer(b_lean_obj_arg o) { return (WGPUBuffer*)lean_get_external_data(o); }
  static inline WGPUTexture* _alloy_of_l_Wgpu_Texture(b_lean_obj_arg o) { return (WGPUTexture*)lean_get_external_data(o); }
  static inline WGPUTextureFormat _alloy_of_l_TextureFormat(uint8_t v) { return (WGPUTextureFormat)v; }
end

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

/- ################################################################## -/
/- # Query Sets & Timestamps (GPU Profiling)                          -/
/- ################################################################## -/

alloy c enum QueryType => WGPUQueryType
| Occlusion  => WGPUQueryType_Occlusion
| Timestamp  => WGPUQueryType_Timestamp
deriving Inhabited, Repr, BEq

alloy c opaque_extern_type QuerySet => WGPUQuerySet where
  finalize(ptr) :=
    if (*ptr) {
      wgpuQuerySetDestroy(*ptr);
      wgpuQuerySetRelease(*ptr);
    }
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

/-- Destroy a query set's GPU resources immediately.
    NOTE: The finalizer also calls destroy+release, so this is optional.
    Use it to reclaim GPU memory earlier than GC would. -/
alloy c extern
def QuerySet.destroy (qs : QuerySet) : IO Unit := {
  WGPUQuerySet *c_qs = of_lean<QuerySet>(qs);
  if (*c_qs) {
    wgpuQuerySetDestroy(*c_qs);
    *c_qs = NULL;
  }
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

alloy c extern
def CommandEncoder.setLabel (encoder : CommandEncoder) (label : @& String) : IO Unit := {
  WGPUCommandEncoder *c_encoder = of_lean<CommandEncoder>(encoder);
  wgpuCommandEncoderSetLabel(*c_encoder, lean_string_cstr(label));
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set the debug label of a command buffer. -/
alloy c extern
def Command.setLabel (command : Command) (label : @& String) : IO Unit := {
  WGPUCommandBuffer *c_cmd = of_lean<Command>(command);
  wgpuCommandBufferSetLabel(*c_cmd, lean_string_cstr(label));
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set the debug label of a shader module. -/
alloy c extern
def Queue.setLabel (queue : Queue) (label : @& String) : IO Unit := {
  WGPUQueue *c_queue = of_lean<Queue>(queue);
  wgpuQueueSetLabel(*c_queue, lean_string_cstr(label));
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set the debug label of a render pass encoder. -/
alloy c extern
def QuerySet.setLabel (qs : QuerySet) (label : @& String) : IO Unit := {
  WGPUQuerySet *c_qs = of_lean<QuerySet>(qs);
  wgpuQuerySetSetLabel(*c_qs, lean_string_cstr(label));
  return lean_io_result_mk_ok(lean_box(0));
}

/- ################################################################## -/
/- # Queue.submitForIndex (wgpu-native extension)                     -/
/- ################################################################## -/

/-- Submit commands and return a submission index that can be used for finer-grained polling. -/
alloy c extern
def Queue.submitForIndex (queue : Queue) (commands : @& Array Command) : IO UInt64 := {
  WGPUQueue *c_queue = of_lean<Queue>(queue);
  size_t n = lean_array_size(commands);
  WGPUCommandBuffer *arr = calloc(n, sizeof(WGPUCommandBuffer));
  for (size_t i = 0; i < n; i++) {
    lean_object *command = lean_array_uget(commands, i);
    WGPUCommandBuffer *c_command = of_lean<Command>(command);
    arr[i] = *c_command;
  }
  WGPUSubmissionIndex idx = wgpuQueueSubmitForIndex(*c_queue, n, arr);
  free(arr);
  return lean_io_result_mk_ok(lean_box_uint64(idx));
}

end Wgpu
