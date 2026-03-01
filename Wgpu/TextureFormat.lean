import Alloy.C
open scoped Alloy.C
open IO

namespace Wgpu

alloy c include <stdio.h>
alloy c include <stdlib.h>
alloy c include <string.h>
alloy c include <lean/lean.h>
alloy c include <wgpu.h>
alloy c include <webgpu.h>

/-- # TextureFormat -/

alloy c enum TextureFormat  => WGPUTextureFormat
| Undefined => WGPUTextureFormat_Undefined
| R8Unorm => WGPUTextureFormat_R8Unorm
| R8Snorm => WGPUTextureFormat_R8Snorm
| R8Uint => WGPUTextureFormat_R8Uint
| R8Sint => WGPUTextureFormat_R8Sint
| R16Uint => WGPUTextureFormat_R16Uint
| R16Sint => WGPUTextureFormat_R16Sint
| R16Float => WGPUTextureFormat_R16Float
| RG8Unorm => WGPUTextureFormat_RG8Unorm
| RG8Snorm => WGPUTextureFormat_RG8Snorm
| RG8Uint => WGPUTextureFormat_RG8Uint
| RG8Sint => WGPUTextureFormat_RG8Sint
| R32Float => WGPUTextureFormat_R32Float
| R32Uint => WGPUTextureFormat_R32Uint
| R32Sint => WGPUTextureFormat_R32Sint
| RG16Uint => WGPUTextureFormat_RG16Uint
| RG16Sint => WGPUTextureFormat_RG16Sint
| RG16Float => WGPUTextureFormat_RG16Float
| RGBA8Unorm => WGPUTextureFormat_RGBA8Unorm
| RGBA8UnormSrgb => WGPUTextureFormat_RGBA8UnormSrgb
| RGBA8Snorm => WGPUTextureFormat_RGBA8Snorm
| RGBA8Uint => WGPUTextureFormat_RGBA8Uint
| RGBA8Sint => WGPUTextureFormat_RGBA8Sint
| BGRA8Unorm => WGPUTextureFormat_BGRA8Unorm
| BGRA8UnormSrgb => WGPUTextureFormat_BGRA8UnormSrgb
| RGB10A2Uint => WGPUTextureFormat_RGB10A2Uint
| RGB10A2Unorm => WGPUTextureFormat_RGB10A2Unorm
| RG11B10Ufloat => WGPUTextureFormat_RG11B10Ufloat
| RGB9E5Ufloat => WGPUTextureFormat_RGB9E5Ufloat
| RG32Float => WGPUTextureFormat_RG32Float
| RG32Uint => WGPUTextureFormat_RG32Uint
| RG32Sint => WGPUTextureFormat_RG32Sint
| RGBA16Uint => WGPUTextureFormat_RGBA16Uint
| RGBA16Sint => WGPUTextureFormat_RGBA16Sint
| RGBA16Float => WGPUTextureFormat_RGBA16Float
| RGBA32Float => WGPUTextureFormat_RGBA32Float
| RGBA32Uint => WGPUTextureFormat_RGBA32Uint
| RGBA32Sint => WGPUTextureFormat_RGBA32Sint
| Stencil8 => WGPUTextureFormat_Stencil8
| Depth16Unorm => WGPUTextureFormat_Depth16Unorm
| Depth24Plus => WGPUTextureFormat_Depth24Plus
| Depth24PlusStencil8 => WGPUTextureFormat_Depth24PlusStencil8
| Depth32Float => WGPUTextureFormat_Depth32Float
| Depth32FloatStencil8 => WGPUTextureFormat_Depth32FloatStencil8
| BC1RGBAUnorm => WGPUTextureFormat_BC1RGBAUnorm
| BC1RGBAUnormSrgb => WGPUTextureFormat_BC1RGBAUnormSrgb
| BC2RGBAUnorm => WGPUTextureFormat_BC2RGBAUnorm
| BC2RGBAUnormSrgb => WGPUTextureFormat_BC2RGBAUnormSrgb
| BC3RGBAUnorm => WGPUTextureFormat_BC3RGBAUnorm
| BC3RGBAUnormSrgb => WGPUTextureFormat_BC3RGBAUnormSrgb
| BC4RUnorm => WGPUTextureFormat_BC4RUnorm
| BC4RSnorm => WGPUTextureFormat_BC4RSnorm
| BC5RGUnorm => WGPUTextureFormat_BC5RGUnorm
| BC5RGSnorm => WGPUTextureFormat_BC5RGSnorm
| BC6HRGBUfloat => WGPUTextureFormat_BC6HRGBUfloat
| BC6HRGBFloat => WGPUTextureFormat_BC6HRGBFloat
| BC7RGBAUnorm => WGPUTextureFormat_BC7RGBAUnorm
| BC7RGBAUnormSrgb => WGPUTextureFormat_BC7RGBAUnormSrgb
| ETC2RGB8Unorm => WGPUTextureFormat_ETC2RGB8Unorm
| ETC2RGB8UnormSrgb => WGPUTextureFormat_ETC2RGB8UnormSrgb
| ETC2RGB8A1Unorm => WGPUTextureFormat_ETC2RGB8A1Unorm
| ETC2RGB8A1UnormSrgb => WGPUTextureFormat_ETC2RGB8A1UnormSrgb
| ETC2RGBA8Unorm => WGPUTextureFormat_ETC2RGBA8Unorm
| ETC2RGBA8UnormSrgb => WGPUTextureFormat_ETC2RGBA8UnormSrgb
| EACR11Unorm => WGPUTextureFormat_EACR11Unorm
| EACR11Snorm => WGPUTextureFormat_EACR11Snorm
| EACRG11Unorm => WGPUTextureFormat_EACRG11Unorm
| EACRG11Snorm => WGPUTextureFormat_EACRG11Snorm
| ASTC4x4Unorm => WGPUTextureFormat_ASTC4x4Unorm
| ASTC4x4UnormSrgb => WGPUTextureFormat_ASTC4x4UnormSrgb
| ASTC5x4Unorm => WGPUTextureFormat_ASTC5x4Unorm
| ASTC5x4UnormSrgb => WGPUTextureFormat_ASTC5x4UnormSrgb
| ASTC5x5Unorm => WGPUTextureFormat_ASTC5x5Unorm
| ASTC5x5UnormSrgb => WGPUTextureFormat_ASTC5x5UnormSrgb
| ASTC6x5Unorm => WGPUTextureFormat_ASTC6x5Unorm
| ASTC6x5UnormSrgb => WGPUTextureFormat_ASTC6x5UnormSrgb
| ASTC6x6Unorm => WGPUTextureFormat_ASTC6x6Unorm
| ASTC6x6UnormSrgb => WGPUTextureFormat_ASTC6x6UnormSrgb
| ASTC8x5Unorm => WGPUTextureFormat_ASTC8x5Unorm
| ASTC8x5UnormSrgb => WGPUTextureFormat_ASTC8x5UnormSrgb
| ASTC8x6Unorm => WGPUTextureFormat_ASTC8x6Unorm
| ASTC8x6UnormSrgb => WGPUTextureFormat_ASTC8x6UnormSrgb
| ASTC8x8Unorm => WGPUTextureFormat_ASTC8x8Unorm
| ASTC8x8UnormSrgb => WGPUTextureFormat_ASTC8x8UnormSrgb
| ASTC10x5Unorm => WGPUTextureFormat_ASTC10x5Unorm
| ASTC10x5UnormSrgb => WGPUTextureFormat_ASTC10x5UnormSrgb
| ASTC10x6Unorm => WGPUTextureFormat_ASTC10x6Unorm
| ASTC10x6UnormSrgb => WGPUTextureFormat_ASTC10x6UnormSrgb
| ASTC10x8Unorm => WGPUTextureFormat_ASTC10x8Unorm
| ASTC10x8UnormSrgb => WGPUTextureFormat_ASTC10x8UnormSrgb
| ASTC10x10Unorm => WGPUTextureFormat_ASTC10x10Unorm
| ASTC10x10UnormSrgb => WGPUTextureFormat_ASTC10x10UnormSrgb
| ASTC12x10Unorm => WGPUTextureFormat_ASTC12x10Unorm
| ASTC12x10UnormSrgb => WGPUTextureFormat_ASTC12x10UnormSrgb
| ASTC12x12Unorm => WGPUTextureFormat_ASTC12x12Unorm
| ASTC12x12UnormSrgb => WGPUTextureFormat_ASTC12x12UnormSrgb
| Force32 => WGPUTextureFormat_Force32
deriving Inhabited, Repr, BEq


end Wgpu
