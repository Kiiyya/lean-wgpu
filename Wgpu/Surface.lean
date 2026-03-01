import Alloy.C
import Wgpu.Core
import Wgpu.Adapter
import Wgpu.Device
import Wgpu.TextureFormat
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
  static inline WGPUSurface* _alloy_of_l_Wgpu_Surface(b_lean_obj_arg o) { return (WGPUSurface*)lean_get_external_data(o); }
  static inline WGPUAdapter* _alloy_of_l_Wgpu_Adapter(b_lean_obj_arg o) { return (WGPUAdapter*)lean_get_external_data(o); }
  static inline WGPUDevice* _alloy_of_l_Wgpu_Device(b_lean_obj_arg o) { return (WGPUDevice*)lean_get_external_data(o); }
  static inline WGPUTextureFormat _alloy_of_l_TextureFormat(uint8_t v) { return (WGPUTextureFormat)v; }
  static inline uint8_t _alloy_to_l_TextureFormat(WGPUTextureFormat v) { return (uint8_t)v; }
end

alloy c extern
def TextureFormat.get (surface : Surface) (adapter : Adapter) : IO TextureFormat := {
    WGPUSurface * c_surface = of_lean<Surface>(surface);
    WGPUAdapter * c_adapter = of_lean<Adapter>(adapter);

    WGPUTextureFormat surfaceFormat =  wgpuSurfaceGetPreferredFormat(*c_surface, *c_adapter);
    return lean_io_result_mk_ok(lean_box(to_lean<TextureFormat>(surfaceFormat)));
}

/-- # SurfaceConfiguration -/

alloy c opaque_extern_type SurfaceConfiguration  => WGPUSurfaceConfiguration  where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUSurfaceConfiguration \n");
    free(ptr);

alloy c extern
def SurfaceConfiguration.mk (width height : UInt32) (device : Device) (textureFormat : TextureFormat)
  : IO SurfaceConfiguration := {
  WGPUDevice * c_device = of_lean<Device>(device);
  WGPUTextureFormat surfaceFormat = of_lean<TextureFormat>(textureFormat);
  fprintf(stderr, "surfaceFormat is %d\n", surfaceFormat); -- Kiiya: I get 24.

  WGPUSurfaceConfiguration *config = calloc(1,sizeof(WGPUSurfaceConfiguration))
  config->nextInChain = NULL; --Is this really needed ?
  config->width = width;
  config->height = height;
  config->usage = WGPUTextureUsage_RenderAttachment;
  config->format = surfaceFormat;

  config->viewFormatCount = 0;
  config->viewFormats = NULL;
  config->device = *c_device;
  -- TODO link present mode
  config->presentMode = WGPUPresentMode_Fifo;
  -- TODO link alpha mode enum
  config->alphaMode = WGPUCompositeAlphaMode_Auto;
  fprintf(stderr, "Done generating surface config !\n");

  return lean_io_result_mk_ok(to_lean<SurfaceConfiguration>(config));
}

alloy c extern
def Surface.configure (surface : Surface) (config : SurfaceConfiguration) : IO Unit := {
  WGPUSurface * c_surface = of_lean<Surface>(surface);
  WGPUSurfaceConfiguration * c_config = of_lean<SurfaceConfiguration>(config);
  wgpuSurfaceConfigure(*c_surface,c_config);
  fprintf(stderr, "Done configuring surface !\n");
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern
def Surface.unconfigure (surface : Surface) : IO Unit := {
  WGPUSurface * c_surface = of_lean<Surface>(surface);
  wgpuSurfaceUnconfigure(*c_surface);
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern
def Surface.present (surface : Surface) : IO Unit := {
  WGPUSurface * c_surface = of_lean<Surface>(surface);
  wgpuSurfacePresent(*c_surface);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- # Surface Texture -/

alloy c opaque_extern_type SurfaceTexture => WGPUSurfaceTexture where
  finalize(ptr) :=
    fprintf(stderr, "finalize WGPUSurfaceTexture \n");
    free(ptr);

alloy c enum SurfaceTextureStatus => WGPUSurfaceGetCurrentTextureStatus
| success => WGPUSurfaceGetCurrentTextureStatus_Success
| timeout => WGPUSurfaceGetCurrentTextureStatus_Timeout
| outdated => WGPUSurfaceGetCurrentTextureStatus_Outdated
| lost => WGPUSurfaceGetCurrentTextureStatus_Lost
| out_of_memory => WGPUSurfaceGetCurrentTextureStatus_OutOfMemory
| device_lost => WGPUSurfaceGetCurrentTextureStatus_DeviceLost
| force32 => WGPUSurfaceGetCurrentTextureStatus_Force32
deriving Inhabited, Repr, BEq

alloy c extern
def SurfaceTexture.mk  : IO SurfaceTexture := {
  WGPUSurfaceTexture * surface_texture = calloc(1,sizeof(WGPUSurfaceTexture));
  return lean_io_result_mk_ok(to_lean<SurfaceTexture>(surface_texture));
}

alloy c extern
def Surface.getCurrent (surface : Surface) : IO SurfaceTexture := {
  WGPUSurfaceTexture * surface_texture = calloc(1,sizeof(WGPUSurfaceTexture));
  WGPUSurface * c_surface = of_lean<Surface>(surface);
  wgpuSurfaceGetCurrentTexture(*c_surface, surface_texture);
  return lean_io_result_mk_ok(to_lean<SurfaceTexture>(surface_texture));
}

alloy c extern
def SurfaceTexture.status (surfaceTexture : SurfaceTexture) : IO SurfaceTextureStatus := {
  WGPUSurfaceGetCurrentTextureStatus status = of_lean<SurfaceTexture>(surfaceTexture)->status;
  return lean_io_result_mk_ok(lean_box(to_lean<SurfaceTextureStatus>(status)));
}

/- # Surface Reconfiguration Helper -/

alloy c extern
def SurfaceConfiguration.mkWith (width height : UInt32) (device : Device) (textureFormat : TextureFormat)
    (presentMode : UInt32 := 2) -- 2 = Fifo
    : IO SurfaceConfiguration := {
  WGPUDevice *c_device = of_lean<Device>(device);
  WGPUTextureFormat surfaceFormat = of_lean<TextureFormat>(textureFormat);

  WGPUSurfaceConfiguration *config = calloc(1, sizeof(WGPUSurfaceConfiguration));
  config->nextInChain = NULL;
  config->width = width;
  config->height = height;
  config->usage = WGPUTextureUsage_RenderAttachment;
  config->format = surfaceFormat;
  config->viewFormatCount = 0;
  config->viewFormats = NULL;
  config->device = *c_device;
  config->presentMode = (WGPUPresentMode)presentMode;
  config->alphaMode = WGPUCompositeAlphaMode_Auto;

  return lean_io_result_mk_ok(to_lean<SurfaceConfiguration>(config));
}

/- ################################################################## -/
/- # Surface Capabilities                                             -/
/- ################################################################## -/

alloy c enum PresentMode => WGPUPresentMode
| Fifo        => WGPUPresentMode_Fifo
| FifoRelaxed => WGPUPresentMode_FifoRelaxed
| Immediate   => WGPUPresentMode_Immediate
| Mailbox     => WGPUPresentMode_Mailbox
deriving Inhabited, Repr, BEq

alloy c enum CompositeAlphaMode => WGPUCompositeAlphaMode
| Auto            => WGPUCompositeAlphaMode_Auto
| Opaque_         => WGPUCompositeAlphaMode_Opaque
| Premultiplied   => WGPUCompositeAlphaMode_Premultiplied
| Unpremultiplied => WGPUCompositeAlphaMode_Unpremultiplied
| Inherit         => WGPUCompositeAlphaMode_Inherit
deriving Inhabited, Repr, BEq

/-- Query surface capabilities: supported formats, present modes, and alpha modes. -/
alloy c extern
def Surface.getCapabilities (surface : Surface) (adapter : Adapter)
    : IO (Array TextureFormat × Array PresentMode × Array CompositeAlphaMode) := {
  WGPUSurface *c_surface = of_lean<Surface>(surface);
  WGPUAdapter *c_adapter = of_lean<Adapter>(adapter);
  WGPUSurfaceCapabilities caps;
  memset(&caps, 0, sizeof(caps));
  wgpuSurfaceGetCapabilities(*c_surface, *c_adapter, &caps);

  // Build format array
  lean_object *fmts = lean_alloc_array(caps.formatCount, caps.formatCount);
  for (size_t i = 0; i < caps.formatCount; i++) {
    lean_array_set_core(fmts, i, lean_box((uint32_t)caps.formats[i]));
  }

  // Build present mode array
  lean_object *pmodes = lean_alloc_array(caps.presentModeCount, caps.presentModeCount);
  for (size_t i = 0; i < caps.presentModeCount; i++) {
    lean_array_set_core(pmodes, i, lean_box((uint32_t)caps.presentModes[i]));
  }

  // Build alpha mode array
  lean_object *amodes = lean_alloc_array(caps.alphaModeCount, caps.alphaModeCount);
  for (size_t i = 0; i < caps.alphaModeCount; i++) {
    lean_array_set_core(amodes, i, lean_box((uint32_t)caps.alphaModes[i]));
  }

  wgpuSurfaceCapabilitiesFreeMembers(caps);

  // Build nested pairs: (fmts, (pmodes, amodes))
  lean_object *inner = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(inner, 0, pmodes);
  lean_ctor_set(inner, 1, amodes);
  lean_object *outer = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(outer, 0, fmts);
  lean_ctor_set(outer, 1, inner);
  return lean_io_result_mk_ok(outer);
}


end Wgpu
