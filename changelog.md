# changelog

## 0.2.1

Re-pin the solver at csar v0.7.0 (was 0.5.0): the chart-form gap
evaluation, so certifications are oracle-honest and typical solves are
a few percent faster. No change to the C or JS surface; the version
doors report the new pin.

## 0.2.0

New declaration: `csar.js`, the JavaScript counterpart to `csar.h` —
the code tables, the `csar_result` layout, and `init`/`solve` over the
wasm module. `just gate-js` checks it against capi's values and the
built module's exports. No change to the C surface. (PR #16.)

## 0.1.1

Ship `scripts/` in the package `.paths`: v0.1.0's tarball stripped
`repack_ar.sh`, so a macOS consumer's build of the dependency could
not run the darwin repack. Surfaced by csar_py's first build against
the tag; no ABI change.

## 0.1.0

The first ABI pin: `csar_solve` over a caller-allocated `csar_result`,
declared as `csar.h` for native hosts, built as a static archive and a
wasm32-freestanding module, with the declaration-drift gate in CI.
Consolidates the two predecessor shims. (PRs #11, #12, #13.)
