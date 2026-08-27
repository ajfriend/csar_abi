//! Two artifact shapes from one door surface. Today: the native
//! static archive (the default install), consumed by csar_py's Cython
//! extension. The wasm32-freestanding module lands as its own comptime
//! root and build step.

const std = @import("std");

// The manifest is the one source of version identity: the ABI version
// is `.version`, and the upstream solver version is recovered from the
// csar dependency pin ("csar-0.5.0-<digest>"). Both are injected into
// capi.zig as the `abi_meta` module, so the version doors and a re-pin
// can never drift apart.
const Manifest = struct {
    name: enum { csar_abi },
    version: []const u8,
    fingerprint: u64,
    minimum_zig_version: []const u8,
    dependencies: struct {
        csar: struct { url: []const u8, hash: []const u8 },
    },
    paths: []const []const u8,
};
const zon: Manifest = @import("build.zig.zon");

fn upstreamVersion(hash: []const u8) []const u8 {
    const start = (std.mem.indexOfScalar(u8, hash, '-') orelse unreachable) + 1;
    const end = std.mem.indexOfScalarPos(u8, hash, start, '-') orelse unreachable;
    return hash[start..end];
}

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

    const meta = b.addOptions();
    meta.addOption([]const u8, "abi_version", zon.version);
    meta.addOption([]const u8, "upstream_version", upstreamVersion(zon.dependencies.csar.hash));
    const meta_mod = meta.createModule();

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
        .imports = &.{
            .{ .name = "csar", .module = csar_mod },
            .{ .name = "abi_meta", .module = meta_mod },
        },
    });

    // Static, not dynamic: avoids the Windows MSVC CRT mismatch and
    // the macOS dylib __dso_handle regression that shipping a Zig
    // dynamic library triggers.
    const lib = b.addLibrary(.{
        .name = "csar",
        .linkage = .static,
        .root_module = native_mod,
    });

    // Artifact validity is the producer's contract: zig 0.16's
    // archiver writes members Apple's ld rejects ("not 8-byte
    // aligned"; fixed upstream for 0.17), so on macOS targets the
    // archive is repacked with ar before anything ships it —
    // consumers install `lib`/`header` below and never see the raw
    // archive. Drop the repack when the pin moves past 0.17.
    // (dev.md "The archive and Apple's linker".)
    const lib_file = if (target.result.os.tag == .macos) blk: {
        const repack = b.addSystemCommand(&.{"sh"});
        repack.addFileArg(b.path("scripts/repack_ar.sh"));
        repack.addFileArg(lib.getEmittedBin());
        break :blk repack.addOutputFileArg("libcsar.a");
    } else lib.getEmittedBin();
    const lib_name = if (target.result.os.tag == .windows) "csar.lib" else "libcsar.a";
    b.addNamedLazyPath("lib", lib_file);
    b.addNamedLazyPath("header", b.path("include/csar.h"));
    b.getInstallStep().dependOn(&b.addInstallLibFile(lib_file, lib_name).step);
    b.getInstallStep().dependOn(&b.addInstallHeaderFile(b.path("include/csar.h"), "csar.h").step);

    // Smoke: call the doors natively, switch on every status. The test
    // imports capi as a module (it lives outside src/, which ships in
    // the tarball) plus abi_meta, to check the doors against the same
    // injected values.
    const capi_mod = b.createModule(.{
        .root_source_file = b.path("src/capi.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "csar", .module = csar_mod },
            .{ .name = "abi_meta", .module = meta_mod },
        },
    });
    const smoke = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("tests/smoke_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "capi", .module = capi_mod },
            .{ .name = "abi_meta", .module = meta_mod },
        },
    }) });
    const test_step = b.step("test", "Run the native smoke test");
    test_step.dependOn(&b.addRunArtifact(smoke).step);

    // ---- The wasm module (`zig build wasm`). ----
    // ReleaseSmall regardless of -Doptimize, forced on the csar
    // dependency too: this artifact ships to browsers. No -Dsimd
    // knob — simd128 was measured to change nothing (dev.md "wasm").
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const csar_wasm_mod = b.dependency("csar", .{
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    }).module("csar");
    const wasm_mod = b.createModule(.{
        .root_source_file = b.path("src/wasm.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
        .imports = &.{
            .{ .name = "csar", .module = csar_wasm_mod },
            .{ .name = "abi_meta", .module = meta_mod },
        },
    });
    // An "executable" with no entry point: rdynamic exports every
    // analyzed `export fn` — capi's doors plus wasm.zig's
    // static-buffer doors, and nothing else (module-graph selection).
    const wasm = b.addExecutable(.{ .name = "csar", .root_module = wasm_mod });
    wasm.entry = .disabled;
    wasm.rdynamic = true;
    const wasm_step = b.step("wasm", "Build the wasm32-freestanding module");
    wasm_step.dependOn(&b.addInstallArtifact(wasm, .{}).step);

    // ---- The declaration-drift gate (`zig build gate`). ----
    // include/csar.h, translated by the same clang frontend that
    // compiles C consumers, is imported beside capi and compared at
    // comptime — constants by value, csar_result by offsets and size,
    // doors by ABI shape. Compiling gate/gate.zig IS the check; drift
    // is a compile error naming the decl. Hand-mirrored declarations
    // are how the predecessor shims drifted; this makes the mirror
    // checkable. csar.js joins via the built module's export section
    // when it lands.
    const hdr_mod = b.addTranslateC(.{
        .root_source_file = b.path("include/csar.h"),
        .target = target,
        .optimize = optimize,
    }).createModule();
    const gate_test = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("gate/gate.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "capi", .module = capi_mod },
            .{ .name = "csar_h", .module = hdr_mod },
        },
    }) });
    const gate = b.step("gate", "Check the declarations against capi.zig");
    gate.dependOn(&b.addRunArtifact(gate_test).step);

    // The ABI reference as JSON, for the JS half of the gate (which
    // node runs — `just gate-js`; keeping it out of `zig build` leaves
    // the build hermetic). Reflection over capi, same as above.
    const emit_json = b.addExecutable(.{ .name = "emit_abi_json", .root_module = b.createModule(.{
        .root_source_file = b.path("gate/emit_abi_json.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "capi", .module = capi_mod },
            .{ .name = "abi_meta", .module = meta_mod },
        },
    }) });
    const write_json = b.addInstallFile(
        b.addRunArtifact(emit_json).captureStdOut(.{}),
        "abi.json",
    );
    const json_step = b.step("abi-json", "Emit the ABI reference as JSON");
    json_step.dependOn(&write_json.step);

    // Compile everything without running or installing — the fast
    // signal for editors and CI. Includes the gate: its check IS its
    // compilation.
    const check = b.step("check", "Compile the archive, the smoke test, the wasm module, and the gate");
    check.dependOn(&lib.step);
    check.dependOn(&smoke.step);
    check.dependOn(&wasm.step);
    check.dependOn(&gate_test.step);
}
