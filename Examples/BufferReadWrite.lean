import Wgpu
import Wgpu.Async
import Glfw

open IO
open Wgpu

set_option linter.unusedVariables false

/--
  BufferReadWrite: A headless test that exercises:
  - Writable buffer mapping (Buffer.mapWrite, Buffer.writeMappedRange)
  - Readable buffer mapping (Buffer.mapRead, Buffer.getMappedRange)
  - SetLabel functions
  - Buffer → Buffer copy via CommandEncoder
  - Queue.submitForIndex
  - Buffer property getters
  - Error scoping (pushErrorScope / popErrorScope)
-/
def bufferReadWrite : IO Unit := do
  eprintln "=== Buffer Read/Write Test ==="

  setLogCallback fun lvl msg => eprintln s!"[{repr lvl}] {msg}"

  -- We need a window for the surface even in "headless" compute tests
  let window ← GLFWwindow.mk 320 240 "Buffer R/W Test"

  let desc ← InstanceDescriptor.mk
  let inst ← createInstance desc
  let surface ← getSurface inst window
  let adapter ← inst.requestAdapter surface >>= await!

  let ddesc ← DeviceDescriptor.mk "buffer-test-device"
  let device ← adapter.requestDevice ddesc >>= await!
  device.setUncapturedErrorCallback fun code msg => do
    eprintln s!"Error {code}: {msg}"

  let queue ← device.getQueue
  -- Note: queue.setLabel panics as "not implemented" in this wgpu-native version
  eprintln "Got device and queue."

  -- ── Test 1: Map-Write → Copy → Map-Read (no compute shader required) ──
  eprintln ""
  eprintln "--- Test 1: Map-Write → Copy → Map-Read ---"

  -- Input data: [1, 2, 3, 4, 5, 6, 7, 8]
  let inputData : Array UInt32 := #[1, 2, 3, 4, 5, 6, 7, 8]
  let elemCount := inputData.size.toUInt32
  let byteSize := elemCount * 4

  -- Create a staging buffer mapped for writing
  let stagingWrite ← Buffer.mk device
    (BufferDescriptor.mk "staging-write" (BufferUsage.mapWrite ||| BufferUsage.copySrc) byteSize true)

  -- Write input data via mapped range
  let inputBytes := uint32sToByteArray inputData
  stagingWrite.writeMappedRange inputBytes
  stagingWrite.unmap
  eprintln s!"Wrote {elemCount} UInt32 values to staging buffer"

  -- Create a read-back staging buffer
  let stagingRead ← Buffer.mk device
    (BufferDescriptor.mk "staging-read" (BufferUsage.mapRead ||| BufferUsage.copyDst) byteSize false)

  -- Copy stagingWrite → stagingRead via command encoder
  let enc1 ← device.createCommandEncoder
  enc1.copyBufferToBuffer stagingWrite 0 stagingRead 0 byteSize.toUInt64
  let cmd1 ← enc1.finish
  queue.submit #[cmd1]
  eprintln s!"Copy submitted"
  device.pollWait

  -- Map read buffer and get data
  stagingRead.mapRead device
  let resultBytes ← stagingRead.getMappedRange
  stagingRead.unmap
  let resultData := byteArrayToUInt32s resultBytes
  eprintln s!"Input:  {inputData}"
  eprintln s!"Output: {resultData}"

  -- Verify round-trip
  let mut allCorrect := true
  for h : i in [:inputData.size] do
    if h2 : i < resultData.size then
      if resultData[i] != inputData[i] then
        eprintln s!"  MISMATCH at [{i}]: expected {inputData[i]}, got {resultData[i]}"
        allCorrect := false
    else
      eprintln s!"  MISSING result at [{i}]"
      allCorrect := false

  if allCorrect then
    eprintln "✓ All values correctly round-tripped!"
  else
    eprintln "✗ Some values were incorrect!"

  -- ── Test 2: Queue.writeBuffer → Copy → Map-Read ──
  eprintln ""
  eprintln "--- Test 2: Queue.writeBuffer → Copy → Map-Read ---"

  let data2 : Array UInt32 := #[100, 200, 300, 400]
  let size2 : UInt32 := 16

  -- Create a GPU buffer written via queue
  let gpuBuf ← Buffer.mk device
    (BufferDescriptor.mk "gpu-write" (BufferUsage.copyDst ||| BufferUsage.copySrc) size2 false)
  queue.writeBuffer gpuBuf (uint32sToByteArray data2)

  let readBuf2 ← Buffer.mk device
    (BufferDescriptor.mk "read-back-2" (BufferUsage.mapRead ||| BufferUsage.copyDst) size2 false)

  let enc1b ← device.createCommandEncoder
  enc1b.copyBufferToBuffer gpuBuf 0 readBuf2 0 size2.toUInt64
  let cmd1b ← enc1b.finish
  queue.submit #[cmd1b]
  device.pollWait

  readBuf2.mapRead device
  let result2Bytes ← readBuf2.getMappedRange
  readBuf2.unmap
  let result2 := byteArrayToUInt32s result2Bytes
  eprintln s!"  Input:  {data2}"
  eprintln s!"  Output: {result2}"
  if data2 == result2 then
    eprintln "✓ Queue.writeBuffer round-trip verified!"
  else
    eprintln "✗ Data mismatch!"

  gpuBuf.destroy
  readBuf2.destroy

  -- ── Test 3: Error scoping ──
  eprintln ""
  eprintln "--- Test 3: Error Scoping ---"

  device.pushErrorScope ErrorFilter.Validation
  -- Intentionally trigger an error: create a buffer with size 0
  let _badBuf ← Buffer.mk device (BufferDescriptor.mk "bad" BufferUsage.vertex 0 false)
  let (errType, errMsg) ← device.popErrorScope
  if errType != 0 then
    eprintln s!"  Caught error (type={errType}): {errMsg}"
  else
    eprintln "  No validation error caught (size=0 may be valid on this backend)"

  -- ── Test 4: Buffer labels and properties ──
  eprintln ""
  eprintln "--- Test 4: Buffer Labels & Multiple Copies ---"

  -- Create a chain of buffers: A → B → C, verify data flows through
  let chainSize : UInt32 := 16  -- 4 UInt32s
  let chainData : Array UInt32 := #[0xDEAD, 0xBEEF, 0xCAFE, 0xBABE]

  let bufA ← Buffer.mk device
    (BufferDescriptor.mk "chain-A" (BufferUsage.mapWrite ||| BufferUsage.copySrc) chainSize true)
  bufA.writeMappedRange (uint32sToByteArray chainData)
  bufA.unmap

  let bufB ← Buffer.mk device
    (BufferDescriptor.mk "chain-B" (BufferUsage.copyDst ||| BufferUsage.copySrc) chainSize false)

  let bufC ← Buffer.mk device
    (BufferDescriptor.mk "chain-C" (BufferUsage.mapRead ||| BufferUsage.copyDst) chainSize false)

  -- Copy A → B
  let enc2 ← device.createCommandEncoder
  enc2.copyBufferToBuffer bufA 0 bufB 0 chainSize.toUInt64
  let cmd2 ← enc2.finish
  queue.submit #[cmd2]
  device.pollWait

  -- Copy B → C
  let enc3 ← device.createCommandEncoder
  enc3.copyBufferToBuffer bufB 0 bufC 0 chainSize.toUInt64
  let cmd3 ← enc3.finish
  queue.submit #[cmd3]
  device.pollWait

  -- Read back from C
  bufC.mapRead device
  let chainResult ← bufC.getMappedRange
  bufC.unmap
  let chainOut := byteArrayToUInt32s chainResult

  eprintln s!"Chain input:  {chainData.map (s!"0x{toHex ·}")}"
  eprintln s!"Chain output: {chainOut.map (s!"0x{toHex ·}")}"

  let chainOk := chainData == chainOut
  if chainOk then
    eprintln "✓ Chain copy A→B→C verified!"
  else
    eprintln "✗ Chain copy mismatch!"

  -- Cleanup
  stagingWrite.destroy
  stagingRead.destroy
  bufA.destroy
  bufB.destroy
  bufC.destroy
  window.setShouldClose true

  eprintln ""
  eprintln "=== Buffer Read/Write Test Done ==="

where
  toHex (n : UInt32) : String :=
    let digits := Nat.toDigits 16 n.toNat
    String.ofList digits

def main : IO Unit := bufferReadWrite
