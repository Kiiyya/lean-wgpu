import Alloy.C
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
  typedef struct {
    lean_object *result;
  } wgpu_callback_data;
end

/- # BufferDescriptor -/

alloy c opaque_extern_type BufferDescriptor => WGPUBufferDescriptor where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUBufferDescriptor \n");
    if (ptr->label) free((void*)ptr->label);
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

/-- Create a buffer descriptor. The label string is copied (strdup) so it is
    safe to use even if the original String is GC'd. -/
alloy c extern
def BufferDescriptor.mk (label : String) (usage : BufferUsage)
  (size : UInt32) (mappedAtCreation : Bool) : BufferDescriptor := {
  WGPUBufferDescriptor * bufferDesc = calloc(1,sizeof(WGPUBufferDescriptor));
  bufferDesc->nextInChain = NULL;
  bufferDesc->label = strdup(lean_string_cstr(label));
  bufferDesc->usage = usage;
  bufferDesc->size = size;
  bufferDesc->mappedAtCreation = mappedAtCreation;
  return to_lean<BufferDescriptor>(bufferDesc);
  }

/- # Buffer -/

alloy c opaque_extern_type Buffer => WGPUBuffer where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUBuffer \n");
    if (*ptr) {
      wgpuBufferDestroy(*ptr);
      wgpuBufferRelease(*ptr);
    }
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
def Buffer.getSize (buffer : Buffer) : IO UInt64 := {
    WGPUBuffer c_buffer = *of_lean<Buffer>(buffer);
    uint64_t sz = wgpuBufferGetSize(c_buffer);
    return lean_io_result_mk_ok(lean_box_uint64(sz));
}

/-- Destroy a buffer's GPU resources immediately.
    NOTE: The finalizer also calls destroy+release, so this is optional.
    Use it to reclaim GPU memory earlier than GC would. -/
alloy c extern
def Buffer.destroy (buffer : Buffer) : IO Unit := {
    WGPUBuffer *c_buffer = of_lean<Buffer>(buffer);
    if (*c_buffer) {
      wgpuBufferDestroy(*c_buffer);
      *c_buffer = NULL;
    }
    return lean_io_result_mk_ok(lean_box(0));
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

/- ################################################################## -/
/- # Writable Buffer Mapping                                          -/
/- ################################################################## -/

/-- Map a buffer for writing. Blocks until mapping is complete by polling the device. -/
alloy c extern
def Buffer.mapWrite (buffer : Buffer) (device : Device) (offset : UInt64 := 0) (size : UInt64 := 0) : IO Unit := {
  WGPUBuffer *c_buffer = of_lean<Buffer>(buffer);
  WGPUDevice *c_device = of_lean<Device>(device);
  uint64_t mapSize = size;
  if (mapSize == 0) {
    mapSize = wgpuBufferGetSize(*c_buffer) - offset;
  }
  wgpu_callback_data cb_data = {0};
  wgpuBufferMapAsync(*c_buffer, WGPUMapMode_Write, offset, mapSize, onBufferMappedCallback, &cb_data);
  while (cb_data.result == NULL) {
    wgpuDevicePoll(*c_device, true, NULL);
  }
  return cb_data.result;
}

/-- Get the writable mapped range of a buffer and write data to it.
    This copies the ByteArray content into the mapped GPU memory. -/
alloy c extern
def Buffer.writeMappedRange (buffer : Buffer) (data : @& ByteArray) (offset : UInt64 := 0) : IO Unit := {
  WGPUBuffer *c_buffer = of_lean<Buffer>(buffer);
  uint64_t mapSize = lean_sarray_size(data);
  void *ptr = wgpuBufferGetMappedRange(*c_buffer, offset, mapSize);
  if (ptr == NULL) {
    return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string("writeMappedRange: getMappedRange returned NULL")));
  }
  memcpy(ptr, lean_sarray_cptr(data), mapSize);
  return lean_io_result_mk_ok(lean_box(0));
}

/- ################################################################## -/
/- # SetLabel Functions                                               -/
/- ################################################################## -/

/-- Set the debug label of a buffer. -/
alloy c extern
def Buffer.setLabel (buffer : Buffer) (label : @& String) : IO Unit := {
  WGPUBuffer *c_buffer = of_lean<Buffer>(buffer);
  wgpuBufferSetLabel(*c_buffer, lean_string_cstr(label));
  return lean_io_result_mk_ok(lean_box(0));
}

end Wgpu
