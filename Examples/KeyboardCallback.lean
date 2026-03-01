import Wgpu
import Wgpu.Async
import Glfw

open IO
open Wgpu

set_option linter.unusedVariables false

/--
  KeyboardCallback: Tests GLFW callback bindings.
  Opens a resizable window and installs key, mouse-button, cursor-position,
  scroll, char, cursor-enter, framebuffer-size, and window-size callbacks.
  Pressing Escape or closing the window exits.
  The background color changes based on the last key pressed.
-/
def keyboardCallback : IO Unit := do
  eprintln "=== Keyboard Callback Test ==="

  setLogCallback fun lvl msg => eprintln s!"[{repr lvl}] {msg}"

  let window ← GLFWwindow.mkResizable 640 480 "Keyboard Callback Test"

  -- State tracked via IORefs
  let colorR ← IO.mkRef (0.1 : Float)
  let colorG ← IO.mkRef (0.1 : Float)
  let colorB ← IO.mkRef (0.3 : Float)
  let lastKeyRef ← IO.mkRef ("(none)" : String)

  -- Key callback: change color and log key
  window.setKeyCallback fun key _scancode action _mods => do
    if action == GLFW.press || action == GLFW.repeat then
      let keyName := match key with
        | 256 => "Escape"
        | 257 => "Enter"
        | 262 => "Right"
        | 263 => "Left"
        | 264 => "Down"
        | 265 => "Up"
        | 32  => "Space"
        | k   => s!"Key({k})"
      lastKeyRef.set keyName
      eprintln s!"Key pressed: {keyName} (action={action})"

      -- Change color based on key
      if key == GLFW.keyR then
        colorR.set 0.8; colorG.set 0.1; colorB.set 0.1
      else if key == GLFW.keyW then -- W for "White-ish"
        colorR.set 0.8; colorG.set 0.8; colorB.set 0.8
      else if key == GLFW.keyA then -- Go blue
        colorR.set 0.1; colorG.set 0.1; colorB.set 0.8
      else if key == GLFW.keyS then -- Go green
        colorR.set 0.1; colorG.set 0.8; colorB.set 0.1
      else if key == GLFW.keyD then -- Go dark
        colorR.set 0.05; colorG.set 0.05; colorB.set 0.05
      else if key == GLFW.keyEscape then
        window.setShouldClose true
      else pure ()
    else pure ()

  -- Mouse button callback
  window.setMouseButtonCallback fun button action _mods => do
    let buttonName := match button with
      | 0 => "Left"
      | 1 => "Right"
      | 2 => "Middle"
      | b => s!"Button({b})"
    let actionName := if action == GLFW.press then "Press" else "Release"
    eprintln s!"Mouse {buttonName} {actionName}"

  -- Cursor position callback (only log occasionally to avoid spam)
  let frameCount ← IO.mkRef (0 : UInt32)
  window.setCursorPosCallback fun x y => do
    let n ← frameCount.get
    if n % 30 == 0 then  -- Log every 30th call
      eprintln s!"Cursor: ({x}, {y})"
    frameCount.set (n + 1)

  -- Scroll callback
  window.setScrollCallback fun xoff yoff => do
    eprintln s!"Scroll: ({xoff}, {yoff})"

  -- Framebuffer size callback
  window.setFramebufferSizeCallback fun w h => do
    eprintln s!"Framebuffer resized: {w} x {h}"

  -- Window size callback
  window.setWindowSizeCallback fun w h => do
    eprintln s!"Window resized: {w} x {h}"

  -- Char callback
  window.setCharCallback fun codepoint => do
    let ch := Char.ofNat codepoint.toNat
    eprintln s!"Char input: '{ch}' (U+{codepoint})"

  -- Cursor enter/leave callback
  window.setCursorEnterCallback fun entered => do
    if entered then
      eprintln "Cursor entered window"
    else
      eprintln "Cursor left window"

  -- WGPU Setup
  let desc ← InstanceDescriptor.mk
  let inst ← createInstance desc
  let surface ← getSurface inst window
  let adapter ← inst.requestAdapter surface >>= await!
  let ddesc ← DeviceDescriptor.mk
  let device ← adapter.requestDevice ddesc >>= await!
  device.setUncapturedErrorCallback fun code msg => do
    eprintln s!"Error {code}: {msg}"

  let queue ← device.getQueue
  let textureFormat ← TextureFormat.get surface adapter

  -- configure initial surface
  let (initW, initH) ← window.getFramebufferSize
  let surfConfig ← SurfaceConfiguration.mk initW initH device textureFormat
  surface.configure surfConfig

  -- Track current size for reconfiguration
  let widthRef ← IO.mkRef initW
  let heightRef ← IO.mkRef initH

  -- Render loop
  while not (← window.shouldClose) do
    GLFW.pollEvents

    -- Check if framebuffer size changed
    let (fbW, fbH) ← window.getFramebufferSize
    let curW ← widthRef.get
    let curH ← heightRef.get
    if fbW != curW || fbH != curH then
      widthRef.set fbW
      heightRef.set fbH
      if fbW > 0 && fbH > 0 then
        let newConfig ← SurfaceConfiguration.mk fbW fbH device textureFormat
        surface.configure newConfig

    let texture ← surface.getCurrent
    let status ← texture.status
    if status != .success then continue
    let targetView ← TextureView.mk texture
    if !(← targetView.is_valid) then continue

    let r ← colorR.get
    let g ← colorG.get
    let b ← colorB.get
    let clearColor ← pure (Color.mk r g b 1.0)

    let encoder ← device.createCommandEncoder
    let renderPass ← RenderPassEncoder.mkWithColor encoder targetView clearColor
    renderPass.end
    let command ← encoder.finish
    queue.submit #[command]
    surface.present
    device.poll

  eprintln "=== Keyboard Callback Test Done ==="

def main : IO Unit := keyboardCallback
