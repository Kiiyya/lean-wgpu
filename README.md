Trying to make wgpu bindings for Lean.

Currently, you need to [download the wgpu_native release from github releases](https://github.com/gfx-rs/wgpu-native/releases) and put it in a folder in the repo root. Might have to adjust `wgpu_native_dir` in the lakefile yourself currently.

Helpful resources for dealing with FFI (only relevant if you want to dev these bindings):
- Lake readme: https://github.com/leanprover/lean4/tree/master/src/lake
- Non-alloy FFI, and Lean ABI: https://lean-lang.org/lean4/doc/dev/ffi.html
  - Lakefile FFI example: https://github.com/leanprover/lean4/blob/master/src/lake/examples/ffi/lib/lakefile.lean
- Zulip thread about this repo, how to set up Lake with Alloy for wgpu: https://leanprover.zulipchat.com/#narrow/stream/270676-lean4/topic/Lake.2BAlloy.3A.20Using.20external.20C.20library/near/442743388
- "S" Example
  - Original: https://github.com/leanprover/lean4/tree/b278a20ac22adcbfde11db386f2dc874d4a215ad/tests/compiler/foreign
  - Alloy adaptation: https://github.com/tydeu/lean4-alloy/blob/master/examples/S/S.lean
- WebGPU Guide. For C++, but explains concepts well, and... just adapt it to C: https://eliemichel.github.io/LearnWebGPU/getting-started/opening-a-window.html
