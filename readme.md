# csar_abi

The stable ABI over [`csar`](https://github.com/ajfriend/csar_zig).
`csar_zig` owns the solver and its Zig API; this repo owns the one C
door surface (`capi.zig`) that every non-Zig consumer goes through,
and publishes it as:

- **two artifact shapes** — a native static archive, and a
  `wasm32-freestanding` module (built from two comptime roots, so the
  module graph, not an export list, decides what each ships), and
- **two declarations of the same contract** — `include/csar.h` for C
  callers, and `csar.js` for JavaScript ones, which additionally
  carries what a C compiler would otherwise do for you (struct byte
  offsets, code tables, instantiating the module).

Declarations live here because lockstep is only enforceable inside
one repo — CI diffs both against `capi.zig`. Idiomatic bindings
(`csar_py`, an npm package if one is ever warranted) live in their
own repos and pin this one by tag. ABI releases are deliberate
events: consumers pin a tag, and this repo pins `csar` by tag; the
ABI — doors, struct layout, code tables — drives version bumps, not
upstream releases.

This consolidates the two hand-rolled shims that preceded it (the one
vendored inside `csar_py`, and the standalone `csar_wasm`), which had
already drifted apart in error codes, naming, and surface.

Status: the native shape (archive + `csar.h`), the wasm module, and
the declaration-drift gate are live; `csar.js` and the browser
consumers land next. The plan lives in the issue tracker; releases
are tagged (dev.md "Releasing").
