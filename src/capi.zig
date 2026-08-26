//! The one C door surface over `csar.solve`. Every non-Zig consumer —
//! the native archive and the wasm module alike — goes through the
//! doors in this file. The comptime roots (`native.zig`, and the wasm
//! root once it lands) select what ships per target, and the
//! declarations (`include/csar.h`, `csar.js`) restate this file for
//! hosts that cannot read it; this file is the source of truth.
//!
//! Door discipline: `csar_` prefix on every symbol; fixed-width
//! scalars only (no `size_t` — wasm32's usize is 32 bits); the call
//! returns a code from the `CSAR_*` table with results in
//! caller-allocated out-params; no cross-call state.

const std = @import("std");
const builtin = @import("builtin");
const csar = @import("csar");

/// Version of this ABI (the doors, `csar_result`, the code tables) and
/// of the `csar` solver it is built over. The ABI version tracks ABI
/// change, not upstream releases — a solver re-pin with no ABI change
/// is a patch bump. Kept in lockstep with build.zig.zon by hand until
/// the drift gate covers them.
const abi_version = "0.1.0";
const upstream_version = "0.5.0";

pub export fn csar_abi_version() [*:0]const u8 {
    return abi_version;
}

pub export fn csar_upstream_version() [*:0]const u8 {
    return upstream_version;
}

/// A COMPTIME per-target seam, never a runtime set-allocator door —
/// that would be this surface's first global mutable state.
pub const ca: std.mem.Allocator = if (builtin.target.os.tag == .freestanding)
    std.heap.wasm_allocator
else
    std.heap.c_allocator;

// Return codes for the `csar_solve` call itself: 0 = "ran, the
// outcome is in `csar_result.status`"; nonzero = "could not run".
// Mirrors the upstream errors-vs-outcome split (src/api.zig in
// csar_zig).
pub const CSAR_OK: i32 = 0;
pub const CSAR_INSUFFICIENT_POINTS: i32 = 1;
pub const CSAR_INVALID_TOLERANCE: i32 = 2;
pub const CSAR_COPLANAR_INPUT: i32 = 3;
pub const CSAR_OUT_OF_MEMORY: i32 = 4;
pub const CSAR_INTERNAL: i32 = 5;
pub const CSAR_INVALID_METHOD: i32 = 6;

// `csar_result.status` values on CSAR_OK — which Outcome variant the
// solver produced.
pub const CSAR_STATUS_CONVERGED: i32 = 0;
pub const CSAR_STATUS_INFEASIBLE: i32 = 1;
pub const CSAR_STATUS_DID_NOT_CONVERGE: i32 = 2;
pub const CSAR_STATUS_PRECISION_FLOOR: i32 = 3;

// `method` in-param values, mapping onto `csar.Method`.
// CSAR_METHOD_AUTO is upstream's alias for its recommended path;
// `csar_result.method` reports the concrete path that produced the
// outcome (-1 when the outcome carries no path tag, i.e. infeasible).
pub const CSAR_METHOD_TRUST: i32 = 0;
pub const CSAR_METHOD_AUTO: i32 = 1;

/// The one declared result layout, shared by every target: the native
/// header declares it as `csar_result`, and `csar.js` reads it from
/// wasm memory at these offsets. All-f64 payload first (one
/// Float64Array view on the JS side), fixed-width ints last.
///
/// `status` selects which fields are meaningful:
///   converged:        q, sigma, gap, method, n_iters
///   did_not_converge,
///   precision_floor:  q, sigma, gap, gap_floor, method, n_iters
///                     (last certified iterate; not a certified cone)
///   infeasible:       residual
/// Fields the variant doesn't define hold NaN (f64) / -1 / 0.
pub const Result = extern struct {
    /// Eigenbasis of A, row-major: q[r*3 + c] = Q(r, c). Column i is
    /// the unit eigenvector paired with sigma[i]; column 0 is the
    /// cone axis. (Row-major is the declared order — the retired
    /// prototype wasm shim wrote column-major; that fork ends here.)
    q: [9]f64,
    /// Eigenvalues pairing with q's columns. sigma[0] is the
    /// structural axial eigenvalue (1/√3); the cone's aspect ratio is
    /// sigma[2]/sigma[1].
    sigma: [3]f64,
    /// Duality gap. Certified ≤ gap_tol only when status is
    /// CSAR_STATUS_CONVERGED; on uncertified outcomes it is the gap
    /// at the last certified iterate.
    gap: f64,
    /// The smallest gap certifiable at f64 for this input's geometry
    /// (uncertified outcomes only; `Uncertified.gap_floor` upstream).
    gap_floor: f64,
    /// Farkas witness magnitude (infeasible only).
    residual: f64,
    /// CSAR_STATUS_* on CSAR_OK; -1 otherwise.
    status: i32,
    /// CSAR_METHOD_* concrete path tag; -1 when the outcome has none.
    method: i32,
    /// Total solver iterations (`Diagnostics.totalIters()` upstream).
    n_iters: u32,
};

/// The `csar_result.method` value for a diagnostics union: which
/// solver path produced the outcome (the union tag).
fn pathTag(diag: csar.Diagnostics) i32 {
    return switch (diag) {
        .trust => CSAR_METHOD_TRUST,
    };
}

fn writeUncertified(out: *Result, status: i32, u: csar.Uncertified) void {
    out.status = status;
    out.q = u.Q.m;
    out.sigma = u.sigma;
    out.gap = u.gap;
    out.gap_floor = u.gap_floor;
    out.method = pathTag(u.diag);
    out.n_iters = u.diag.totalIters();
}

/// Solve the spherical aspect-ratio problem for a point set.
///
/// `pts` is an interleaved `(n, 3)` row-major buffer `[x0, y0, z0, …]`
/// — what numpy hands us for an `(n, 3)` float64 array, and what the
/// wasm input buffer holds. `[3]f64` is exactly that layout, so the
/// pointer is reinterpreted with no copy. `gap_tol`, `n_hull`,
/// `coplanarity_tol`, and `max_outer` map straight onto
/// `csar.SolveOptions`; pass CSAR_METHOD_AUTO to take upstream's
/// recommended solver path.
///
/// `out` is fully written on every return (NaN/-1/0 for fields the
/// outcome doesn't define). `out_lambdas`, if non-NULL, must have
/// length `n`: it is zeroed, and on a converged outcome the dual
/// multipliers are scattered into it at the caller's own point order —
/// nonzero exactly on the support set, zeroed on every non-converged
/// outcome. NULL skips certificate marshaling entirely. (The
/// infeasible and uncertified outcomes also carry certificates
/// upstream; marshaling those is deferred until a consumer needs
/// them.)
pub export fn csar_solve(
    pts: [*]const f64,
    n: u32,
    gap_tol: f64,
    n_hull: i32,
    coplanarity_tol: f64,
    max_outer: u32,
    method: i32,
    out: *Result,
    out_lambdas: ?[*]f64,
) i32 {
    const nan = std.math.nan(f64);
    out.* = .{
        .q = @splat(nan),
        .sigma = @splat(nan),
        .gap = nan,
        .gap_floor = nan,
        .residual = nan,
        .status = -1,
        .method = -1,
        .n_iters = 0,
    };
    if (out_lambdas) |l| @memset(l[0..n], 0);

    const X: []const [3]f64 = @as([*]const [3]f64, @ptrCast(pts))[0..n];
    const opts: csar.SolveOptions = .{
        .gap_tol = gap_tol,
        .n_hull = n_hull,
        .coplanarity_tol = coplanarity_tol,
        .max_outer = max_outer,
        .method = switch (method) {
            CSAR_METHOD_TRUST => .trust,
            CSAR_METHOD_AUTO => .auto,
            else => return CSAR_INVALID_METHOD,
        },
    };

    var outcome = csar.solve(ca, X, opts) catch |err| return switch (err) {
        error.InsufficientPoints => CSAR_INSUFFICIENT_POINTS,
        error.InvalidTolerance => CSAR_INVALID_TOLERANCE,
        error.CoplanarInput => CSAR_COPLANAR_INPUT,
        error.OutOfMemory => CSAR_OUT_OF_MEMORY,
        // SolveError variants (NegativeEigenvalue / SingularMoment):
        // internal-correctness bugs in the library, not the caller's
        // input.
        else => CSAR_INTERNAL,
    };
    defer outcome.deinit();

    switch (outcome) {
        .converged => |c| {
            out.status = CSAR_STATUS_CONVERGED;
            out.q = c.Q.m;
            out.sigma = c.sigma;
            out.gap = c.gap;
            out.method = pathTag(c.diag);
            out.n_iters = c.diag.totalIters();
            if (out_lambdas) |l| {
                // Cert indices are already in the caller's point order.
                for (c.cert.indices, c.cert.lambdas) |idx, lam| {
                    if (idx < n) l[idx] = lam;
                }
            }
        },
        .infeasible => |inf| {
            out.status = CSAR_STATUS_INFEASIBLE;
            out.residual = inf.residual;
        },
        .did_not_converge => |u| writeUncertified(out, CSAR_STATUS_DID_NOT_CONVERGE, u),
        .precision_floor => |u| writeUncertified(out, CSAR_STATUS_PRECISION_FLOOR, u),
    }
    return CSAR_OK;
}
