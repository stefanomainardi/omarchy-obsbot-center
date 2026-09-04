#!/usr/bin/env bash

set -euo pipefail

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# The script declares read-only constants from its environment, so every
# scenario sources it in its own subshell.

# A symlinked cache directory is refused before anything is built.
(
  export XDG_CACHE_HOME="$WORK/symlinked"
  mkdir -p "$WORK/symlinked" "$WORK/elsewhere"
  ln -s "$WORK/elsewhere" "$WORK/symlinked/obsbot-center-omarchy"
  source "$ROOT_DIR/bin/obsbot-control"
  if ensure_xu_helper 2>/dev/null; then
    fail "symlinked cache directory was accepted"
  fi
  [[ -z "$(find "$WORK/elsewhere" -mindepth 1)" ]] || fail "symlinked cache directory was written to"
)

# A cache directory owned by this user but left world-accessible is tightened,
# and the clean build it produces is the reference for the scenarios below.
(
  export XDG_CACHE_HOME="$WORK/loose"
  mkdir -p "$WORK/loose/obsbot-center-omarchy"
  chmod 755 "$WORK/loose/obsbot-center-omarchy"
  source "$ROOT_DIR/bin/obsbot-control"
  ensure_xu_helper
  [[ "$(stat -c %a "$WORK/loose/obsbot-center-omarchy")" == "700" ]] || fail "loose cache directory kept its mode"
  cp "$XU_HELPER" "$WORK/good-helper"
)

# A planted executable at the helper path, without a matching hash record, is
# replaced by a fresh build instead of being executed. A helper whose recorded
# hash no longer matches its content is rebuilt too.
(
  export XDG_CACHE_HOME="$WORK/planted"
  mkdir -m 700 -p "$WORK/planted/obsbot-center-omarchy"
  source "$ROOT_DIR/bin/obsbot-control"
  planted="$WORK/planted/obsbot-center-omarchy/xu-probe-$(sha256sum "$XU_SOURCE" | sed 's/ .*//')"
  printf '#!/bin/sh\nprintf planted\n' >"$planted"
  chmod 700 "$planted"
  ensure_xu_helper
  [[ "$XU_HELPER" == "$planted" ]] || fail "unexpected helper path"
  [[ "$("$XU_HELPER" --encode fov wide)" == 040100* ]] || fail "planted helper survived the trust check"
  cmp -s "$XU_HELPER" "$WORK/good-helper" || fail "rebuilt helper differs from a clean build"

  printf 'tampered' >>"$XU_HELPER"
  ensure_xu_helper
  cmp -s "$XU_HELPER" "$WORK/good-helper" || fail "tampered helper was not rebuilt"
)

# A symlinked state file is ignored.
(
  export XDG_STATE_HOME="$WORK/state"
  mkdir -m 700 -p "$WORK/state/obsbot-center-omarchy"
  printf 'fov=narrow\n' >"$WORK/victim.conf"
  ln -s "$WORK/victim.conf" "$WORK/state/obsbot-center-omarchy/meet2.conf"
  source "$ROOT_DIR/bin/obsbot-control"
  if vendor_state_readable; then
    fail "symlinked state file was accepted"
  fi
)

# External tools run under a wall-clock bound and an output cap.
(
  export OBSBOT_TOOL_TIMEOUT=1
  source "$ROOT_DIR/bin/obsbot-control"
  start="$(date +%s)"
  if run_bounded sleep 30 >/dev/null 2>&1; then
    fail "hung tool was not interrupted"
  fi
  (( $(date +%s) - start < 10 )) || fail "hung tool ran past its timeout"
  [[ "$(run_bounded head -c 200000 /dev/zero | wc -c)" == "65536" ]] || fail "tool output was not capped"
)

# The C helper bounds its own device session as well.
grep -q 'alarm(IO_TIMEOUT_SECONDS)' "$ROOT_DIR/tools/xu-probe.c" || fail "helper has no I/O alarm"

printf 'Hardening tests passed.\n'
