//! Comptime root of the wasm32-freestanding module: the whole door
//! surface (capi.zig, forced below) plus the browser-only
//! static-buffer doors — JS never allocates on our behalf.
//!
//! The calling sequence csar.js wraps (offsets are capi.Result's,
//! asserted at comptime there):
//!
//!   const pts = new Float64Array(memory.buffer, ptsPtr(), 3 * n);
//!   // write unit vectors [x0, y0, z0, …]
//!   const rc = solve(n);                        // CSAR_* call code
//!   const f = new Float64Array(memory.buffer, resultPtr(), 15);
//!   //   f[0..9] q row-major, f[9..12] sigma, f[12] gap,
//!   //   f[13] gap_floor, f[14] residual
//!   const i = new Int32Array(memory.buffer, resultPtr() + 120, 2);
//!   //   i[0] status, i[1] method; u32 n_iters at +128
//!   const lam = new Float64Array(memory.buffer, lambdasPtr(), n);
//!
//! Solve options stay pinned at upstream's defaults (CSAR_DEFAULT_*)
//! under the .auto method — the browser consumer is a demo; an
//! options door gets added when a consumer needs one, not before.

const capi = @import("capi.zig");

comptime {
    // Force analysis: capi's export fns are this module's ABI.
    _ = capi;
}

/// Input cap for the static buffer. csar.js guards it; solve()
/// returns CSAR_TOO_MANY_POINTS past it.
pub const MAX_PTS = 4096;

var pts_buf: [MAX_PTS][3]f64 = undefined;
var result: capi.Result = undefined;
var lam_buf: [MAX_PTS]f64 = undefined;

export fn ptsPtr() [*]f64 {
    return @ptrCast(&pts_buf);
}

export fn resultPtr() *capi.Result {
    return &result;
}

/// One dual multiplier per input point, in the caller's own order:
/// nonzero exactly on the support set, zeroed on every non-converged
/// outcome (csar_solve's out_lambdas contract).
export fn lambdasPtr() [*]f64 {
    return &lam_buf;
}

/// One thin door over csar_solve against the static buffers — the
/// same ABI as native, no wasm-only conventions beyond the buffers
/// themselves.
export fn solve(n: u32) i32 {
    if (n > MAX_PTS) return capi.CSAR_TOO_MANY_POINTS;
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
