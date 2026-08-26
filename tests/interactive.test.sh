#!/usr/bin/env bash
set -euo pipefail

plugin_dir=$(cd "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/melonamin-fast-interactive-test.XXXXXX)
wrapper_pid=""

cleanup() {
  [[ -z $wrapper_pid ]] || kill "$wrapper_pid" 2>/dev/null || true
  rm -rf "$test_dir"
}
trap cleanup EXIT

MELONAMIN_FAST_HELPER="$plugin_dir/tests/fixtures/locking-speedtest" \
MELONAMIN_FAST_STATE_DIR="$test_dir/state" \
MELONAMIN_FAST_UP_STARTED="$test_dir/up-started" \
MELONAMIN_FAST_RELEASE="$test_dir/release" \
  "$plugin_dir/run-interactive-test" 1 >"$test_dir/output" &
wrapper_pid=$!

for _ in $(seq 1 100); do
  [[ -e $test_dir/up-started ]] && break
  sleep 0.02
done
[[ -e $test_dir/up-started ]] || {
  echo "interactive wrapper never reached upload" >&2
  exit 1
}

exec 8>"$test_dir/state/speedtest.lock"
if flock -n 8; then
  echo "interactive wrapper released its lock between phases" >&2
  exit 1
fi

: >"$test_dir/release"
wait "$wrapper_pid"
wrapper_pid=""

diff -u <(printf '__MELONAMIN_FAST_PHASE__:down\n101.0\n__MELONAMIN_FAST_PHASE__:up\n201.0\n') \
  "$test_dir/output"
flock -n 8

printf 'ok — interactive lock held across download and upload\n'
