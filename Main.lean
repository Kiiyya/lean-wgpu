import Wgpu
import Wgpu.Async
import Glfw

open IO
open Wgpu

set_option linter.unusedVariables false

def triangle : IO Unit := do
  let window ← GLFWwindow.mk 1366 768

  let desc <- InstanceDescriptor.mk
  let inst <- createInstance desc

  let surface <- getSurface inst window

  let adapter <- inst.requestAdapter surface >>= await!

  let ddesc <- DeviceDescriptor.mk "default device" fun msg => do
    eprintln s!"device was lost: {msg}"
    return pure ()
  let device : Device <- adapter.requestDevice ddesc >>= await!
  device.setUncapturedErrorCallback fun code msg => do
    eprintln s!"uncaptured error, code{code}, message is \"{msg}\""
  let queue : Queue <- device.getQueue
  queue.onSubmittedWorkDone fun status => do
    eprintln s!"queue work done! status {status}"
  let encoder ← device.createCommandEncoder
  encoder.insertDebugMarker "rawr"

  let texture_format := TextureFormat.get surface adapter

  let surface_config := SurfaceConfiguration.mk 1366 768 device texture_format
  surface.configure surface_config

  let shaderModuleDescriptor := ShaderModuleDescriptor.mk <| ShaderModuleWGSLDescriptor.mk ()
  let shaderModule := ShaderModule.mk device shaderModuleDescriptor

  let blendState := BlendState.mk shaderModule
  let colorTargetState := ColorTargetState.mk texture_format blendState
  let fragmentState := FragmentState.mk shaderModule colorTargetState
  let renderPipelineDescriptor := RenderPipelineDescriptor.mk shaderModule fragmentState

  let pipeline ← RenderPipeline.mk device renderPipelineDescriptor

  while not (← window.shouldClose) do

    GLFW.pollEvents
    let texture ← surface.getCurrent
    let status ← texture.status
    if (status != .success) then continue
    let targetView ← TextureView.mk texture
    if !(←  targetView.is_valid) then
      continue
    let encoder ← device.createCommandEncoder
    let renderPass ← RenderPassEncoder.mk encoder targetView
    renderPass.setPipeline pipeline
    renderPass.draw 3 1 0 0
    let command <- encoder.finish
    queue.submit #[command]
    surface.present
    -- renderPass.release
    device.poll




    -- pure ()
    -- println! "polling !"
    -- println! (repr <| texture.status)
    -- surface.present
    -- device.poll
    -- GLFW.pollEvents


def main : IO Unit := do
  triangle
  eprintln s!"done"
