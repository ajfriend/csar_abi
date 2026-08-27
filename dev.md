# csar_abi — dev notes

## Releasing

Tags are deliberate ABI pins: consumers fetch `vX.Y.Z` by URL+hash and
never track main. Procedure: land the release PR, then tag the merge
commit `v<version>` matching `build.zig.zon`'s `.version` — the
release-check workflow alarms on a mismatch after the push. Release
name is the version; the body is a sentence pointing at the PRs;
changelog.md entries are equally short.

**Versioning posture.** The ABI — doors, `csar_result`, code tables,
declarations — drives bumps, not upstream releases: a csar re-pin with
no ABI change is a patch bump here (the version doors self-report both
identities, so nothing is lost). An ABI break is a major bump once
past 1.0; pre-1.0, a minor.

## The archive and Apple's linker

Zig 0.16's archiver writes members 2-byte aligned with bogus modes;
Xcode 26's ld rejects the archive ("member not 8-byte aligned") the
moment a NON-zig linker consumes it. Zig-to-zig consumption (this
repo's smoke, wasm) never crosses that boundary, which is why our
tests stay green while a raw `cc … libcsar.a` fails on macOS.
Artifact validity is the producer's contract, so the fix lives here:
on macOS targets, build.zig repacks the archive with `ar`
(`scripts/repack_ar.sh` — NOT `libtool -static`, which silently
skips misaligned members and emits an empty archive) before install,
and exposes the result as the named lazy paths `lib` and `header`,
which consumers (csar_py's `src/zig/build.zig`) install instead of
the raw artifact. Fixed upstream for zig 0.17; when the pin moves
past it, the repack becomes a pass-through and can be dropped.

## wasm

**Optimize mode.** The browser artifact is ReleaseSmall, hardcoded in
build.zig (rationale there). Measured against ReleaseFast under node
on an M-series laptop (2026-08): Fast solves 1.3–1.5x faster
(7.5 → 5.0 µs at n = 9; 570 → 439 µs at n = 1009) at ~1.75x the
stripped code size (42 KB → 73 KB). Both sit far inside a 16 ms frame
budget — the worst measured case is ~3.5% of a frame — so size wins.

**No `-Dsimd` knob.** The predecessor build carried a simd128 option
with the measurement recorded against it: no effect — 592 vs 592 µs on
a 9-point solve, 8.9 vs 9.1 ms at n = 1009, and 50355 vs 50806 bytes.
csar's `@Vector`-based linalg looked like it should benefit; measured,
it does not, and that measurement is why the option doesn't exist
here. Re-add it in an afternoon (`query.cpu_features_add =
std.Target.wasm.featureSet(&.{.simd128})`) if wasm perf ever matters.
