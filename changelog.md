# changelog

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
