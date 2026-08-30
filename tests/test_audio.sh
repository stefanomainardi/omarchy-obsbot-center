#!/usr/bin/env bash

set -euo pipefail

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly MOCK_DIR="$(mktemp -d)"
trap 'rm -rf -- "$MOCK_DIR"' EXIT

cat >"$MOCK_DIR/wpctl" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  status) printf ' ├─ Sources:\n │      49. alsa_input.usb-OBSBOT_Meet_2.analog-stereo [vol: 1.00]\n ├─ Filters:\n' ;;
  set-volume|set-mute) printf '%s\n' "$*" >>"$MOCK_LOG" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$MOCK_DIR/wpctl"

export MOCK_LOG="$MOCK_DIR/calls"
PATH="$MOCK_DIR:$PATH" "$ROOT_DIR/bin/obsbot-control" audio volume 125
PATH="$MOCK_DIR:$PATH" "$ROOT_DIR/bin/obsbot-control" audio mute on
PATH="$MOCK_DIR:$PATH" "$ROOT_DIR/bin/obsbot-control" audio mute off
PATH="$MOCK_DIR:$PATH" "$ROOT_DIR/bin/obsbot-control" audio mute toggle

diff -u <(printf 'set-volume 49 125%%\nset-mute 49 1\nset-mute 49 0\nset-mute 49 toggle\n') "$MOCK_LOG"

if PATH="$MOCK_DIR:$PATH" "$ROOT_DIR/bin/obsbot-control" audio volume 151 2>/dev/null; then
  printf 'FAIL: accepted out-of-range microphone volume\n' >&2
  exit 1
fi

printf 'Audio backend tests passed.\n'
