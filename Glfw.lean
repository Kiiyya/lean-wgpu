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

/-- Get the GLFW time in seconds since initialization. -/
alloy c extern
def GLFW.getTime : IO Float := {
  double t = glfwGetTime();
  return lean_io_result_mk_ok(lean_box_float(t));
}

/-- Swap interval (vsync). 0 = off, 1 = on. -/
alloy c extern
def GLFW.swapInterval (interval : UInt32) : IO Unit := {
  glfwSwapInterval(interval);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set the window size. -/
alloy c extern
def GLFWwindow.setSize (l_window : GLFWwindow) (width height : UInt32) : IO Unit := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  glfwSetWindowSize(window, width, height);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Get the state of a mouse button. Returns GLFW_PRESS (1) or GLFW_RELEASE (0). -/
alloy c extern
def GLFWwindow.getMouseButton (l_window : GLFWwindow) (button : UInt32) : IO UInt32 := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  int state = glfwGetMouseButton(window, button);
  return lean_io_result_mk_ok(lean_box(state));
}

section GLFWKeys
  /-- Common GLFW key constants -/
  def GLFW.keyEscape   : UInt32 := 256
  def GLFW.keyEnter    : UInt32 := 257
  def GLFW.keyTab      : UInt32 := 258
  def GLFW.keyBackspace : UInt32 := 259
  def GLFW.keyRight    : UInt32 := 262
  def GLFW.keyLeft     : UInt32 := 263
  def GLFW.keyDown     : UInt32 := 264
  def GLFW.keyUp       : UInt32 := 265
  def GLFW.keySpace    : UInt32 := 32
  def GLFW.keyW        : UInt32 := 87
  def GLFW.keyA        : UInt32 := 65
  def GLFW.keyS        : UInt32 := 83
  def GLFW.keyD        : UInt32 := 68
  def GLFW.keyQ        : UInt32 := 81

  def GLFW.press       : UInt32 := 1
  def GLFW.release     : UInt32 := 0
  def GLFW.repeat      : UInt32 := 2

  /-- Mouse button constants -/
  def GLFW.mouseButtonLeft   : UInt32 := 0
  def GLFW.mouseButtonRight  : UInt32 := 1
  def GLFW.mouseButtonMiddle : UInt32 := 2

  /-- More key constants -/
  def GLFW.keyF1 : UInt32 := 290
  def GLFW.keyF2 : UInt32 := 291
  def GLFW.keyF3 : UInt32 := 292
  def GLFW.keyF11 : UInt32 := 300
  def GLFW.keyR : UInt32 := 82
  def GLFW.keyC : UInt32 := 67
  def GLFW.keyP : UInt32 := 80
  def GLFW.key1 : UInt32 := 49
  def GLFW.key2 : UInt32 := 50
  def GLFW.key3 : UInt32 := 51
  def GLFW.key4 : UInt32 := 52
  def GLFW.key5 : UInt32 := 53

  /-- Cursor modes -/
  def GLFW.cursorNormal   : UInt32 := 0x00034001
  def GLFW.cursorHidden   : UInt32 := 0x00034002
  def GLFW.cursorDisabled : UInt32 := 0x00034003
end GLFWKeys

/-- Set cursor input mode. Use GLFW.cursorNormal, cursorHidden, or cursorDisabled. -/
alloy c extern
def GLFWwindow.setInputMode (l_window : GLFWwindow) (mode : UInt32) (value : UInt32) : IO Unit := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  glfwSetInputMode(window, mode, value);
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

  WGPUSurface *surface = calloc(1,sizeof(WGPUSurface));
  *surface = glfwGetWGPUSurface(*c_inst, c_window);
  return lean_io_result_mk_ok(to_lean<Surface>(surface));
}
