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

/// The ABI-relevant shape of a field's type, as the string the JS gate
/// compares. Offsets alone are not the unit that breaks: retyping
/// n_iters from u32 to i32 moves nothing, and csar.js would keep
/// reading it through the wrong view.
fn shape(comptime T: type) []const u8 {
    return switch (@typeInfo(T)) {
        .int => |i| std.fmt.comptimePrint("{s}{d}", .{ if (i.signedness == .signed) "i" else "u", i.bits }),
        .float => |f| std.fmt.comptimePrint("f{d}", .{f.bits}),
        .array => |a| std.fmt.comptimePrint("{s}[{d}]", .{ shape(a.child), a.len }),
        else => @compileError("shape: unhandled type " ++ @typeName(T)),
    };
}

pub fn main(init: std.process.Init) !void {
    var buf: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(init.io, &buf);
    var js: std.json.Stringify = .{ .writer = &file_writer.interface, .options = .{ .whitespace = .indent_2 } };

    try js.beginObject();
    try js.objectField("constants");
    try js.beginObject();
    inline for (@typeInfo(capi).@"struct".decls) |d| {
        if (comptime std.mem.startsWith(u8, d.name, "CSAR_")) {
            const v = @field(capi, d.name);
            // Every CSAR_* constant, whatever its type — deciding
            // which ones a host needs is the declaration's job, not
            // this emitter's. JSON numbers are f64, so the defaults
            // round-trip exactly.
            switch (@typeInfo(@TypeOf(v))) {
                .int, .float => {
                    try js.objectField(d.name);
                    try js.write(v);
                },
                else => @compileError("unhandled CSAR_ decl type: " ++ d.name),
            }
        }
    }
    try js.endObject();

    try js.objectField("layout");
    try js.beginObject();
    inline for (@typeInfo(capi.Result).@"struct".fields) |f| {
        try js.objectField(f.name);
        try js.beginObject();
        try js.objectField("offset");
        try js.write(@offsetOf(capi.Result, f.name));
        try js.objectField("type");
        try js.write(comptime shape(f.type));
        try js.endObject();
    }
    try js.endObject();

    try js.objectField("sizeof");
    try js.write(@sizeOf(capi.Result));
    try js.endObject();
    try file_writer.interface.flush();
}
