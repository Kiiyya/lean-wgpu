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

/- ################################################################## -/
/- # GLFW Callbacks                                                   -/
/- ################################################################## -/

alloy c section
  /* ── Key Callback ── */
  static lean_object* g_key_callback = NULL;
  static void key_callback_trampoline(GLFWwindow* w, int key, int scancode, int action, int mods) {
    (void)w;
    if (!g_key_callback) return;
    lean_inc(g_key_callback);
    lean_object *res = lean_apply_5(g_key_callback,
      lean_box((uint32_t)key), lean_box((uint32_t)scancode),
      lean_box((uint32_t)action), lean_box((uint32_t)mods),
      lean_io_mk_world());
    if (!lean_io_result_is_ok(res)) {
      fprintf(stderr, "key_callback closure errored!\n"); abort();
    }
    lean_dec(res);
  }

  /* ── Mouse‑button Callback ── */
  static lean_object* g_mouse_button_callback = NULL;
  static void mouse_button_callback_trampoline(GLFWwindow* w, int button, int action, int mods) {
    (void)w;
    if (!g_mouse_button_callback) return;
    lean_inc(g_mouse_button_callback);
    lean_object *res = lean_apply_4(g_mouse_button_callback,
      lean_box((uint32_t)button), lean_box((uint32_t)action),
      lean_box((uint32_t)mods), lean_io_mk_world());
    if (!lean_io_result_is_ok(res)) {
      fprintf(stderr, "mouse_button_callback closure errored!\n"); abort();
    }
    lean_dec(res);
  }

  /* ── Cursor‑position Callback ── */
  static lean_object* g_cursor_pos_callback = NULL;
  static void cursor_pos_callback_trampoline(GLFWwindow* w, double x, double y) {
    (void)w;
    if (!g_cursor_pos_callback) return;
    lean_inc(g_cursor_pos_callback);
    lean_object *res = lean_apply_3(g_cursor_pos_callback,
      lean_box_float(x), lean_box_float(y), lean_io_mk_world());
    if (!lean_io_result_is_ok(res)) {
      fprintf(stderr, "cursor_pos_callback closure errored!\n"); abort();
    }
    lean_dec(res);
  }

  /* ── Scroll Callback ── */
  static lean_object* g_scroll_callback = NULL;
  static void scroll_callback_trampoline(GLFWwindow* w, double xoff, double yoff) {
    (void)w;
    if (!g_scroll_callback) return;
    lean_inc(g_scroll_callback);
    lean_object *res = lean_apply_3(g_scroll_callback,
      lean_box_float(xoff), lean_box_float(yoff), lean_io_mk_world());
    if (!lean_io_result_is_ok(res)) {
      fprintf(stderr, "scroll_callback closure errored!\n"); abort();
    }
    lean_dec(res);
  }

  /* ── Framebuffer‑size Callback ── */
  static lean_object* g_framebuffer_size_callback = NULL;
  static void framebuffer_size_callback_trampoline(GLFWwindow* w, int width, int height) {
    (void)w;
    if (!g_framebuffer_size_callback) return;
    lean_inc(g_framebuffer_size_callback);
    lean_object *res = lean_apply_3(g_framebuffer_size_callback,
      lean_box((uint32_t)width), lean_box((uint32_t)height), lean_io_mk_world());
    if (!lean_io_result_is_ok(res)) {
      fprintf(stderr, "framebuffer_size_callback closure errored!\n"); abort();
    }
    lean_dec(res);
  }

  /* ── Window‑size Callback ── */
  static lean_object* g_window_size_callback = NULL;
  static void window_size_callback_trampoline(GLFWwindow* w, int width, int height) {
    (void)w;
    if (!g_window_size_callback) return;
    lean_inc(g_window_size_callback);
    lean_object *res = lean_apply_3(g_window_size_callback,
      lean_box((uint32_t)width), lean_box((uint32_t)height), lean_io_mk_world());
    if (!lean_io_result_is_ok(res)) {
      fprintf(stderr, "window_size_callback closure errored!\n"); abort();
    }
    lean_dec(res);
  }

  /* ── Char Callback ── */
  static lean_object* g_char_callback = NULL;
  static void char_callback_trampoline(GLFWwindow* w, unsigned int codepoint) {
    (void)w;
    if (!g_char_callback) return;
    lean_inc(g_char_callback);
    lean_object *res = lean_apply_2(g_char_callback,
      lean_box(codepoint), lean_io_mk_world());
    if (!lean_io_result_is_ok(res)) {
      fprintf(stderr, "char_callback closure errored!\n"); abort();
    }
    lean_dec(res);
  }

  /* ── Cursor‑enter Callback ── */
  static lean_object* g_cursor_enter_callback = NULL;
  static void cursor_enter_callback_trampoline(GLFWwindow* w, int entered) {
    (void)w;
    if (!g_cursor_enter_callback) return;
    lean_inc(g_cursor_enter_callback);
    lean_object *res = lean_apply_2(g_cursor_enter_callback,
      lean_box(entered ? 1 : 0), lean_io_mk_world());
    if (!lean_io_result_is_ok(res)) {
      fprintf(stderr, "cursor_enter_callback closure errored!\n"); abort();
    }
    lean_dec(res);
  }

  /* ── Drop Callback ── */
  static lean_object* g_drop_callback = NULL;
  static void drop_callback_trampoline(GLFWwindow* w, int count, const char** paths) {
    (void)w;
    if (!g_drop_callback) return;
    lean_inc(g_drop_callback);
    lean_object *arr = lean_mk_array(lean_box(0), lean_box(0));
    for (int i = 0; i < count; i++) {
      arr = lean_array_push(arr, lean_mk_string(paths[i]));
    }
    lean_object *res = lean_apply_2(g_drop_callback, arr, lean_io_mk_world());
    if (!lean_io_result_is_ok(res)) {
      fprintf(stderr, "drop_callback closure errored!\n"); abort();
    }
    lean_dec(res);
  }
end

/-- Set a key callback: `(key scancode action mods : UInt32) → IO Unit`.
    action is 0=release, 1=press, 2=repeat. -/
alloy c extern
def GLFWwindow.setKeyCallback (l_window : GLFWwindow)
    (f : UInt32 → UInt32 → UInt32 → UInt32 → IO Unit) : IO Unit := {
  GLFWwindow *window = of_lean<GLFWwindow>(l_window);
  if (g_key_callback) lean_dec(g_key_callback);
  lean_inc(f);
  g_key_callback = f;
  glfwSetKeyCallback(window, key_callback_trampoline);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set a mouse‑button callback: `(button action mods : UInt32) → IO Unit`. -/
alloy c extern
def GLFWwindow.setMouseButtonCallback (l_window : GLFWwindow)
    (f : UInt32 → UInt32 → UInt32 → IO Unit) : IO Unit := {
  GLFWwindow *window = of_lean<GLFWwindow>(l_window);
  if (g_mouse_button_callback) lean_dec(g_mouse_button_callback);
  lean_inc(f);
  g_mouse_button_callback = f;
  glfwSetMouseButtonCallback(window, mouse_button_callback_trampoline);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set a cursor‑position callback: `(x y : Float) → IO Unit`. -/
alloy c extern
def GLFWwindow.setCursorPosCallback (l_window : GLFWwindow)
    (f : Float → Float → IO Unit) : IO Unit := {
  GLFWwindow *window = of_lean<GLFWwindow>(l_window);
  if (g_cursor_pos_callback) lean_dec(g_cursor_pos_callback);
  lean_inc(f);
  g_cursor_pos_callback = f;
  glfwSetCursorPosCallback(window, cursor_pos_callback_trampoline);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set a scroll callback: `(xoffset yoffset : Float) → IO Unit`. -/
alloy c extern
def GLFWwindow.setScrollCallback (l_window : GLFWwindow)
    (f : Float → Float → IO Unit) : IO Unit := {
  GLFWwindow *window = of_lean<GLFWwindow>(l_window);
  if (g_scroll_callback) lean_dec(g_scroll_callback);
  lean_inc(f);
  g_scroll_callback = f;
  glfwSetScrollCallback(window, scroll_callback_trampoline);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set a framebuffer‑size callback: `(width height : UInt32) → IO Unit`.
    Called when the framebuffer is resized (e.g. on HiDPI changes). -/
alloy c extern
def GLFWwindow.setFramebufferSizeCallback (l_window : GLFWwindow)
    (f : UInt32 → UInt32 → IO Unit) : IO Unit := {
  GLFWwindow *window = of_lean<GLFWwindow>(l_window);
  if (g_framebuffer_size_callback) lean_dec(g_framebuffer_size_callback);
  lean_inc(f);
  g_framebuffer_size_callback = f;
  glfwSetFramebufferSizeCallback(window, framebuffer_size_callback_trampoline);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set a window‑size callback: `(width height : UInt32) → IO Unit`.
    Called when the window content area is resized. -/
alloy c extern
def GLFWwindow.setWindowSizeCallback (l_window : GLFWwindow)
    (f : UInt32 → UInt32 → IO Unit) : IO Unit := {
  GLFWwindow *window = of_lean<GLFWwindow>(l_window);
  if (g_window_size_callback) lean_dec(g_window_size_callback);
  lean_inc(f);
  g_window_size_callback = f;
  glfwSetWindowSizeCallback(window, window_size_callback_trampoline);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set a character input callback: `(codepoint : UInt32) → IO Unit`.
    Receives Unicode codepoints for text input. -/
alloy c extern
def GLFWwindow.setCharCallback (l_window : GLFWwindow)
    (f : UInt32 → IO Unit) : IO Unit := {
  GLFWwindow *window = of_lean<GLFWwindow>(l_window);
  if (g_char_callback) lean_dec(g_char_callback);
  lean_inc(f);
  g_char_callback = f;
  glfwSetCharCallback(window, char_callback_trampoline);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set a cursor‑enter callback: `(entered : Bool) → IO Unit`.
    Called when cursor enters or leaves the window content area. -/
alloy c extern
def GLFWwindow.setCursorEnterCallback (l_window : GLFWwindow)
    (f : Bool → IO Unit) : IO Unit := {
  GLFWwindow *window = of_lean<GLFWwindow>(l_window);
  if (g_cursor_enter_callback) lean_dec(g_cursor_enter_callback);
  lean_inc(f);
  g_cursor_enter_callback = f;
  glfwSetCursorEnterCallback(window, cursor_enter_callback_trampoline);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set a file‑drop callback: `(paths : Array String) → IO Unit`.
    Called when files are dragged and dropped on the window. -/
alloy c extern
def GLFWwindow.setDropCallback (l_window : GLFWwindow)
    (f : Array String → IO Unit) : IO Unit := {
  GLFWwindow *window = of_lean<GLFWwindow>(l_window);
  if (g_drop_callback) lean_dec(g_drop_callback);
  lean_inc(f);
  g_drop_callback = f;
  glfwSetDropCallback(window, drop_callback_trampoline);
  return lean_io_result_mk_ok(lean_box(0));
}

section GLFWModifiers
  /-- Modifier key bits (for mods parameter in key/mouse callbacks) -/
  def GLFW.modShift   : UInt32 := 0x0001
  def GLFW.modControl : UInt32 := 0x0002
  def GLFW.modAlt     : UInt32 := 0x0004
  def GLFW.modSuper   : UInt32 := 0x0008
  def GLFW.modCapsLock : UInt32 := 0x0010
  def GLFW.modNumLock  : UInt32 := 0x0020

  /-- Additional key constants -/
  def GLFW.keyLeftShift   : UInt32 := 340
  def GLFW.keyLeftControl : UInt32 := 341
  def GLFW.keyLeftAlt     : UInt32 := 342
  def GLFW.keyLeftSuper   : UInt32 := 343
  def GLFW.keyRightShift  : UInt32 := 344
  def GLFW.keyRightControl : UInt32 := 345
  def GLFW.keyRightAlt    : UInt32 := 346
  def GLFW.keyRightSuper  : UInt32 := 347
  def GLFW.keyDelete      : UInt32 := 261
  def GLFW.keyInsert      : UInt32 := 260
  def GLFW.keyHome        : UInt32 := 268
  def GLFW.keyEnd         : UInt32 := 269
  def GLFW.keyPageUp      : UInt32 := 266
  def GLFW.keyPageDown    : UInt32 := 267

  /-- Input mode constants for setInputMode -/
  def GLFW.cursor       : UInt32 := 0x00033001
  def GLFW.stickyKeys   : UInt32 := 0x00033002
  def GLFW.stickyMouseButtons : UInt32 := 0x00033003
  def GLFW.rawMouseMotion : UInt32 := 0x00033005
end GLFWModifiers

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

section GLFWWindowAttribs
  def GLFW.decorated    : UInt32 := 0x00020005
  def GLFW.resizable    : UInt32 := 0x00020003
  def GLFW.floating     : UInt32 := 0x00020007
  def GLFW.autoIconify  : UInt32 := 0x00020006
  def GLFW.focusOnShow  : UInt32 := 0x0002000C
end GLFWWindowAttribs

/- ################################################################## -/
/- # GLFW Input Extensions                                            -/
/- ################################################################## -/

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

/-- Warp/set the cursor position. -/
alloy c extern
def GLFWwindow.setCursorPos (l_window : GLFWwindow) (x y : Float) : IO Unit := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  glfwSetCursorPos(window, x, y);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Get the current input mode value. -/
alloy c extern
def GLFWwindow.getInputMode (l_window : GLFWwindow) (mode : UInt32) : IO UInt32 := {
  GLFWwindow* window = of_lean<GLFWwindow>(l_window);
  return lean_io_result_mk_ok(lean_box((uint32_t)glfwGetInputMode(window, (int)mode)));
}

/-- Check if raw mouse motion is supported on this platform. -/
alloy c extern
def GLFW.rawMouseMotionSupported : IO Bool := {
  return lean_io_result_mk_ok(lean_box(glfwRawMouseMotionSupported()));
}

/- Standard cursor shape constants:
   0x00036001=Arrow, 0x00036002=IBeam, 0x00036003=Crosshair,
   0x00036004=Hand, 0x00036005=HResize, 0x00036006=VResize -/
section GLFWCursorShapes
  def GLFW.cursorArrow     : UInt32 := 0x00036001
  def GLFW.cursorIBeam     : UInt32 := 0x00036002
  def GLFW.cursorCrosshair : UInt32 := 0x00036003
  def GLFW.cursorHand      : UInt32 := 0x00036004
  def GLFW.cursorHResize   : UInt32 := 0x00036005
  def GLFW.cursorVResize   : UInt32 := 0x00036006
end GLFWCursorShapes

/- ################################################################## -/
/- # GLFW Joystick / Gamepad                                          -/
/- ################################################################## -/

/-- Check if a joystick is connected. jid is 0-15. -/
alloy c extern
def GLFW.joystickPresent (jid : UInt32) : IO Bool := {
  return lean_io_result_mk_ok(lean_box(glfwJoystickPresent((int)jid)));
}

/-- Get the name of a joystick, or empty string if not connected. -/
alloy c extern
def GLFW.getJoystickName (jid : UInt32) : IO String := {
  const char *name = glfwGetJoystickName((int)jid);
  if (name == NULL) return lean_io_result_mk_ok(lean_mk_string(""));
  return lean_io_result_mk_ok(lean_mk_string(name));
}

/-- Get joystick axis values as an array of Floats. -/
alloy c extern
def GLFW.getJoystickAxes (jid : UInt32) : IO (Array Float) := {
  int count = 0;
  const float *axes = glfwGetJoystickAxes((int)jid, &count);
  lean_object *arr = lean_mk_array(lean_box(0), lean_box(0));
  if (axes != NULL) {
    for (int i = 0; i < count; i++) {
      arr = lean_array_push(arr, lean_box_float((double)axes[i]));
    }
  }
  return lean_io_result_mk_ok(arr);
}

/-- Get joystick button states as an array of UInt32 (0=released, 1=pressed). -/
alloy c extern
def GLFW.getJoystickButtons (jid : UInt32) : IO (Array UInt32) := {
  int count = 0;
  const unsigned char *buttons = glfwGetJoystickButtons((int)jid, &count);
  lean_object *arr = lean_mk_array(lean_box(0), lean_box(0));
  if (buttons != NULL) {
    for (int i = 0; i < count; i++) {
      arr = lean_array_push(arr, lean_box((uint32_t)buttons[i]));
    }
  }
  return lean_io_result_mk_ok(arr);
}

/-- Get joystick hat states as an array of UInt32 (bitmask: 1=up, 2=right, 4=down, 8=left). -/
alloy c extern
def GLFW.getJoystickHats (jid : UInt32) : IO (Array UInt32) := {
  int count = 0;
  const unsigned char *hats = glfwGetJoystickHats((int)jid, &count);
  lean_object *arr = lean_mk_array(lean_box(0), lean_box(0));
  if (hats != NULL) {
    for (int i = 0; i < count; i++) {
      arr = lean_array_push(arr, lean_box((uint32_t)hats[i]));
    }
  }
  return lean_io_result_mk_ok(arr);
}

/-- Check if a joystick has a gamepad mapping. -/
alloy c extern
def GLFW.joystickIsGamepad (jid : UInt32) : IO Bool := {
  return lean_io_result_mk_ok(lean_box(glfwJoystickIsGamepad((int)jid)));
}

/-- Get the gamepad name, or empty string if not a gamepad. -/
alloy c extern
def GLFW.getGamepadName (jid : UInt32) : IO String := {
  const char *name = glfwGetGamepadName((int)jid);
  if (name == NULL) return lean_io_result_mk_ok(lean_mk_string(""));
  return lean_io_result_mk_ok(lean_mk_string(name));
}

/-- Get gamepad state: returns (axes: Array Float, buttons: Array UInt32).
    Axes: 0=LeftX, 1=LeftY, 2=RightX, 3=RightY, 4=LeftTrigger, 5=RightTrigger
    Buttons: 0=A, 1=B, 2=X, 3=Y, 4=LeftBumper, 5=RightBumper, 6=Back, 7=Start,
             8=Guide, 9=LeftThumb, 10=RightThumb, 11=Up, 12=Right, 13=Down, 14=Left -/
alloy c extern
def GLFW.getGamepadState (jid : UInt32) : IO (Array Float × Array UInt32) := {
  GLFWgamepadstate state;
  lean_object *axes = lean_mk_array(lean_box(0), lean_box(0));
  lean_object *buttons = lean_mk_array(lean_box(0), lean_box(0));

  if (glfwGetGamepadState((int)jid, &state)) {
    for (int i = 0; i < 6; i++) {
      axes = lean_array_push(axes, lean_box_float((double)state.axes[i]));
    }
    for (int i = 0; i < 15; i++) {
      buttons = lean_array_push(buttons, lean_box((uint32_t)state.buttons[i]));
    }
  }

  lean_object *pair = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(pair, 0, axes);
  lean_ctor_set(pair, 1, buttons);
  return lean_io_result_mk_ok(pair);
}

/-- Get the GUID of a joystick. -/
alloy c extern
def GLFW.getJoystickGUID (jid : UInt32) : IO String := {
  const char *guid = glfwGetJoystickGUID((int)jid);
  if (guid == NULL) return lean_io_result_mk_ok(lean_mk_string(""));
  return lean_io_result_mk_ok(lean_mk_string(guid));
}

/- ################################################################## -/
/- # GLFW Timer Functions                                             -/
/- ################################################################## -/

/-- Set the GLFW time in seconds. -/
alloy c extern
def GLFW.setTime (time : Float) : IO Unit := {
  glfwSetTime(time);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Get the raw timer value in timer ticks. -/
alloy c extern
def GLFW.getTimerValue : IO UInt64 := {
  uint64_t val = glfwGetTimerValue();
  return lean_io_result_mk_ok(lean_box_uint64(val));
}

/-- Get the timer frequency in ticks per second. -/
alloy c extern
def GLFW.getTimerFrequency : IO UInt64 := {
  uint64_t freq = glfwGetTimerFrequency();
  return lean_io_result_mk_ok(lean_box_uint64(freq));
}

/-- Get the GLFW version as (major, minor, rev). -/
alloy c extern
def GLFW.getVersion : IO (UInt32 × UInt32 × UInt32) := {
  int major, minor, rev;
  glfwGetVersion(&major, &minor, &rev);

  lean_object *p2 = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(p2, 0, lean_box((uint32_t)minor));
  lean_ctor_set(p2, 1, lean_box((uint32_t)rev));

  lean_object *p1 = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(p1, 0, lean_box((uint32_t)major));
  lean_ctor_set(p1, 1, p2);

  return lean_io_result_mk_ok(p1);
}

/-- Get the GLFW version string. -/
alloy c extern
def GLFW.getVersionString : IO String := {
  const char *s = glfwGetVersionString();
  return lean_io_result_mk_ok(lean_mk_string(s ? s : ""));
}

/- ################################################################## -/
/- # Additional GLFW Window Callbacks                                 -/
/- ################################################################## -/

alloy c section
  /* ── Window‑position Callback ── */
  static lean_object* g_window_pos_callback = NULL;
  static void window_pos_callback_trampoline(GLFWwindow* w, int xpos, int ypos) {
    (void)w;
    if (!g_window_pos_callback) return;
    lean_inc(g_window_pos_callback);
    lean_object *res = lean_apply_3(g_window_pos_callback,
      lean_box((uint32_t)xpos), lean_box((uint32_t)ypos), lean_io_mk_world());
    if (!lean_io_result_is_ok(res)) {
      fprintf(stderr, "window_pos_callback closure errored!\n"); abort();
    }
    lean_dec(res);
  }

  /* ── Window‑close Callback ── */
  static lean_object* g_window_close_callback = NULL;
  static void window_close_callback_trampoline(GLFWwindow* w) {
    (void)w;
    if (!g_window_close_callback) return;
    lean_inc(g_window_close_callback);
    lean_object *res = lean_apply_1(g_window_close_callback, lean_io_mk_world());
    if (!lean_io_result_is_ok(res)) {
      fprintf(stderr, "window_close_callback closure errored!\n"); abort();
    }
    lean_dec(res);
  }

  /* ── Window‑focus Callback ── */
  static lean_object* g_window_focus_callback = NULL;
  static void window_focus_callback_trampoline(GLFWwindow* w, int focused) {
    (void)w;
    if (!g_window_focus_callback) return;
    lean_inc(g_window_focus_callback);
    lean_object *res = lean_apply_2(g_window_focus_callback,
      lean_box(focused ? 1 : 0), lean_io_mk_world());
    if (!lean_io_result_is_ok(res)) {
      fprintf(stderr, "window_focus_callback closure errored!\n"); abort();
    }
    lean_dec(res);
  }

  /* ── Window‑iconify Callback ── */
  static lean_object* g_window_iconify_callback = NULL;
  static void window_iconify_callback_trampoline(GLFWwindow* w, int iconified) {
    (void)w;
    if (!g_window_iconify_callback) return;
    lean_inc(g_window_iconify_callback);
    lean_object *res = lean_apply_2(g_window_iconify_callback,
      lean_box(iconified ? 1 : 0), lean_io_mk_world());
    if (!lean_io_result_is_ok(res)) {
      fprintf(stderr, "window_iconify_callback closure errored!\n"); abort();
    }
    lean_dec(res);
  }

  /* ── Window‑maximize Callback ── */
  static lean_object* g_window_maximize_callback = NULL;
  static void window_maximize_callback_trampoline(GLFWwindow* w, int maximized) {
    (void)w;
    if (!g_window_maximize_callback) return;
    lean_inc(g_window_maximize_callback);
    lean_object *res = lean_apply_2(g_window_maximize_callback,
      lean_box(maximized ? 1 : 0), lean_io_mk_world());
    if (!lean_io_result_is_ok(res)) {
      fprintf(stderr, "window_maximize_callback closure errored!\n"); abort();
    }
    lean_dec(res);
  }

  /* ── Window‑refresh Callback ── */
  static lean_object* g_window_refresh_callback = NULL;
  static void window_refresh_callback_trampoline(GLFWwindow* w) {
    (void)w;
    if (!g_window_refresh_callback) return;
    lean_inc(g_window_refresh_callback);
    lean_object *res = lean_apply_1(g_window_refresh_callback, lean_io_mk_world());
    if (!lean_io_result_is_ok(res)) {
      fprintf(stderr, "window_refresh_callback closure errored!\n"); abort();
    }
    lean_dec(res);
  }

  /* ── Window content‑scale Callback ── */
  static lean_object* g_content_scale_callback = NULL;
  static void content_scale_callback_trampoline(GLFWwindow* w, float xscale, float yscale) {
    (void)w;
    if (!g_content_scale_callback) return;
    lean_inc(g_content_scale_callback);
    lean_object *res = lean_apply_3(g_content_scale_callback,
      lean_box_float((double)xscale), lean_box_float((double)yscale), lean_io_mk_world());
    if (!lean_io_result_is_ok(res)) {
      fprintf(stderr, "content_scale_callback closure errored!\n"); abort();
    }
    lean_dec(res);
  }
end

/-- Set a window position callback: `(x y : UInt32) → IO Unit`. -/
alloy c extern
def GLFWwindow.setWindowPosCallback (l_window : GLFWwindow)
    (f : UInt32 → UInt32 → IO Unit) : IO Unit := {
  GLFWwindow *window = of_lean<GLFWwindow>(l_window);
  if (g_window_pos_callback) lean_dec(g_window_pos_callback);
  lean_inc(f);
  g_window_pos_callback = f;
  glfwSetWindowPosCallback(window, window_pos_callback_trampoline);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set a close callback: `IO Unit`. Called when the user attempts to close the window. -/
alloy c extern
def GLFWwindow.setCloseCallback (l_window : GLFWwindow)
    (f : IO Unit) : IO Unit := {
  GLFWwindow *window = of_lean<GLFWwindow>(l_window);
  if (g_window_close_callback) lean_dec(g_window_close_callback);
  lean_inc(f);
  g_window_close_callback = f;
  glfwSetWindowCloseCallback(window, window_close_callback_trampoline);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set a focus callback: `(focused : Bool) → IO Unit`. -/
alloy c extern
def GLFWwindow.setFocusCallback (l_window : GLFWwindow)
    (f : Bool → IO Unit) : IO Unit := {
  GLFWwindow *window = of_lean<GLFWwindow>(l_window);
  if (g_window_focus_callback) lean_dec(g_window_focus_callback);
  lean_inc(f);
  g_window_focus_callback = f;
  glfwSetWindowFocusCallback(window, window_focus_callback_trampoline);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set an iconify callback: `(iconified : Bool) → IO Unit`. -/
alloy c extern
def GLFWwindow.setIconifyCallback (l_window : GLFWwindow)
    (f : Bool → IO Unit) : IO Unit := {
  GLFWwindow *window = of_lean<GLFWwindow>(l_window);
  if (g_window_iconify_callback) lean_dec(g_window_iconify_callback);
  lean_inc(f);
  g_window_iconify_callback = f;
  glfwSetWindowIconifyCallback(window, window_iconify_callback_trampoline);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set a maximize callback: `(maximized : Bool) → IO Unit`. -/
alloy c extern
def GLFWwindow.setMaximizeCallback (l_window : GLFWwindow)
    (f : Bool → IO Unit) : IO Unit := {
  GLFWwindow *window = of_lean<GLFWwindow>(l_window);
  if (g_window_maximize_callback) lean_dec(g_window_maximize_callback);
  lean_inc(f);
  g_window_maximize_callback = f;
  glfwSetWindowMaximizeCallback(window, window_maximize_callback_trampoline);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set a refresh callback: `IO Unit`. Called when the window needs to be redrawn. -/
alloy c extern
def GLFWwindow.setRefreshCallback (l_window : GLFWwindow)
    (f : IO Unit) : IO Unit := {
  GLFWwindow *window = of_lean<GLFWwindow>(l_window);
  if (g_window_refresh_callback) lean_dec(g_window_refresh_callback);
  lean_inc(f);
  g_window_refresh_callback = f;
  glfwSetWindowRefreshCallback(window, window_refresh_callback_trampoline);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Set a content scale callback: `(xscale yscale : Float) → IO Unit`.
    Called when the content scale changes (e.g. window moved between monitors). -/
alloy c extern
def GLFWwindow.setContentScaleCallback (l_window : GLFWwindow)
    (f : Float → Float → IO Unit) : IO Unit := {
  GLFWwindow *window = of_lean<GLFWwindow>(l_window);
  if (g_content_scale_callback) lean_dec(g_content_scale_callback);
  lean_inc(f);
  g_content_scale_callback = f;
  glfwSetWindowContentScaleCallback(window, content_scale_callback_trampoline);
  return lean_io_result_mk_ok(lean_box(0));
}

/- ################################################################## -/
/- # Error Handling                                                   -/
/- ################################################################## -/

/-- Get the last GLFW error code and description. Returns (errorCode, description). -/
alloy c extern
def GLFW.getError : IO (UInt32 × String) := {
  const char *desc = NULL;
  int code = glfwGetError(&desc);
  lean_object *pair = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(pair, 0, lean_box((uint32_t)code));
  lean_ctor_set(pair, 1, lean_mk_string(desc ? desc : ""));
  return lean_io_result_mk_ok(pair);
}

alloy c section
  static lean_object *g_glfw_error_callback = NULL;

  void glfw_error_callback_trampoline(int error_code, const char *description) {
    if (g_glfw_error_callback != NULL) {
      lean_inc(g_glfw_error_callback);
      lean_object *code_obj = lean_box((uint32_t)error_code);
      lean_object *desc_obj = lean_mk_string(description ? description : "");
      lean_object *res = lean_apply_2(g_glfw_error_callback, code_obj, desc_obj);
      if (lean_io_result_is_ok(res)) { lean_dec(lean_io_result_get_value(res)); }
      lean_dec(res);
    }
  }
end

/-- Set the GLFW error callback. The callback receives (errorCode : UInt32, description : String). -/
alloy c extern
def GLFW.setErrorCallback (f : UInt32 → String → IO Unit) : IO Unit := {
  lean_inc(f);
  if (g_glfw_error_callback != NULL) lean_dec(g_glfw_error_callback);
  g_glfw_error_callback = f;
  glfwSetErrorCallback(glfw_error_callback_trampoline);
  return lean_io_result_mk_ok(lean_box(0));
}

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

/- ################################################################## -/
/- # Monitor Functions                                                -/
/- ################################################################## -/

alloy c opaque_extern_type GLFWmonitor => GLFWmonitor where
  finalize(ptr) :=
    -- Monitors are owned by GLFW, do NOT free or destroy them
    return;

/-- Get the primary monitor. -/
alloy c extern
def GLFWmonitor.getPrimary : IO GLFWmonitor := {
  GLFWmonitor *mon = glfwGetPrimaryMonitor();
  if (mon == NULL) {
    return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string("glfwGetPrimaryMonitor returned NULL")));
  }
  return lean_io_result_mk_ok(to_lean<GLFWmonitor>(mon));
}

/-- Get all connected monitors. -/
alloy c extern
def GLFWmonitor.getAll : IO (Array GLFWmonitor) := {
  int count = 0;
  GLFWmonitor **monitors = glfwGetMonitors(&count);
  lean_object *arr = lean_alloc_array(0, count > 0 ? count : 1);
  for (int i = 0; i < count; i++) {
    arr = lean_array_push(arr, to_lean<GLFWmonitor>(monitors[i]));
  }
  return lean_io_result_mk_ok(arr);
}

/-- Get the name of a monitor. -/
alloy c extern
def GLFWmonitor.getName (mon : @& GLFWmonitor) : IO String := {
  GLFWmonitor *c_mon = of_lean<GLFWmonitor>(mon);
  const char *name = glfwGetMonitorName(c_mon);
  return lean_io_result_mk_ok(lean_mk_string(name ? name : ""));
}

/-- Get the position of the monitor's viewport on the virtual screen. Returns (x, y). -/
alloy c extern
def GLFWmonitor.getPos (mon : @& GLFWmonitor) : IO (Int32 × Int32) := {
  GLFWmonitor *c_mon = of_lean<GLFWmonitor>(mon);
  int x = 0, y = 0;
  glfwGetMonitorPos(c_mon, &x, &y);
  lean_object *pair = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(pair, 0, lean_box((uint32_t)x));
  lean_ctor_set(pair, 1, lean_box((uint32_t)y));
  return lean_io_result_mk_ok(pair);
}

/-- Get the work area of the monitor (excludes taskbar, etc). Returns (x, y, width, height). -/
alloy c extern
def GLFWmonitor.getWorkarea (mon : @& GLFWmonitor) : IO (Int32 × Int32 × Int32 × Int32) := {
  GLFWmonitor *c_mon = of_lean<GLFWmonitor>(mon);
  int x = 0, y = 0, w = 0, h = 0;
  glfwGetMonitorWorkarea(c_mon, &x, &y, &w, &h);

  lean_object *p3 = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(p3, 0, lean_box((uint32_t)w));
  lean_ctor_set(p3, 1, lean_box((uint32_t)h));

  lean_object *p2 = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(p2, 0, lean_box((uint32_t)y));
  lean_ctor_set(p2, 1, p3);

  lean_object *p1 = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(p1, 0, lean_box((uint32_t)x));
  lean_ctor_set(p1, 1, p2);

  return lean_io_result_mk_ok(p1);
}

/-- Get the physical size of the monitor in millimeters. Returns (widthMM, heightMM). -/
alloy c extern
def GLFWmonitor.getPhysicalSize (mon : @& GLFWmonitor) : IO (Int32 × Int32) := {
  GLFWmonitor *c_mon = of_lean<GLFWmonitor>(mon);
  int wmm = 0, hmm = 0;
  glfwGetMonitorPhysicalSize(c_mon, &wmm, &hmm);
  lean_object *pair = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(pair, 0, lean_box((uint32_t)wmm));
  lean_ctor_set(pair, 1, lean_box((uint32_t)hmm));
  return lean_io_result_mk_ok(pair);
}

/-- Get the content scale of the monitor. Returns (xscale, yscale). -/
alloy c extern
def GLFWmonitor.getContentScale (mon : @& GLFWmonitor) : IO (Float32 × Float32) := {
  GLFWmonitor *c_mon = of_lean<GLFWmonitor>(mon);
  float xs = 0, ys = 0;
  glfwGetMonitorContentScale(c_mon, &xs, &ys);
  lean_object *pair = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(pair, 0, lean_box_float32(xs));
  lean_ctor_set(pair, 1, lean_box_float32(ys));
  return lean_io_result_mk_ok(pair);
}

/-- Get the current video mode of a monitor. Returns (width, height, redBits, greenBits, blueBits, refreshRate). -/
alloy c extern
def GLFWmonitor.getVideoMode (mon : @& GLFWmonitor) : IO (Int32 × Int32 × Int32 × Int32 × Int32 × Int32) := {
  GLFWmonitor *c_mon = of_lean<GLFWmonitor>(mon);
  const GLFWvidmode *mode = glfwGetVideoMode(c_mon);
  if (mode == NULL) {
    return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string("glfwGetVideoMode returned NULL")));
  }
  -- 6-tuple: nested pairs (a, (b, (c, (d, (e, f)))))
  lean_object *t5 = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(t5, 0, lean_box((uint32_t)mode->blueBits));
  lean_ctor_set(t5, 1, lean_box((uint32_t)mode->refreshRate));
  lean_object *t4 = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(t4, 0, lean_box((uint32_t)mode->greenBits));
  lean_ctor_set(t4, 1, t5);
  lean_object *t3 = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(t3, 0, lean_box((uint32_t)mode->redBits));
  lean_ctor_set(t3, 1, t4);
  lean_object *t2 = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(t2, 0, lean_box((uint32_t)mode->height));
  lean_ctor_set(t2, 1, t3);
  lean_object *t1 = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(t1, 0, lean_box((uint32_t)mode->width));
  lean_ctor_set(t1, 1, t2);
  return lean_io_result_mk_ok(t1);
}

/-- Set the gamma ramp of a monitor. gamma should typically be 1.0. -/
alloy c extern
def GLFWmonitor.setGamma (mon : @& GLFWmonitor) (gamma : Float) : IO Unit := {
  GLFWmonitor *c_mon = of_lean<GLFWmonitor>(mon);
  glfwSetGamma(c_mon, (float)gamma);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Get the monitor that the window is fullscreen on, or none if windowed. -/
alloy c extern
def GLFWwindow.getMonitor (window : @& GLFWwindow) : IO (Option GLFWmonitor) := {
  GLFWwindow *c_window = of_lean<GLFWwindow>(window);
  GLFWmonitor *mon = glfwGetWindowMonitor(c_window);
  if (mon == NULL) {
    return lean_io_result_mk_ok(lean_box(0)); -- Option.none
  }
  lean_object *some = lean_alloc_ctor(1, 1, 0);
  lean_ctor_set(some, 0, to_lean<GLFWmonitor>(mon));
  return lean_io_result_mk_ok(some);
}

/-- Set the monitor for the window (fullscreen or windowed).
    Pass `none` for windowed mode with the given position and size.
    Pass `some monitor` for fullscreen on that monitor. -/
alloy c extern
def GLFWwindow.setMonitor (window : @& GLFWwindow) (monitor : @& Option GLFWmonitor)
  (xpos ypos width height refreshRate : Int32) : IO Unit := {
  GLFWwindow *c_window = of_lean<GLFWwindow>(window);
  GLFWmonitor *c_mon = NULL;
  if (lean_obj_tag(monitor) == 1) { -- Option.some
    c_mon = of_lean<GLFWmonitor>(lean_ctor_get(monitor, 0));
  }
  glfwSetWindowMonitor(c_window, c_mon, (int)xpos, (int)ypos, (int)width, (int)height, (int)refreshRate);
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

/- GLFW window hint constants -/
def GLFW.hintFocused        : UInt32 := 0x00020001
def GLFW.hintIconified       : UInt32 := 0x00020002
def GLFW.hintResizable       : UInt32 := 0x00020003
def GLFW.hintVisible         : UInt32 := 0x00020004
def GLFW.hintDecorated       : UInt32 := 0x00020005
def GLFW.hintAutoIconify     : UInt32 := 0x00020006
def GLFW.hintFloating        : UInt32 := 0x00020007
def GLFW.hintMaximized       : UInt32 := 0x00020008
def GLFW.hintCenterCursor    : UInt32 := 0x00020009
def GLFW.hintTransparentFB   : UInt32 := 0x0002000A
def GLFW.hintFocusOnShow     : UInt32 := 0x0002000C
def GLFW.hintScaleToMonitor  : UInt32 := 0x0002200C
def GLFW.hintRedBits         : UInt32 := 0x00021001
def GLFW.hintGreenBits       : UInt32 := 0x00021002
def GLFW.hintBlueBits        : UInt32 := 0x00021003
def GLFW.hintAlphaBits       : UInt32 := 0x00021004
def GLFW.hintDepthBits       : UInt32 := 0x00021005
def GLFW.hintStencilBits     : UInt32 := 0x00021006
def GLFW.hintSamples         : UInt32 := 0x0002100D
def GLFW.hintRefreshRate      : UInt32 := 0x0002100F
def GLFW.hintClientAPI        : UInt32 := 0x00022001
def GLFW.hintNoAPI : UInt32 := 0

/- ################################################################## -/
/- # Clipboard                                                        -/
/- ################################################################## -/

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
