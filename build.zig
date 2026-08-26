//! Two artifact shapes from one door surface. Today: the native
//! static archive (the default install), consumed by csar_py's Cython
//! extension. The wasm32-freestanding module lands as its own comptime
//! root and build step.

const std = @import("std");

pub fn build(b: *std.Build) void {
    // `standardTargetOptions` is load-bearing for csar_py: its meson
    // build passes `-Dtarget=<arch>-macos.<deployment_target>` so the
    // archive honors the wheel's deployment target.
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const csar_mod = b.dependency("csar", .{
        .target = target,
        .optimize = optimize,
    }).module("csar");

    const native_mod = b.createModule(.{
        .root_source_file = b.path("src/native.zig"),
        .target = target,
        .optimize = optimize,
        // csar.solve allocates; on native targets the doors hand it
        // std.heap.c_allocator (the comptime seam in capi.zig).
        .link_libc = true,
        // The archive ends up linked into a Python extension
        // (.so / .pyd), itself a shared library — its objects must be
        // position-independent.
        .pic = true,
        .imports = &.{.{ .name = "csar", .module = csar_mod }},
    });

    // Static, not dynamic: avoids the Windows MSVC CRT mismatch and
    // the macOS dylib __dso_handle regression that shipping a Zig
    // dynamic library triggers.
    const lib = b.addLibrary(.{
        .name = "csar",
        .linkage = .static,
        .root_module = native_mod,
    });
    lib.installHeader(b.path("include/csar.h"), "csar.h");
    b.installArtifact(lib);

    // Smoke: call the doors natively, switch on every status.
    const capi_mod = b.createModule(.{
        .root_source_file = b.path("src/capi.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "csar", .module = csar_mod }},
    });
    const smoke = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("tests/smoke_test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "capi", .module = capi_mod }},
    }) });
    const test_step = b.step("test", "Run the native smoke test");
    test_step.dependOn(&b.addRunArtifact(smoke).step);
}
