#!/usr/bin/env bash

set -euo pipefail

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly BUILD_DIR="$(mktemp -d)"
readonly HELPER="${BUILD_DIR}/xu-probe"
trap 'rm -rf -- "$BUILD_DIR"' EXIT

cc -std=c11 -Wall -Wextra -Werror -O2 -D_FORTIFY_SOURCE=3 \
  -fstack-protector-strong -fPIE -pie -Wl,-z,relro,-z,now \
  "${ROOT_DIR}/tools/xu-probe.c" -o "$HELPER"

assert_prefix() {
  local feature="$1" value="$2" expected="$3" actual
  actual="$($HELPER --encode "$feature" "$value")"
  [[ "$actual" == "$expected"* ]] || {
    printf 'FAIL: %s %s encoded as %s, expected prefix %s\n' \
      "$feature" "$value" "${actual:0:${#expected}}" "$expected" >&2
    return 1
  }
}

assert_prefix hdr on 010101
assert_prefix fov wide 040100
assert_prefix fov medium 040101
assert_prefix fov narrow 040102
assert_prefix auto-framing off 0d020000
assert_prefix auto-framing solo 0d020100
assert_prefix auto-framing group 0d020101
assert_prefix mirror on 140101
assert_prefix vertical on 0c0101
assert_prefix led on 180101
assert_prefix keep-awake on 120101
assert_prefix microphone on 1c0101
assert_prefix audio-agc on 170101
assert_prefix sleep-microphone on 130101
assert_prefix audio-distance standard 1b0100
assert_prefix audio-distance near 1b0101
assert_prefix audio-distance far 1b0102
assert_prefix audio-mode pure 22020005
assert_prefix audio-mode omni 22020000
assert_prefix audio-mode directional 22020002
assert_prefix audio-mode dual-directional 22020004
# The gesture zoom factor is a ratio scaled by 100, and it shares the frame
# with the gesture control toggle, so both carry it.
assert_prefix gesture-control on 2005010201c800
assert_prefix gesture-control off 2005000200c800
assert_prefix gesture-zoom 1x 20050102016400
assert_prefix gesture-zoom 2x 2005010201c800
assert_prefix gesture-zoom 3x 20050102012c01
assert_prefix gesture-zoom 4x 20050102019001
assert_prefix auto-sleep off 0b020000
assert_prefix auto-sleep 30s 0b021e00
assert_prefix auto-sleep 2m 0b027800
assert_prefix auto-sleep 10m 0b025802

if "$HELPER" --encode fov invalid >/dev/null 2>&1; then
  printf 'FAIL: invalid protocol value was accepted\n' >&2
  exit 1
fi

printf 'Protocol encoding tests passed.\n'
