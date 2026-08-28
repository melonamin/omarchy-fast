#!/usr/bin/env bash
set -euo pipefail

plugin_dir=$(cd "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/melonamin-fast-failure-test.XXXXXX)
wrapper_pid=""

cleanup() {
  [[ -z $wrapper_pid ]] || kill -TERM "$wrapper_pid" 2>/dev/null || true
  rm -rf "$test_dir"
}
trap cleanup EXIT

set +e
PATH="$plugin_dir/tests/fixtures/network:$plugin_dir/tests/fixtures/failing-backend:$PATH" \
XDG_STATE_HOME="$test_dir/state" \
  "$plugin_dir/run-speedtest" down 1 >"$test_dir/output" 2>"$test_dir/error"
status=$?
set -e

[[ $status == 42 ]] || {
  echo "expected backend exit 42, got $status" >&2
  exit 1
}
[[ ! -s $test_dir/output ]] || {
  echo "failed backend produced successful-looking samples" >&2
  exit 1
}
rg -q 'simulated Fast.com backend failure' "$test_dir/error"
rg -q 'stopped before the measurement completed' "$test_dir/error"

set +e
PATH="$plugin_dir/tests/fixtures/network:$plugin_dir/tests/fixtures/failing-backend:$PATH" \
HOME="$test_dir/empty-home" \
MELONAMIN_FAST_STATE_DIR="$test_dir/scheduled-state" \
MELONAMIN_FAST_DURATION=1 \
  "$plugin_dir/run-scheduled-test" >"$test_dir/scheduled-output" 2>"$test_dir/scheduled-error"
scheduled_status=$?
set -e

[[ $scheduled_status == 42 ]] || {
  echo "expected scheduled backend exit 42, got $scheduled_status" >&2
  exit 1
}
[[ ! -e $test_dir/scheduled-state/history.json ]] || {
  echo "scheduled failure was persisted as a history result" >&2
  exit 1
}

set +e
PATH="$plugin_dir/tests/fixtures/network:$plugin_dir/tests/fixtures/hanging-backend:$PATH" \
XDG_STATE_HOME="$test_dir/readiness-state" \
MELONAMIN_FAST_READY_TIMEOUT=1 \
MELONAMIN_FAST_TEST_PID_FILE="$test_dir/backend-pid" \
  "$plugin_dir/run-speedtest" down 1 >"$test_dir/readiness-output" 2>"$test_dir/readiness-error"
readiness_status=$?
set -e

[[ $readiness_status == 1 ]] || {
  echo "expected readiness timeout exit 1, got $readiness_status" >&2
  exit 1
}
[[ ! -s $test_dir/readiness-output ]] || {
  echo "unready backend produced successful-looking samples" >&2
  exit 1
}
rg -q 'did not begin transferring within 1s' "$test_dir/readiness-error"
backend_pid=$(<"$test_dir/backend-pid")
if kill -0 "$backend_pid" 2>/dev/null; then
  echo "unready backend survived timeout cleanup" >&2
  exit 1
fi

printf '1000\n' >"$test_dir/idle-counter"
set +e
PATH="$plugin_dir/tests/fixtures/network:$plugin_dir/tests/fixtures/stalled-backend:$PATH" \
XDG_STATE_HOME="$test_dir/stalled-state" \
MELONAMIN_FAST_COUNTER_PATH="$test_dir/idle-counter" \
MELONAMIN_FAST_READY_TIMEOUT=1 \
MELONAMIN_FAST_TEST_PID_FILE="$test_dir/stalled-pid" \
  "$plugin_dir/run-speedtest" down 1 >"$test_dir/stalled-output" 2>"$test_dir/stalled-error"
stalled_status=$?
set -e

[[ $stalled_status == 1 ]] || {
  echo "expected stalled-transfer exit 1, got $stalled_status" >&2
  exit 1
}
[[ ! -s $test_dir/stalled-output ]] || {
  echo "zero-output backend produced successful-looking samples without moving bytes" >&2
  exit 1
}
rg -q 'did not begin transferring within 1s' "$test_dir/stalled-error"
stalled_pid=$(<"$test_dir/stalled-pid")
if kill -0 "$stalled_pid" 2>/dev/null; then
  echo "stalled backend survived timeout cleanup" >&2
  exit 1
fi

printf '1000\n' >"$test_dir/cancel-counter"
PATH="$plugin_dir/tests/fixtures/network:$plugin_dir/tests/fixtures/stalled-backend:$PATH" \
XDG_STATE_HOME="$test_dir/cancel-state" \
MELONAMIN_FAST_COUNTER_PATH="$test_dir/cancel-counter" \
MELONAMIN_FAST_READY_TIMEOUT=10 \
MELONAMIN_FAST_TEST_PID_FILE="$test_dir/cancel-pid" \
  "$plugin_dir/run-speedtest" down 1 >"$test_dir/cancel-output" 2>"$test_dir/cancel-error" &
wrapper_pid=$!

for _ in $(seq 1 100); do
  [[ -s $test_dir/cancel-pid ]] && break
  sleep 0.02
done
[[ -s $test_dir/cancel-pid ]] || {
  echo "cancellation backend never started" >&2
  exit 1
}
cancel_pid=$(<"$test_dir/cancel-pid")
kill -TERM "$wrapper_pid"
set +e
wait "$wrapper_pid"
cancel_status=$?
set -e
wrapper_pid=""

[[ $cancel_status == 143 ]] || {
  echo "expected cancelled wrapper exit 143, got $cancel_status" >&2
  exit 1
}
if kill -0 "$cancel_pid" 2>/dev/null; then
  echo "cancelled backend survived wrapper cleanup" >&2
  exit 1
fi

printf 'ok — backend failures, readiness stalls, and cancellation handled safely\n'
