_:
    just --list

# The native static archive + installed header (the shape csar_py
# links).
build:
    zig build -Doptimize=ReleaseFast

# Native smoke: every status, every input-error code, the
# nullable-lambdas contract, the version doors.
test:
    zig build test --summary all

# The wasm32-freestanding module. Size is a tracked number.
wasm:
    zig build wasm
    ls -la zig-out/bin/csar.wasm

# Compile everything without running or installing.
check:
    zig build check

# The declaration-drift gate: csar.h translated and compared against
# capi at comptime.
gate:
    zig build gate

# The JS half of the gate: csar.js against capi's values and struct
# layout (via the emitted abi.json), then driving the built module.
# Needs node, which is why it lives here and not in `zig build`.
gate-js:
    zig build abi-json wasm
    node gate/gate_js.mjs zig-out/abi.json zig-out/bin/csar.wasm

# Everything CI checks that can run on this machine.
ci: check test build gate gate-js

clean:
    rm -rf .zig-cache zig-out
