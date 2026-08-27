//! The declaration-drift gate: include/csar.h, translated by the same
//! clang frontend that compiles C consumers (std.Build.addTranslateC),
//! compared against capi at comptime. Compiling this file IS the
//! check — drift is a compile error naming the decl.
//!
//! What each kind is compared by: constants by value; `csar_result`
//! by field names, offsets, and size, both ways; doors by ABI shape
//! (param/return kinds, widths, signedness, constness — nullability
//! and sentinels erased, since C cannot spell them and the ABI does
//! not carry them).
//!
//! Membership is an exhaustive partition, not a prefix filter: every
//! pub decl of capi must be a CSAR_* constant, a listed door, or a
//! listed internal — an unclassified decl fails the build rather than
//! silently escaping the gate.

const std = @import("std");
const capi = @import("capi");
const hdr = @import("csar_h");

const doors = [_][]const u8{ "csar_solve", "csar_abi_version", "csar_upstream_version" };
// Result is gated by the layout block below; ca is the allocator seam,
// internal to the Zig side.
const internal = [_][]const u8{ "Result", "ca" };

fn isIn(comptime list: []const []const u8, comptime name: []const u8) bool {
    for (list) |x| if (std.mem.eql(u8, x, name)) return true;
    return false;
}

/// ABI-relevant shape of a type, as a comptime string — the unit the
/// door comparison (and its error message) speaks.
fn shape(comptime T: type) []const u8 {
    comptime return switch (@typeInfo(T)) {
        .int => |i| std.fmt.comptimePrint("{s}{d}", .{ if (i.signedness == .signed) "i" else "u", i.bits }),
        .float => |f| std.fmt.comptimePrint("f{d}", .{f.bits}),
        .void => "void",
        .optional => |o| shape(o.child), // nullability erased
        .pointer => |p| std.fmt.comptimePrint("*{s}{s}", .{
            if (p.is_const) "const " else "",
            if (@typeInfo(p.child) == .@"struct")
                std.fmt.comptimePrint("struct{d}", .{@sizeOf(p.child)})
            else
                shape(p.child),
        }),
        .@"fn" => |f| blk: {
            var s: []const u8 = "fn(";
            for (f.params, 0..) |prm, i| {
                if (i != 0) s = s ++ ", ";
                s = s ++ shape(prm.type.?);
            }
            break :blk s ++ ") -> " ++ shape(f.return_type.?);
        },
        else => @compileError("shape: unhandled type " ++ @typeName(T)),
    };
}

comptime {
    for (@typeInfo(capi).@"struct".decls) |d| {
        if (std.mem.startsWith(u8, d.name, "CSAR_")) {
            if (!@hasDecl(hdr, d.name))
                @compileError("csar.h is missing " ++ d.name);
            if (@field(capi, d.name) != @field(hdr, d.name))
                @compileError("csar.h disagrees on the value of " ++ d.name);
        } else if (isIn(&doors, d.name)) {
            if (!@hasDecl(hdr, d.name))
                @compileError("csar.h is missing the door " ++ d.name);
            const zs = shape(@TypeOf(@field(capi, d.name)));
            const cs = shape(@TypeOf(@field(hdr, d.name)));
            if (!std.mem.eql(u8, zs, cs))
                @compileError("prototype drift on " ++ d.name ++ ": capi " ++ zs ++ " vs csar.h " ++ cs);
        } else if (isIn(&internal, d.name)) {
            // classified: not part of the C declaration surface
        } else {
            @compileError("pub decl not classified by the drift gate: " ++ d.name);
        }
    }

    // csar_result: same fields at the same offsets, same size, both ways.
    const zf = @typeInfo(capi.Result).@"struct".fields;
    const cf = @typeInfo(hdr.csar_result).@"struct".fields;
    if (zf.len != cf.len)
        @compileError("csar_result field-count drift between capi.Result and csar.h");
    for (zf) |f| {
        if (!@hasField(hdr.csar_result, f.name))
            @compileError("csar.h csar_result is missing ." ++ f.name);
        if (@offsetOf(capi.Result, f.name) != @offsetOf(hdr.csar_result, f.name))
            @compileError("csar_result offset drift on ." ++ f.name);
    }
    if (@sizeOf(capi.Result) != @sizeOf(hdr.csar_result))
        @compileError("csar_result size drift between capi.Result and csar.h");
}

test "the declarations match capi" {
    // Empty on purpose: the comptime block above is the gate, and
    // running this test forces it through compilation.
}
