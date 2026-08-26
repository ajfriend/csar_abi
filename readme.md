# csar_c

The C-ABI waist over [`csar`](https://github.com/ajfriend/csar_zig).
`csar_zig` stays pure Zig (`b.addModule` only); this repo owns the C
door surface and builds it in two artifact shapes from one `capi.zig`:

- a native static archive plus `include/csar.h` — what `csar_py` links, and
- a `wasm32-freestanding` module — what browser consumers load.

Two comptime roots, not two export lists: `src/native.zig` and
`src/wasm.zig` each pull in the doors they ship, and the module graph
does the excluding. ABI releases are deliberate pinned events —
consumers pin this repo by tag, and this repo pins `csar` by tag.

This consolidates the two hand-rolled shims that preceded it (the one
vendored inside `csar_py`, and the standalone `csar_wasm`), which had
already drifted apart in error codes, naming, and surface.

Status: planning. The plan lives in the issue tracker.
