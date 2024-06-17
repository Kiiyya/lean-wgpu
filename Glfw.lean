import Wgpu
import Alloy.C
open scoped Alloy.C

open Wgpu

alloy c section
  #include <stdio.h>
  #include <lean/lean.h>
  #include <GLFW/glfw3.h>
  #include <glfw3webgpu.h>
end

alloy c opaque_extern_type GLFWwindow => GLFWwindow where
  finalize(ptr) :=
    fprintf(stderr, "finalize GLFWwindow\n");
    glfwDestroyWindow(ptr);
    glfwTerminate();
    free(ptr);

-- TODO add `GLFWmonitor` and `GLFWwindow`
/-(title : String)-/
alloy c extern
def GLFWwindow.mk (width height : UInt32) (title : String) : IO GLFWwindow := {
  fprintf(stderr, "mk GLFWwindow\n");
  if (!glfwInit()) {
    return lean_mk_io_user_error(lean_mk_string("Could not initialize GLFW!\n"));
  }
  glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API); // <-- extra info for glfwCreateWindow
  glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE);
  GLFWwindow* window = glfwCreateWindow(width, height, lean_string_cstr(title), NULL, NULL);
  return lean_io_result_mk_ok(to_lean<GLFWwindow>(window));
}

alloy c extern
def GLFWwindow.shouldClose (l_window : GLFWwindow) : IO Bool := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  return lean_io_result_mk_ok(lean_box(glfwWindowShouldClose(window)));

}
alloy c extern
def GLFW.pollEvents : IO Unit := {
  glfwPollEvents();
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c section
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

  WGPUSurface *surface = malloc(sizeof(WGPUSurface));
  *surface = glfwGetWGPUSurface(*c_inst, c_window);
  return lean_io_result_mk_ok(to_lean<Surface>(surface));
}
