import Alloy.C
import Wgpu.Device
import Wgpu.TextureFormat
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
  static inline WGPUTextureFormat _alloy_of_l_TextureFormat(uint8_t v) { return (WGPUTextureFormat)v; }
  static inline uint8_t _alloy_to_l_TextureFormat(WGPUTextureFormat v) { return (uint8_t)v; }
  static inline WGPUBuffer* _alloy_of_l_Wgpu_Buffer(b_lean_obj_arg o) { return (WGPUBuffer*)lean_get_external_data(o); }
  static inline WGPUTextureView* _alloy_of_l_Wgpu_TextureView(b_lean_obj_arg o) { return (WGPUTextureView*)lean_get_external_data(o); }
  static inline WGPUSampler* _alloy_of_l_Wgpu_Sampler(b_lean_obj_arg o) { return (WGPUSampler*)lean_get_external_data(o); }
  static inline WGPUAddressMode _alloy_of_l_AddressMode(uint8_t v) { return (WGPUAddressMode)v; }
  static inline WGPUFilterMode _alloy_of_l_FilterMode(uint8_t v) { return (WGPUFilterMode)v; }
  static inline WGPUCompareFunction _alloy_of_l_CompareFunction(uint8_t v) { return (WGPUCompareFunction)v; }
end

def shaderSource : String :=
"@vertex \
  fn vs_main(@builtin(vertex_index) in_vertex_index: u32) -> @builtin(position) vec4f { \
    var p = vec2f(0.0, 0.0); \
    if (in_vertex_index == 0u) { \
        p = vec2f(-0.5, -0.5); \
    } else if (in_vertex_index == 1u) { \
        p = vec2f(0.5, -0.5); \
    } else { \
        p = vec2f(0.0, 0.5); \
    } \
    return vec4f(p, 0.0, 1.0); \
  } \
   \
  @fragment \
  fn fs_main() -> @location(0) vec4f { \
      return vec4f(0.0, 0.4, 1.0, 1.0); \
  }"

/-- # ShaderModuleWGSLDescriptor -/

alloy c opaque_extern_type ShaderModuleWGSLDescriptor => WGPUShaderModuleWGSLDescriptor where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUShaderModuleWGSLDescriptor \n");
    if (ptr->code) free((void*)ptr->code);
    free(ptr);

/-- WARNING: Stores a pointer into the Lean String's buffer for `code`.
    Safe only because `ShaderModuleDescriptor.mk` → `ShaderModule.mk` → `wgpuDeviceCreateShaderModule`
    copies the string. The strdup'd copy is freed in the finalizer. -/
-- TODO put shaderSource as parameter to the function (how to transform String into char* ?)
alloy c extern
def ShaderModuleWGSLDescriptor.mk (shaderSource : String) : IO ShaderModuleWGSLDescriptor := {
  char const * c_shaderSource = lean_string_cstr(shaderSource);
  fprintf(stderr, "uhhh %s \n",c_shaderSource);
  fprintf(stderr, "mk ShaderModuleWGSLDescriptor \n");
  WGPUShaderModuleWGSLDescriptor * shaderCodeDesc = calloc(1,sizeof(WGPUShaderModuleWGSLDescriptor));
  shaderCodeDesc->chain.next = NULL;
  shaderCodeDesc->chain.sType = WGPUSType_ShaderModuleWGSLDescriptor;
  shaderCodeDesc->code = strdup(c_shaderSource);
  -- ! shaderDesc.code = &shaderCodeDesc.chain; "connect the chain"
  return lean_io_result_mk_ok(to_lean<ShaderModuleWGSLDescriptor>(shaderCodeDesc));
}

/-- # ShaderModuleDescriptor -/

alloy c opaque_extern_type ShaderModuleDescriptor => WGPUShaderModuleDescriptor where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUShaderModuleDescriptor \n");
    -- wgpuRenderPipelineRelease(*ptr);
    free(ptr);

alloy c extern
def ShaderModuleDescriptor.mk (shaderCodeDesc : ShaderModuleWGSLDescriptor) : IO ShaderModuleDescriptor := {
  fprintf(stderr, "mk ShaderModuleDescriptor \n");
  WGPUShaderModuleWGSLDescriptor * c_shaderCodeDesc = of_lean<ShaderModuleWGSLDescriptor>(shaderCodeDesc);
  WGPUShaderModuleDescriptor * shaderDesc = calloc(1, sizeof(WGPUShaderModuleDescriptor));
  -- shaderDesc->hintCount = 0;
  -- shaderDesc->hints = NULL;
  shaderDesc->nextInChain = &c_shaderCodeDesc->chain;
  return lean_io_result_mk_ok(to_lean<ShaderModuleDescriptor>(shaderDesc));
}

alloy c opaque_extern_type ShaderModule => WGPUShaderModule where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUShaderModule \n");
    if (*ptr) wgpuShaderModuleRelease(*ptr);
    free(ptr);

alloy c extern
def ShaderModule.mk (device : Device) (shaderDesc : ShaderModuleDescriptor) : IO ShaderModule := {
  fprintf(stderr, "mk ShaderModule \n");
  WGPUDevice * c_device = of_lean<Device>(device);
  WGPUShaderModuleDescriptor * c_shaderDesc = of_lean<ShaderModuleDescriptor>(shaderDesc);
  WGPUShaderModule * shaderModule = calloc(1,sizeof(WGPUShaderModule));
  *shaderModule = wgpuDeviceCreateShaderModule(*c_device, c_shaderDesc);
  return lean_io_result_mk_ok(to_lean<ShaderModule>(shaderModule));
}

/-- # BlendState -/

alloy c opaque_extern_type BlendState => WGPUBlendState where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUBlendState \n");
    free(ptr);

alloy c extern
def BlendState.mk (shaderModule : ShaderModule) : IO BlendState := {
  fprintf(stderr, "mk BlendState \n");

  WGPUBlendState * blendState = calloc(1,sizeof(WGPUBlendState));
  blendState->color.srcFactor = WGPUBlendFactor_SrcAlpha;
  blendState->color.dstFactor = WGPUBlendFactor_OneMinusSrcAlpha;
  blendState->color.operation = WGPUBlendOperation_Add;
  blendState->alpha.srcFactor = WGPUBlendFactor_Zero;
  blendState->alpha.dstFactor = WGPUBlendFactor_One;
  blendState->alpha.operation = WGPUBlendOperation_Add;

  return lean_io_result_mk_ok(to_lean<BlendState>(blendState));
}

/-- # ColorTargetState -/

alloy c opaque_extern_type ColorTargetState => WGPUColorTargetState where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUColorTargetState \n");
    if (ptr->blend) free((void*)ptr->blend);
    free(ptr);

alloy c extern
def ColorTargetState.mk (surfaceFormat : TextureFormat) (blendState : BlendState) : IO ColorTargetState := {
  fprintf(stderr, "mk ColorTargetState \n");
  WGPUTextureFormat c_surfaceFormat = of_lean<TextureFormat>(surfaceFormat);
  WGPUBlendState * c_blendState = of_lean<BlendState>(blendState);

  WGPUColorTargetState * colorTarget = calloc(1,sizeof(WGPUColorTargetState));
  colorTarget->format = c_surfaceFormat;
  WGPUBlendState *ownedBlend = calloc(1, sizeof(WGPUBlendState));
  *ownedBlend = *c_blendState;
  colorTarget->blend  = ownedBlend;
  -- TODO add writeMask param
  colorTarget->writeMask = WGPUColorWriteMask_All; // We could write to only some of the color channels.
  return lean_io_result_mk_ok(to_lean<ColorTargetState>(colorTarget));
}


/-- # FragmentState -/

alloy c opaque_extern_type FragmentState => WGPUFragmentState where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUFragmentState \n");
    if (ptr->targets) {
      for (size_t i = 0; i < ptr->targetCount; i++) {
        if (ptr->targets[i].blend) free((void*)ptr->targets[i].blend);
      }
      free((void*)ptr->targets);
    }
    if (ptr->entryPoint) free((void*)ptr->entryPoint);
    free(ptr);

alloy c extern
def FragmentState.mk (shaderModule : ShaderModule) (colorTarget : ColorTargetState) : IO FragmentState := {
  fprintf(stderr, "mk FragmentState \n");
  WGPUShaderModule * c_shaderModule = of_lean<ShaderModule>(shaderModule);
  WGPUColorTargetState * c_colorTarget = of_lean<ColorTargetState>(colorTarget);

  WGPUFragmentState * fragmentState = calloc(1,sizeof(WGPUFragmentState));
  fragmentState->module = *c_shaderModule;
  fragmentState->entryPoint = strdup("fs_main");
  fragmentState->constantCount = 0;
  fragmentState->constants = NULL;
  fragmentState->targetCount = 1;
  -- Deep-copy the color target so FragmentState owns the memory
  WGPUColorTargetState *ownedTarget = calloc(1, sizeof(WGPUColorTargetState));
  *ownedTarget = *c_colorTarget;
  if (c_colorTarget->blend) {
    WGPUBlendState *blendCopy = calloc(1, sizeof(WGPUBlendState));
    *blendCopy = *(c_colorTarget->blend);
    ownedTarget->blend = blendCopy;
  }
  fragmentState->targets = ownedTarget;
  return lean_io_result_mk_ok(to_lean<FragmentState>(fragmentState));
}

/-- # RenderPipelineDescriptor -/

alloy c opaque_extern_type RenderPipelineDescriptor => WGPURenderPipelineDescriptor where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPURenderPipelineDescriptor \n");
    if (ptr->vertex.entryPoint) free((void*)ptr->vertex.entryPoint);
    if (ptr->vertex.buffers) {
      for (uint32_t i = 0; i < ptr->vertex.bufferCount; i++) {
        if (ptr->vertex.buffers[i].attributes)
          free((void*)ptr->vertex.buffers[i].attributes);
      }
      free((void*)ptr->vertex.buffers);
    }
    if (ptr->depthStencil) free((void*)ptr->depthStencil);
    free(ptr);

alloy c extern
def RenderPipelineDescriptor.mk  (shaderModule : ShaderModule) (fState : FragmentState) : IO RenderPipelineDescriptor := {
  WGPUShaderModule * c_shaderModule = of_lean<ShaderModule>(shaderModule);
  WGPUFragmentState * fragmentState = of_lean<FragmentState>(fState);

  WGPURenderPipelineDescriptor * pipelineDesc = calloc(1,sizeof(WGPURenderPipelineDescriptor));
  pipelineDesc->nextInChain = NULL;

  pipelineDesc->vertex.bufferCount = 0;
  pipelineDesc->vertex.buffers = NULL;
  pipelineDesc->vertex.module = *c_shaderModule;
  pipelineDesc->vertex.entryPoint = strdup("vs_main");
  pipelineDesc->vertex.constantCount = 0;
  pipelineDesc->vertex.constants = NULL;

  pipelineDesc->primitive.topology = WGPUPrimitiveTopology_TriangleList;
  pipelineDesc->primitive.stripIndexFormat = WGPUIndexFormat_Undefined;
  pipelineDesc->primitive.frontFace = WGPUFrontFace_CCW;
  pipelineDesc->primitive.cullMode = WGPUCullMode_None;

  pipelineDesc->fragment = fragmentState;
  pipelineDesc->depthStencil = NULL;
  pipelineDesc->multisample.count = 1;
  -- fprintf(stderr, "multisample mask size: %d", sizeof(pipelineDesc->multisample.mask)); -- Kiiya: I get 4, so 0xFFFFFFFF should be okay
  pipelineDesc->multisample.mask = 0xFFFFFFFF;
  pipelineDesc->multisample.alphaToCoverageEnabled = false;
  pipelineDesc->layout = NULL;

  return lean_io_result_mk_ok(to_lean<RenderPipelineDescriptor>(pipelineDesc));
}

/-- Like `mk` but with a configurable multisample count (e.g. 4 for 4x MSAA). -/
alloy c extern
def RenderPipelineDescriptor.mkSampled (shaderModule : ShaderModule) (fState : FragmentState)
    (sampleCount : UInt32 := 1) : IO RenderPipelineDescriptor := {
  WGPUShaderModule *c_shaderModule = of_lean<ShaderModule>(shaderModule);
  WGPUFragmentState *fragmentState = of_lean<FragmentState>(fState);

  WGPURenderPipelineDescriptor *pipelineDesc = calloc(1,sizeof(WGPURenderPipelineDescriptor));
  pipelineDesc->nextInChain = NULL;
  pipelineDesc->vertex.bufferCount = 0;
  pipelineDesc->vertex.buffers = NULL;
  pipelineDesc->vertex.module = *c_shaderModule;
  pipelineDesc->vertex.entryPoint = strdup("vs_main");
  pipelineDesc->vertex.constantCount = 0;
  pipelineDesc->vertex.constants = NULL;
  pipelineDesc->primitive.topology = WGPUPrimitiveTopology_TriangleList;
  pipelineDesc->primitive.stripIndexFormat = WGPUIndexFormat_Undefined;
  pipelineDesc->primitive.frontFace = WGPUFrontFace_CCW;
  pipelineDesc->primitive.cullMode = WGPUCullMode_None;
  pipelineDesc->fragment = fragmentState;
  pipelineDesc->depthStencil = NULL;
  pipelineDesc->multisample.count = sampleCount;
  pipelineDesc->multisample.mask = 0xFFFFFFFF;
  pipelineDesc->multisample.alphaToCoverageEnabled = false;
  pipelineDesc->layout = NULL;
  return lean_io_result_mk_ok(to_lean<RenderPipelineDescriptor>(pipelineDesc));
}

/-- # RenderPipeline -/

alloy c opaque_extern_type RenderPipeline => WGPURenderPipeline where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPURenderPipeline \n");
    wgpuRenderPipelineRelease(*ptr);
    free(ptr);

-- TODO unclog that mess
alloy c extern
def RenderPipeline.mk (device : Device) (pipelineDesc : RenderPipelineDescriptor) : IO RenderPipeline := {
  WGPUDevice * c_device = of_lean<Device>(device);
  WGPURenderPipelineDescriptor * c_pipelineDesc = of_lean<RenderPipelineDescriptor>(pipelineDesc);
  WGPURenderPipeline * pipeline = calloc(1,sizeof(WGPURenderPipeline));
  *pipeline = wgpuDeviceCreateRenderPipeline(*c_device, c_pipelineDesc);
  return lean_io_result_mk_ok(to_lean<RenderPipeline>(pipeline));
}

/- # Vertex Buffer Support -/

alloy c enum VertexFormat => WGPUVertexFormat
| Undefined => WGPUVertexFormat_Undefined
| Uint8x2 => WGPUVertexFormat_Uint8x2
| Uint8x4 => WGPUVertexFormat_Uint8x4
| Sint8x2 => WGPUVertexFormat_Sint8x2
| Sint8x4 => WGPUVertexFormat_Sint8x4
| Unorm8x2 => WGPUVertexFormat_Unorm8x2
| Unorm8x4 => WGPUVertexFormat_Unorm8x4
| Snorm8x2 => WGPUVertexFormat_Snorm8x2
| Snorm8x4 => WGPUVertexFormat_Snorm8x4
| Uint16x2 => WGPUVertexFormat_Uint16x2
| Uint16x4 => WGPUVertexFormat_Uint16x4
| Sint16x2 => WGPUVertexFormat_Sint16x2
| Sint16x4 => WGPUVertexFormat_Sint16x4
| Unorm16x2 => WGPUVertexFormat_Unorm16x2
| Unorm16x4 => WGPUVertexFormat_Unorm16x4
| Snorm16x2 => WGPUVertexFormat_Snorm16x2
| Snorm16x4 => WGPUVertexFormat_Snorm16x4
| Float16x2 => WGPUVertexFormat_Float16x2
| Float16x4 => WGPUVertexFormat_Float16x4
| Float32 => WGPUVertexFormat_Float32
| Float32x2 => WGPUVertexFormat_Float32x2
| Float32x3 => WGPUVertexFormat_Float32x3
| Float32x4 => WGPUVertexFormat_Float32x4
| Uint32 => WGPUVertexFormat_Uint32
| Uint32x2 => WGPUVertexFormat_Uint32x2
| Uint32x3 => WGPUVertexFormat_Uint32x3
| Uint32x4 => WGPUVertexFormat_Uint32x4
| Sint32 => WGPUVertexFormat_Sint32
| Sint32x2 => WGPUVertexFormat_Sint32x2
| Sint32x3 => WGPUVertexFormat_Sint32x3
| Sint32x4 => WGPUVertexFormat_Sint32x4
| Force32 => WGPUVertexFormat_Force32
deriving Inhabited, Repr, BEq

/-- A single vertex attribute description (format, offset, shaderLocation). -/
structure VertexAttributeDesc where
  format : VertexFormat
  offset : UInt64
  shaderLocation : UInt32
deriving Inhabited, Repr

alloy c enum VertexStepMode => WGPUVertexStepMode
| Vertex => WGPUVertexStepMode_Vertex
| Instance => WGPUVertexStepMode_Instance
| VertexBufferNotUsed => WGPUVertexStepMode_VertexBufferNotUsed
| Force32 => WGPUVertexStepMode_Force32
deriving Inhabited, Repr, BEq

/-- Description of a vertex buffer layout (stride, stepMode, attributes). -/
structure VertexBufferLayoutDesc where
  arrayStride : UInt64
  stepMode : VertexStepMode
  attributes : Array VertexAttributeDesc
deriving Inhabited, Repr

alloy c enum IndexFormat => WGPUIndexFormat
| Undefined => WGPUIndexFormat_Undefined
| Uint16 => WGPUIndexFormat_Uint16
| Uint32 => WGPUIndexFormat_Uint32
| Force32 => WGPUIndexFormat_Force32
/- # RenderPipeline with Vertex Buffers -/

/--
  Create a render pipeline descriptor with vertex buffer layouts.
  `vertexBufferLayouts` is an array of `(arrayStride, stepMode, Array (format, offset, shaderLocation))`.
-/
alloy c extern
def RenderPipelineDescriptor.mkWithVertexBuffers
    (shaderModule : ShaderModule)
    (fState : FragmentState)
    (vertexEntryPoint : String := "vs_main")
    (strides : @& Array UInt64)
    (stepModes : @& Array UInt32)
    (attrFormats : @& Array UInt32)
    (attrOffsets : @& Array UInt64)
    (attrShaderLocations : @& Array UInt32)
    (attrBufferIndices : @& Array UInt32)
    (bufferCount : UInt32)
    : IO RenderPipelineDescriptor := {
  WGPUShaderModule *c_shaderModule = of_lean<ShaderModule>(shaderModule);
  WGPUFragmentState *fragmentState = of_lean<FragmentState>(fState);

  uint32_t nBuffers = bufferCount;
  size_t nAttrs = lean_array_size(attrFormats);

  -- Allocate vertex buffer layouts
  WGPUVertexBufferLayout *bufferLayouts = calloc(nBuffers, sizeof(WGPUVertexBufferLayout));
  for (uint32_t i = 0; i < nBuffers; i++) {
    bufferLayouts[i].arrayStride = lean_unbox_uint64(lean_array_uget(strides, i));
    bufferLayouts[i].stepMode = (WGPUVertexStepMode)lean_unbox(lean_array_uget(stepModes, i));
    bufferLayouts[i].attributeCount = 0;
    bufferLayouts[i].attributes = NULL;
  }

  -- Count attributes per buffer
  for (size_t i = 0; i < nAttrs; i++) {
    uint32_t bufIdx = lean_unbox(lean_array_uget(attrBufferIndices, i));
    bufferLayouts[bufIdx].attributeCount++;
  }

  -- Allocate attributes per buffer
  WGPUVertexAttribute **attrArrays = calloc(nBuffers, sizeof(WGPUVertexAttribute*));
  uint32_t *attrCounters = calloc(nBuffers, sizeof(uint32_t));
  for (uint32_t i = 0; i < nBuffers; i++) {
    attrArrays[i] = calloc(bufferLayouts[i].attributeCount, sizeof(WGPUVertexAttribute));
    bufferLayouts[i].attributes = attrArrays[i];
  }

  -- Fill in attributes
  for (size_t i = 0; i < nAttrs; i++) {
    uint32_t bufIdx = lean_unbox(lean_array_uget(attrBufferIndices, i));
    uint32_t ai = attrCounters[bufIdx]++;
    attrArrays[bufIdx][ai].format = (WGPUVertexFormat)lean_unbox(lean_array_uget(attrFormats, i));
    attrArrays[bufIdx][ai].offset = lean_unbox_uint64(lean_array_uget(attrOffsets, i));
    attrArrays[bufIdx][ai].shaderLocation = lean_unbox(lean_array_uget(attrShaderLocations, i));
  }
  free(attrCounters);
  free(attrArrays);

  WGPURenderPipelineDescriptor *pipelineDesc = calloc(1,sizeof(WGPURenderPipelineDescriptor));
  pipelineDesc->nextInChain = NULL;

  pipelineDesc->vertex.bufferCount = nBuffers;
  pipelineDesc->vertex.buffers = bufferLayouts;
  pipelineDesc->vertex.module = *c_shaderModule;
  pipelineDesc->vertex.entryPoint = strdup(lean_string_cstr(vertexEntryPoint));
  pipelineDesc->vertex.constantCount = 0;
  pipelineDesc->vertex.constants = NULL;

  pipelineDesc->primitive.topology = WGPUPrimitiveTopology_TriangleList;
  pipelineDesc->primitive.stripIndexFormat = WGPUIndexFormat_Undefined;
  pipelineDesc->primitive.frontFace = WGPUFrontFace_CCW;
  pipelineDesc->primitive.cullMode = WGPUCullMode_None;

  pipelineDesc->fragment = fragmentState;
  pipelineDesc->depthStencil = NULL;
  pipelineDesc->multisample.count = 1;
  pipelineDesc->multisample.mask = 0xFFFFFFFF;
  pipelineDesc->multisample.alphaToCoverageEnabled = false;
  pipelineDesc->layout = NULL;

  return lean_io_result_mk_ok(to_lean<RenderPipelineDescriptor>(pipelineDesc));
}

/-- Helper: Build a RenderPipelineDescriptor from pure Lean VertexBufferLayoutDesc array. -/
def RenderPipelineDescriptor.mkWithLayouts
    (shaderModule : ShaderModule)
    (fState : FragmentState)
    (layouts : Array VertexBufferLayoutDesc)
    (vertexEntryPoint : String := "vs_main")
    : IO RenderPipelineDescriptor := do
  let mut strides : Array UInt64 := #[]
  let mut stepModes : Array UInt32 := #[]
  let mut attrFormats : Array UInt32 := #[]
  let mut attrOffsets : Array UInt64 := #[]
  let mut attrShaderLocations : Array UInt32 := #[]
  let mut attrBufferIndices : Array UInt32 := #[]
  for h : i in [:layouts.size] do
    let layout := layouts[i]
    strides := strides.push layout.arrayStride
    stepModes := stepModes.push (match layout.stepMode with
      | .Vertex => 0 | .Instance => 1 | .VertexBufferNotUsed => 2 | .Force32 => 3)
    for attr in layout.attributes do
      attrFormats := attrFormats.push (match attr.format with
        | .Undefined => 0 | .Uint8x2 => 1 | .Uint8x4 => 2 | .Sint8x2 => 3 | .Sint8x4 => 4
        | .Unorm8x2 => 5 | .Unorm8x4 => 6 | .Snorm8x2 => 7 | .Snorm8x4 => 8
        | .Uint16x2 => 9 | .Uint16x4 => 10 | .Sint16x2 => 11 | .Sint16x4 => 12
        | .Unorm16x2 => 13 | .Unorm16x4 => 14 | .Snorm16x2 => 15 | .Snorm16x4 => 16
        | .Float16x2 => 17 | .Float16x4 => 18
        | .Float32 => 19 | .Float32x2 => 20 | .Float32x3 => 21 | .Float32x4 => 22
        | .Uint32 => 23 | .Uint32x2 => 24 | .Uint32x3 => 25 | .Uint32x4 => 26
        | .Sint32 => 27 | .Sint32x2 => 28 | .Sint32x3 => 29 | .Sint32x4 => 30
        | .Force32 => 31)
      attrOffsets := attrOffsets.push attr.offset
      attrShaderLocations := attrShaderLocations.push attr.shaderLocation
      attrBufferIndices := attrBufferIndices.push i.toUInt32
  RenderPipelineDescriptor.mkWithVertexBuffers shaderModule fState vertexEntryPoint
    strides stepModes attrFormats attrOffsets attrShaderLocations attrBufferIndices layouts.size.toUInt32

/- # Bind Group Support -/

alloy c opaque_extern_type BindGroupLayout => WGPUBindGroupLayout where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUBindGroupLayout \n");
    wgpuBindGroupLayoutRelease(*ptr);
    free(ptr);

alloy c opaque_extern_type BindGroup => WGPUBindGroup where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUBindGroup \n");
    wgpuBindGroupRelease(*ptr);
    free(ptr);

alloy c opaque_extern_type PipelineLayout => WGPUPipelineLayout where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUPipelineLayout \n");
    wgpuPipelineLayoutRelease(*ptr);
    free(ptr);

/-- Create a bind group layout with a single uniform buffer binding at the given binding index. -/
alloy c extern
def BindGroupLayout.mkUniform (device : Device) (binding : UInt32) (visibility : UInt32)
    (minBindingSize : UInt64 := 0) : IO BindGroupLayout := {
  WGPUDevice c_device = *of_lean<Device>(device);

  WGPUBindGroupLayoutEntry *entry = calloc(1, sizeof(WGPUBindGroupLayoutEntry));
  entry->binding = binding;
  entry->visibility = visibility;
  entry->buffer.type = WGPUBufferBindingType_Uniform;
  entry->buffer.hasDynamicOffset = false;
  entry->buffer.minBindingSize = minBindingSize;
  -- Zero-init the rest
  entry->sampler.type = WGPUSamplerBindingType_Undefined;
  entry->texture.sampleType = WGPUTextureSampleType_Undefined;
  entry->storageTexture.access = WGPUStorageTextureAccess_Undefined;

  WGPUBindGroupLayoutDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "Uniform bind group layout";
  desc.entryCount = 1;
  desc.entries = entry;

  WGPUBindGroupLayout *layout = calloc(1, sizeof(WGPUBindGroupLayout));
  *layout = wgpuDeviceCreateBindGroupLayout(c_device, &desc);
  free(entry);
  return lean_io_result_mk_ok(to_lean<BindGroupLayout>(layout));
}

/-- Create a bind group that binds a buffer to a layout. -/
alloy c extern
def BindGroup.mk (device : Device) (layout : BindGroupLayout) (binding : UInt32)
    (buffer : Buffer) (offset : UInt64 := 0) (size : UInt64 := 0) : IO BindGroup := {
  WGPUDevice c_device = *of_lean<Device>(device);
  WGPUBindGroupLayout *c_layout = of_lean<BindGroupLayout>(layout);
  WGPUBuffer *c_buffer = of_lean<Buffer>(buffer);

  uint64_t bufSize = size;
  if (bufSize == 0) {
    bufSize = wgpuBufferGetSize(*c_buffer) - offset;
  }

  WGPUBindGroupEntry *entry = calloc(1, sizeof(WGPUBindGroupEntry));
  entry->nextInChain = NULL;
  entry->binding = binding;
  entry->buffer = *c_buffer;
  entry->offset = offset;
  entry->size = bufSize;
  entry->sampler = NULL;
  entry->textureView = NULL;

  WGPUBindGroupDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "Bind group";
  desc.layout = *c_layout;
  desc.entryCount = 1;
  desc.entries = entry;

  WGPUBindGroup *bg = calloc(1, sizeof(WGPUBindGroup));
  *bg = wgpuDeviceCreateBindGroup(c_device, &desc);
  free(entry);
  return lean_io_result_mk_ok(to_lean<BindGroup>(bg));
}

/-- Create a pipeline layout from an array of bind group layouts. -/
alloy c extern
def PipelineLayout.mk (device : Device) (layouts : @& Array BindGroupLayout) : IO PipelineLayout := {
  WGPUDevice c_device = *of_lean<Device>(device);
  size_t n = lean_array_size(layouts);
  WGPUBindGroupLayout *c_layouts = calloc(n, sizeof(WGPUBindGroupLayout));
  for (size_t i = 0; i < n; i++) {
    lean_object *obj = lean_array_uget(layouts, i);
    WGPUBindGroupLayout *l = of_lean<BindGroupLayout>(obj);
    c_layouts[i] = *l;
  }
  WGPUPipelineLayoutDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "Pipeline layout";
  desc.bindGroupLayoutCount = n;
  desc.bindGroupLayouts = c_layouts;

  WGPUPipelineLayout *pl = calloc(1, sizeof(WGPUPipelineLayout));
  *pl = wgpuDeviceCreatePipelineLayout(c_device, &desc);
  free(c_layouts);
  return lean_io_result_mk_ok(to_lean<PipelineLayout>(pl));
}

/-- Create a render pipeline with an explicit pipeline layout.
    NOTE: This mutates `pipelineDesc.layout` in place. Do not reuse the
    descriptor with a different layout without re-setting it. -/
alloy c extern
def RenderPipeline.mkWithLayout (device : Device) (pipelineDesc : RenderPipelineDescriptor) (layout : PipelineLayout) : IO RenderPipeline := {
  WGPUDevice *c_device = of_lean<Device>(device);
  WGPURenderPipelineDescriptor *c_pipelineDesc = of_lean<RenderPipelineDescriptor>(pipelineDesc);
  WGPUPipelineLayout *c_layout = of_lean<PipelineLayout>(layout);
  c_pipelineDesc->layout = *c_layout;
  WGPURenderPipeline *pipeline = calloc(1,sizeof(WGPURenderPipeline));
  *pipeline = wgpuDeviceCreateRenderPipeline(*c_device, c_pipelineDesc);
  return lean_io_result_mk_ok(to_lean<RenderPipeline>(pipeline));
}

/- # Shader Stage Flags -/
abbrev ShaderStageFlags := UInt32
def ShaderStageFlags.none     : ShaderStageFlags := 0x00000000
def ShaderStageFlags.vertex   : ShaderStageFlags := 0x00000001
def ShaderStageFlags.fragment : ShaderStageFlags := 0x00000002
def ShaderStageFlags.compute  : ShaderStageFlags := 0x00000004

alloy c extern
def BindGroupLayout.mkTextureSampler (device : Device)
    (textureBinding samplerBinding : UInt32) (visibility : UInt32)
    : IO BindGroupLayout := {
  WGPUDevice c_device = *of_lean<Device>(device);

  WGPUBindGroupLayoutEntry *entries = calloc(2, sizeof(WGPUBindGroupLayoutEntry));

  entries[0].binding = textureBinding;
  entries[0].visibility = visibility;
  entries[0].texture.sampleType = WGPUTextureSampleType_Float;
  entries[0].texture.viewDimension = WGPUTextureViewDimension_2D;
  entries[0].texture.multisampled = false;
  entries[0].buffer.type = WGPUBufferBindingType_Undefined;
  entries[0].sampler.type = WGPUSamplerBindingType_Undefined;
  entries[0].storageTexture.access = WGPUStorageTextureAccess_Undefined;

  entries[1].binding = samplerBinding;
  entries[1].visibility = visibility;
  entries[1].sampler.type = WGPUSamplerBindingType_Filtering;
  entries[1].texture.sampleType = WGPUTextureSampleType_Undefined;
  entries[1].buffer.type = WGPUBufferBindingType_Undefined;
  entries[1].storageTexture.access = WGPUStorageTextureAccess_Undefined;

  WGPUBindGroupLayoutDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "Texture+Sampler bind group layout";
  desc.entryCount = 2;
  desc.entries = entries;

  WGPUBindGroupLayout *layout = calloc(1, sizeof(WGPUBindGroupLayout));
  *layout = wgpuDeviceCreateBindGroupLayout(c_device, &desc);
  free(entries);
  return lean_io_result_mk_ok(to_lean<BindGroupLayout>(layout));
}

/-- Create a bind group that binds a texture view and sampler. -/
alloy c extern
def BindGroup.mkTextureSampler (device : Device) (layout : BindGroupLayout)
    (textureBinding : UInt32) (textureView : TextureView)
    (samplerBinding : UInt32) (sampler : Sampler)
    : IO BindGroup := {
  WGPUDevice c_device = *of_lean<Device>(device);
  WGPUBindGroupLayout *c_layout = of_lean<BindGroupLayout>(layout);
  WGPUTextureView *c_view = of_lean<TextureView>(textureView);
  WGPUSampler *c_sampler = of_lean<Sampler>(sampler);

  WGPUBindGroupEntry *entries = calloc(2, sizeof(WGPUBindGroupEntry));

  entries[0].binding = textureBinding;
  entries[0].textureView = *c_view;
  entries[0].sampler = NULL;
  entries[0].buffer = NULL;
  entries[0].offset = 0;
  entries[0].size = 0;

  entries[1].binding = samplerBinding;
  entries[1].sampler = *c_sampler;
  entries[1].textureView = NULL;
  entries[1].buffer = NULL;
  entries[1].offset = 0;
  entries[1].size = 0;

  WGPUBindGroupDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "Texture+Sampler bind group";
  desc.layout = *c_layout;
  desc.entryCount = 2;
  desc.entries = entries;

  WGPUBindGroup *bg = calloc(1, sizeof(WGPUBindGroup));
  *bg = wgpuDeviceCreateBindGroup(c_device, &desc);
  free(entries);
  return lean_io_result_mk_ok(to_lean<BindGroup>(bg));
}

/- # Storage Buffer Bind Group Layouts -/

/-- Create a bind group layout for a single storage buffer binding. -/
alloy c extern
def BindGroupLayout.mkStorage (device : Device) (binding : UInt32) (visibility : UInt32)
    (readOnly : Bool := false) (minBindingSize : UInt64 := 0) : IO BindGroupLayout := {
  WGPUDevice c_device = *of_lean<Device>(device);

  WGPUBindGroupLayoutEntry *entry = calloc(1, sizeof(WGPUBindGroupLayoutEntry));
  entry->binding = binding;
  entry->visibility = visibility;
  entry->buffer.type = readOnly ? WGPUBufferBindingType_ReadOnlyStorage : WGPUBufferBindingType_Storage;
  entry->buffer.hasDynamicOffset = false;
  entry->buffer.minBindingSize = minBindingSize;
  entry->sampler.type = WGPUSamplerBindingType_Undefined;
  entry->texture.sampleType = WGPUTextureSampleType_Undefined;
  entry->storageTexture.access = WGPUStorageTextureAccess_Undefined;

  WGPUBindGroupLayoutDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "Storage bind group layout";
  desc.entryCount = 1;
  desc.entries = entry;

  WGPUBindGroupLayout *layout = calloc(1, sizeof(WGPUBindGroupLayout));
  *layout = wgpuDeviceCreateBindGroupLayout(c_device, &desc);
  free(entry);
  return lean_io_result_mk_ok(to_lean<BindGroupLayout>(layout));
}

/-- Create a bind group layout with two storage buffer bindings (e.g., input + output). -/
alloy c extern
def BindGroupLayout.mk2Storage (device : Device)
    (binding0 : UInt32) (visibility0 : UInt32) (readOnly0 : Bool)
    (binding1 : UInt32) (visibility1 : UInt32) (readOnly1 : Bool)
    : IO BindGroupLayout := {
  WGPUDevice c_device = *of_lean<Device>(device);

  WGPUBindGroupLayoutEntry *entries = calloc(2, sizeof(WGPUBindGroupLayoutEntry));

  entries[0].binding = binding0;
  entries[0].visibility = visibility0;
  entries[0].buffer.type = readOnly0 ? WGPUBufferBindingType_ReadOnlyStorage : WGPUBufferBindingType_Storage;
  entries[0].buffer.hasDynamicOffset = false;
  entries[0].buffer.minBindingSize = 0;
  entries[0].sampler.type = WGPUSamplerBindingType_Undefined;
  entries[0].texture.sampleType = WGPUTextureSampleType_Undefined;
  entries[0].storageTexture.access = WGPUStorageTextureAccess_Undefined;

  entries[1].binding = binding1;
  entries[1].visibility = visibility1;
  entries[1].buffer.type = readOnly1 ? WGPUBufferBindingType_ReadOnlyStorage : WGPUBufferBindingType_Storage;
  entries[1].buffer.hasDynamicOffset = false;
  entries[1].buffer.minBindingSize = 0;
  entries[1].sampler.type = WGPUSamplerBindingType_Undefined;
  entries[1].texture.sampleType = WGPUTextureSampleType_Undefined;
  entries[1].storageTexture.access = WGPUStorageTextureAccess_Undefined;

  WGPUBindGroupLayoutDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "2-Storage bind group layout";
  desc.entryCount = 2;
  desc.entries = entries;

  WGPUBindGroupLayout *layout = calloc(1, sizeof(WGPUBindGroupLayout));
  *layout = wgpuDeviceCreateBindGroupLayout(c_device, &desc);
  free(entries);
  return lean_io_result_mk_ok(to_lean<BindGroupLayout>(layout));
}

/-- Create a bind group with two buffer bindings. -/
alloy c extern
def BindGroup.mk2Buffers (device : Device) (layout : BindGroupLayout)
    (binding0 : UInt32) (buffer0 : Buffer)
    (binding1 : UInt32) (buffer1 : Buffer)
    : IO BindGroup := {
  WGPUDevice c_device = *of_lean<Device>(device);
  WGPUBindGroupLayout *c_layout = of_lean<BindGroupLayout>(layout);
  WGPUBuffer *c_buf0 = of_lean<Buffer>(buffer0);
  WGPUBuffer *c_buf1 = of_lean<Buffer>(buffer1);

  WGPUBindGroupEntry *entries = calloc(2, sizeof(WGPUBindGroupEntry));

  entries[0].binding = binding0;
  entries[0].buffer = *c_buf0;
  entries[0].offset = 0;
  entries[0].size = wgpuBufferGetSize(*c_buf0);
  entries[0].sampler = NULL;
  entries[0].textureView = NULL;

  entries[1].binding = binding1;
  entries[1].buffer = *c_buf1;
  entries[1].offset = 0;
  entries[1].size = wgpuBufferGetSize(*c_buf1);
  entries[1].sampler = NULL;
  entries[1].textureView = NULL;

  WGPUBindGroupDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "2-Buffer bind group";
  desc.layout = *c_layout;
  desc.entryCount = 2;
  desc.entries = entries;

  WGPUBindGroup *bg = calloc(1, sizeof(WGPUBindGroup));
  *bg = wgpuDeviceCreateBindGroup(c_device, &desc);
  free(entries);
  return lean_io_result_mk_ok(to_lean<BindGroup>(bg));
}

/- # Primitive Topology & Cull Mode -/

alloy c enum PrimitiveTopology => WGPUPrimitiveTopology
| PointList => WGPUPrimitiveTopology_PointList
| LineList => WGPUPrimitiveTopology_LineList
| LineStrip => WGPUPrimitiveTopology_LineStrip
| TriangleList => WGPUPrimitiveTopology_TriangleList
| TriangleStrip => WGPUPrimitiveTopology_TriangleStrip
| Force32 => WGPUPrimitiveTopology_Force32
deriving Inhabited, Repr, BEq

alloy c enum CullMode => WGPUCullMode
| None => WGPUCullMode_None
| Front => WGPUCullMode_Front
| Back => WGPUCullMode_Back
| Force32 => WGPUCullMode_Force32
deriving Inhabited, Repr, BEq

alloy c enum FrontFace => WGPUFrontFace
| CCW => WGPUFrontFace_CCW
| CW => WGPUFrontFace_CW
| Force32 => WGPUFrontFace_Force32
deriving Inhabited, Repr, BEq

alloy c extern
def RenderPipelineDescriptor.mkFull
    (shaderModule : ShaderModule)
    (fState : FragmentState)
    (vertexEntryPoint : String := "vs_main")
    (strides : @& Array UInt64)
    (stepModes : @& Array UInt32)
    (attrFormats : @& Array UInt32)
    (attrOffsets : @& Array UInt64)
    (attrShaderLocations : @& Array UInt32)
    (attrBufferIndices : @& Array UInt32)
    (bufferCount : UInt32)
    (topology : PrimitiveTopology := PrimitiveTopology.TriangleList)
    (cullMode : CullMode := CullMode.None)
    (frontFace : FrontFace := FrontFace.CCW)
    (enableDepth : Bool := false)
    (depthFormat : TextureFormat := TextureFormat.Depth24Plus)
    (depthCompare : CompareFunction := CompareFunction.Less)
    (depthWriteEnabled : Bool := true)
    : IO RenderPipelineDescriptor := {
  WGPUShaderModule *c_shaderModule = of_lean<ShaderModule>(shaderModule);
  WGPUFragmentState *fragmentState = of_lean<FragmentState>(fState);

  uint32_t nBuffers = bufferCount;
  size_t nAttrs = lean_array_size(attrFormats);

  WGPUVertexBufferLayout *bufferLayouts = calloc(nBuffers, sizeof(WGPUVertexBufferLayout));
  for (uint32_t i = 0; i < nBuffers; i++) {
    bufferLayouts[i].arrayStride = lean_unbox_uint64(lean_array_uget(strides, i));
    bufferLayouts[i].stepMode = (WGPUVertexStepMode)lean_unbox(lean_array_uget(stepModes, i));
    bufferLayouts[i].attributeCount = 0;
    bufferLayouts[i].attributes = NULL;
  }
  for (size_t i = 0; i < nAttrs; i++) {
    uint32_t bufIdx = lean_unbox(lean_array_uget(attrBufferIndices, i));
    bufferLayouts[bufIdx].attributeCount++;
  }
  WGPUVertexAttribute **attrArrays = calloc(nBuffers, sizeof(WGPUVertexAttribute*));
  uint32_t *attrCounters = calloc(nBuffers, sizeof(uint32_t));
  for (uint32_t i = 0; i < nBuffers; i++) {
    attrArrays[i] = calloc(bufferLayouts[i].attributeCount, sizeof(WGPUVertexAttribute));
    bufferLayouts[i].attributes = attrArrays[i];
  }
  for (size_t i = 0; i < nAttrs; i++) {
    uint32_t bufIdx = lean_unbox(lean_array_uget(attrBufferIndices, i));
    uint32_t ai = attrCounters[bufIdx]++;
    attrArrays[bufIdx][ai].format = (WGPUVertexFormat)lean_unbox(lean_array_uget(attrFormats, i));
    attrArrays[bufIdx][ai].offset = lean_unbox_uint64(lean_array_uget(attrOffsets, i));
    attrArrays[bufIdx][ai].shaderLocation = lean_unbox(lean_array_uget(attrShaderLocations, i));
  }
  free(attrCounters);
  free(attrArrays);

  WGPURenderPipelineDescriptor *pipelineDesc = calloc(1, sizeof(WGPURenderPipelineDescriptor));
  pipelineDesc->nextInChain = NULL;
  pipelineDesc->vertex.bufferCount = nBuffers;
  pipelineDesc->vertex.buffers = bufferLayouts;
  pipelineDesc->vertex.module = *c_shaderModule;
  pipelineDesc->vertex.entryPoint = strdup(lean_string_cstr(vertexEntryPoint));
  pipelineDesc->vertex.constantCount = 0;
  pipelineDesc->vertex.constants = NULL;

  pipelineDesc->primitive.topology = of_lean<PrimitiveTopology>(topology);
  pipelineDesc->primitive.stripIndexFormat = WGPUIndexFormat_Undefined;
  pipelineDesc->primitive.frontFace = of_lean<FrontFace>(frontFace);
  pipelineDesc->primitive.cullMode = of_lean<CullMode>(cullMode);

  if (enableDepth) {
    WGPUDepthStencilState *depthState = calloc(1, sizeof(WGPUDepthStencilState));
    depthState->nextInChain = NULL;
    depthState->format = of_lean<TextureFormat>(depthFormat);
    depthState->depthWriteEnabled = depthWriteEnabled;
    depthState->depthCompare = of_lean<CompareFunction>(depthCompare);
    depthState->stencilFront.compare = WGPUCompareFunction_Always;
    depthState->stencilFront.failOp = WGPUStencilOperation_Keep;
    depthState->stencilFront.depthFailOp = WGPUStencilOperation_Keep;
    depthState->stencilFront.passOp = WGPUStencilOperation_Keep;
    depthState->stencilBack = depthState->stencilFront;
    depthState->stencilReadMask = 0xFFFFFFFF;
    depthState->stencilWriteMask = 0xFFFFFFFF;
    depthState->depthBias = 0;
    depthState->depthBiasSlopeScale = 0.0f;
    depthState->depthBiasClamp = 0.0f;
    pipelineDesc->depthStencil = depthState;
  } else {
    pipelineDesc->depthStencil = NULL;
  }

  pipelineDesc->fragment = fragmentState;
  pipelineDesc->multisample.count = 1;
  pipelineDesc->multisample.mask = 0xFFFFFFFF;
  pipelineDesc->multisample.alphaToCoverageEnabled = false;
  pipelineDesc->layout = NULL;

  return lean_io_result_mk_ok(to_lean<RenderPipelineDescriptor>(pipelineDesc));
}

/-- High-level helper: build a pipeline descriptor with depth, topology, and cull mode from Lean data. -/
def RenderPipelineDescriptor.mkFullLayouts
    (shaderModule : ShaderModule)
    (fState : FragmentState)
    (layouts : Array VertexBufferLayoutDesc)
    (vertexEntryPoint : String := "vs_main")
    (topology : PrimitiveTopology := PrimitiveTopology.TriangleList)
    (cullMode : CullMode := CullMode.None)
    (frontFace : FrontFace := FrontFace.CCW)
    (enableDepth : Bool := false)
    (depthFormat : TextureFormat := TextureFormat.Depth24Plus)
    (depthCompare : CompareFunction := CompareFunction.Less)
    (depthWriteEnabled : Bool := true)
    : IO RenderPipelineDescriptor := do
  let mut strides : Array UInt64 := #[]
  let mut stepModes : Array UInt32 := #[]
  let mut attrFormats : Array UInt32 := #[]
  let mut attrOffsets : Array UInt64 := #[]
  let mut attrShaderLocations : Array UInt32 := #[]
  let mut attrBufferIndices : Array UInt32 := #[]
  for h : i in [:layouts.size] do
    let layout := layouts[i]
    strides := strides.push layout.arrayStride
    stepModes := stepModes.push (match layout.stepMode with
      | .Vertex => 0 | .Instance => 1 | .VertexBufferNotUsed => 2 | .Force32 => 3)
    for attr in layout.attributes do
      attrFormats := attrFormats.push (match attr.format with
        | .Undefined => 0 | .Uint8x2 => 1 | .Uint8x4 => 2 | .Sint8x2 => 3 | .Sint8x4 => 4
        | .Unorm8x2 => 5 | .Unorm8x4 => 6 | .Snorm8x2 => 7 | .Snorm8x4 => 8
        | .Uint16x2 => 9 | .Uint16x4 => 10 | .Sint16x2 => 11 | .Sint16x4 => 12
        | .Unorm16x2 => 13 | .Unorm16x4 => 14 | .Snorm16x2 => 15 | .Snorm16x4 => 16
        | .Float16x2 => 17 | .Float16x4 => 18
        | .Float32 => 19 | .Float32x2 => 20 | .Float32x3 => 21 | .Float32x4 => 22
        | .Uint32 => 23 | .Uint32x2 => 24 | .Uint32x3 => 25 | .Uint32x4 => 26
        | .Sint32 => 27 | .Sint32x2 => 28 | .Sint32x3 => 29 | .Sint32x4 => 30
        | .Force32 => 31)
      attrOffsets := attrOffsets.push attr.offset
      attrShaderLocations := attrShaderLocations.push attr.shaderLocation
      attrBufferIndices := attrBufferIndices.push i.toUInt32
  RenderPipelineDescriptor.mkFull shaderModule fState vertexEntryPoint
    strides stepModes attrFormats attrOffsets attrShaderLocations attrBufferIndices
    layouts.size.toUInt32 topology cullMode frontFace enableDepth depthFormat depthCompare depthWriteEnabled

/- # Multiple Color Targets (MRT) -/

/-- Create a FragmentState with multiple color targets. -/
alloy c extern
def FragmentState.mkMulti (shaderModule : ShaderModule)
    (colorTargets : @& Array ColorTargetState)
    (entryPoint : String := "fs_main")
    : IO FragmentState := {
  WGPUShaderModule *c_shaderModule = of_lean<ShaderModule>(shaderModule);
  size_t n = lean_array_size(colorTargets);
  WGPUColorTargetState *targets = calloc(n, sizeof(WGPUColorTargetState));
  for (size_t i = 0; i < n; i++) {
    WGPUColorTargetState *ct = of_lean<ColorTargetState>(lean_array_uget(colorTargets, i));
    targets[i] = *ct;
    -- Deep-copy the blend state so FragmentState owns it
    if (ct->blend) {
      WGPUBlendState *blendCopy = calloc(1, sizeof(WGPUBlendState));
      *blendCopy = *(ct->blend);
      targets[i].blend = blendCopy;
    }
  }
  WGPUFragmentState *fragmentState = calloc(1, sizeof(WGPUFragmentState));
  fragmentState->module = *c_shaderModule;
  fragmentState->entryPoint = strdup(lean_string_cstr(entryPoint));
  fragmentState->constantCount = 0;
  fragmentState->constants = NULL;
  fragmentState->targetCount = n;
  fragmentState->targets = targets;
  return lean_io_result_mk_ok(to_lean<FragmentState>(fragmentState));
}

/- # Pipeline Bind Group Layout Introspection -/

/-- Get the bind group layout from a render pipeline at the given group index. -/
alloy c extern
def RenderPipeline.getBindGroupLayout (pipeline : RenderPipeline) (groupIndex : UInt32)
    : IO BindGroupLayout := {
  WGPURenderPipeline *c_pipeline = of_lean<RenderPipeline>(pipeline);
  WGPUBindGroupLayout *layout = calloc(1, sizeof(WGPUBindGroupLayout));
  *layout = wgpuRenderPipelineGetBindGroupLayout(*c_pipeline, groupIndex);
  return lean_io_result_mk_ok(to_lean<BindGroupLayout>(layout));
}

/- ################################################################## -/
/- # Stencil Operations                                               -/
/- ################################################################## -/

alloy c enum StencilOperation => WGPUStencilOperation
| Keep           => WGPUStencilOperation_Keep
| Zero           => WGPUStencilOperation_Zero
| Replace        => WGPUStencilOperation_Replace
| Invert         => WGPUStencilOperation_Invert
| IncrementClamp => WGPUStencilOperation_IncrementClamp
| DecrementClamp => WGPUStencilOperation_DecrementClamp
| IncrementWrap  => WGPUStencilOperation_IncrementWrap
| DecrementWrap  => WGPUStencilOperation_DecrementWrap
deriving Inhabited, Repr, BEq

/-- A stencil face state descriptor. -/
structure StencilFaceState where
  compare   : CompareFunction := CompareFunction.Always
  failOp    : StencilOperation := StencilOperation.Keep
  depthFailOp : StencilOperation := StencilOperation.Keep
  passOp    : StencilOperation := StencilOperation.Keep
  deriving Inhabited, Repr

/- ################################################################## -/
/- # Pipeline Descriptor with Stencil Configuration                   -/
/- ################################################################## -/

/-- Create a render pipeline descriptor with full depth-stencil configuration including
    custom stencil operations, read/write masks, and depth bias. -/
alloy c extern
def RenderPipelineDescriptor.mkWithStencil
    (shaderModule : ShaderModule) (fState : FragmentState)
    (buffers : @& Array VertexBufferLayoutDesc)
    (topology : PrimitiveTopology := PrimitiveTopology.TriangleList)
    (cullMode : CullMode := CullMode.None)
    (frontFace : FrontFace := FrontFace.CCW)
    (depthFormat : TextureFormat := TextureFormat.Depth24Plus)
    (depthCompare : CompareFunction := CompareFunction.Less)
    (depthWriteEnabled : Bool := true)
    (stencilFront : StencilFaceState := {})
    (stencilBack : StencilFaceState := {})
    (stencilReadMask : UInt32 := 0xFF)
    (stencilWriteMask : UInt32 := 0xFF)
    (sampleCount : UInt32 := 1)
    : IO RenderPipelineDescriptor := {
  WGPUShaderModule *sm = of_lean<ShaderModule>(shaderModule);
  WGPUFragmentState *fs = of_lean<FragmentState>(fState);

  size_t buf_count = lean_array_size(buffers);
  WGPUVertexBufferLayout *c_buffers = NULL;
  WGPUVertexAttribute **attr_arrays = NULL;
  if (buf_count > 0) {
    c_buffers = calloc(buf_count, sizeof(WGPUVertexBufferLayout));
    attr_arrays = calloc(buf_count, sizeof(WGPUVertexAttribute*));
    for (size_t i = 0; i < buf_count; i++) {
      lean_object *vbl_obj = lean_array_get_core(buffers, i);
      uint64_t stride = lean_unbox_uint64(lean_ctor_get(vbl_obj, 0));
      uint8_t step = lean_unbox(lean_ctor_get(vbl_obj, 1));
      lean_object *attrs = lean_ctor_get(vbl_obj, 2);
      size_t attr_count = lean_array_size(attrs);
      WGPUVertexAttribute *c_attrs = calloc(attr_count, sizeof(WGPUVertexAttribute));
      attr_arrays[i] = c_attrs;
      for (size_t j = 0; j < attr_count; j++) {
        lean_object *a = lean_array_get_core(attrs, j);
        c_attrs[j].format = (WGPUVertexFormat)lean_unbox(lean_ctor_get(a, 0));
        c_attrs[j].offset = lean_unbox_uint64(lean_ctor_get(a, 1));
        c_attrs[j].shaderLocation = lean_unbox(lean_ctor_get(a, 2));
      }
      c_buffers[i].arrayStride = stride;
      c_buffers[i].stepMode = (WGPUVertexStepMode)step;
      c_buffers[i].attributeCount = attr_count;
      c_buffers[i].attributes = c_attrs;
    }
    free(attr_arrays);
  }

  // Extract stencil face state fields
  uint8_t sf_compare  = lean_unbox(lean_ctor_get(stencilFront, 0));
  uint8_t sf_fail     = lean_unbox(lean_ctor_get(stencilFront, 1));
  uint8_t sf_depthFail= lean_unbox(lean_ctor_get(stencilFront, 2));
  uint8_t sf_pass     = lean_unbox(lean_ctor_get(stencilFront, 3));

  uint8_t sb_compare  = lean_unbox(lean_ctor_get(stencilBack, 0));
  uint8_t sb_fail     = lean_unbox(lean_ctor_get(stencilBack, 1));
  uint8_t sb_depthFail= lean_unbox(lean_ctor_get(stencilBack, 2));
  uint8_t sb_pass     = lean_unbox(lean_ctor_get(stencilBack, 3));

  WGPURenderPipelineDescriptor *desc = calloc(1, sizeof(WGPURenderPipelineDescriptor));
  desc->nextInChain = NULL;
  desc->label = NULL;
  desc->layout = NULL;

  desc->vertex.module = *sm;
  desc->vertex.entryPoint = strdup("vs_main");
  desc->vertex.constantCount = 0;
  desc->vertex.constants = NULL;
  desc->vertex.bufferCount = buf_count;
  desc->vertex.buffers = c_buffers;

  desc->primitive.topology = of_lean<PrimitiveTopology>(topology);
  desc->primitive.frontFace = of_lean<FrontFace>(frontFace);
  desc->primitive.cullMode = of_lean<CullMode>(cullMode);
  desc->primitive.stripIndexFormat = WGPUIndexFormat_Undefined;

  WGPUDepthStencilState *ds = calloc(1, sizeof(WGPUDepthStencilState));
  ds->format = of_lean<TextureFormat>(depthFormat);
  ds->depthWriteEnabled = depthWriteEnabled ? 1 : 0;
  ds->depthCompare = of_lean<CompareFunction>(depthCompare);
  ds->stencilFront.compare = (WGPUCompareFunction)sf_compare;
  ds->stencilFront.failOp = (WGPUStencilOperation)sf_fail;
  ds->stencilFront.depthFailOp = (WGPUStencilOperation)sf_depthFail;
  ds->stencilFront.passOp = (WGPUStencilOperation)sf_pass;
  ds->stencilBack.compare = (WGPUCompareFunction)sb_compare;
  ds->stencilBack.failOp = (WGPUStencilOperation)sb_fail;
  ds->stencilBack.depthFailOp = (WGPUStencilOperation)sb_depthFail;
  ds->stencilBack.passOp = (WGPUStencilOperation)sb_pass;
  ds->stencilReadMask = stencilReadMask;
  ds->stencilWriteMask = stencilWriteMask;
  ds->depthBias = 0;
  ds->depthBiasSlopeScale = 0.0f;
  ds->depthBiasClamp = 0.0f;
  desc->depthStencil = ds;

  desc->multisample.count = sampleCount;
  desc->multisample.mask = 0xFFFFFFFF;
  desc->multisample.alphaToCoverageEnabled = 0;

  desc->fragment = fs;

  return lean_io_result_mk_ok(to_lean<RenderPipelineDescriptor>(desc));
}

/- ################################################################## -/
/- # BindGroup with N buffer entries (generic)                        -/
/- ################################################################## -/

/-- Create a bind group with an arbitrary array of buffer bindings.
    Each element of `bindings` is (bindingIndex, buffer, offset, size). -/
alloy c extern
def BindGroup.mkBuffers (device : Device) (layout : BindGroupLayout)
    (bindings : @& Array (UInt32 × Buffer × UInt64 × UInt64)) : IO BindGroup := {
  WGPUDevice *c_device = of_lean<Device>(device);
  WGPUBindGroupLayout *c_layout = of_lean<BindGroupLayout>(layout);
  size_t count = lean_array_size(bindings);
  WGPUBindGroupEntry *entries = calloc(count, sizeof(WGPUBindGroupEntry));
  for (size_t i = 0; i < count; i++) {
    lean_object *tuple = lean_array_get_core(bindings, i);
    uint32_t binding = lean_unbox(lean_ctor_get(tuple, 0));
    lean_object *rest1 = lean_ctor_get(tuple, 1);
    lean_object *buf_obj = lean_ctor_get(rest1, 0);
    lean_object *rest2 = lean_ctor_get(rest1, 1);
    uint64_t offset = lean_unbox_uint64(lean_ctor_get(rest2, 0));
    uint64_t size = lean_unbox_uint64(lean_ctor_get(rest2, 1));
    WGPUBuffer *c_buf = of_lean<Buffer>(buf_obj);
    entries[i].binding = binding;
    entries[i].buffer = *c_buf;
    entries[i].offset = offset;
    entries[i].size = size;
    entries[i].sampler = NULL;
    entries[i].textureView = NULL;
  }
  WGPUBindGroupDescriptor desc = {
    .nextInChain = NULL,
    .label = NULL,
    .layout = *c_layout,
    .entryCount = count,
    .entries = entries,
  };
  WGPUBindGroup *bg = calloc(1, sizeof(WGPUBindGroup));
  *bg = wgpuDeviceCreateBindGroup(*c_device, &desc);
  free(entries);
  return lean_io_result_mk_ok(to_lean<BindGroup>(bg));
}

/- ################################################################## -/
/- # BindGroupLayout with N uniform/storage entries (generic)         -/
/- ################################################################## -/

/-- Create a bind group layout with an arbitrary array of buffer binding entries.
    Each element: (binding, visibility, isStorage : Bool, minBindingSize).
    If isStorage=false, creates a uniform binding. If true, a read-only storage binding. -/
alloy c extern
def BindGroupLayout.mkEntries (device : Device)
    (entries : @& Array (UInt32 × UInt32 × Bool × UInt64)) : IO BindGroupLayout := {
  WGPUDevice *c_device = of_lean<Device>(device);
  size_t count = lean_array_size(entries);
  WGPUBindGroupLayoutEntry *c_entries = calloc(count, sizeof(WGPUBindGroupLayoutEntry));
  for (size_t i = 0; i < count; i++) {
    lean_object *tuple = lean_array_get_core(entries, i);
    uint32_t binding = lean_unbox(lean_ctor_get(tuple, 0));
    lean_object *rest1 = lean_ctor_get(tuple, 1);
    uint32_t visibility = lean_unbox(lean_ctor_get(rest1, 0));
    lean_object *rest2 = lean_ctor_get(rest1, 1);
    uint8_t is_storage = lean_unbox(lean_ctor_get(rest2, 0));
    uint64_t min_size = lean_unbox_uint64(lean_ctor_get(rest2, 1));

    memset(&c_entries[i], 0, sizeof(WGPUBindGroupLayoutEntry));
    c_entries[i].binding = binding;
    c_entries[i].visibility = visibility;
    if (is_storage) {
      c_entries[i].buffer.type = WGPUBufferBindingType_ReadOnlyStorage;
    } else {
      c_entries[i].buffer.type = WGPUBufferBindingType_Uniform;
    }
    c_entries[i].buffer.minBindingSize = min_size;
  }
  WGPUBindGroupLayoutDescriptor desc = {
    .nextInChain = NULL,
    .label = NULL,
    .entryCount = count,
    .entries = c_entries,
  };
  WGPUBindGroupLayout *bgl = calloc(1, sizeof(WGPUBindGroupLayout));
  *bgl = wgpuDeviceCreateBindGroupLayout(*c_device, &desc);
  free(c_entries);
  return lean_io_result_mk_ok(to_lean<BindGroupLayout>(bgl));
}

/- ################################################################## -/
/- # Depth texture + comparison sampler layout/bind group             -/
/- ################################################################## -/

/-- Create a bind group layout for a depth texture (comparison) + comparison sampler.
    This is used for shadow mapping: the texture is sampled with textureSampleCompare. -/
alloy c extern
def BindGroupLayout.mkDepthTextureSampler (device : Device)
    (textureBinding samplerBinding : UInt32) (visibility : UInt32)
    : IO BindGroupLayout := {
  WGPUDevice c_device = *of_lean<Device>(device);

  WGPUBindGroupLayoutEntry *entries = calloc(2, sizeof(WGPUBindGroupLayoutEntry));

  entries[0].binding = textureBinding;
  entries[0].visibility = visibility;
  entries[0].texture.sampleType = WGPUTextureSampleType_Depth;
  entries[0].texture.viewDimension = WGPUTextureViewDimension_2D;
  entries[0].texture.multisampled = false;
  entries[0].buffer.type = WGPUBufferBindingType_Undefined;
  entries[0].sampler.type = WGPUSamplerBindingType_Undefined;
  entries[0].storageTexture.access = WGPUStorageTextureAccess_Undefined;

  entries[1].binding = samplerBinding;
  entries[1].visibility = visibility;
  entries[1].sampler.type = WGPUSamplerBindingType_Comparison;
  entries[1].buffer.type = WGPUBufferBindingType_Undefined;
  entries[1].texture.sampleType = WGPUTextureSampleType_Undefined;
  entries[1].storageTexture.access = WGPUStorageTextureAccess_Undefined;

  WGPUBindGroupLayoutDescriptor desc = {
    .nextInChain = NULL,
    .label = NULL,
    .entryCount = 2,
    .entries = entries,
  };

  WGPUBindGroupLayout *layout = calloc(1, sizeof(WGPUBindGroupLayout));
  *layout = wgpuDeviceCreateBindGroupLayout(c_device, &desc);
  free(entries);
  return lean_io_result_mk_ok(to_lean<BindGroupLayout>(layout));
}

/-- Create a render pass with ONLY depth (no color attachment). For shadow map generation. -/
alloy c extern
def RenderPipelineDescriptor.mkDepthOnly
    (shaderModule : ShaderModule)
    (buffers : @& Array VertexBufferLayoutDesc)
    (topology : PrimitiveTopology := PrimitiveTopology.TriangleList)
    (cullMode : CullMode := CullMode.Back)
    (frontFace : FrontFace := FrontFace.CCW)
    (depthFormat : TextureFormat := TextureFormat.Depth24Plus)
    (depthCompare : CompareFunction := CompareFunction.Less)
    : IO RenderPipelineDescriptor := {
  WGPUShaderModule *sm = of_lean<ShaderModule>(shaderModule);

  size_t buf_count = lean_array_size(buffers);
  WGPUVertexBufferLayout *c_buffers = NULL;
  WGPUVertexAttribute **attr_arrays = NULL;
  if (buf_count > 0) {
    c_buffers = calloc(buf_count, sizeof(WGPUVertexBufferLayout));
    attr_arrays = calloc(buf_count, sizeof(WGPUVertexAttribute*));
    for (size_t i = 0; i < buf_count; i++) {
      lean_object *vbl_obj = lean_array_get_core(buffers, i);
      uint64_t stride = lean_unbox_uint64(lean_ctor_get(vbl_obj, 0));
      uint8_t step = lean_unbox(lean_ctor_get(vbl_obj, 1));
      lean_object *attrs = lean_ctor_get(vbl_obj, 2);
      size_t attr_count = lean_array_size(attrs);
      WGPUVertexAttribute *c_attrs = calloc(attr_count, sizeof(WGPUVertexAttribute));
      attr_arrays[i] = c_attrs;
      for (size_t j = 0; j < attr_count; j++) {
        lean_object *a = lean_array_get_core(attrs, j);
        c_attrs[j].format = (WGPUVertexFormat)lean_unbox(lean_ctor_get(a, 0));
        c_attrs[j].offset = lean_unbox_uint64(lean_ctor_get(a, 1));
        c_attrs[j].shaderLocation = lean_unbox(lean_ctor_get(a, 2));
      }
      c_buffers[i].arrayStride = stride;
      c_buffers[i].stepMode = (WGPUVertexStepMode)step;
      c_buffers[i].attributeCount = attr_count;
      c_buffers[i].attributes = c_attrs;
    }
    free(attr_arrays);
  }

  WGPURenderPipelineDescriptor *desc = calloc(1, sizeof(WGPURenderPipelineDescriptor));
  desc->nextInChain = NULL;
  desc->label = NULL;
  desc->layout = NULL;

  desc->vertex.module = *sm;
  desc->vertex.entryPoint = strdup("vs_shadow");
  desc->vertex.constantCount = 0;
  desc->vertex.constants = NULL;
  desc->vertex.bufferCount = buf_count;
  desc->vertex.buffers = c_buffers;

  desc->primitive.topology = of_lean<PrimitiveTopology>(topology);
  desc->primitive.frontFace = of_lean<FrontFace>(frontFace);
  desc->primitive.cullMode = of_lean<CullMode>(cullMode);
  desc->primitive.stripIndexFormat = WGPUIndexFormat_Undefined;

  WGPUDepthStencilState *ds = calloc(1, sizeof(WGPUDepthStencilState));
  ds->format = of_lean<TextureFormat>(depthFormat);
  ds->depthWriteEnabled = 1;
  ds->depthCompare = of_lean<CompareFunction>(depthCompare);
  ds->stencilFront.compare = WGPUCompareFunction_Always;
  ds->stencilFront.failOp = WGPUStencilOperation_Keep;
  ds->stencilFront.depthFailOp = WGPUStencilOperation_Keep;
  ds->stencilFront.passOp = WGPUStencilOperation_Keep;
  ds->stencilBack = ds->stencilFront;
  ds->stencilReadMask = 0xFF;
  ds->stencilWriteMask = 0xFF;
  desc->depthStencil = ds;

  desc->multisample.count = 1;
  desc->multisample.mask = 0xFFFFFFFF;
  desc->multisample.alphaToCoverageEnabled = 0;

  // No fragment state — depth only
  desc->fragment = NULL;

  return lean_io_result_mk_ok(to_lean<RenderPipelineDescriptor>(desc));
}

alloy c extern
def RenderPipeline.setLabel (pipeline : RenderPipeline) (label : @& String) : IO Unit := {
  WGPURenderPipeline *c_pipeline = of_lean<RenderPipeline>(pipeline);
  wgpuRenderPipelineSetLabel(*c_pipeline, lean_string_cstr(label));
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set the debug label of a compute pipeline. -/
alloy c extern
def ShaderModule.setLabel (sm : ShaderModule) (label : @& String) : IO Unit := {
  WGPUShaderModule *c_sm = of_lean<ShaderModule>(sm);
  wgpuShaderModuleSetLabel(*c_sm, lean_string_cstr(label));
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Explicitly release a shader module.
    Useful to free GPU memory early instead of waiting for GC.
    The handle becomes invalid after this call. -/
alloy c extern
def ShaderModule.release (sm : ShaderModule) : IO Unit := {
  WGPUShaderModule *c_sm = of_lean<ShaderModule>(sm);
  wgpuShaderModuleRelease(*c_sm);
  *c_sm = NULL;
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set the debug label of a bind group layout. -/
alloy c extern
def BindGroupLayout.setLabel (layout : BindGroupLayout) (label : @& String) : IO Unit := {
  WGPUBindGroupLayout *c_layout = of_lean<BindGroupLayout>(layout);
  wgpuBindGroupLayoutSetLabel(*c_layout, lean_string_cstr(label));
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set the debug label of a bind group. -/
alloy c extern
def BindGroup.setLabel (bg : BindGroup) (label : @& String) : IO Unit := {
  WGPUBindGroup *c_bg = of_lean<BindGroup>(bg);
  wgpuBindGroupSetLabel(*c_bg, lean_string_cstr(label));
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set the debug label of a pipeline layout. -/
alloy c extern
def PipelineLayout.setLabel (layout : PipelineLayout) (label : @& String) : IO Unit := {
  WGPUPipelineLayout *c_layout = of_lean<PipelineLayout>(layout);
  wgpuPipelineLayoutSetLabel(*c_layout, lean_string_cstr(label));
  return lean_io_result_mk_ok(lean_box(0));
}

/- ################################################################## -/
/- # Shader Compilation Info                                          -/
/- ################################################################## -/

/-- A single shader compilation message. -/
structure CompilationMessage where
  message : String
  lineNum : UInt64
  linePos : UInt64
  offset  : UInt64
  length  : UInt64
  msgType : UInt32  -- 0=error, 1=warning, 2=info
deriving Repr

@[export lean_wgpu_mk_compilation_message]
def mkCompilationMessage (msg : String) (lineNum linePos offset length : UInt64) (msgType : UInt32) : CompilationMessage :=
  { message := msg, lineNum, linePos, offset, length, msgType }

alloy c section
  extern lean_object* lean_wgpu_mk_compilation_message(
    lean_object* msg, uint64_t lineNum, uint64_t linePos,
    uint64_t offset, uint64_t length, uint32_t msgType);

  static lean_object* g_compilation_info_result = NULL;
  static int g_compilation_info_done = 0;

  static void compilation_info_cb(WGPUCompilationInfoRequestStatus status,
      struct WGPUCompilationInfo const *info, void *userdata) {
    (void)userdata;
    if (status != WGPUCompilationInfoRequestStatus_Success || info == NULL) {
      g_compilation_info_result = lean_mk_array(lean_box(0), lean_box(0));
      g_compilation_info_done = 1;
      return;
    }
    lean_object *arr = lean_mk_array(lean_box(0), lean_box(0));
    for (size_t i = 0; i < info->messageCount; i++) {
      const WGPUCompilationMessage *m = &info->messages[i];
      lean_object *msg = lean_mk_string(m->message ? m->message : "");
      lean_object *cm = lean_wgpu_mk_compilation_message(
        msg, m->lineNum, m->linePos, m->offset, m->length, (uint32_t)m->type);
      arr = lean_array_push(arr, cm);
    }
    g_compilation_info_result = arr;
    g_compilation_info_done = 1;
  }
end

/-- Get shader compilation info (messages/warnings/errors). Polls the device until ready. -/
alloy c extern
def ShaderModule.getCompilationInfo (sm : ShaderModule) (device : Device) : IO (Array CompilationMessage) := {
  WGPUShaderModule *c_sm = of_lean<ShaderModule>(sm);
  WGPUDevice *c_device = of_lean<Device>(device);

  g_compilation_info_done = 0;
  g_compilation_info_result = NULL;
  wgpuShaderModuleGetCompilationInfo(*c_sm, compilation_info_cb, NULL);

  for (int i = 0; i < 1000 && !g_compilation_info_done; i++) {
    wgpuDevicePoll(*c_device, false, NULL);
  }

  if (g_compilation_info_result == NULL) {
    g_compilation_info_result = lean_mk_array(lean_box(0), lean_box(0));
  }
  return lean_io_result_mk_ok(g_compilation_info_result);
}


end Wgpu
