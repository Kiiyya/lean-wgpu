import Wgpu
import Wgpu.Async
import Glfw
import Wgsl.Syntax

open IO
open Wgpu

set_option linter.unusedVariables false

/--
  RenderToTexture: Renders a triangle into an offscreen texture, then copies
  the pixel data back to CPU and prints a summary.
  Tests: offscreen rendering, Texture creation with RenderAttachment + CopySrc usage,
  CommandEncoder.copyTextureToBuffer, buffer mapping/readback.
  Shows how to do headless rendering (no display) with WebGPU.
-/

def offscreenShaderSource : String := !WGSL{
struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) color: vec3f,
};

@vertex
fn vs_main(@builtin(vertex_index) idx: u32) -> VertexOutput {
    var pos = array<vec2f, 3>(
        vec2f( 0.0,  0.5),
        vec2f(-0.5, -0.5),
        vec2f( 0.5, -0.5) 
    );
    var col = array<vec3f, 3>(
        vec3f(1.0, 0.0, 0.0),
        vec3f(0.0, 1.0, 0.0),
        vec3f(0.0, 0.0, 1.0) 
    );
    var out: VertexOutput;
    out.position = vec4f(pos[idx], 0.0, 1.0);
    out.color = col[idx];
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4f {
    return vec4f(in.color, 1.0);
}
}

def renderToTexture : IO Unit := do
  eprintln "=== RenderToTexture (Offscreen Rendering + Readback) ==="

  setLogCallback fun lvl msg => eprintln s!"[{repr lvl}] {msg}"

  -- Need a window to get a device (same bootstrap as other examples)
  let window ← GLFWwindow.mk 320 240 "RenderToTexture"

  let instDesc ← InstanceDescriptor.mk
  let inst ← createInstance instDesc
  let surface ← getSurface inst window

  let adapter ← inst.requestAdapter surface >>= await!
  adapter.printProperties

  let ddesc ← DeviceDescriptor.mk "offscreen device"
  let device ← adapter.requestDevice ddesc >>= await!
  device.setUncapturedErrorCallback fun code msg => do
    eprintln s!"uncaptured error, code {code}: \"{msg}\""

  let queue ← device.getQueue

  -- Create an offscreen texture (RGBA8, 64x64)
  let texWidth : UInt32 := 64
  let texHeight : UInt32 := 64
  let bytesPerPixel : UInt32 := 4
  -- bytesPerRow must be aligned to 256
  let bytesPerRow : UInt32 := ((texWidth * bytesPerPixel + 255) / 256) * 256
  let readbackSize : UInt32 := bytesPerRow * texHeight

  eprintln s!"Offscreen texture: {texWidth}×{texHeight}, bytesPerRow={bytesPerRow}, readback={readbackSize} bytes"

  let offscreenTex ← Device.createTexture device texWidth texHeight
    TextureFormat.RGBA8Unorm
    (TextureUsage.renderAttachment.lor TextureUsage.copySrc)
  let offscreenView ← offscreenTex.createView TextureFormat.RGBA8Unorm

  -- Staging buffer for readback
  let stagingBufDesc := BufferDescriptor.mk "staging buffer"
    (BufferUsage.mapRead.lor BufferUsage.copyDst) readbackSize false
  let stagingBuffer ← Buffer.mk device stagingBufDesc

  -- Shader
  let shaderWGSL ← ShaderModuleWGSLDescriptor.mk offscreenShaderSource
  let shaderDesc ← ShaderModuleDescriptor.mk shaderWGSL
  let shaderModule ← ShaderModule.mk device shaderDesc

  -- Pipeline targeting RGBA8Unorm (our offscreen format)
  let blendState ← BlendState.mk shaderModule
  let colorTargetState ← ColorTargetState.mk TextureFormat.RGBA8Unorm blendState
  let fragmentState ← FragmentState.mk shaderModule colorTargetState
  let pipelineDesc ← RenderPipelineDescriptor.mk shaderModule fragmentState
  let pipeline ← RenderPipeline.mk device pipelineDesc

  -- Render the triangle to the offscreen texture
  eprintln "Rendering triangle to offscreen texture..."
  let clearColor := Color.mk 0.1 0.1 0.15 1.0
  let encoder ← device.createCommandEncoder

  -- Use debug group
  encoder.pushDebugGroup "Offscreen Render"
  let renderPass ← RenderPassEncoder.mkWithColor encoder offscreenView clearColor
  renderPass.setPipeline pipeline
  renderPass.draw 3 1 0 0
  renderPass.end
  encoder.popDebugGroup

  -- Copy the texture to the staging buffer
  encoder.pushDebugGroup "Texture Readback"
  encoder.copyTextureToBuffer offscreenTex stagingBuffer texWidth texHeight bytesPerRow
  encoder.popDebugGroup

  let command ← encoder.finish
  queue.submit #[command]
  eprintln "Submitted render + copy commands"

  -- Map and read back
  stagingBuffer.mapRead device
  let resultBytes ← stagingBuffer.getMappedRange
  stagingBuffer.unmap

  eprintln s!"Read back {resultBytes.size} bytes"

  -- Analyze the image data
  let mut nonBlackPixels : UInt32 := 0
  let mut redPixels : UInt32 := 0
  let mut greenPixels : UInt32 := 0
  let mut bluePixels : UInt32 := 0
  let mut clearPixels : UInt32 := 0

  for row in [:texHeight.toNat] do
    for col in [:texWidth.toNat] do
      let offset := row * bytesPerRow.toNat + col * bytesPerPixel.toNat
      if offset + 3 < resultBytes.size then
        let r := resultBytes.get! offset
        let g := resultBytes.get! (offset + 1)
        let b := resultBytes.get! (offset + 2)
        if r > 128 && g < 64 && b < 64 then redPixels := redPixels + 1
        else if g > 128 && r < 64 && b < 64 then greenPixels := greenPixels + 1
        else if b > 128 && r < 64 && g < 64 then bluePixels := bluePixels + 1
        else if r < 30 && g < 30 && b < 50 then clearPixels := clearPixels + 1
        if r > 10 || g > 10 || b > 10 then nonBlackPixels := nonBlackPixels + 1

  let totalPixels := texWidth * texHeight
  eprintln s!"Total pixels: {totalPixels}"
  eprintln s!"Non-black pixels: {nonBlackPixels}"
  eprintln s!"Red-ish pixels: {redPixels}"
  eprintln s!"Green-ish pixels: {greenPixels}"
  eprintln s!"Blue-ish pixels: {bluePixels}"
  eprintln s!"Clear color pixels: {clearPixels}"

  -- Print a tiny ASCII preview (sample every 4th pixel in a 16x16 grid)
  eprintln "ASCII preview (16×16 downsampled):"
  let mut preview : String := ""
  for row in [:16] do
    let mut line : String := "  "
    for col in [:16] do
      let srcRow := row * texHeight.toNat / 16
      let srcCol := col * texWidth.toNat / 16
      let offset := srcRow * bytesPerRow.toNat + srcCol * bytesPerPixel.toNat
      if offset + 2 < resultBytes.size then
        let r := resultBytes.get! offset
        let g := resultBytes.get! (offset + 1)
        let b := resultBytes.get! (offset + 2)
        let brightness := (r.toNat + g.toNat + b.toNat) / 3
        let ch := if brightness > 200 then "█"
                  else if brightness > 150 then "▓"
                  else if brightness > 100 then "▒"
                  else if brightness > 50 then "░"
                  else " "
        line := line ++ ch
      else
        line := line ++ "?"
    preview := preview ++ line ++ "\n"
  eprintln preview

  -- Verify that the triangle was actually rendered (should have some colored pixels)
  if redPixels > 0 || greenPixels > 0 || bluePixels > 0 then
    eprintln "✓ Offscreen rendering successful! Triangle was rendered and read back."
  else
    eprintln "✗ No colored pixels found — something went wrong."

  -- Cleanup
  stagingBuffer.destroy
  offscreenTex.destroy

  eprintln "=== Done ==="

def main : IO Unit := renderToTexture
