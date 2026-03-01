import Glfw

open IO

set_option linter.unusedVariables false

def glfwInfo : IO Unit := do
  eprintln "=== GLFW Info Test ==="

  -- Set up error callback (works before init)
  GLFW.setErrorCallback fun code desc => do
    eprintln s!"GLFW Error [{code}]: {desc}"

  -- Version info (compile-time, works before glfwInit)
  let (major, minor, rev) ← GLFW.getVersion
  eprintln s!"GLFW Version: {major}.{minor}.{rev}"
  let verStr ← GLFW.getVersionString
  eprintln s!"Version String: {verStr}"

  -- Create window (calls glfwInit internally)
  let window ← GLFWwindow.mk 640 480 "GLFW Info Test"
  eprintln "Window created"

  -- Timer (needs glfwInit)
  let timerFreq ← GLFW.getTimerFrequency
  let timerVal ← GLFW.getTimerValue
  eprintln s!"Timer frequency: {timerFreq} Hz"
  eprintln s!"Timer value: {timerVal}"
  let time ← GLFW.getTime
  eprintln s!"GLFW time: {time}"

  -- Error state
  let (errCode, errDesc) ← GLFW.getError
  eprintln s!"Last error: code={errCode}"

  -- Monitor enumeration
  eprintln ""
  eprintln "--- Monitors ---"
  let monitors ← GLFWmonitor.getAll
  eprintln s!"Found {monitors.size} monitor(s)"

  for h : i in [:monitors.size] do
    let mon := monitors[i]
    let name ← mon.getName
    let (mx, my) ← mon.getPos
    eprintln s!"  Monitor [{i}]: {name} pos=({mx},{my})"
    let (wa_x, wa_y, wa_w, wa_h) ← mon.getWorkarea
    eprintln s!"    Workarea: ({wa_x},{wa_y}) {wa_w}x{wa_h}"
    let (pmm_w, pmm_h) ← mon.getPhysicalSize
    eprintln s!"    Physical: {pmm_w}x{pmm_h} mm"
    let (cs_x, cs_y) ← mon.getContentScale
    eprintln s!"    ContentScale: ({cs_x},{cs_y})"
    let (vm_w, vm_h, vm_r, vm_g, vm_b, vm_hz) ← mon.getVideoMode
    eprintln s!"    VideoMode: {vm_w}x{vm_h} @ {vm_hz}Hz RGB({vm_r},{vm_g},{vm_b})"

  if monitors.size > 0 then
    let primary ← GLFWmonitor.getPrimary
    let primaryName ← primary.getName
    eprintln s!"Primary monitor: {primaryName}"
  else
    eprintln "No monitors available (WSL2/headless?)"

  -- Window properties
  eprintln ""
  eprintln "--- Window ---"
  let (wx, wy) ← window.getPos
  eprintln s!"  Position: ({wx}, {wy})"
  let (ww, wh) ← window.getWindowSize
  eprintln s!"  Size: {ww}x{wh}"
  let (fl, ft, fr, fb) ← window.getFrameSize
  eprintln s!"  Frame borders: left={fl} top={ft} right={fr} bottom={fb}"
  let (csx, csy) ← window.getContentScale
  eprintln s!"  Content scale: ({csx}, {csy})"

  let visible ← window.isVisible
  let focused ← window.isFocused
  let maximized ← window.isMaximized
  let decorated ← window.isDecorated
  let floating ← window.isFloating
  eprintln s!"  Visible={visible} Focused={focused} Maximized={maximized}"
  eprintln s!"  Decorated={decorated} Floating={floating}"

  let monOpt ← window.getMonitor
  match monOpt with
  | .none => eprintln "  Monitor: windowed (none)"
  | .some m => do
    let mname ← m.getName
    eprintln s!"  Monitor: {mname} (fullscreen)"

  window.setPos 100 100
  let (nx, ny) ← window.getPos
  eprintln s!"  After setPos(100,100): ({nx}, {ny})"
  window.setTitle "GLFW Info - Updated Title"
  eprintln "  Title updated"

  -- Clipboard
  eprintln ""
  eprintln "--- Clipboard ---"
  GLFW.setClipboardString "Hello from lean-wgpu!"
  let clipContent ← GLFW.getClipboardString
  eprintln s!"  Clipboard: {clipContent}"

  -- Cursors
  eprintln ""
  eprintln "--- Cursors ---"
  let cursorArrow ← GLFWcursor.createStandard GLFW.cursorArrow
  let cursorIBeam ← GLFWcursor.createStandard GLFW.cursorIBeam
  let cursorCrosshair ← GLFWcursor.createStandard GLFW.cursorCrosshair
  let cursorHand ← GLFWcursor.createStandard GLFW.cursorHand
  eprintln "  Created standard cursors: arrow, ibeam, crosshair, hand"
  window.setCursor cursorArrow
  eprintln "  Set cursor to arrow"
  window.setCursor cursorHand
  eprintln "  Set cursor to hand"
  window.resetCursor
  eprintln "  Reset cursor to default"

  -- Input
  eprintln ""
  eprintln "--- Input ---"
  let rawSupported ← GLFW.rawMouseMotionSupported
  eprintln s!"  Raw mouse motion supported: {rawSupported}"
  let scanA ← GLFW.getKeyScancode 65
  eprintln s!"  Scancode for key 65 (A): {scanA}"

  -- Joystick
  eprintln ""
  eprintln "--- Joysticks ---"
  let mut foundJoy := false
  for jid in [:16] do
    let present ← GLFW.joystickPresent jid.toUInt32
    if present then
      let name ← GLFW.getJoystickName jid.toUInt32
      let guid ← GLFW.getJoystickGUID jid.toUInt32
      let isGP ← GLFW.joystickIsGamepad jid.toUInt32
      eprintln s!"  Joystick [{jid}]: {name} (GUID: {guid}, gamepad: {isGP})"
      foundJoy := true
  if !foundJoy then
    eprintln "  (no joysticks detected)"

  -- Cleanup
  window.setShouldClose true

  eprintln ""
  eprintln "=== GLFW Info Test Done ==="

def main : IO Unit := glfwInfo
