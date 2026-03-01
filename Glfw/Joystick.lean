import Alloy.C
open scoped Alloy.C

alloy c section
  #include <stdio.h>
  #include <stdlib.h>
  #include <lean/lean.h>
  #include <GLFW/glfw3.h>
end

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
