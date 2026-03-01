import Glfw.Core
import Alloy.C
open scoped Alloy.C

alloy c section
  #include <stdio.h>
  #include <stdlib.h>
  #include <lean/lean.h>
  #include <GLFW/glfw3.h>

  // GLFWwindow converter (mirrors Alloy-generated code from Glfw.Core)
  static inline GLFWwindow* _alloy_of_l_GLFWwindow(b_lean_obj_arg o) {
    return (GLFWwindow*)lean_get_external_data(o);
  }
end

/- ################################################################## -/
/- # Cursor Management                                                -/
/- ################################################################## -/

alloy c opaque_extern_type GLFWcursor => GLFWcursor where
  finalize(ptr) :=
    glfwDestroyCursor(ptr);

/-- Create a standard cursor from one of the GLFW cursor shape constants.
    See GLFW.cursorArrow, GLFW.cursorIBeam, GLFW.cursorCrosshair, etc. -/
alloy c extern
def GLFWcursor.createStandard (shape : UInt32) : IO GLFWcursor := {
  GLFWcursor *cursor = glfwCreateStandardCursor((int)shape);
  if (cursor == NULL) {
    return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string("glfwCreateStandardCursor failed")));
  }
  return lean_io_result_mk_ok(to_lean<GLFWcursor>(cursor));
}

/-- Set the cursor for a window. Pass a GLFWcursor created by createStandard. -/
alloy c extern
def GLFWwindow.setCursor (window : @& GLFWwindow) (cursor : @& GLFWcursor) : IO Unit := {
  GLFWwindow *c_window = of_lean<GLFWwindow>(window);
  GLFWcursor *c_cursor = of_lean<GLFWcursor>(cursor);
  glfwSetCursor(c_window, c_cursor);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Reset the cursor for a window to the default arrow. -/
alloy c extern
def GLFWwindow.resetCursor (window : @& GLFWwindow) : IO Unit := {
  GLFWwindow *c_window = of_lean<GLFWwindow>(window);
  glfwSetCursor(c_window, NULL);
  return lean_io_result_mk_ok(lean_box(0));
}
