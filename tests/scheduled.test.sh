#!/usr/bin/env bash
set -euo pipefail

plugin_dir=$(cd "$(dirname "$0")/.." && pwd)
state_dir=$(mktemp -d /tmp/melonamin-fast-scheduled-test.XXXXXX)

cleanup() {
  rm -rf "$state_dir"
}
trap cleanup EXIT

MELONAMIN_FAST_HELPER="$plugin_dir/tests/fixtures/fake-speedtest" \
MELONAMIN_FAST_STATUS_COMMAND="$plugin_dir/tests/fixtures/fake-status" \
MELONAMIN_FAST_STATE_DIR="$state_dir" \
MELONAMIN_FAST_DURATION=1 \
  "$plugin_dir/run-scheduled-test" >/dev/null

jq -e '
  length == 1
  and .[0].automatic == true
  and .[0].down == 106
  and .[0].up == 206
  and .[0].ping == 12.3
' "$state_dir/history.json" >/dev/null

# Numeric output must stay machine-readable even when the user runs under a
# locale whose decimal separator is a comma.
locale_dir="$state_dir/locale"
mkdir -p "$locale_dir"
localedef -i de_DE -f UTF-8 "$locale_dir/de_DE.UTF-8"
LOCPATH="$locale_dir" \
LC_ALL=de_DE.UTF-8 \
MELONAMIN_FAST_HELPER="$plugin_dir/tests/fixtures/fake-speedtest" \
MELONAMIN_FAST_STATUS_COMMAND="$plugin_dir/tests/fixtures/fake-status" \
MELONAMIN_FAST_STATE_DIR="$state_dir" \
MELONAMIN_FAST_DURATION=1 \
  "$plugin_dir/run-scheduled-test" >"$state_dir/locale-output"

rg -q '^Fast monitor complete: down 106\.0 Mbps, up 206\.0 Mbps, ping 12\.3 ms$' \
  "$state_dir/locale-output"
[[ $(jq length "$state_dir/history.json") == 2 ]]

exec 8>"$state_dir/speedtest.lock"
flock -n 8
MELONAMIN_FAST_HELPER="$plugin_dir/tests/fixtures/fake-speedtest" \
MELONAMIN_FAST_STATUS_COMMAND="$plugin_dir/tests/fixtures/fake-status" \
MELONAMIN_FAST_STATE_DIR="$state_dir" \
MELONAMIN_FAST_DURATION=1 \
  "$plugin_dir/run-scheduled-test" >/dev/null
flock -u 8

[[ $(jq length "$state_dir/history.json") == 2 ]]
printf 'ok — scheduled result persisted, locale-safe output emitted, and lock contention skipped\n'
