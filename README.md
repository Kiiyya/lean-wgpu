# lean-wgpu

**WebGPU bindings for [Lean 4](https://lean-lang.org/)** — write GPU-accelerated graphics and compute programs in Lean, powered by [wgpu-native](https://github.com/gfx-rs/wgpu-native) and [GLFW](https://www.glfw.org/).

> [!NOTE]
> This project is experimental and under active development.

## Overview

lean-wgpu provides Lean 4 FFI bindings to the WebGPU API via wgpu-native, along with GLFW bindings for window management and input handling. The bindings are built using [Alloy](https://github.com/tydeu/lean4-alloy), which allows writing inline C inside Lean source files.

### What's Included

| Module | Description |
|--------|-------------|
| `Wgpu` | Core WebGPU bindings — instances, adapters, devices, buffers, textures, pipelines, render/compute passes, etc. (~4900 lines) |
| `Glfw` | GLFW bindings — window creation, input callbacks (keyboard, mouse, scroll), cursor management, and window surface integration (~1500 lines) |
| `Wgpu.Async` | Async callback helpers for wgpu request patterns |

### Examples

The project ships with **27 example programs** covering a wide range of GPU programming topics:

| Example | Description |
|---------|-------------|
| `helloworld` | Basic triangle rendering (default target) |
| `coloredtriangle` | Vertex-colored triangle |
| `uniformtriangle` | Triangle with uniform buffer |
| `indexedquad` | Indexed drawing with a quad |
| `texturedquad` | Texture sampling |
| `depthcube` | 3D cube with depth testing |
| `instancing` | Instanced rendering |
| `linegrid` | Line primitive rendering |
| `wireframe` | Wireframe rendering mode |
| `msaatriangle` | Multi-sample anti-aliasing |
| `stenciloutline` | Stencil buffer outline effect |
| `shadowmap` | Shadow mapping |
| `postprocessblur` | Post-processing blur effect |
| `rendertotexture` | Off-screen render targets |
| `computedouble` | Compute shader (doubles array values) |
| `gameoflife` | Conway's Game of Life (compute) |
| `bouncingballs` | Animated bouncing balls |
| `particles` | Particle system |
| `raytracer` | Compute-based ray tracer |
| `mousepaint` | Mouse-driven painting |
| `bufferreadwrite` | GPU buffer read/write |
| `resizablewindow` | Dynamic window resizing |
| `keyboardcallback` | Keyboard input handling |
| `adapterenum` | Enumerate available GPU adapters |
| `deviceinfo` | Print GPU device information |
| `instancereport` | wgpu instance report |
| `glfwinfo` | GLFW system information |

## Requirements

- **Lean 4** (v4.28.0) — see [lean-toolchain](lean-toolchain)
- **clang** — used to compile the glfw3webgpu bridge
- **wgpu-native** — prebuilt static library (see below)
- **GLFW 3** — system-installed shared library

### Supported Platforms

| OS | Architecture | Status |
|----|-------------|--------|
| Linux | x86_64 | Supported |
| macOS | arm64 (Apple Silicon) | Supported |

## Setup

### 1. Install GLFW

**macOS:**
```sh
brew install glfw
```

**Linux (Debian/Ubuntu):**
```sh
sudo apt install libglfw3-dev
```

**Linux (Arch):**
```sh
sudo pacman -S glfw
```

### 2. Download wgpu-native

Download the appropriate **debug** build from the [wgpu-native GitHub releases](https://github.com/gfx-rs/wgpu-native/releases) and extract it into the `libs/` directory so the structure looks like:

```
libs/
  wgpu-linux-x86_64-debug/
    libwgpu_native.a
    webgpu.h
    wgpu.h
  # or for macOS:
  wgpu-macos-aarch64-debug/
    libwgpu_native.a
    webgpu.h
    wgpu.h
```

The lakefile automatically selects the right directory based on your OS and architecture.

### 3. Build

```sh
lake build
```

This builds the default target (`helloworld`— a basic triangle).

### 4. Run Examples

Run any example by name:

```sh
lake exe helloworld
lake exe coloredtriangle
lake exe computedouble
lake exe raytracer
# ...etc
```

Or using the `-R` flag for a release-profile build:
```sh
lake -R exe raytracer
```

## Project Structure

```
├── Wgpu.lean              # Core WebGPU bindings
├── Wgpu/
│   └── Async.lean         # Async callback utilities
├── Glfw.lean              # GLFW window/input bindings
├── Examples/              # 27 example programs
│   ├── Main.lean          # Default triangle example
│   ├── ColoredTriangle.lean
│   ├── RayTracer.lean
│   └── ...
├── glfw3webgpu/           # C bridge: GLFW ↔ WebGPU surface creation
├── libs/                  # wgpu-native prebuilt libraries (user-provided)
├── lakefile.lean          # Build configuration
└── lean-toolchain         # Lean version pin
```

## How It Works

The bindings use [Alloy](https://github.com/tydeu/lean4-alloy) to embed C code directly in Lean source files. Alloy's `alloy c extern` and `alloy c opaque_extern_type` declarations create Lean-accessible wrappers around the C WebGPU API. Opaque extern types are reference-counted by Lean's runtime, with custom finalizers that call the appropriate `wgpu*Release` functions.

The [glfw3webgpu](https://github.com/nicholasgasior/glfw3webgpu) bridge handles the platform-specific logic for creating a WebGPU surface from a GLFW window.

## Contributing

Contributions are welcome! If you'd like to help, some areas that could use attention:

- Expanding binding coverage (not all WebGPU functions are wrapped yet)
- Windows support
- Automatic downloading of wgpu-native in the build
- Higher-level Lean abstractions over the raw C API
- More examples and documentation

## Resources

- [WebGPU specification](https://www.w3.org/TR/webgpu/)
- [wgpu-native](https://github.com/gfx-rs/wgpu-native)
- [LearnWebGPU guide](https://eliemichel.github.io/LearnWebGPU/) — C++ focused, but explains WebGPU concepts well
- [Lean 4 FFI documentation](https://lean-lang.org/lean4/doc/dev/ffi.html)
- [Alloy (Lean 4 C FFI)](https://github.com/tydeu/lean4-alloy)
