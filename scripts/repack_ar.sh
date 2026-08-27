#!/bin/sh
# Repack the zig-written static archive for darwin consumers (member
# alignment; Apple's ld rejects the raw archive). libtool -static on
# the archive is NOT a fix: when a member is misaligned it warns and
# SKIPS it, emitting an empty archive. Extract and re-archive with ar
# instead — extracted members are fresh files, so alignment and the
# zig archive's bogus member mode (000, hence the chmod) both wash
# out.
#
# The alignment bug is fixed upstream for zig 0.17 (not 0.16); the
# member-mode bug is filed separately. Once the toolchain pin moves
# past 0.17 this step becomes a harmless pass-through and can be
# dropped. Ported from the sibling bindings repo that first hit this.
#
# Usage: repack_ar.sh <input.a> <output.a> (paths relative to $PWD ok)
set -e
b="$PWD"
case "$1" in /*) in="$1";; *) in="$b/$1";; esac
case "$2" in /*) out="$2";; *) out="$b/$2";; esac
d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cd "$d"
ar x "$in"
chmod u+rw *.o
ar rcs "$out" *.o
