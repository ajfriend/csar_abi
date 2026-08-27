//! Emits the ABI reference as JSON, by comptime reflection over capi:
//! every pub CSAR_* constant plus csar_result's offsets and size.
//!
//! The C declaration needs no such thing — `zig build gate` hands
//! csar.h to the same clang frontend a C consumer uses and compares
//! types directly. Nothing can do that for JavaScript, so the JS gate
//! (gate/gate_js.mjs) reads the values from here instead; reflection
//! keeps this from being one more hand-maintained list.

const std = @import("std");
const capi = @import("capi");

pub fn main(init: std.process.Init) !void {
    var buf: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buf);
    const w = &file_writer.interface;

    try w.print("{{\n  \"constants\": {{", .{});
    var first = true;
    inline for (@typeInfo(capi).@"struct".decls) |d| {
        if (comptime std.mem.startsWith(u8, d.name, "CSAR_")) {
            const v = @field(capi, d.name);
            // Every CSAR_* constant, whatever its type — deciding
            // which ones a host needs is the declaration's job, not
            // this emitter's. JSON numbers are f64, so the defaults
            // round-trip exactly.
            switch (@TypeOf(v)) {
                i32, u32, f64 => {
                    try w.print("{s}\n    \"{s}\": {d}", .{ if (first) "" else ",", d.name, v });
                    first = false;
                },
                else => @compileError("unhandled CSAR_ decl type: " ++ d.name),
            }
        }
    }
    try w.print("\n  }},\n  \"layout\": {{", .{});
    inline for (@typeInfo(capi.Result).@"struct".fields, 0..) |f, i| {
        try w.print("{s}\n    \"{s}\": {d}", .{
            if (i == 0) "" else ",",
            f.name,
            @offsetOf(capi.Result, f.name),
        });
    }
    try w.print(",\n    \"sizeof\": {d}\n  }}\n}}\n", .{@sizeOf(capi.Result)});
    try w.flush();
}
