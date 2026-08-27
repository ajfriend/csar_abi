//! Comptime root of the wasm32-freestanding module: the whole door
//! surface (capi.zig, forced below) plus the browser-only
//! static-buffer doors — JS never allocates on our behalf.
//!
//! The calling sequence csar.js wraps:
//!
//!   1. reject n > CSAR_WASM_MAX_PTS — BEFORE constructing a view:
//!      an oversized Float64Array writes past the buffer, and
//!      solve()'s CSAR_TOO_MANY_POINTS is the backstop, not the
//!      guard (this layer cannot intercept JS memory writes);
//!   2. write 3·n f64 unit vectors [x0, y0, z0, …] at ptsPtr();
//!   3. rc = solve(n) — a CSAR_* call code;
//!   4. read the csar_result at resultPtr(), and one lambda per
//!      input point at lambdasPtr().
//!
//! Field offsets are capi.Result's. The byte numbers live in its
//! comptime assert block and in csar.js, which the drift gate
//! checks; this comment deliberately does not repeat them.
//!
//! Solve options stay pinned at upstream's defaults (CSAR_DEFAULT_*)
//! under the .auto method — the browser consumer is a demo; an
//! options door gets added when a consumer needs one, not before.

const capi = @import("capi.zig");

comptime {
    // Force analysis: capi's export fns are this module's ABI.
    _ = capi;
}

var pts_buf: [capi.CSAR_WASM_MAX_PTS][3]f64 = undefined;
var result: capi.Result = undefined;
var lam_buf: [capi.CSAR_WASM_MAX_PTS]f64 = undefined;

export fn ptsPtr() [*]f64 {
    return @ptrCast(&pts_buf);
}

export fn resultPtr() *capi.Result {
    return &result;
}

/// csar_solve's out_lambdas contract; length CSAR_WASM_MAX_PTS.
export fn lambdasPtr() [*]f64 {
    return &lam_buf;
}

/// One thin door over csar_solve against the static buffers — the
/// same ABI as native, no wasm-only conventions beyond the buffers
/// themselves.
export fn solve(n: u32) i32 {
    if (n > capi.CSAR_WASM_MAX_PTS) return capi.CSAR_TOO_MANY_POINTS;
    return capi.csar_solve(
        @ptrCast(&pts_buf),
        n,
        capi.CSAR_DEFAULT_GAP_TOL,
        capi.CSAR_DEFAULT_N_HULL,
        capi.CSAR_DEFAULT_COPLANARITY_TOL,
        capi.CSAR_DEFAULT_MAX_OUTER,
        capi.CSAR_METHOD_AUTO,
        &result,
        &lam_buf,
    );
}
