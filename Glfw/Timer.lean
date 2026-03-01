import Alloy.C
open scoped Alloy.C

alloy c section
  #include <stdio.h>
  #include <stdlib.h>
  #include <lean/lean.h>
  #include <GLFW/glfw3.h>

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

/- ################################################################## -/
/- # GLFW Timer Functions                                             -/
/- ################################################################## -/

/-- Get the GLFW time in seconds since initialization. -/
alloy c extern
def GLFW.getTime : IO Float := {
  double t = glfwGetTime();
  return lean_io_result_mk_ok(lean_box_float(t));
}

/-- Set the GLFW time in seconds. -/
alloy c extern
def GLFW.setTime (time : Float) : IO Unit := {
  glfwSetTime(time);
  return lean_io_result_mk_ok(lean_box(0));
}

/-- Swap interval (vsync). 0 = off, 1 = on. -/
alloy c extern
def GLFW.swapInterval (interval : UInt32) : IO Unit := {
  glfwSwapInterval(interval);
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

/-- Set the GLFW error callback. The callback receives (errorCode : UInt32, description : String). -/
alloy c extern
def GLFW.setErrorCallback (f : UInt32 → String → IO Unit) : IO Unit := {
  lean_inc(f);
  if (g_glfw_error_callback != NULL) lean_dec(g_glfw_error_callback);
  g_glfw_error_callback = f;
  glfwSetErrorCallback(glfw_error_callback_trampoline);
  return lean_io_result_mk_ok(lean_box(0));
}
