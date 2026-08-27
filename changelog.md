# changelog

## 0.1.0

The first ABI pin: `csar_solve` over a caller-allocated `csar_result`,
declared as `csar.h` for native hosts, built as a static archive and a
wasm32-freestanding module, with the declaration-drift gate in CI.
Consolidates the two predecessor shims. (PRs #11, #12, #13.)
