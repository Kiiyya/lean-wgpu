import Alloy.C
open scoped Alloy.C

alloy c section
  #include <lean/lean.h>
  #include <wgpu.h>
  #include <webgpu.h>
end

alloy c extern
def rawrr (x : UInt32) : UInt32 := {
  WGPUInstance *inst = NULL;
  return sizeof(WGPUInstance);
}

alloy c extern
def hewwo (n : UInt32) : UInt32 := {
  return 1 + 123;
}
