import Wgpu
import Wgpu.Async
import Glfw
import Wgsl.Syntax

open IO
open Wgpu

set_option linter.unusedVariables false

/--
  ComputeDouble: A compute shader that doubles each element in an array.
  Tests: compute pipeline, storage buffers, bind group for storage,
  buffer mapping, copyBufferToBuffer, readback of GPU results.
  Uses a GLFW window + surface just to get a device (same pattern as other examples).
-/

def computeShaderSource : String := !WGSL{
@group(0) @binding(0) var<storage, read> input: array<u32>;
@group(0) @binding(1) var<storage, read_write> output: array<u32>;

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let index = id.x;
    if (index < arrayLength(&input)) {
        output[index] = input[index] * 2u;
    }
}
}

def computeDouble : IO Unit := do
  eprintln "=== Compute Double (GPU Compute) ==="

  setLogCallback fun lvl msg => eprintln s!"[{repr lvl}] {msg}"

  -- We need a window/surface to get an adapter+device (same bootstrap as other examples)
  let window ← GLFWwindow.mk 320 240 "Compute Double"

  let instDesc ← InstanceDescriptor.mk
  let inst ← createInstance instDesc
  let surface ← getSurface inst window

  let adapter ← inst.requestAdapter surface >>= await!
  adapter.printProperties

  let ddesc ← DeviceDescriptor.mk "compute device"
  let device ← adapter.requestDevice ddesc >>= await!
  device.setUncapturedErrorCallback fun code msg => do
    eprintln s!"uncaptured error, code {code}: \"{msg}\""

  let queue ← device.getQueue

  -- Prepare input data: [1, 2, 3, ..., 256]
  let numElements : UInt32 := 256
  let inputArray : Array UInt32 := Array.ofFn fun (i : Fin 256) => i.val.toUInt32 + 1
  let inputBytes := uint32sToByteArray inputArray
  let bufferSize : UInt32 := numElements * 4  -- 4 bytes per u32

  eprintln s!"Input: {numElements} elements, {inputBytes.size} bytes"
  eprintln s!"First 8: {inputArray.toList.take 8}"

  -- Create input storage buffer (read-only from shader, GPU writes via queue)
  let inputBufDesc := BufferDescriptor.mk "input buffer"
    (BufferUsage.storage.lor BufferUsage.copyDst) bufferSize false
  let inputBuffer ← Buffer.mk device inputBufDesc
  queue.writeBuffer inputBuffer inputBytes

  -- Create output storage buffer (read-write from shader, source for copy)
  let outputBufDesc := BufferDescriptor.mk "output buffer"
    (BufferUsage.storage.lor BufferUsage.copySrc) bufferSize false
  let outputBuffer ← Buffer.mk device outputBufDesc

  -- Create staging buffer for readback (mapRead + copyDst)
  let stagingBufDesc := BufferDescriptor.mk "staging buffer"
    (BufferUsage.mapRead.lor BufferUsage.copyDst) bufferSize false
  let stagingBuffer ← Buffer.mk device stagingBufDesc

  -- Bind group layout: binding 0 = read-only storage, binding 1 = read-write storage
  let bindGroupLayout ← BindGroupLayout.mk2Storage device
    0 ShaderStageFlags.compute true   -- binding 0: read-only storage
    1 ShaderStageFlags.compute false  -- binding 1: read-write storage
  let bindGroup ← BindGroup.mk2Buffers device bindGroupLayout 0 inputBuffer 1 outputBuffer

  -- Pipeline
  let pipelineLayout ← PipelineLayout.mk device #[bindGroupLayout]
  let shaderWGSL ← ShaderModuleWGSLDescriptor.mk computeShaderSource
  let shaderDesc ← ShaderModuleDescriptor.mk shaderWGSL
  let shaderModule ← ShaderModule.mk device shaderDesc
  let computePipeline ← device.createComputePipeline shaderModule pipelineLayout "main"

  -- Encode and dispatch compute work + copy output to staging
  let encoder ← device.createCommandEncoder

  let computePass ← encoder.beginComputePass
  computePass.setPipeline computePipeline
  computePass.setBindGroup 0 bindGroup
  -- Dispatch enough workgroups to cover all elements (workgroup_size=64)
  let workgroupCount := (numElements + 63) / 64
  computePass.dispatchWorkgroups workgroupCount
  computePass.end_

  -- Copy output to staging buffer for CPU readback
  encoder.copyBufferToBuffer outputBuffer 0 stagingBuffer 0 bufferSize.toUInt64

  let command ← encoder.finish
  queue.submit #[command]
  eprintln "Submitted compute work"

  -- Map staging buffer and read results
  stagingBuffer.mapRead device
  let resultBytes ← stagingBuffer.getMappedRange
  stagingBuffer.unmap
  let resultArray := byteArrayToUInt32s resultBytes

  eprintln s!"Output: {resultArray.size} elements"
  eprintln s!"First 8: {resultArray.toList.take 8}"
  eprintln s!"Last 8: {resultArray.toList.reverse.take 8 |>.reverse}"

  -- Verify correctness
  let mut correct : UInt32 := 0
  for h : i in [:resultArray.size] do
    if i < inputArray.size then
      if resultArray[i] == inputArray[i]! * 2 then
        correct := correct + 1
  eprintln s!"Verification: {correct}/{numElements} correct"

  if correct == numElements then
    eprintln "✓ All results correct! GPU compute works."
  else
    eprintln "✗ Some results were incorrect."

  -- Cleanup
  inputBuffer.destroy
  outputBuffer.destroy
  stagingBuffer.destroy

  eprintln "=== Done ==="

def main : IO Unit := computeDouble
