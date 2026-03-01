import Alloy.C
open scoped Alloy.C

alloy c section
  #include <stdio.h>
  #include <stdlib.h>
  #include <lean/lean.h>
  #include <GLFW/glfw3.h>
end

alloy c opaque_extern_type GLFWwindow => GLFWwindow where
  finalize(ptr) :=
    fprintf(stderr, "finalize GLFWwindow\n");
    glfwDestroyWindow(ptr);
    glfwTerminate();
    -- NOTE: do NOT free(ptr) — GLFW owns this memory, glfwDestroyWindow handles it.

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

/-- Create a resizable GLFW window. -/
alloy c extern
def GLFWwindow.mkResizable (width height : UInt32) (title : String) : IO GLFWwindow := {
  fprintf(stderr, "mk GLFWwindow (resizable)\n");
  if (!glfwInit()) {
    return lean_mk_io_user_error(lean_mk_string("Could not initialize GLFW!\n"));
  }
  glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
  glfwWindowHint(GLFW_RESIZABLE, GLFW_TRUE);
  GLFWwindow* window = glfwCreateWindow(width, height, lean_string_cstr(title), NULL, NULL);
  return lean_io_result_mk_ok(to_lean<GLFWwindow>(window));
}

alloy c extern
def GLFWwindow.shouldClose (l_window : GLFWwindow) : IO Bool := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  return lean_io_result_mk_ok(lean_box(glfwWindowShouldClose(window)));
}

alloy c extern
def GLFWwindow.setShouldClose (l_window : GLFWwindow) (value : Bool) : IO Unit := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  glfwSetWindowShouldClose(window, value);
  return lean_io_result_mk_ok(lean_box(0));
}

alloy c extern
def GLFW.pollEvents : IO Unit := {
  glfwPollEvents();
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Wait until events are queued and process them. More efficient than pollEvents for non-game apps. -/
alloy c extern
def GLFW.waitEvents : IO Unit := {
  glfwWaitEvents();
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Wait for events with timeout (in seconds). -/
alloy c extern
def GLFW.waitEventsTimeout (timeout : Float) : IO Unit := {
  glfwWaitEventsTimeout(timeout);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Post an empty event to wake up the event loop. -/
alloy c extern
def GLFW.postEmptyEvent : IO Unit := {
  glfwPostEmptyEvent();
  return lean_io_result_mk_ok(lean_box(0));
}
