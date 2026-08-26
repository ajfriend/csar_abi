//! Native smoke over the door surface: every `csar_result.status`
//! variant, every input-error code, the nullable-lambdas contract,
//! and the version doors. The per-outcome inputs are the canonical
//! set from csar_zig's examples/status.zig.

const std = @import("std");
const capi = @import("capi");

// One octant: converges to a circular cone.
const octant = [_]f64{ 1, 0, 0, 0, 1, 0, 0, 0, 1 };
// Two antipodal points plus one more: no hemisphere holds them all.
const antipodal = [_]f64{ 1, 0, 0, -1, 0, 0, 0, 1, 0 };
// Irregular triple; with a budget of one and a tolerance below the
// f64 floor, the budget runs out first.
const irregular = [_]f64{ 1, 0, 0, 0.1, 0.97, 0.2, -0.2, 0.3, 0.93 };
// A hexagon ~4e-10 rad across: its certificate's f64 floor is above
// the default tolerance, so the cone is found but cannot be certified.
const tiny_hex = [_]f64{
    0.6746833027403286,  0.7369617968776201, -0.04110658032859652,
    0.674683302801862,   0.7369617968319514, -0.04110658013740184,
    0.6746833029130066,  0.736961796730196,  -0.04110658013746045,
    0.674683302962618,   0.7369617966741094, -0.04110658032871372,
    0.6746833029010845,  0.7369617967197781, -0.041106580519908585,
    0.6746833027899399,  0.7369617968215336, -0.04110658051984987,
};
// Four points on the equator great circle (within one hemisphere):
// rank-deficient tangent scatter.
const equator = [_]f64{ 1, 0, 0, 0.9238795325112867, 0.3826834323650898, 0, 0.7071067811865476, 0.7071067811865476, 0, 0.3826834323650898, 0.9238795325112867, 0 };

fn solve(pts: []const f64, gap_tol: f64, max_outer: u32, out: *capi.Result, lambdas: ?[*]f64) i32 {
    return capi.csar_solve(pts.ptr, @intCast(pts.len / 3), gap_tol, 10, 1e-12, max_outer, capi.CSAR_METHOD_AUTO, out, lambdas);
}

test "converged: cone, certified gap, scattered lambdas" {
    var r: capi.Result = undefined;
    var lam = [_]f64{ -1, -1, -1 };
    try std.testing.expectEqual(capi.CSAR_OK, solve(&octant, 1e-6, 100, &r, &lam));
    try std.testing.expectEqual(capi.CSAR_STATUS_CONVERGED, r.status);
    try std.testing.expectEqual(capi.CSAR_METHOD_TRUST, r.method);
    try std.testing.expect(r.gap <= 1e-6);
    try std.testing.expectApproxEqAbs(1.0 / @sqrt(3.0), r.sigma[0], 1e-12);
    try std.testing.expect(r.sigma[2] / r.sigma[1] >= 1.0);
    // The cone axis (column 0 of row-major q) is a unit vector.
    const ax = .{ r.q[0], r.q[3], r.q[6] };
    try std.testing.expectApproxEqAbs(1.0, @sqrt(ax[0] * ax[0] + ax[1] * ax[1] + ax[2] * ax[2]), 1e-12);
    // Dual multipliers: nonzero exactly on the support set — for the
    // symmetric octant, all three points are active. (Scaling is
    // upstream's convention, not the ABI's; don't pin it here.)
    for (lam) |l| try std.testing.expect(l > 0);
    // Fields the variant doesn't define are NaN.
    try std.testing.expect(std.math.isNan(r.gap_floor));
    try std.testing.expect(std.math.isNan(r.residual));
}

test "converged: NULL lambdas skips certificate marshaling" {
    var r: capi.Result = undefined;
    try std.testing.expectEqual(capi.CSAR_OK, solve(&octant, 1e-6, 100, &r, null));
    try std.testing.expectEqual(capi.CSAR_STATUS_CONVERGED, r.status);
}

test "infeasible: residual reported, lambdas zeroed, q is NaN" {
    var r: capi.Result = undefined;
    var lam = [_]f64{ -1, -1, -1 };
    try std.testing.expectEqual(capi.CSAR_OK, solve(&antipodal, 1e-6, 100, &r, &lam));
    try std.testing.expectEqual(capi.CSAR_STATUS_INFEASIBLE, r.status);
    try std.testing.expectEqual(@as(i32, -1), r.method);
    try std.testing.expect(r.residual >= 0);
    try std.testing.expect(std.math.isNan(r.q[0]));
    // Zeroed on every non-converged outcome.
    for (lam) |l| try std.testing.expectEqual(@as(f64, 0), l);
}

test "did_not_converge: budget of one, tolerance below the floor" {
    var r: capi.Result = undefined;
    try std.testing.expectEqual(capi.CSAR_OK, solve(&irregular, 1e-20, 1, &r, null));
    try std.testing.expectEqual(capi.CSAR_STATUS_DID_NOT_CONVERGE, r.status);
    try std.testing.expectEqual(capi.CSAR_METHOD_TRUST, r.method);
    try std.testing.expect(!std.math.isNan(r.gap));
    try std.testing.expect(!std.math.isNan(r.gap_floor));
}

test "precision_floor: tiny hexagon at the default tolerance" {
    var r: capi.Result = undefined;
    try std.testing.expectEqual(capi.CSAR_OK, solve(&tiny_hex, 1e-6, 100, &r, null));
    try std.testing.expectEqual(capi.CSAR_STATUS_PRECISION_FLOOR, r.status);
    try std.testing.expect(r.gap_floor > 1e-6);
    // Uncertified, but the iterate still carries a cone estimate.
    try std.testing.expect(r.sigma[2] / r.sigma[1] >= 1.0);
}

test "input errors: each code" {
    var r: capi.Result = undefined;
    const two = [_]f64{ 1, 0, 0, 0, 1, 0 };
    try std.testing.expectEqual(capi.CSAR_INSUFFICIENT_POINTS, solve(&two, 1e-6, 100, &r, null));
    try std.testing.expectEqual(capi.CSAR_INVALID_TOLERANCE, solve(&octant, -1.0, 100, &r, null));
    try std.testing.expectEqual(capi.CSAR_COPLANAR_INPUT, solve(&equator, 1e-6, 100, &r, null));
    try std.testing.expectEqual(capi.CSAR_INVALID_METHOD, capi.csar_solve(&octant, 3, 1e-6, 10, 1e-12, 100, 99, &r, null));
    // A failed call leaves status at -1: the outcome fields are not
    // meaningful unless the call returned CSAR_OK.
    try std.testing.expectEqual(@as(i32, -1), r.status);
}

test "version doors" {
    try std.testing.expectEqualStrings("0.1.0", std.mem.span(capi.csar_abi_version()));
    try std.testing.expectEqualStrings("0.5.0", std.mem.span(capi.csar_upstream_version()));
}
