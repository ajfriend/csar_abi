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

# Compile everything without running or installing.
check:
    zig build check

# Everything CI checks that can run on this machine. Grows with the
# wasm shape and the declaration-drift gate.
ci: check test build

clean:
    rm -rf .zig-cache zig-out
