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

/-- Get the size of the window's content area in screen coordinates. -/
alloy c extern
def GLFWwindow.getWindowSize (l_window : GLFWwindow) : IO (UInt32 × UInt32) := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  int w, h;
  glfwGetWindowSize(window, &w, &h);
  lean_object *pair = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(pair, 0, lean_box(w));
  lean_ctor_set(pair, 1, lean_box(h));
  return lean_io_result_mk_ok(pair);
}

/-- Get the size of the framebuffer in pixels (may differ from window size on HiDPI). -/
alloy c extern
def GLFWwindow.getFramebufferSize (l_window : GLFWwindow) : IO (UInt32 × UInt32) := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  int w, h;
  glfwGetFramebufferSize(window, &w, &h);
  lean_object *pair = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(pair, 0, lean_box(w));
  lean_ctor_set(pair, 1, lean_box(h));
  return lean_io_result_mk_ok(pair);
}

/-- Set the title of the window. -/
alloy c extern
def GLFWwindow.setTitle (l_window : GLFWwindow) (title : String) : IO Unit := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  glfwSetWindowTitle(window, lean_string_cstr(title));
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set the window size. -/
alloy c extern
def GLFWwindow.setSize (l_window : GLFWwindow) (width height : UInt32) : IO Unit := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  glfwSetWindowSize(window, width, height);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Get the window position in screen coordinates. -/
alloy c extern
def GLFWwindow.getWindowPos (l_window : GLFWwindow) : IO (UInt32 × UInt32) := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  int x, y;
  glfwGetWindowPos(window, &x, &y);
  lean_object *pair = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(pair, 0, lean_box(x));
  lean_ctor_set(pair, 1, lean_box(y));
  return lean_io_result_mk_ok(pair);
}

/-- Set the window position in screen coordinates. -/
alloy c extern
def GLFWwindow.setWindowPos (l_window : GLFWwindow) (x y : UInt32) : IO Unit := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  glfwSetWindowPos(window, x, y);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Iconify (minimize) the window. -/
alloy c extern
def GLFWwindow.iconify (l_window : GLFWwindow) : IO Unit := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  glfwIconifyWindow(window);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Restore the window from iconified/maximized state. -/
alloy c extern
def GLFWwindow.restore (l_window : GLFWwindow) : IO Unit := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  glfwRestoreWindow(window);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Maximize the window. -/
alloy c extern
def GLFWwindow.maximize (l_window : GLFWwindow) : IO Unit := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  glfwMaximizeWindow(window);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Focus the window, bringing it to front. -/
alloy c extern
def GLFWwindow.focus (l_window : GLFWwindow) : IO Unit := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  glfwFocusWindow(window);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Check if the window is focused. -/
alloy c extern
def GLFWwindow.isFocused (l_window : GLFWwindow) : IO Bool := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  int focused = glfwGetWindowAttrib(window, GLFW_FOCUSED);
  return lean_io_result_mk_ok(lean_box(focused));
}

/-- Check if the window is iconified (minimized). -/
alloy c extern
def GLFWwindow.isIconified (l_window : GLFWwindow) : IO Bool := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  int val = glfwGetWindowAttrib(window, GLFW_ICONIFIED);
  return lean_io_result_mk_ok(lean_box(val));
}

/-- Check if the window is visible. -/
alloy c extern
def GLFWwindow.isVisible (l_window : GLFWwindow) : IO Bool := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  int val = glfwGetWindowAttrib(window, GLFW_VISIBLE);
  return lean_io_result_mk_ok(lean_box(val));
}

/- ################################################################## -/
/- # Additional GLFW Window Management                                -/
/- ################################################################## -/

/-- Set minimum and maximum size limits for the window.
    Pass 0 for any value to leave it unconstrained. -/
alloy c extern
def GLFWwindow.setSizeLimits (l_window : GLFWwindow)
    (minW minH maxW maxH : UInt32) : IO Unit := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  int minWidth  = (minW == 0) ? GLFW_DONT_CARE : (int)minW;
  int minHeight = (minH == 0) ? GLFW_DONT_CARE : (int)minH;
  int maxWidth  = (maxW == 0) ? GLFW_DONT_CARE : (int)maxW;
  int maxHeight = (maxH == 0) ? GLFW_DONT_CARE : (int)maxH;
  glfwSetWindowSizeLimits(window, minWidth, minHeight, maxWidth, maxHeight);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Lock the window to a specific aspect ratio (numer:denom).
    Pass (0, 0) to remove the constraint. -/
alloy c extern
def GLFWwindow.setAspectRatio (l_window : GLFWwindow) (numer denom : UInt32) : IO Unit := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  int n = (numer == 0) ? GLFW_DONT_CARE : (int)numer;
  int d = (denom == 0) ? GLFW_DONT_CARE : (int)denom;
  glfwSetWindowAspectRatio(window, n, d);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Get the content scale for the window (HiDPI factor). -/
alloy c extern
def GLFWwindow.getContentScale (l_window : GLFWwindow) : IO (Float × Float) := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  float xscale, yscale;
  glfwGetWindowContentScale(window, &xscale, &yscale);
  lean_object *pair = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(pair, 0, lean_box_float((double)xscale));
  lean_ctor_set(pair, 1, lean_box_float((double)yscale));
  return lean_io_result_mk_ok(pair);
}

/-- Get the frame border sizes (left, top, right, bottom) in screen coordinates. -/
alloy c extern
def GLFWwindow.getFrameSize (l_window : GLFWwindow) : IO (UInt32 × UInt32 × UInt32 × UInt32) := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  int left, top, right, bottom;
  glfwGetWindowFrameSize(window, &left, &top, &right, &bottom);

  lean_object *p3 = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(p3, 0, lean_box((uint32_t)right));
  lean_ctor_set(p3, 1, lean_box((uint32_t)bottom));

  lean_object *p2 = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(p2, 0, lean_box((uint32_t)top));
  lean_ctor_set(p2, 1, p3);

  lean_object *p1 = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(p1, 0, lean_box((uint32_t)left));
  lean_ctor_set(p1, 1, p2);

  return lean_io_result_mk_ok(p1);
}

/-- Get the window opacity (0.0 = fully transparent, 1.0 = fully opaque). -/
alloy c extern
def GLFWwindow.getOpacity (l_window : GLFWwindow) : IO Float := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  float opacity = glfwGetWindowOpacity(window);
  return lean_io_result_mk_ok(lean_box_float((double)opacity));
}

/-- Set the window opacity (0.0 = fully transparent, 1.0 = fully opaque). -/
alloy c extern
def GLFWwindow.setOpacity (l_window : GLFWwindow) (opacity : Float) : IO Unit := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  glfwSetWindowOpacity(window, (float)opacity);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Show a previously hidden window. -/
alloy c extern
def GLFWwindow.show (l_window : GLFWwindow) : IO Unit := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  glfwShowWindow(window);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Hide the window (make it invisible). -/
alloy c extern
def GLFWwindow.hide (l_window : GLFWwindow) : IO Unit := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  glfwHideWindow(window);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Request attention (flash the taskbar/dock icon). -/
alloy c extern
def GLFWwindow.requestAttention (l_window : GLFWwindow) : IO Unit := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  glfwRequestWindowAttention(window);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Check if the window is maximized. -/
alloy c extern
def GLFWwindow.isMaximized (l_window : GLFWwindow) : IO Bool := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  return lean_io_result_mk_ok(lean_box(glfwGetWindowAttrib(window, GLFW_MAXIMIZED)));
}

/-- Check if the window is decorated (has title bar, borders). -/
alloy c extern
def GLFWwindow.isDecorated (l_window : GLFWwindow) : IO Bool := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  return lean_io_result_mk_ok(lean_box(glfwGetWindowAttrib(window, GLFW_DECORATED)));
}

/-- Check if the window is floating (always-on-top). -/
alloy c extern
def GLFWwindow.isFloating (l_window : GLFWwindow) : IO Bool := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  return lean_io_result_mk_ok(lean_box(glfwGetWindowAttrib(window, GLFW_FLOATING)));
}

/-- Set a window attribute. Common attributes:
    GLFW_DECORATED (0x00020005), GLFW_RESIZABLE (0x00020003),
    GLFW_FLOATING (0x00020007), GLFW_AUTO_ICONIFY (0x00020006). -/
alloy c extern
def GLFWwindow.setAttrib (l_window : GLFWwindow) (attrib : UInt32) (value : Bool) : IO Unit := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  glfwSetWindowAttrib(window, attrib, value ? GLFW_TRUE : GLFW_FALSE);
  return lean_io_result_mk_ok(lean_box(0));
}

/- ################################################################## -/
/- # Window Hints                                                     -/
/- ################################################################## -/

/-- Reset all window hints to their default values. -/
alloy c extern
def GLFW.defaultWindowHints : IO Unit := {
  glfwDefaultWindowHints();
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set a window hint to an integer value. Must be called before window creation. -/
alloy c extern
def GLFW.windowHint (hint : UInt32) (value : UInt32) : IO Unit := {
  glfwWindowHint((int)hint, (int)value);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set a window hint to a string value. Must be called before window creation. -/
alloy c extern
def GLFW.windowHintString (hint : UInt32) (value : @& String) : IO Unit := {
  glfwWindowHintString((int)hint, lean_string_cstr(value));
  return lean_io_result_mk_ok(lean_box(0));
}

/- ################################################################## -/
/- # Extra Window Functions                                           -/
/- ################################################################## -/

/-- Get the position of the window. Returns (x, y). -/
alloy c extern
def GLFWwindow.getPos (window : @& GLFWwindow) : IO (Int32 × Int32) := {
  GLFWwindow *c_window = of_lean<GLFWwindow>(window);
  int x = 0, y = 0;
  glfwGetWindowPos(c_window, &x, &y);
  lean_object *pair = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(pair, 0, lean_box((uint32_t)x));
  lean_ctor_set(pair, 1, lean_box((uint32_t)y));
  return lean_io_result_mk_ok(pair);
}

/-- Set the position of the window. -/
alloy c extern
def GLFWwindow.setPos (window : @& GLFWwindow) (x y : Int32) : IO Unit := {
  GLFWwindow *c_window = of_lean<GLFWwindow>(window);
  glfwSetWindowPos(c_window, (int)x, (int)y);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Check if the window is hovered by the cursor. -/
alloy c extern
def GLFWwindow.isHovered (window : @& GLFWwindow) : IO Bool := {
  GLFWwindow *c_window = of_lean<GLFWwindow>(window);
  int v = glfwGetWindowAttrib(c_window, GLFW_HOVERED);
  return lean_io_result_mk_ok(lean_box(v ? 1 : 0));
}
