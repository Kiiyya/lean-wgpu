import Alloy.C
open scoped Alloy.C

alloy c section
  #include <stdio.h>
  #include <lean/lean.h>
  #include <GLFW/glfw3.h>
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
def GLFWwindow.mk (width height: UInt32) : IO GLFWwindow := {
  fprintf(stderr, "mk GLFWwindow\n");
  if (!glfwInit()) {
    return lean_mk_io_user_error(lean_mk_string("Could not initialize GLFW!\n"));
  }
  glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API); // <-- extra info for glfwCreateWindow
  glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE);
  GLFWwindow* window = glfwCreateWindow(width, height, "TODO manage title", NULL, NULL);
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
}
