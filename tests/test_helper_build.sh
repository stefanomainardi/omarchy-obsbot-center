#!/usr/bin/env bash

set -euo pipefail

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEST_CACHE="$(mktemp -d)"
trap 'rm -rf -- "$TEST_CACHE"' EXIT

export XDG_CACHE_HOME="$TEST_CACHE"
source "$ROOT_DIR/bin/obsbot-control"

for _ in {1..4}; do
  (ensure_xu_helper) &
done
wait
ensure_xu_helper
readonly FIRST_HELPER="$XU_HELPER"
readonly EXPECTED_HASH="$(sha256sum "$ROOT_DIR/tools/xu-probe.c" | sed 's/ .*//')"

[[ "$(find "$TEST_CACHE/obsbot-center-omarchy" -maxdepth 1 -type f | wc -l)" == "1" ]]
[[ "$FIRST_HELPER" == "$TEST_CACHE/obsbot-center-omarchy/xu-probe-$EXPECTED_HASH" ]]
[[ -x "$FIRST_HELPER" ]]
[[ "$(stat -c %a "$TEST_CACHE/obsbot-center-omarchy")" == "700" ]]
[[ "$(stat -c %a "$FIRST_HELPER")" == "700" ]]
[[ "$($FIRST_HELPER --encode fov wide)" == 040100* ]]

readonly FIRST_MTIME="$(stat -c %Y "$FIRST_HELPER")"
ensure_xu_helper
[[ "$XU_HELPER" == "$FIRST_HELPER" ]]
[[ "$(stat -c %Y "$FIRST_HELPER")" == "$FIRST_MTIME" ]]

printf 'Local helper build tests passed.\n'
