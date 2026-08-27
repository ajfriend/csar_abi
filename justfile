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

# Everything CI checks that can run on this machine. Grows with the
# declaration-drift gate.
ci: check test build wasm

clean:
    rm -rf .zig-cache zig-out
