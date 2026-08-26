//! Comptime root of the native artifact: the archive ships the whole
//! door surface and nothing else. The wasm root makes its own
//! selection for the freestanding target — the module graph, not an
//! export list, decides what each shape ships.
comptime {
    _ = @import("capi.zig");
}
