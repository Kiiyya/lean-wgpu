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
