//! One half of the declaration-drift gate (`zig build gate`): prints
//! the ABI reference by comptime reflection over capi — every pub
//! `CSAR_*` constant and csar_result's layout — in the exact format
//! gate/emit_ref.c prints from include/csar.h. The build step diffs
//! the two.
//!
//! Reflection, not a hand list, on this side: a new CSAR_* decl in
//! capi.zig shows up here automatically and diffs red until the
//! header (and emit_ref.c's list) carry it too.
//!
//! f64 values print as their bit pattern — exact, and immune to
//! printf-vs-Zig float formatting differences.

const std = @import("std");
const capi = @import("capi");

pub fn main(init: std.process.Init) !void {
    var buf: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buf);
    const w = &file_writer.interface;

    inline for (@typeInfo(capi).@"struct".decls) |d| {
        if (comptime std.mem.startsWith(u8, d.name, "CSAR_")) {
            const v = @field(capi, d.name);
            switch (@TypeOf(v)) {
                i32, u32 => try w.print("{s} {d}\n", .{ d.name, v }),
                f64 => try w.print("{s} bits:{x}\n", .{ d.name, @as(u64, @bitCast(v)) }),
                else => @compileError("unhandled CSAR_ decl type: " ++ d.name),
            }
        }
    }
    inline for (@typeInfo(capi.Result).@"struct".fields) |f| {
        try w.print("offsetof {s} {d}\n", .{ f.name, @offsetOf(capi.Result, f.name) });
    }
    try w.print("sizeof csar_result {d}\n", .{@sizeOf(capi.Result)});
    try w.flush();
}
