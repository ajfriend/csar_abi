# csar_abi — dev notes

## wasm

The browser artifact is `ReleaseSmall`, hardcoded in build.zig
regardless of `-Doptimize`, and forced on the `csar` dependency too —
it ships to browsers, and size is the number `just wasm` prints.

**No `-Dsimd` knob.** The predecessor build carried a simd128 option
with the measurement recorded against it: no effect — 592 vs 592 µs on
a 9-point solve, 8.9 vs 9.1 ms at n = 1009, and 50355 vs 50806 bytes.
csar's `@Vector`-based linalg looked like it should benefit; measured,
it does not, and that measurement is why the option doesn't exist
here. Re-add it in an afternoon (`query.cpu_features_add =
std.Target.wasm.featureSet(&.{.simd128})`) if wasm perf ever matters.
