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
