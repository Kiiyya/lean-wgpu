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

/-- Get the state of a keyboard key. Returns GLFW_PRESS (1) or GLFW_RELEASE (0). -/
alloy c extern
def GLFWwindow.getKey (l_window : GLFWwindow) (key : UInt32) : IO UInt32 := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  int state = glfwGetKey(window, key);
  return lean_io_result_mk_ok(lean_box(state));
}

/-- Get the current cursor position in screen coordinates. -/
alloy c extern
def GLFWwindow.getCursorPos (l_window : GLFWwindow) : IO (Float × Float) := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  double xpos, ypos;
  glfwGetCursorPos(window, &xpos, &ypos);
  lean_object *pair = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(pair, 0, lean_box_float(xpos));
  lean_ctor_set(pair, 1, lean_box_float(ypos));
  return lean_io_result_mk_ok(pair);
}

/-- Get the state of a mouse button. Returns GLFW_PRESS (1) or GLFW_RELEASE (0). -/
alloy c extern
def GLFWwindow.getMouseButton (l_window : GLFWwindow) (button : UInt32) : IO UInt32 := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  int state = glfwGetMouseButton(window, button);
  return lean_io_result_mk_ok(lean_box(state));
}

/-- Set cursor input mode. Use GLFW.cursorNormal, cursorHidden, or cursorDisabled. -/
alloy c extern
def GLFWwindow.setInputMode (l_window : GLFWwindow) (mode : UInt32) (value : UInt32) : IO Unit := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  glfwSetInputMode(window, mode, value);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Get the current input mode value. -/
alloy c extern
def GLFWwindow.getInputMode (l_window : GLFWwindow) (mode : UInt32) : IO UInt32 := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  return lean_io_result_mk_ok(lean_box((uint32_t)glfwGetInputMode(window, (int)mode)));
}

/-- Warp/set the cursor position. -/
alloy c extern
def GLFWwindow.setCursorPos (l_window : GLFWwindow) (x y : Float) : IO Unit := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  glfwSetCursorPos(window, x, y);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Get the printable name of a key, or empty string if not printable. -/
alloy c extern
def GLFW.getKeyName (key : UInt32) (scancode : UInt32) : IO String := {
  const char *name = glfwGetKeyName((int)key, (int)scancode);
  if (name == NULL) return lean_io_result_mk_ok(lean_mk_string(""));
  return lean_io_result_mk_ok(lean_mk_string(name));
}

/-- Get the platform-specific scancode for a key. -/
alloy c extern
def GLFW.getKeyScancode (key : UInt32) : IO UInt32 := {
  return lean_io_result_mk_ok(lean_box((uint32_t)glfwGetKeyScancode((int)key)));
}

/-- Check if raw mouse motion is supported on this platform. -/
alloy c extern
def GLFW.rawMouseMotionSupported : IO Bool := {
  return lean_io_result_mk_ok(lean_box(glfwRawMouseMotionSupported()));
}

/- ################################################################## -/
/- # Clipboard                                                        -/
/- ################################################################## -/

/-- Set the clipboard string. -/
alloy c extern
def GLFW.setClipboardString (text : String) : IO Unit := {
  glfwSetClipboardString(NULL, lean_string_cstr(text));
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Get the clipboard string. -/
alloy c extern
def GLFW.getClipboardString : IO String := {
  const char *s = glfwGetClipboardString(NULL);
  if (s == NULL) return lean_io_result_mk_ok(lean_mk_string(""));
  return lean_io_result_mk_ok(lean_mk_string(s));
}

/-- Get the clipboard contents as a string. -/
alloy c extern
def GLFWwindow.getClipboardString (window : @& GLFWwindow) : IO String := {
  GLFWwindow *c_window = of_lean<GLFWwindow>(window);
  const char *str = glfwGetClipboardString(c_window);
  return lean_io_result_mk_ok(lean_mk_string(str ? str : ""));
}

/-- Set the clipboard contents. -/
alloy c extern
def GLFWwindow.setClipboardString (window : @& GLFWwindow) (str : @& String) : IO Unit := {
  GLFWwindow *c_window = of_lean<GLFWwindow>(window);
  glfwSetClipboardString(c_window, lean_string_cstr(str));
  return lean_io_result_mk_ok(lean_box(0));
}
