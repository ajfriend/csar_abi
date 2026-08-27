# csar_abi — dev notes

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
