import Wgpu
import Wgpu.Async
import Glfw
import Wgsl.Syntax

open IO
open Wgpu

set_option linter.unusedVariables false

/--
  GameOfLife: Conway's Game of Life implemented as a GPU compute shader.
  Each frame, a compute shader reads the current grid and writes the next generation.
  A render pass displays the grid as colored pixels using a fullscreen quad.
  Tests: compute pipeline, double-buffered storage textures, bind group swapping,
  compute→render pipeline interop.
-/

def golComputeSource : String := !WGSL{
@group(0) @binding(0) var<storage, read> cellsIn: array<u32>;
@group(0) @binding(1) var<storage, read_write> cellsOut: array<u32>;

const GRID_W: u32 = 128u;
const GRID_H: u32 = 128u;

fn getCell(x: i32, y: i32) -> u32 {
    let wx = ((x % i32(GRID_W)) + i32(GRID_W)) % i32(GRID_W);
    let wy = ((y % i32(GRID_H)) + i32(GRID_H)) % i32(GRID_H);
    return cellsIn[u32(wy) * GRID_W + u32(wx)];
}

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    if (id.x >= GRID_W || id.y >= GRID_H) { return; }
    let x = i32(id.x);
    let y = i32(id.y);
    let neighbors = getCell(x-1,y-1) + getCell(x,y-1) + getCell(x+1,y-1)
                  + getCell(x-1,y)                     + getCell(x+1,y)
                  + getCell(x-1,y+1) + getCell(x,y+1) + getCell(x+1,y+1);
    let alive = cellsIn[id.y * GRID_W + id.x];
    var next: u32 = 0u;
    if (alive == 1u && (neighbors == 2u || neighbors == 3u)) { next = 1u; }
    if (alive == 0u && neighbors == 3u) { next = 1u; }
    cellsOut[id.y * GRID_W + id.x] = next;
}
}

def golRenderSource : String := !WGSL{
@group(0) @binding(0) var<storage, read> cells: array<u32>;

const GRID_W: u32 = 128u;
const GRID_H: u32 = 128u;

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) uv: vec2f,
};

@vertex
fn vs_main(@builtin(vertex_index) idx: u32) -> VertexOutput {
    var pos = array<vec2f, 6>(
        vec2f(-1.0, -1.0), vec2f(1.0, -1.0), vec2f(1.0, 1.0),
        vec2f(-1.0, -1.0), vec2f(1.0, 1.0), vec2f(-1.0, 1.0) 
    );
    var uv = array<vec2f, 6>(
        vec2f(0.0, 1.0), vec2f(1.0, 1.0), vec2f(1.0, 0.0),
        vec2f(0.0, 1.0), vec2f(1.0, 0.0), vec2f(0.0, 0.0) 
    );
    var out: VertexOutput;
    out.position = vec4f(pos[idx], 0.0, 1.0);
    out.uv = uv[idx];
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4f {
    let x = u32(in.uv.x * f32(GRID_W));
    let y = u32(in.uv.y * f32(GRID_H));
    let alive = cells[y * GRID_W + x];
    if (alive == 1u) {
        let r = f32(x) / f32(GRID_W);
        let g = f32(y) / f32(GRID_H);
        return vec4f(r * 0.3 + 0.2, g * 0.5 + 0.3, 0.8, 1.0);
    }
    return vec4f(0.05, 0.05, 0.08, 1.0);
}
}

def gridW : Nat := 128
def gridH : Nat := 128

-- Initialize with a mix of patterns: glider, r-pentomino, and random-ish fill
def mkInitialCells : Array UInt32 := Id.run do
  let mut cells : Array UInt32 := Array.replicate (gridW * gridH) 0
  let set (c : Array UInt32) (x y : Nat) : Array UInt32 :=
    if y * gridW + x < c.size then c.set! (y * gridW + x) 1 else c
  -- Glider at (2, 2)
  cells := set cells 3 2
  cells := set cells 4 3
  cells := set cells 2 4; cells := set cells 3 4; cells := set cells 4 4
  -- R-pentomino at (60, 60)
  cells := set cells 61 60; cells := set cells 62 60
  cells := set cells 60 61; cells := set cells 61 61
  cells := set cells 61 62
  -- Lightweight spaceship at (20, 20)
  cells := set cells 21 20; cells := set cells 24 20
  cells := set cells 20 21
  cells := set cells 20 22; cells := set cells 24 22
  cells := set cells 20 23; cells := set cells 21 23; cells := set cells 22 23; cells := set cells 23 23
  -- Pulsar seed at (80, 80) - a few cells to spark interesting patterns
  for i in [:6] do
    cells := set cells (80 + i) 80
  for i in [:6] do
    cells := set cells 80 (82 + i)
  -- Diagonal line
  for i in [:20] do
    cells := set cells (40 + i) (40 + i)
  -- Random-ish pattern using a simple hash
  for y in [:gridH] do
    for x in [:gridW] do
      let hash := (x * 374761393 + y * 668265263) % 1000
      if hash < 200 then  -- ~20% fill
        cells := set cells x y
  return cells

def gameOfLife : IO Unit := do
  eprintln "=== Game of Life (GPU Compute + Render) ==="

  setLogCallback fun lvl msg => eprintln s!"[{repr lvl}] {msg}"
  let window ← GLFWwindow.mk 640 480 "Game of Life"

  let desc ← InstanceDescriptor.mk
  let inst ← createInstance desc
  let surface ← getSurface inst window

  let adapter ← inst.requestAdapter surface >>= await!
  let ddesc ← DeviceDescriptor.mk "gol device"
  let device ← adapter.requestDevice ddesc >>= await!
  device.setUncapturedErrorCallback fun code msg => do
    eprintln s!"uncaptured error, code {code}: \"{msg}\""

  let queue ← device.getQueue
  let texture_format ← TextureFormat.get surface adapter
  let surface_config ← SurfaceConfiguration.mk 640 480 device texture_format
  surface.configure surface_config

  let numCells := gridW * gridH
  let bufferSize : UInt32 := (numCells * 4).toUInt32  -- u32 per cell

  -- Two cell buffers for ping-pong (double buffering)
  let cellBufA_Desc := BufferDescriptor.mk "cells A"
    (BufferUsage.storage.lor BufferUsage.copyDst) bufferSize false
  let cellBufA ← Buffer.mk device cellBufA_Desc

  let cellBufB_Desc := BufferDescriptor.mk "cells B"
    (BufferUsage.storage.lor BufferUsage.copyDst) bufferSize false
  let cellBufB ← Buffer.mk device cellBufB_Desc

  -- Initialize cells A
  let initialCells := mkInitialCells
  let initialBytes := uint32sToByteArray initialCells
  queue.writeBuffer cellBufA initialBytes
  eprintln s!"Grid: {gridW}×{gridH} = {numCells} cells, {initialBytes.size} bytes"

  -- Compute pipeline: reads from A, writes to B (then swap)
  let computeWGSL ← ShaderModuleWGSLDescriptor.mk golComputeSource
  let computeShaderDesc ← ShaderModuleDescriptor.mk computeWGSL
  let computeShader ← ShaderModule.mk device computeShaderDesc

  let computeBGL ← BindGroupLayout.mk2Storage device
    0 ShaderStageFlags.compute true   -- cells read
    1 ShaderStageFlags.compute false  -- cells write
  let computePL ← PipelineLayout.mk device #[computeBGL]
  let computePipeline ← device.createComputePipeline computeShader computePL "main"

  -- Two bind groups for ping-pong
  let computeBG_AB ← BindGroup.mk2Buffers device computeBGL 0 cellBufA 1 cellBufB  -- read A → write B
  let computeBG_BA ← BindGroup.mk2Buffers device computeBGL 0 cellBufB 1 cellBufA  -- read B → write A

  -- Render pipeline: fullscreen quad that reads cell data
  let renderWGSL ← ShaderModuleWGSLDescriptor.mk golRenderSource
  let renderShaderDesc ← ShaderModuleDescriptor.mk renderWGSL
  let renderShader ← ShaderModule.mk device renderShaderDesc

  -- Render bind group layout: one read-only storage buffer at binding 0
  let renderBGL ← BindGroupLayout.mkStorage device 0 ShaderStageFlags.fragment true
  let renderPL ← PipelineLayout.mk device #[renderBGL]

  let blendState ← BlendState.mk renderShader
  let cts ← ColorTargetState.mk texture_format blendState
  let fragState ← FragmentState.mk renderShader cts
  let pipeDesc ← RenderPipelineDescriptor.mk renderShader fragState
  let renderPipeline ← RenderPipeline.mkWithLayout device pipeDesc renderPL

  -- Render bind groups: read from the output buffer
  let renderBG_B ← BindGroup.mk device renderBGL 0 cellBufB  -- after A→B compute, render B
  let renderBG_A ← BindGroup.mk device renderBGL 0 cellBufA  -- after B→A compute, render A

  let clearColor := Color.mk 0.05 0.05 0.08 1.0

  eprintln "Entering render loop (press Q or Escape to quit)..."

  let mut frameCount : UInt32 := 0
  let mut pingPong : Bool := true  -- true = read A write B, false = read B write A

  while not (← window.shouldClose) do
    GLFW.pollEvents

    let esc ← window.getKey GLFW.keyEscape
    let q ← window.getKey GLFW.keyQ
    if esc == GLFW.press || q == GLFW.press then
      window.setShouldClose true
      continue

    let texture ← surface.getCurrent
    let status ← texture.status
    if (status != .success) then continue
    let targetView ← TextureView.mk texture
    if !(← targetView.is_valid) then continue

    let encoder ← device.createCommandEncoder

    -- Compute pass: advance one generation
    let computePass ← encoder.beginComputePass
    computePass.setPipeline computePipeline
    if pingPong then
      computePass.setBindGroup 0 computeBG_AB  -- read A → write B
    else
      computePass.setBindGroup 0 computeBG_BA  -- read B → write A
    let wgX := ((gridW + 7) / 8).toUInt32
    let wgY := ((gridH + 7) / 8).toUInt32
    computePass.dispatchWorkgroups wgX wgY 1
    computePass.end_

    -- Render pass: display the newly computed buffer
    let renderPass ← RenderPassEncoder.mkWithColor encoder targetView clearColor
    renderPass.setPipeline renderPipeline
    if pingPong then
      renderPass.setBindGroup 0 renderBG_B  -- display B (just written)
    else
      renderPass.setBindGroup 0 renderBG_A  -- display A (just written)
    renderPass.draw 6 1 0 0
    renderPass.end

    let command ← encoder.finish
    queue.submit #[command]
    surface.present
    device.poll

    pingPong := !pingPong
    frameCount := frameCount + 1
    if frameCount % 300 == 0 then
      let t ← GLFW.getTime
      window.setTitle s!"Game of Life - Gen {frameCount} ({t.toString}s)"

  eprintln s!"Simulated {frameCount} generations"
  cellBufA.destroy
  cellBufB.destroy
  eprintln "=== Done ==="

def main : IO Unit := gameOfLife
