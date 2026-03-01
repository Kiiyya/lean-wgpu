/- GLFW key, modifier, cursor shape, and window attribute constants. -/

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

section GLFWWindowAttribs
  def GLFW.decorated    : UInt32 := 0x00020005
  def GLFW.resizable    : UInt32 := 0x00020003
  def GLFW.floating     : UInt32 := 0x00020007
  def GLFW.autoIconify  : UInt32 := 0x00020006
  def GLFW.focusOnShow  : UInt32 := 0x0002000C
end GLFWWindowAttribs

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
