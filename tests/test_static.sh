#!/usr/bin/env bash

set -euo pipefail

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"
omarchy plugin validate .
bash -n bin/obsbot-control tests/test_audio.sh tests/test_protocol.sh tests/test_static.sh
bin/obsbot-control detect | rg -q '^connected=[01]$'
cc -std=c11 -Wall -Wextra -Werror -O2 -D_FORTIFY_SOURCE=3 -fstack-protector-strong -fPIE -pie -Wl,-z,relro,-z,now tools/xu-probe.c -o tools/xu-probe
tests/test_protocol.sh
tests/test_audio.sh

if bin/obsbot-control reset invalid 2>/dev/null; then
  printf 'FAIL: accepted an invalid reset group\n' >&2
  exit 1
fi

if rg -n '#[0-9a-fA-F]{6,8}' --glob '*.qml' .; then
  printf 'FAIL: fixed UI colors bypass the Omarchy theme\n' >&2
  exit 1
fi

if rg -q 'return mediaDevices\.defaultVideoInput' Panel.qml; then
  printf 'FAIL: preview may fall back to an unrelated camera\n' >&2
  exit 1
fi

if ! rg -q 'if \(root\.opened && panelLoader\.item && panelLoader\.item\.refresh\)' BarWidget.qml; then
  printf 'FAIL: closed-panel refresh may open the camera device\n' >&2
  exit 1
fi

printf 'Static plugin tests passed.\n'
