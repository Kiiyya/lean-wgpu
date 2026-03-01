import Glfw.Core
import Wgpu
import Alloy.C
open scoped Alloy.C
open Wgpu

alloy c section
  #include <stdio.h>
  #include <stdlib.h>
  #include <lean/lean.h>
  #include <GLFW/glfw3.h>
  #include <glfw3webgpu.h>

  // GLFWwindow converter (mirrors Alloy-generated code from Glfw.Core)
  static inline GLFWwindow* _alloy_of_l_GLFWwindow(b_lean_obj_arg o) {
    return (GLFWwindow*)lean_get_external_data(o);
  }

  -- Hacky: Copied from the C code genered by alloy in Wgpu.alloy.c
  static inline void _alloy_finalize_l_Wgpu_Surface ( WGPUSurface * ptr) { fprintf(stderr, "finalize WGPUSurface\n");wgpuSurfaceRelease(*ptr);free(ptr);}
  static inline void _alloy_foreach_l_Wgpu_Surface ( void * ptr , b_lean_obj_arg f ) { }
  static lean_external_class * _alloy_g_class_l_Wgpu_Surface = NULL ;
  static inline WGPUInstance * _alloy_of_l_Wgpu_Instance ( b_lean_obj_arg o ) { return ( WGPUInstance * ) ( lean_get_external_data ( o ) ) ;}
  static inline lean_obj_res _alloy_to_l_Wgpu_Surface ( WGPUSurface * o ) { if ( _alloy_g_class_l_Wgpu_Surface == NULL ) { _alloy_g_class_l_Wgpu_Surface = lean_register_external_class ( ( void ( * ) ( void * ) ) _alloy_finalize_l_Wgpu_Surface , ( void ( * ) ( void * , b_lean_obj_arg ) ) _alloy_foreach_l_Wgpu_Surface ) ;} return lean_alloc_external ( _alloy_g_class_l_Wgpu_Surface , o ) ;}
end

alloy c extern def getSurface (inst : Instance) (window : GLFWwindow) : IO Surface := {
  WGPUInstance *c_inst = of_lean<Instance>(inst);
  GLFWwindow *c_window = of_lean<GLFWwindow>(window);

  WGPUSurface *surface = calloc(1,sizeof(WGPUSurface));
  *surface = glfwGetWGPUSurface(*c_inst, c_window);
  return lean_io_result_mk_ok(to_lean<Surface>(surface));
}
