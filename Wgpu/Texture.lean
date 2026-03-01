import Alloy.C
import Wgpu.Device
import Wgpu.TextureFormat
import Wgpu.Surface
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
  static inline WGPUSurfaceTexture* _alloy_of_l_Wgpu_SurfaceTexture(b_lean_obj_arg o) { return (WGPUSurfaceTexture*)lean_get_external_data(o); }
end

/-- # TextureView -/

alloy c opaque_extern_type TextureView => WGPUTextureView where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUTextureView \n");
    wgpuTextureViewRelease(*ptr);
    free(ptr);

alloy c extern
def TextureView.mk (surfaceTexture : SurfaceTexture): IO TextureView := {
  WGPUSurfaceTexture * surface_texture = of_lean<SurfaceTexture>(surfaceTexture)
  if (surface_texture->status != WGPUSurfaceGetCurrentTextureStatus_Success) {
    return lean_io_result_mk_error(lean_decode_io_error(0,NULL));
  }
  WGPUTextureViewDescriptor * viewDescriptor = calloc(1,sizeof(WGPUTextureViewDescriptor));
  viewDescriptor->nextInChain = NULL;
  viewDescriptor->label = "Surface texture view";
  viewDescriptor->format = wgpuTextureGetFormat(surface_texture->texture);
  viewDescriptor->dimension = WGPUTextureViewDimension_2D;
  viewDescriptor->baseMipLevel = 0;
  viewDescriptor->mipLevelCount = 1;
  viewDescriptor->baseArrayLayer = 0;
  viewDescriptor->arrayLayerCount = 1;
  viewDescriptor->aspect = WGPUTextureAspect_All;

  WGPUTextureView * targetView = calloc(1,sizeof(WGPUTextureView));
  *targetView = wgpuTextureCreateView(surface_texture->texture, viewDescriptor);
  free(viewDescriptor);
  return lean_io_result_mk_ok(to_lean<TextureView>(targetView));
}

alloy c extern
def TextureView.is_valid (t : TextureView) : IO Bool :=
  WGPUTextureView * view = of_lean<TextureView>(t);
  return lean_io_result_mk_ok(lean_box(*view != NULL));


/-- # Color -/
alloy c opaque_extern_type Color => WGPUColor  where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUColor  \n");
    -- TODO call release
    free(ptr);

alloy c section
  static WGPUColor color_mk(double r, double g, double b, double a) {
    WGPUColor c = {};
    c.r = r;
    c.g = g;
    c.b = b;
    c.a = a;
    return c
  }
end

alloy c extern
def Color.mk (r g b a : Float) : Color := {
  WGPUColor * c = calloc(1,sizeof(WGPUColor));
  *c = color_mk(r,g,b,a)
  return to_lean<Color>(c);
}


/- # Texture Support -/

abbrev TextureUsage := UInt32
def TextureUsage.none             : TextureUsage := 0x00000000
def TextureUsage.copySrc          : TextureUsage := 0x00000001
def TextureUsage.copyDst          : TextureUsage := 0x00000002
def TextureUsage.textureBinding   : TextureUsage := 0x00000004
def TextureUsage.storageBinding   : TextureUsage := 0x00000008
def TextureUsage.renderAttachment : TextureUsage := 0x00000010

alloy c opaque_extern_type Texture => WGPUTexture where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUTexture\n");
    if (*ptr) {
      wgpuTextureDestroy(*ptr);
      wgpuTextureRelease(*ptr);
    }
    free(ptr);

/-- Create a 2D texture. -/
alloy c extern
def Device.createTexture (device : Device) (width height : UInt32)
    (format : TextureFormat) (usage : TextureUsage)
    (mipLevelCount : UInt32 := 1) (sampleCount : UInt32 := 1)
    : IO Texture := {
  WGPUDevice c_device = *of_lean<Device>(device);

  WGPUTextureDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "Texture";
  desc.usage = usage;
  desc.dimension = WGPUTextureDimension_2D;
  desc.size.width = width;
  desc.size.height = height;
  desc.size.depthOrArrayLayers = 1;
  desc.format = of_lean<TextureFormat>(format);
  desc.mipLevelCount = mipLevelCount;
  desc.sampleCount = sampleCount;
  desc.viewFormatCount = 0;
  desc.viewFormats = NULL;

  WGPUTexture *tex = calloc(1, sizeof(WGPUTexture));
  *tex = wgpuDeviceCreateTexture(c_device, &desc);
  return lean_io_result_mk_ok(to_lean<Texture>(tex));
}

/-- Create a TextureView from a Texture (2D, all mips, all layers). -/
alloy c extern
def Texture.createView (texture : Texture) (format : TextureFormat) : IO TextureView := {
  WGPUTexture *c_tex = of_lean<Texture>(texture);

  WGPUTextureViewDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "Texture view";
  desc.format = of_lean<TextureFormat>(format);
  desc.dimension = WGPUTextureViewDimension_2D;
  desc.baseMipLevel = 0;
  desc.mipLevelCount = 1;
  desc.baseArrayLayer = 0;
  desc.arrayLayerCount = 1;
  desc.aspect = WGPUTextureAspect_All;

  WGPUTextureView *view = calloc(1, sizeof(WGPUTextureView));
  *view = wgpuTextureCreateView(*c_tex, &desc);
  return lean_io_result_mk_ok(to_lean<TextureView>(view));
}

/-- Write pixel data to a 2D texture. -/
alloy c extern
def Texture.destroy (texture : Texture) : IO Unit := {
  WGPUTexture *c_tex = of_lean<Texture>(texture);
  if (*c_tex) {
    wgpuTextureDestroy(*c_tex);
    *c_tex = NULL;
  }
  return lean_io_result_mk_ok(lean_box(0));
}

/- # Sampler Support -/

alloy c enum AddressMode => WGPUAddressMode
| Repeat => WGPUAddressMode_Repeat
| MirrorRepeat => WGPUAddressMode_MirrorRepeat
| ClampToEdge => WGPUAddressMode_ClampToEdge
| Force32 => WGPUAddressMode_Force32
deriving Inhabited, Repr, BEq

alloy c enum FilterMode => WGPUFilterMode
| Nearest => WGPUFilterMode_Nearest
| Linear => WGPUFilterMode_Linear
| Force32 => WGPUFilterMode_Force32
deriving Inhabited, Repr, BEq

alloy c opaque_extern_type Sampler => WGPUSampler where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUSampler\n");
    wgpuSamplerRelease(*ptr);
    free(ptr);

/-- Create a sampler with configurable filtering and address modes. -/
alloy c extern
def Device.createSampler (device : Device)
    (magFilter : FilterMode := FilterMode.Linear)
    (minFilter : FilterMode := FilterMode.Linear)
    (addressModeU : AddressMode := AddressMode.ClampToEdge)
    (addressModeV : AddressMode := AddressMode.ClampToEdge)
    : IO Sampler := {
  WGPUDevice c_device = *of_lean<Device>(device);

  WGPUSamplerDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "Sampler";
  desc.addressModeU = of_lean<AddressMode>(addressModeU);
  desc.addressModeV = of_lean<AddressMode>(addressModeV);
  desc.addressModeW = WGPUAddressMode_ClampToEdge;
  desc.magFilter = of_lean<FilterMode>(magFilter);
  desc.minFilter = of_lean<FilterMode>(minFilter);
  desc.mipmapFilter = WGPUMipmapFilterMode_Nearest;
  desc.lodMinClamp = 0.0f;
  desc.lodMaxClamp = 1.0f;
  desc.compare = WGPUCompareFunction_Undefined;
  desc.maxAnisotropy = 1;

  WGPUSampler *sampler = calloc(1, sizeof(WGPUSampler));
  *sampler = wgpuDeviceCreateSampler(c_device, &desc);
  return lean_io_result_mk_ok(to_lean<Sampler>(sampler));
}

alloy c enum CompareFunction => WGPUCompareFunction
| Undefined => WGPUCompareFunction_Undefined
| Never => WGPUCompareFunction_Never
| Less => WGPUCompareFunction_Less
| LessEqual => WGPUCompareFunction_LessEqual
| Greater => WGPUCompareFunction_Greater
| GreaterEqual => WGPUCompareFunction_GreaterEqual
| Equal => WGPUCompareFunction_Equal
| NotEqual => WGPUCompareFunction_NotEqual
| Always => WGPUCompareFunction_Always
| Force32 => WGPUCompareFunction_Force32
deriving Inhabited, Repr, BEq

/-- Create a comparison sampler (used for shadow mapping PCF). -/
alloy c extern
def Device.createComparisonSampler (device : Device)
    (compare : CompareFunction := CompareFunction.Less)
    (addressMode : AddressMode := AddressMode.ClampToEdge)
    (magFilter : FilterMode := FilterMode.Linear)
    (minFilter : FilterMode := FilterMode.Linear)
    : IO Sampler := {
  WGPUDevice *c_device = of_lean<Device>(device);
  WGPUSamplerDescriptor desc = {
    .nextInChain = NULL,
    .label = NULL,
    .addressModeU = of_lean<AddressMode>(addressMode),
    .addressModeV = of_lean<AddressMode>(addressMode),
    .addressModeW = of_lean<AddressMode>(addressMode),
    .magFilter = of_lean<FilterMode>(magFilter),
    .minFilter = of_lean<FilterMode>(minFilter),
    .mipmapFilter = WGPUMipmapFilterMode_Nearest,
    .lodMinClamp = 0.0f,
    .lodMaxClamp = 1.0f,
    .compare = of_lean<CompareFunction>(compare),
    .maxAnisotropy = 1,
  };
  WGPUSampler *sampler = calloc(1, sizeof(WGPUSampler));
  *sampler = wgpuDeviceCreateSampler(*c_device, &desc);
  return lean_io_result_mk_ok(to_lean<Sampler>(sampler));
}

/- # Depth / Stencil Support -/

/-- Create a depth texture for use as a depth attachment. -/
alloy c extern
def Device.createDepthTexture (device : Device) (width height : UInt32)
    (format : TextureFormat := TextureFormat.Depth24Plus)
    : IO Texture := {
  WGPUDevice c_device = *of_lean<Device>(device);

  WGPUTextureDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "Depth texture";
  desc.usage = WGPUTextureUsage_RenderAttachment;
  desc.dimension = WGPUTextureDimension_2D;
  desc.size.width = width;
  desc.size.height = height;
  desc.size.depthOrArrayLayers = 1;
  desc.format = of_lean<TextureFormat>(format);
  desc.mipLevelCount = 1;
  desc.sampleCount = 1;
  desc.viewFormatCount = 0;
  desc.viewFormats = NULL;

  WGPUTexture *tex = calloc(1, sizeof(WGPUTexture));
  *tex = wgpuDeviceCreateTexture(c_device, &desc);
  return lean_io_result_mk_ok(to_lean<Texture>(tex));
}

/-- Create a depth TextureView. -/
alloy c extern
def Texture.createDepthView (texture : Texture) (format : TextureFormat := TextureFormat.Depth24Plus) : IO TextureView := {
  WGPUTexture *c_tex = of_lean<Texture>(texture);

  WGPUTextureViewDescriptor desc = {};
  desc.nextInChain = NULL;
  desc.label = "Depth texture view";
  desc.format = of_lean<TextureFormat>(format);
  desc.dimension = WGPUTextureViewDimension_2D;
  desc.baseMipLevel = 0;
  desc.mipLevelCount = 1;
  desc.baseArrayLayer = 0;
  desc.arrayLayerCount = 1;
  desc.aspect = WGPUTextureAspect_DepthOnly;

  WGPUTextureView *view = calloc(1, sizeof(WGPUTextureView));
  *view = wgpuTextureCreateView(*c_tex, &desc);
  return lean_io_result_mk_ok(to_lean<TextureView>(view));
}

/- # Texture Introspection -/

/-- Get the width of a texture. -/
alloy c extern
def Texture.getWidth (texture : Texture) : IO UInt32 := {
  WGPUTexture *c_tex = of_lean<Texture>(texture);
  return lean_io_result_mk_ok(lean_box(wgpuTextureGetWidth(*c_tex)));
}

/-- Get the height of a texture. -/
alloy c extern
def Texture.getHeight (texture : Texture) : IO UInt32 := {
  WGPUTexture *c_tex = of_lean<Texture>(texture);
  return lean_io_result_mk_ok(lean_box(wgpuTextureGetHeight(*c_tex)));
}

/-- Get the format of a texture (returned as TextureFormat). -/
alloy c extern
def Texture.getFormat (texture : Texture) : IO TextureFormat := {
  WGPUTexture *c_tex = of_lean<Texture>(texture);
  WGPUTextureFormat fmt = wgpuTextureGetFormat(*c_tex);
  return lean_io_result_mk_ok(lean_box(fmt));
}

/-- Get the mip level count of a texture. -/
alloy c extern
def Texture.getMipLevelCount (texture : Texture) : IO UInt32 := {
  WGPUTexture *c_tex = of_lean<Texture>(texture);
  return lean_io_result_mk_ok(lean_box(wgpuTextureGetMipLevelCount(*c_tex)));
}

/-- Get the sample count of a texture. -/
alloy c extern
def Texture.getSampleCount (texture : Texture) : IO UInt32 := {
  WGPUTexture *c_tex = of_lean<Texture>(texture);
  return lean_io_result_mk_ok(lean_box(wgpuTextureGetSampleCount(*c_tex)));
}

/- ################################################################## -/
/- # Texture View Dimension & Aspect Enums                            -/
/- ################################################################## -/

alloy c enum TextureViewDimension => WGPUTextureViewDimension
| Undefined => WGPUTextureViewDimension_Undefined
| D1        => WGPUTextureViewDimension_1D
| D2        => WGPUTextureViewDimension_2D
| D2Array   => WGPUTextureViewDimension_2DArray
| Cube      => WGPUTextureViewDimension_Cube
| CubeArray => WGPUTextureViewDimension_CubeArray
| D3        => WGPUTextureViewDimension_3D
deriving Inhabited, Repr, BEq

alloy c enum TextureAspect => WGPUTextureAspect
| All         => WGPUTextureAspect_All
| StencilOnly => WGPUTextureAspect_StencilOnly
| DepthOnly   => WGPUTextureAspect_DepthOnly
deriving Inhabited, Repr, BEq

/-- Create a texture view with full control over dimension, format, mip range, array layers, and aspect. -/
alloy c extern
def Texture.createViewFull (texture : Texture) (format : TextureFormat)
    (dimension : TextureViewDimension := TextureViewDimension.D2)
    (baseMipLevel : UInt32 := 0) (mipLevelCount : UInt32 := 1)
    (baseArrayLayer : UInt32 := 0) (arrayLayerCount : UInt32 := 1)
    (aspect : TextureAspect := TextureAspect.All) : IO TextureView := {
  WGPUTexture *c_tex = of_lean<Texture>(texture);
  WGPUTextureViewDescriptor desc = {
    .nextInChain = NULL,
    .label = NULL,
    .format = of_lean<TextureFormat>(format),
    .dimension = of_lean<TextureViewDimension>(dimension),
    .baseMipLevel = baseMipLevel,
    .mipLevelCount = mipLevelCount,
    .baseArrayLayer = baseArrayLayer,
    .arrayLayerCount = arrayLayerCount,
    .aspect = of_lean<TextureAspect>(aspect),
  };
  WGPUTextureView *view = calloc(1, sizeof(WGPUTextureView));
  *view = wgpuTextureCreateView(*c_tex, &desc);
  return lean_io_result_mk_ok(to_lean<TextureView>(view));
}

/- ################################################################## -/
/- # Texture extra introspection                                      -/
/- ################################################################## -/

/-- Get the depth or array layer count of a texture. -/
alloy c extern
def Texture.getDepthOrArrayLayers (texture : Texture) : IO UInt32 := {
  WGPUTexture *c_tex = of_lean<Texture>(texture);
  return lean_io_result_mk_ok(lean_box(wgpuTextureGetDepthOrArrayLayers(*c_tex)));
}

/-- Get the usage flags of a texture. -/
alloy c extern
def Texture.getUsage (texture : Texture) : IO TextureUsage := {
  WGPUTexture *c_tex = of_lean<Texture>(texture);
  return lean_io_result_mk_ok(lean_box((uint32_t)wgpuTextureGetUsage(*c_tex)));
}

/- ################################################################## -/
/- # Depth-Stencil texture creation (Depth24PlusStencil8)             -/
/- ################################################################## -/

/-- Create a depth-stencil texture with Depth24PlusStencil8 format. -/
alloy c extern
def Device.createDepthStencilTexture (device : Device) (width height : UInt32)
    : IO Texture := {
  WGPUDevice *c_device = of_lean<Device>(device);
  WGPUTextureDescriptor desc = {
    .nextInChain = NULL,
    .label = NULL,
    .usage = WGPUTextureUsage_RenderAttachment,
    .dimension = WGPUTextureDimension_2D,
    .size = { .width = width, .height = height, .depthOrArrayLayers = 1 },
    .format = WGPUTextureFormat_Depth24PlusStencil8,
    .mipLevelCount = 1,
    .sampleCount = 1,
    .viewFormatCount = 0,
    .viewFormats = NULL,
  };
  WGPUTexture *tex = calloc(1, sizeof(WGPUTexture));
  *tex = wgpuDeviceCreateTexture(*c_device, &desc);
  return lean_io_result_mk_ok(to_lean<Texture>(tex));
}

/-- Create a view for a depth-stencil texture (Depth24PlusStencil8). -/
alloy c extern
def Texture.createDepthStencilView (texture : Texture) : IO TextureView := {
  WGPUTexture *c_tex = of_lean<Texture>(texture);
  WGPUTextureViewDescriptor desc = {
    .nextInChain = NULL,
    .label = NULL,
    .format = WGPUTextureFormat_Depth24PlusStencil8,
    .dimension = WGPUTextureViewDimension_2D,
    .baseMipLevel = 0,
    .mipLevelCount = 1,
    .baseArrayLayer = 0,
    .arrayLayerCount = 1,
    .aspect = WGPUTextureAspect_All,
  };
  WGPUTextureView *view = calloc(1, sizeof(WGPUTextureView));
  *view = wgpuTextureCreateView(*c_tex, &desc);
  return lean_io_result_mk_ok(to_lean<TextureView>(view));
}

/- ################################################################## -/
/- # MSAA texture helpers                                             -/
/- ################################################################## -/

/-- Create an MSAA (multi-sample) render target texture. -/
alloy c extern
def Device.createMSAATexture (device : Device) (width height : UInt32)
    (format : TextureFormat) (sampleCount : UInt32 := 4) : IO Texture := {
  WGPUDevice *c_device = of_lean<Device>(device);
  WGPUTextureDescriptor desc = {
    .nextInChain = NULL,
    .label = NULL,
    .usage = WGPUTextureUsage_RenderAttachment,
    .dimension = WGPUTextureDimension_2D,
    .size = { .width = width, .height = height, .depthOrArrayLayers = 1 },
    .format = of_lean<TextureFormat>(format),
    .mipLevelCount = 1,
    .sampleCount = sampleCount,
    .viewFormatCount = 0,
    .viewFormats = NULL,
  };
  WGPUTexture *tex = calloc(1, sizeof(WGPUTexture));
  *tex = wgpuDeviceCreateTexture(*c_device, &desc);
  return lean_io_result_mk_ok(to_lean<Texture>(tex));
}

alloy c extern
def Texture.setLabel (texture : Texture) (label : @& String) : IO Unit := {
  WGPUTexture *c_tex = of_lean<Texture>(texture);
  wgpuTextureSetLabel(*c_tex, lean_string_cstr(label));
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set the debug label of a texture view. -/
alloy c extern
def TextureView.setLabel (view : TextureView) (label : @& String) : IO Unit := {
  WGPUTextureView *c_view = of_lean<TextureView>(view);
  wgpuTextureViewSetLabel(*c_view, lean_string_cstr(label));
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set the debug label of a sampler. -/
alloy c extern
def Sampler.setLabel (sampler : Sampler) (label : @& String) : IO Unit := {
  WGPUSampler *c_sampler = of_lean<Sampler>(sampler);
  wgpuSamplerSetLabel(*c_sampler, lean_string_cstr(label));
  return lean_io_result_mk_ok(lean_box(0));
}

/- ################################################################## -/
/- # Texture Dimension enum                                           -/
/- ################################################################## -/

/-- Get the dimension of a texture. 0=1D, 1=2D, 2=3D. -/
alloy c extern
def Texture.getDimension (texture : Texture) : IO UInt32 := {
  WGPUTexture *c_tex = of_lean<Texture>(texture);
  return lean_io_result_mk_ok(lean_box((uint32_t)wgpuTextureGetDimension(*c_tex)));
}


end Wgpu
