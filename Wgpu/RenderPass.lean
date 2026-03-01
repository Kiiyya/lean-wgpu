import Alloy.C
import Wgpu.Command
import Wgpu.Texture
import Wgpu.Pipeline
import Wgpu.Buffer
import Wgpu.TextureFormat
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
  static inline WGPUCommandEncoder* _alloy_of_l_Wgpu_CommandEncoder(b_lean_obj_arg o) { return (WGPUCommandEncoder*)lean_get_external_data(o); }
  static inline WGPUTextureView* _alloy_of_l_Wgpu_TextureView(b_lean_obj_arg o) { return (WGPUTextureView*)lean_get_external_data(o); }
  static inline WGPUColor* _alloy_of_l_Wgpu_Color(b_lean_obj_arg o) { return (WGPUColor*)lean_get_external_data(o); }
  static inline WGPURenderPipeline* _alloy_of_l_Wgpu_RenderPipeline(b_lean_obj_arg o) { return (WGPURenderPipeline*)lean_get_external_data(o); }
  static inline WGPUBindGroup* _alloy_of_l_Wgpu_BindGroup(b_lean_obj_arg o) { return (WGPUBindGroup*)lean_get_external_data(o); }
  static inline WGPUBuffer* _alloy_of_l_Wgpu_Buffer(b_lean_obj_arg o) { return (WGPUBuffer*)lean_get_external_data(o); }
  static inline WGPUDevice* _alloy_of_l_Wgpu_Device(b_lean_obj_arg o) { return (WGPUDevice*)lean_get_external_data(o); }
  static inline WGPUQuerySet* _alloy_of_l_Wgpu_QuerySet(b_lean_obj_arg o) { return (WGPUQuerySet*)lean_get_external_data(o); }
  static inline WGPUIndexFormat _alloy_of_l_IndexFormat(uint8_t v) { return (WGPUIndexFormat)v; }
  static inline WGPUTextureFormat _alloy_of_l_TextureFormat(uint8_t v) { return (WGPUTextureFormat)v; }
  static WGPUColor color_mk(double r, double g, double b, double a) {
    WGPUColor c = {};
    c.r = r; c.g = g; c.b = b; c.a = a;
    return c;
  }
end

/-- # RenderPassDescriptor  -/

alloy c opaque_extern_type RenderPassEncoder => WGPURenderPassEncoder  where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPURenderPassEncoder  \n");
    -- TODO call release
    wgpuRenderPassEncoderRelease(*ptr);
    free(ptr);

alloy c extern
def RenderPassEncoder.mk (encoder : CommandEncoder) (view : TextureView): IO RenderPassEncoder := {
  WGPUCommandEncoder * c_encoder = of_lean<CommandEncoder>(encoder);
  WGPURenderPassDescriptor * renderPassDesc = calloc(1,sizeof(WGPURenderPassDescriptor));
  renderPassDesc->nextInChain = NULL;

  -- TODO link ColorAttachment
  WGPURenderPassColorAttachment * renderPassColorAttachment = calloc(1,sizeof(WGPURenderPassColorAttachment));
  WGPUTextureView * c_view = of_lean<TextureView>(view)
  renderPassColorAttachment->view = *c_view;
  renderPassColorAttachment->resolveTarget = NULL;
  renderPassColorAttachment->loadOp = WGPULoadOp_Clear;
  renderPassColorAttachment->storeOp = WGPUStoreOp_Store;
  WGPUColor c = color_mk(0.9, 0.3, 0.9, 0.5);
  renderPassColorAttachment->clearValue = c;

  renderPassDesc->colorAttachmentCount = 1;
  renderPassDesc->colorAttachments = renderPassColorAttachment;
  renderPassDesc->depthStencilAttachment = NULL;
  renderPassDesc->timestampWrites = NULL;

  WGPURenderPassEncoder * renderPass = calloc(1,sizeof(WGPURenderPassEncoder));
  *renderPass = wgpuCommandEncoderBeginRenderPass(*c_encoder, renderPassDesc);

  free(renderPassColorAttachment);
  free(renderPassDesc);

  -- ! This was the culprit: wgpuRenderPassEncoderEnd(*renderPass);
  return lean_io_result_mk_ok(to_lean<RenderPassEncoder>(renderPass));
}

/-- Release a render pass encoder.
    NOTE: The finalizer also releases, so this is intentionally a no-op to prevent double-release.
    Kept for API compatibility — call it for readability, but the real release happens via GC. -/
def RenderPassEncoder.release (_ : RenderPassEncoder) : IO Unit := pure ()



alloy c extern
def RenderPassEncoder.setPipeline (r : RenderPassEncoder) (p : RenderPipeline) : IO Unit := {
  WGPURenderPassEncoder * renderPass = of_lean<RenderPassEncoder>(r);
  WGPURenderPipeline * pipeline = of_lean<RenderPipeline>(p);
  wgpuRenderPassEncoderSetPipeline(*renderPass, *pipeline);
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern
def RenderPassEncoder.end (r : RenderPassEncoder) : IO Unit := {
  WGPURenderPassEncoder * renderPass = of_lean<RenderPassEncoder>(r);
  wgpuRenderPassEncoderEnd(*renderPass);
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern
def RenderPassEncoder.draw (r : RenderPassEncoder) (vShape n_inst i j : UInt32) : IO Unit := {
  WGPURenderPassEncoder * renderPass = of_lean<RenderPassEncoder>(r);
  wgpuRenderPassEncoderDraw(*renderPass, vShape, n_inst, i, j);
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern
def RenderPassEncoder.setVertexBuffer (r : RenderPassEncoder) (slot : UInt32) (buffer : Buffer)
    (offset : UInt64 := 0) : IO Unit := {
  WGPURenderPassEncoder *renderPass = of_lean<RenderPassEncoder>(r);
  WGPUBuffer *c_buffer = of_lean<Buffer>(buffer);
  uint64_t size = wgpuBufferGetSize(*c_buffer) - offset;
  wgpuRenderPassEncoderSetVertexBuffer(*renderPass, slot, *c_buffer, offset, size);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set an index buffer on a render pass encoder. -/
alloy c extern
def RenderPassEncoder.setIndexBuffer (r : RenderPassEncoder) (buffer : Buffer) (format : IndexFormat)
    (offset : UInt64 := 0) : IO Unit := {
  WGPURenderPassEncoder *renderPass = of_lean<RenderPassEncoder>(r);
  WGPUBuffer *c_buffer = of_lean<Buffer>(buffer);
  uint64_t size = wgpuBufferGetSize(*c_buffer) - offset;
  wgpuRenderPassEncoderSetIndexBuffer(*renderPass, *c_buffer, of_lean<IndexFormat>(format), offset, size);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Draw indexed primitives. -/
alloy c extern
def RenderPassEncoder.drawIndexed (r : RenderPassEncoder) (indexCount instanceCount firstIndex : UInt32)
    (baseVertex : Int32 := 0) (firstInstance : UInt32 := 0) : IO Unit := {
  WGPURenderPassEncoder *renderPass = of_lean<RenderPassEncoder>(r);
  wgpuRenderPassEncoderDrawIndexed(*renderPass, indexCount, instanceCount, firstIndex, baseVertex, firstInstance);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set the viewport on a render pass encoder. -/
alloy c extern
def RenderPassEncoder.setViewport (r : RenderPassEncoder) (x y width height minDepth maxDepth : Float) : IO Unit := {
  WGPURenderPassEncoder *renderPass = of_lean<RenderPassEncoder>(r);
  wgpuRenderPassEncoderSetViewport(*renderPass, x, y, width, height, minDepth, maxDepth);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set the scissor rect on a render pass encoder. -/
alloy c extern
def RenderPassEncoder.setScissorRect (r : RenderPassEncoder) (x y width height : UInt32) : IO Unit := {
  WGPURenderPassEncoder *renderPass = of_lean<RenderPassEncoder>(r);
  wgpuRenderPassEncoderSetScissorRect(*renderPass, x, y, width, height);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- # RenderPassEncoder with configurable clear color -/

alloy c extern
def RenderPassEncoder.mkWithColor (encoder : CommandEncoder) (view : TextureView) (color : Color) : IO RenderPassEncoder := {
  WGPUCommandEncoder *c_encoder = of_lean<CommandEncoder>(encoder);
  WGPURenderPassDescriptor *renderPassDesc = calloc(1,sizeof(WGPURenderPassDescriptor));
  renderPassDesc->nextInChain = NULL;

  WGPURenderPassColorAttachment *renderPassColorAttachment = calloc(1,sizeof(WGPURenderPassColorAttachment));
  WGPUTextureView *c_view = of_lean<TextureView>(view)
  renderPassColorAttachment->view = *c_view;
  renderPassColorAttachment->resolveTarget = NULL;
  renderPassColorAttachment->loadOp = WGPULoadOp_Clear;
  renderPassColorAttachment->storeOp = WGPUStoreOp_Store;
  WGPUColor *c_color = of_lean<Color>(color);
  renderPassColorAttachment->clearValue = *c_color;

  renderPassDesc->colorAttachmentCount = 1;
  renderPassDesc->colorAttachments = renderPassColorAttachment;
  renderPassDesc->depthStencilAttachment = NULL;
  renderPassDesc->timestampWrites = NULL;

  WGPURenderPassEncoder *renderPass = calloc(1,sizeof(WGPURenderPassEncoder));
  *renderPass = wgpuCommandEncoderBeginRenderPass(*c_encoder, renderPassDesc);

  free(renderPassColorAttachment);
  free(renderPassDesc);

  return lean_io_result_mk_ok(to_lean<RenderPassEncoder>(renderPass));
}

alloy c extern
def RenderPassEncoder.setBindGroup (r : RenderPassEncoder) (groupIndex : UInt32) (bg : BindGroup) : IO Unit := {
  WGPURenderPassEncoder *renderPass = of_lean<RenderPassEncoder>(r);
  WGPUBindGroup *c_bg = of_lean<BindGroup>(bg);
  wgpuRenderPassEncoderSetBindGroup(*renderPass, groupIndex, *c_bg, 0, NULL);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Create a render pipeline with an explicit pipeline layout.
    NOTE: This mutates `pipelineDesc.layout` in place. Do not reuse the
    descriptor with a different layout without re-setting it. -/
alloy c extern
def RenderPassEncoder.mkWithDepth (encoder : CommandEncoder)
    (colorView : TextureView) (color : Color)
    (depthView : TextureView)
    : IO RenderPassEncoder := {
  WGPUCommandEncoder *c_encoder = of_lean<CommandEncoder>(encoder);

  WGPURenderPassColorAttachment *colorAttachment = calloc(1, sizeof(WGPURenderPassColorAttachment));
  WGPUTextureView *c_colorView = of_lean<TextureView>(colorView);
  colorAttachment->view = *c_colorView;
  colorAttachment->resolveTarget = NULL;
  colorAttachment->loadOp = WGPULoadOp_Clear;
  colorAttachment->storeOp = WGPUStoreOp_Store;
  WGPUColor *c_color = of_lean<Color>(color);
  colorAttachment->clearValue = *c_color;

  WGPURenderPassDepthStencilAttachment *depthAttachment = calloc(1, sizeof(WGPURenderPassDepthStencilAttachment));
  WGPUTextureView *c_depthView = of_lean<TextureView>(depthView);
  depthAttachment->view = *c_depthView;
  depthAttachment->depthLoadOp = WGPULoadOp_Clear;
  depthAttachment->depthStoreOp = WGPUStoreOp_Store;
  depthAttachment->depthClearValue = 1.0f;
  depthAttachment->depthReadOnly = false;
  depthAttachment->stencilLoadOp = WGPULoadOp_Undefined;
  depthAttachment->stencilStoreOp = WGPUStoreOp_Undefined;
  depthAttachment->stencilClearValue = 0;
  depthAttachment->stencilReadOnly = true;

  WGPURenderPassDescriptor *renderPassDesc = calloc(1, sizeof(WGPURenderPassDescriptor));
  renderPassDesc->nextInChain = NULL;
  renderPassDesc->colorAttachmentCount = 1;
  renderPassDesc->colorAttachments = colorAttachment;
  renderPassDesc->depthStencilAttachment = depthAttachment;
  renderPassDesc->timestampWrites = NULL;

  WGPURenderPassEncoder *renderPass = calloc(1, sizeof(WGPURenderPassEncoder));
  *renderPass = wgpuCommandEncoderBeginRenderPass(*c_encoder, renderPassDesc);

  free(colorAttachment);
  free(depthAttachment);
  free(renderPassDesc);

  return lean_io_result_mk_ok(to_lean<RenderPassEncoder>(renderPass));
}

/-- Set the stencil reference value. -/
alloy c extern
def RenderPassEncoder.setStencilReference (r : RenderPassEncoder) (reference : UInt32) : IO Unit := {
  WGPURenderPassEncoder *renderPass = of_lean<RenderPassEncoder>(r);
  wgpuRenderPassEncoderSetStencilReference(*renderPass, reference);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Create a render pipeline descriptor with vertex buffers, depth test, and configurable primitive state. -/
alloy c extern
def RenderPassEncoder.pushDebugGroup (r : RenderPassEncoder) (label : String) : IO Unit := {
  WGPURenderPassEncoder *renderPass = of_lean<RenderPassEncoder>(r);
  wgpuRenderPassEncoderPushDebugGroup(*renderPass, lean_string_cstr(label));
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Pop a debug group label from a render pass encoder. -/
alloy c extern
def RenderPassEncoder.popDebugGroup (r : RenderPassEncoder) : IO Unit := {
  WGPURenderPassEncoder *renderPass = of_lean<RenderPassEncoder>(r);
  wgpuRenderPassEncoderPopDebugGroup(*renderPass);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Insert a debug marker on a render pass encoder. -/
alloy c extern
def RenderPassEncoder.insertDebugMarker (r : RenderPassEncoder) (label : String) : IO Unit := {
  WGPURenderPassEncoder *renderPass = of_lean<RenderPassEncoder>(r);
  wgpuRenderPassEncoderInsertDebugMarker(*renderPass, lean_string_cstr(label));
  return lean_io_result_mk_ok(lean_box(0));
}

/- # Render Bundle Support -/

alloy c opaque_extern_type RenderBundle => WGPURenderBundle where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPURenderBundle\n");
    wgpuRenderBundleRelease(*ptr);
    free(ptr);

alloy c opaque_extern_type RenderBundleEncoder => WGPURenderBundleEncoder where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPURenderBundleEncoder\n");
    wgpuRenderBundleEncoderRelease(*ptr);
    free(ptr);

/-- Create a render bundle encoder. colorFormats is an array of TextureFormat values
    (passed as UInt32 since alloy c enum maps to UInt32). -/
alloy c extern
def Device.createRenderBundleEncoder (device : Device)
    (colorFormats : @& Array UInt32)
    (depthStencilFormat : TextureFormat := TextureFormat.Undefined)
    (sampleCount : UInt32 := 1)
    (depthReadOnly : Bool := false)
    (stencilReadOnly : Bool := false)
    : IO RenderBundleEncoder := {
  WGPUDevice c_device = *of_lean<Device>(device);

  size_t nFormats = lean_array_size(colorFormats);
  WGPUTextureFormat *formats = calloc(nFormats, sizeof(WGPUTextureFormat));
  for (size_t i = 0; i < nFormats; i++) {
    formats[i] = (WGPUTextureFormat)lean_unbox(lean_array_uget(colorFormats, i));
  }

  WGPURenderBundleEncoderDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "Render bundle encoder";
  desc.colorFormatCount = nFormats;
  desc.colorFormats = formats;
  desc.depthStencilFormat = of_lean<TextureFormat>(depthStencilFormat);
  desc.sampleCount = sampleCount;
  desc.depthReadOnly = depthReadOnly;
  desc.stencilReadOnly = stencilReadOnly;

  WGPURenderBundleEncoder *enc = calloc(1, sizeof(WGPURenderBundleEncoder));
  *enc = wgpuDeviceCreateRenderBundleEncoder(c_device, &desc);
  free(formats);
  return lean_io_result_mk_ok(to_lean<RenderBundleEncoder>(enc));
}

alloy c extern
def RenderBundleEncoder.setPipeline (enc : RenderBundleEncoder) (pipeline : RenderPipeline) : IO Unit := {
  WGPURenderBundleEncoder *c_enc = of_lean<RenderBundleEncoder>(enc);
  WGPURenderPipeline *c_pipeline = of_lean<RenderPipeline>(pipeline);
  wgpuRenderBundleEncoderSetPipeline(*c_enc, *c_pipeline);
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern
def RenderBundleEncoder.setVertexBuffer (enc : RenderBundleEncoder) (slot : UInt32) (buffer : Buffer)
    (offset : UInt64 := 0) : IO Unit := {
  WGPURenderBundleEncoder *c_enc = of_lean<RenderBundleEncoder>(enc);
  WGPUBuffer *c_buffer = of_lean<Buffer>(buffer);
  uint64_t size = wgpuBufferGetSize(*c_buffer) - offset;
  wgpuRenderBundleEncoderSetVertexBuffer(*c_enc, slot, *c_buffer, offset, size);
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern
def RenderBundleEncoder.setIndexBuffer (enc : RenderBundleEncoder) (buffer : Buffer) (format : IndexFormat)
    (offset : UInt64 := 0) : IO Unit := {
  WGPURenderBundleEncoder *c_enc = of_lean<RenderBundleEncoder>(enc);
  WGPUBuffer *c_buffer = of_lean<Buffer>(buffer);
  uint64_t size = wgpuBufferGetSize(*c_buffer) - offset;
  wgpuRenderBundleEncoderSetIndexBuffer(*c_enc, *c_buffer, of_lean<IndexFormat>(format), offset, size);
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern
def RenderBundleEncoder.setBindGroup (enc : RenderBundleEncoder) (groupIndex : UInt32) (bg : BindGroup) : IO Unit := {
  WGPURenderBundleEncoder *c_enc = of_lean<RenderBundleEncoder>(enc);
  WGPUBindGroup *c_bg = of_lean<BindGroup>(bg);
  wgpuRenderBundleEncoderSetBindGroup(*c_enc, groupIndex, *c_bg, 0, NULL);
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern
def RenderBundleEncoder.draw (enc : RenderBundleEncoder)
    (vertexCount instanceCount firstVertex firstInstance : UInt32) : IO Unit := {
  WGPURenderBundleEncoder *c_enc = of_lean<RenderBundleEncoder>(enc);
  wgpuRenderBundleEncoderDraw(*c_enc, vertexCount, instanceCount, firstVertex, firstInstance);
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern
def RenderBundleEncoder.drawIndexed (enc : RenderBundleEncoder)
    (indexCount instanceCount firstIndex : UInt32)
    (baseVertex : Int32 := 0) (firstInstance : UInt32 := 0) : IO Unit := {
  WGPURenderBundleEncoder *c_enc = of_lean<RenderBundleEncoder>(enc);
  wgpuRenderBundleEncoderDrawIndexed(*c_enc, indexCount, instanceCount, firstIndex, baseVertex, firstInstance);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Finish recording the render bundle. -/
alloy c extern
def RenderBundleEncoder.finish (enc : RenderBundleEncoder) : IO RenderBundle := {
  WGPURenderBundleEncoder *c_enc = of_lean<RenderBundleEncoder>(enc);
  WGPURenderBundleDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "Render bundle";
  WGPURenderBundle *bundle = calloc(1, sizeof(WGPURenderBundle));
  *bundle = wgpuRenderBundleEncoderFinish(*c_enc, &desc);
  return lean_io_result_mk_ok(to_lean<RenderBundle>(bundle));
}

/-- Execute render bundles on a render pass encoder. -/
alloy c extern
def RenderPassEncoder.executeBundles (r : RenderPassEncoder) (bundles : @& Array RenderBundle) : IO Unit := {
  WGPURenderPassEncoder *renderPass = of_lean<RenderPassEncoder>(r);
  size_t n = lean_array_size(bundles);
  WGPURenderBundle *c_bundles = calloc(n, sizeof(WGPURenderBundle));
  for (size_t i = 0; i < n; i++) {
    WGPURenderBundle *b = of_lean<RenderBundle>(lean_array_uget(bundles, i));
    c_bundles[i] = *b;
  }
  wgpuRenderPassEncoderExecuteBundles(*renderPass, n, c_bundles);
  free(c_bundles);
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern
def RenderPassEncoder.mkMultiColor (encoder : CommandEncoder)
    (views : @& Array TextureView) (colors : @& Array Color)
    : IO RenderPassEncoder := {
  WGPUCommandEncoder *c_encoder = of_lean<CommandEncoder>(encoder);
  size_t n = lean_array_size(views);

  WGPURenderPassColorAttachment *attachments = calloc(n, sizeof(WGPURenderPassColorAttachment));
  for (size_t i = 0; i < n; i++) {
    WGPUTextureView *v = of_lean<TextureView>(lean_array_uget(views, i));
    WGPUColor *c = of_lean<Color>(lean_array_uget(colors, i));
    attachments[i].view = *v;
    attachments[i].resolveTarget = NULL;
    attachments[i].loadOp = WGPULoadOp_Clear;
    attachments[i].storeOp = WGPUStoreOp_Store;
    attachments[i].clearValue = *c;
  }

  WGPURenderPassDescriptor *desc = calloc(1, sizeof(WGPURenderPassDescriptor));
  desc->nextInChain = NULL;
  desc->colorAttachmentCount = n;
  desc->colorAttachments = attachments;
  desc->depthStencilAttachment = NULL;
  desc->timestampWrites = NULL;

  WGPURenderPassEncoder *renderPass = calloc(1, sizeof(WGPURenderPassEncoder));
  *renderPass = wgpuCommandEncoderBeginRenderPass(*c_encoder, desc);

  free(attachments);
  free(desc);

  return lean_io_result_mk_ok(to_lean<RenderPassEncoder>(renderPass));
}

/- # Indirect Drawing -/

/-- Draw indirect — reads draw parameters from a GPU buffer. -/
alloy c extern
def RenderPassEncoder.drawIndirect (r : RenderPassEncoder) (indirectBuffer : Buffer) (indirectOffset : UInt64 := 0) : IO Unit := {
  WGPURenderPassEncoder *renderPass = of_lean<RenderPassEncoder>(r);
  WGPUBuffer *c_buffer = of_lean<Buffer>(indirectBuffer);
  wgpuRenderPassEncoderDrawIndirect(*renderPass, *c_buffer, indirectOffset);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Draw indexed indirect — reads indexed draw parameters from a GPU buffer. -/
alloy c extern
def RenderPassEncoder.drawIndexedIndirect (r : RenderPassEncoder) (indirectBuffer : Buffer) (indirectOffset : UInt64 := 0) : IO Unit := {
  WGPURenderPassEncoder *renderPass = of_lean<RenderPassEncoder>(r);
  WGPUBuffer *c_buffer = of_lean<Buffer>(indirectBuffer);
  wgpuRenderPassEncoderDrawIndexedIndirect(*renderPass, *c_buffer, indirectOffset);
  return lean_io_result_mk_ok(lean_box(0));
}

/- # Blend Constant -/

/-- Set the blend constant color for the render pass. -/
alloy c extern
def RenderPassEncoder.setBlendConstant (r : RenderPassEncoder) (color : Color) : IO Unit := {
  WGPURenderPassEncoder *renderPass = of_lean<RenderPassEncoder>(r);
  WGPUColor *c_color = of_lean<Color>(color);
  wgpuRenderPassEncoderSetBlendConstant(*renderPass, c_color);
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern
def RenderPassEncoder.beginOcclusionQuery (r : RenderPassEncoder) (queryIndex : UInt32) : IO Unit := {
  WGPURenderPassEncoder *rp = of_lean<RenderPassEncoder>(r);
  wgpuRenderPassEncoderBeginOcclusionQuery(*rp, queryIndex);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- End the current occlusion query in the render pass. -/
alloy c extern
def RenderPassEncoder.endOcclusionQuery (r : RenderPassEncoder) : IO Unit := {
  WGPURenderPassEncoder *rp = of_lean<RenderPassEncoder>(r);
  wgpuRenderPassEncoderEndOcclusionQuery(*rp);
  return lean_io_result_mk_ok(lean_box(0));
}

/- ################################################################## -/
/- # Render pass with stencil clear/load/store control                -/
/- ################################################################## -/

/-- Create a render pass with depth+stencil, allowing stencil clear value and
    load/store operation control. -/
alloy c extern
def RenderPassEncoder.mkWithDepthStencil (encoder : CommandEncoder)
    (colorView : TextureView) (clearColor : Color)
    (depthView : TextureView)
    (depthClearValue : Float := 1.0)
    (stencilClearValue : UInt32 := 0)
    (stencilLoadOp : UInt32 := 1)  -- 1=Clear, 2=Load
    (stencilStoreOp : UInt32 := 1) -- 1=Store, 2=Discard
    : IO RenderPassEncoder := {
  WGPUCommandEncoder *c_enc = of_lean<CommandEncoder>(encoder);
  WGPUTextureView *c_view = of_lean<TextureView>(colorView);
  WGPUColor *c_color = of_lean<Color>(clearColor);
  WGPUTextureView *c_depth = of_lean<TextureView>(depthView);

  WGPURenderPassColorAttachment colorAttachment = {
    .nextInChain = NULL,
    .view = *c_view,
    .resolveTarget = NULL,
    .loadOp = WGPULoadOp_Clear,
    .storeOp = WGPUStoreOp_Store,
    .clearValue = *c_color,
  };

  WGPURenderPassDepthStencilAttachment dsAttach = {
    .view = *c_depth,
    .depthLoadOp = WGPULoadOp_Clear,
    .depthStoreOp = WGPUStoreOp_Store,
    .depthClearValue = (float)depthClearValue,
    .depthReadOnly = 0,
    .stencilLoadOp = (WGPULoadOp)stencilLoadOp,
    .stencilStoreOp = (WGPUStoreOp)stencilStoreOp,
    .stencilClearValue = stencilClearValue,
    .stencilReadOnly = 0,
  };

  WGPURenderPassDescriptor desc = {
    .nextInChain = NULL,
    .label = NULL,
    .colorAttachmentCount = 1,
    .colorAttachments = &colorAttachment,
    .depthStencilAttachment = &dsAttach,
    .occlusionQuerySet = NULL,
    .timestampWrites = NULL,
  };

  WGPURenderPassEncoder *rp = calloc(1, sizeof(WGPURenderPassEncoder));
  *rp = wgpuCommandEncoderBeginRenderPass(*c_enc, &desc);
  return lean_io_result_mk_ok(to_lean<RenderPassEncoder>(rp));
}

alloy c extern
def RenderPassEncoder.mkMSAA (encoder : CommandEncoder)
    (msaaView : TextureView) (resolveView : TextureView) (clearColor : Color)
    : IO RenderPassEncoder := {
  WGPUCommandEncoder *c_enc = of_lean<CommandEncoder>(encoder);
  WGPUTextureView *c_msaa = of_lean<TextureView>(msaaView);
  WGPUTextureView *c_resolve = of_lean<TextureView>(resolveView);
  WGPUColor *c_color = of_lean<Color>(clearColor);

  WGPURenderPassColorAttachment colorAttachment = {
    .nextInChain = NULL,
    .view = *c_msaa,
    .resolveTarget = *c_resolve,
    .loadOp = WGPULoadOp_Clear,
    .storeOp = WGPUStoreOp_Store,
    .clearValue = *c_color,
  };

  WGPURenderPassDescriptor desc = {
    .nextInChain = NULL,
    .label = NULL,
    .colorAttachmentCount = 1,
    .colorAttachments = &colorAttachment,
    .depthStencilAttachment = NULL,
    .occlusionQuerySet = NULL,
    .timestampWrites = NULL,
  };

  WGPURenderPassEncoder *rp = calloc(1, sizeof(WGPURenderPassEncoder));
  *rp = wgpuCommandEncoderBeginRenderPass(*c_enc, &desc);
  return lean_io_result_mk_ok(to_lean<RenderPassEncoder>(rp));
}

/- ################################################################## -/
/- # RenderPass with Load (no clear)                                  -/
/- ################################################################## -/

/-- Create a render pass that loads existing content (no clear). -/
alloy c extern
def RenderPassEncoder.mkLoad (encoder : CommandEncoder) (view : TextureView) : IO RenderPassEncoder := {
  WGPUCommandEncoder *c_enc = of_lean<CommandEncoder>(encoder);
  WGPUTextureView *c_view = of_lean<TextureView>(view);

  WGPURenderPassColorAttachment colorAttachment = {
    .nextInChain = NULL,
    .view = *c_view,
    .resolveTarget = NULL,
    .loadOp = WGPULoadOp_Load,
    .storeOp = WGPUStoreOp_Store,
    .clearValue = {0, 0, 0, 0},
  };

  WGPURenderPassDescriptor desc = {
    .nextInChain = NULL,
    .label = NULL,
    .colorAttachmentCount = 1,
    .colorAttachments = &colorAttachment,
    .depthStencilAttachment = NULL,
    .occlusionQuerySet = NULL,
    .timestampWrites = NULL,
  };

  WGPURenderPassEncoder *rp = calloc(1, sizeof(WGPURenderPassEncoder));
  *rp = wgpuCommandEncoderBeginRenderPass(*c_enc, &desc);
  return lean_io_result_mk_ok(to_lean<RenderPassEncoder>(rp));
}

/-- Create a render pass that loads existing color AND depth buffers (no clear). -/
alloy c extern
def RenderPassEncoder.mkLoadWithDepth (encoder : CommandEncoder) (view : TextureView) (depthView : TextureView) : IO RenderPassEncoder := {
  WGPUCommandEncoder *c_enc = of_lean<CommandEncoder>(encoder);
  WGPUTextureView *c_view = of_lean<TextureView>(view);
  WGPUTextureView *c_depth = of_lean<TextureView>(depthView);

  WGPURenderPassColorAttachment colorAttachment = {
    .nextInChain = NULL,
    .view = *c_view,
    .resolveTarget = NULL,
    .loadOp = WGPULoadOp_Load,
    .storeOp = WGPUStoreOp_Store,
    .clearValue = {0, 0, 0, 0},
  };

  WGPURenderPassDepthStencilAttachment dsAttach = {
    .view = *c_depth,
    .depthLoadOp = WGPULoadOp_Load,
    .depthStoreOp = WGPUStoreOp_Store,
    .depthClearValue = 1.0f,
    .depthReadOnly = 0,
    .stencilLoadOp = WGPULoadOp_Undefined,
    .stencilStoreOp = WGPUStoreOp_Undefined,
    .stencilClearValue = 0,
    .stencilReadOnly = 1,
  };

  WGPURenderPassDescriptor desc = {
    .nextInChain = NULL,
    .label = NULL,
    .colorAttachmentCount = 1,
    .colorAttachments = &colorAttachment,
    .depthStencilAttachment = &dsAttach,
    .occlusionQuerySet = NULL,
    .timestampWrites = NULL,
  };

  WGPURenderPassEncoder *rp = calloc(1, sizeof(WGPURenderPassEncoder));
  *rp = wgpuCommandEncoderBeginRenderPass(*c_enc, &desc);
  return lean_io_result_mk_ok(to_lean<RenderPassEncoder>(rp));
}

/- ################################################################## -/
/- # Render pass with color load/store control                        -/
/- ################################################################## -/

/-- Create a render pass with configurable load/store ops.
    loadOp: 1=Clear, 2=Load. storeOp: 1=Store, 2=Discard. -/
alloy c extern
def RenderPassEncoder.mkWithOps (encoder : CommandEncoder) (view : TextureView)
    (clearColor : Color) (loadOp : UInt32 := 1) (storeOp : UInt32 := 1)
    : IO RenderPassEncoder := {
  WGPUCommandEncoder *c_enc = of_lean<CommandEncoder>(encoder);
  WGPUTextureView *c_view = of_lean<TextureView>(view);
  WGPUColor *c_color = of_lean<Color>(clearColor);

  WGPURenderPassColorAttachment colorAttachment = {
    .nextInChain = NULL,
    .view = *c_view,
    .resolveTarget = NULL,
    .loadOp = (WGPULoadOp)loadOp,
    .storeOp = (WGPUStoreOp)storeOp,
    .clearValue = *c_color,
  };

  WGPURenderPassDescriptor desc = {
    .nextInChain = NULL,
    .label = NULL,
    .colorAttachmentCount = 1,
    .colorAttachments = &colorAttachment,
    .depthStencilAttachment = NULL,
    .occlusionQuerySet = NULL,
    .timestampWrites = NULL,
  };

  WGPURenderPassEncoder *rp = calloc(1, sizeof(WGPURenderPassEncoder));
  *rp = wgpuCommandEncoderBeginRenderPass(*c_enc, &desc);
  return lean_io_result_mk_ok(to_lean<RenderPassEncoder>(rp));
}

alloy c extern
def RenderPassEncoder.mkDepthOnly (encoder : CommandEncoder) (depthView : TextureView)
    : IO RenderPassEncoder := {
  WGPUCommandEncoder *c_enc = of_lean<CommandEncoder>(encoder);
  WGPUTextureView *c_depth = of_lean<TextureView>(depthView);

  WGPURenderPassDepthStencilAttachment dsAttach = {
    .view = *c_depth,
    .depthLoadOp = WGPULoadOp_Clear,
    .depthStoreOp = WGPUStoreOp_Store,
    .depthClearValue = 1.0f,
    .depthReadOnly = 0,
    .stencilLoadOp = WGPULoadOp_Undefined,
    .stencilStoreOp = WGPUStoreOp_Undefined,
    .stencilClearValue = 0,
    .stencilReadOnly = 1,
  };

  WGPURenderPassDescriptor desc = {
    .nextInChain = NULL,
    .label = "Shadow pass",
    .colorAttachmentCount = 0,
    .colorAttachments = NULL,
    .depthStencilAttachment = &dsAttach,
    .occlusionQuerySet = NULL,
    .timestampWrites = NULL,
  };

  WGPURenderPassEncoder *rp = calloc(1, sizeof(WGPURenderPassEncoder));
  *rp = wgpuCommandEncoderBeginRenderPass(*c_enc, &desc);
  return lean_io_result_mk_ok(to_lean<RenderPassEncoder>(rp));
}

/-- Create a render pipeline descriptor with depth-only output (no color targets).
    Used for shadow map rendering from the light's perspective. -/
alloy c extern
def RenderPassEncoder.setLabel (r : RenderPassEncoder) (label : @& String) : IO Unit := {
  WGPURenderPassEncoder *c_rp = of_lean<RenderPassEncoder>(r);
  wgpuRenderPassEncoderSetLabel(*c_rp, lean_string_cstr(label));
  return lean_io_result_mk_ok(lean_box(0));
}

/- ################################################################## -/
/- # Push Constants (wgpu-native extension)                           -/
/- ################################################################## -/

/-- Set push constant data on a render pass encoder.
    `stages` is a ShaderStageFlags bitmask. `offset` and data size must be 4-byte aligned. -/
alloy c extern
def RenderPassEncoder.setPushConstants (r : RenderPassEncoder)
    (stages : ShaderStageFlags) (offset : UInt32) (data : @& ByteArray) : IO Unit := {
  WGPURenderPassEncoder *renderPass = of_lean<RenderPassEncoder>(r);
  uint8_t *ptr = lean_sarray_cptr(data);
  uint32_t sizeBytes = (uint32_t)lean_sarray_size(data);
  wgpuRenderPassEncoderSetPushConstants(*renderPass, stages, offset, sizeBytes, ptr);
  return lean_io_result_mk_ok(lean_box(0));
}

/- ################################################################## -/
/- # Multi-Draw Indirect (wgpu-native extension)                      -/
/- ################################################################## -/

/-- Issue multiple indirect draw calls from a buffer. -/
alloy c extern
def RenderPassEncoder.multiDrawIndirect (r : RenderPassEncoder)
    (buffer : Buffer) (offset : UInt64) (count : UInt32) : IO Unit := {
  WGPURenderPassEncoder *rp = of_lean<RenderPassEncoder>(r);
  WGPUBuffer *c_buf = of_lean<Buffer>(buffer);
  wgpuRenderPassEncoderMultiDrawIndirect(*rp, *c_buf, offset, count);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Issue multiple indexed indirect draw calls from a buffer. -/
alloy c extern
def RenderPassEncoder.multiDrawIndexedIndirect (r : RenderPassEncoder)
    (buffer : Buffer) (offset : UInt64) (count : UInt32) : IO Unit := {
  WGPURenderPassEncoder *rp = of_lean<RenderPassEncoder>(r);
  WGPUBuffer *c_buf = of_lean<Buffer>(buffer);
  wgpuRenderPassEncoderMultiDrawIndexedIndirect(*rp, *c_buf, offset, count);
  return lean_io_result_mk_ok(lean_box(0));
}

/- ################################################################## -/
/- # Render Bundle Encoder debug markers                              -/
/- ################################################################## -/

/-- Push a debug group on a render bundle encoder. -/
alloy c extern
def RenderBundleEncoder.pushDebugGroup (enc : RenderBundleEncoder) (label : @& String) : IO Unit := {
  WGPURenderBundleEncoder *c_enc = of_lean<RenderBundleEncoder>(enc);
  wgpuRenderBundleEncoderPushDebugGroup(*c_enc, lean_string_cstr(label));
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Pop a debug group from a render bundle encoder. -/
alloy c extern
def RenderBundleEncoder.popDebugGroup (enc : RenderBundleEncoder) : IO Unit := {
  WGPURenderBundleEncoder *c_enc = of_lean<RenderBundleEncoder>(enc);
  wgpuRenderBundleEncoderPopDebugGroup(*c_enc);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Insert a debug marker on a render bundle encoder. -/
alloy c extern
def RenderBundleEncoder.insertDebugMarker (enc : RenderBundleEncoder) (label : @& String) : IO Unit := {
  WGPURenderBundleEncoder *c_enc = of_lean<RenderBundleEncoder>(enc);
  wgpuRenderBundleEncoderInsertDebugMarker(*c_enc, lean_string_cstr(label));
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern
def RenderPassEncoder.beginPipelineStatisticsQuery (r : RenderPassEncoder) (qs : QuerySet) (queryIndex : UInt32) : IO Unit := {
  WGPURenderPassEncoder *rp = of_lean<RenderPassEncoder>(r);
  WGPUQuerySet *c_qs = of_lean<QuerySet>(qs);
  wgpuRenderPassEncoderBeginPipelineStatisticsQuery(*rp, *c_qs, queryIndex);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- End a pipeline statistics query in a render pass. -/
alloy c extern
def RenderPassEncoder.endPipelineStatisticsQuery (r : RenderPassEncoder) : IO Unit := {
  WGPURenderPassEncoder *rp = of_lean<RenderPassEncoder>(r);
  wgpuRenderPassEncoderEndPipelineStatisticsQuery(*rp);
  return lean_io_result_mk_ok(lean_box(0));
}

/- ################################################################## -/
/- # RenderBundle / RenderBundleEncoder SetLabel + indirect draw      -/
/- ################################################################## -/

/-- Set the debug label of a render bundle. -/
alloy c extern
def RenderBundle.setLabel (rb : RenderBundle) (label : @& String) : IO Unit := {
  WGPURenderBundle *c_rb = of_lean<RenderBundle>(rb);
  wgpuRenderBundleSetLabel(*c_rb, lean_string_cstr(label));
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set the debug label of a render bundle encoder. -/
alloy c extern
def RenderBundleEncoder.setLabel (enc : RenderBundleEncoder) (label : @& String) : IO Unit := {
  WGPURenderBundleEncoder *c_enc = of_lean<RenderBundleEncoder>(enc);
  wgpuRenderBundleEncoderSetLabel(*c_enc, lean_string_cstr(label));
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Issue an indirect draw call from a render bundle encoder. -/
alloy c extern
def RenderBundleEncoder.drawIndirect (enc : RenderBundleEncoder)
    (buffer : Buffer) (offset : UInt64) : IO Unit := {
  WGPURenderBundleEncoder *c_enc = of_lean<RenderBundleEncoder>(enc);
  WGPUBuffer *c_buf = of_lean<Buffer>(buffer);
  wgpuRenderBundleEncoderDrawIndirect(*c_enc, *c_buf, offset);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Issue an indexed indirect draw call from a render bundle encoder. -/
alloy c extern
def RenderBundleEncoder.drawIndexedIndirect (enc : RenderBundleEncoder)
    (buffer : Buffer) (offset : UInt64) : IO Unit := {
  WGPURenderBundleEncoder *c_enc = of_lean<RenderBundleEncoder>(enc);
  WGPUBuffer *c_buf = of_lean<Buffer>(buffer);
  wgpuRenderBundleEncoderDrawIndexedIndirect(*c_enc, *c_buf, offset);
  return lean_io_result_mk_ok(lean_box(0));
}

/- ################################################################## -/
/- # Multi-Draw Indirect Count (wgpu-native extension)                -/
/- ################################################################## -/

/-- Issue multiple indirect draw calls with a GPU-driven count buffer. -/
alloy c extern
def RenderPassEncoder.multiDrawIndirectCount (r : RenderPassEncoder)
    (buffer : Buffer) (offset : UInt64)
    (countBuffer : Buffer) (countBufferOffset : UInt64)
    (maxCount : UInt32) : IO Unit := {
  WGPURenderPassEncoder *rp = of_lean<RenderPassEncoder>(r);
  WGPUBuffer *c_buf = of_lean<Buffer>(buffer);
  WGPUBuffer *c_count_buf = of_lean<Buffer>(countBuffer);
  wgpuRenderPassEncoderMultiDrawIndirectCount(*rp, *c_buf, offset, *c_count_buf, countBufferOffset, maxCount);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Issue multiple indexed indirect draw calls with a GPU-driven count buffer. -/
alloy c extern
def RenderPassEncoder.multiDrawIndexedIndirectCount (r : RenderPassEncoder)
    (buffer : Buffer) (offset : UInt64)
    (countBuffer : Buffer) (countBufferOffset : UInt64)
    (maxCount : UInt32) : IO Unit := {
  WGPURenderPassEncoder *rp = of_lean<RenderPassEncoder>(r);
  WGPUBuffer *c_buf = of_lean<Buffer>(buffer);
  WGPUBuffer *c_count_buf = of_lean<Buffer>(countBuffer);
  wgpuRenderPassEncoderMultiDrawIndexedIndirectCount(*rp, *c_buf, offset, *c_count_buf, countBufferOffset, maxCount);
  return lean_io_result_mk_ok(lean_box(0));
}


end Wgpu
