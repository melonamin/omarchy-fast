#!/usr/bin/env bash
set -euo pipefail

plugin_dir=$(cd "$(dirname "$0")/.." && pwd)
output=$(mktemp)
wrapper_pid=""
group_pid=""

cleanup() {
  [[ -z $wrapper_pid ]] || kill "$wrapper_pid" 2>/dev/null || true
  [[ -z $group_pid ]] || kill -KILL -- "-$group_pid" 2>/dev/null || true
  rm -f "$output"
}
trap cleanup EXIT

"$plugin_dir/run-speedtest" down 3 >"$output" &
wrapper_pid=$!

for _ in 1 2 3 4 5 6 7 8 9 10; do
  group_pid=$(pgrep -P "$wrapper_pid" -f 'omarchy-network-speedtest down$' | head -n 1 || true)
  [[ -n $group_pid ]] && break
  sleep 0.1
done

[[ -n $group_pid ]] || {
  echo "could not observe the guarded process group" >&2
  exit 1
}

wait "$wrapper_pid"
wrapper_pid=""

[[ -s $output ]] || {
  echo "speed test produced no samples" >&2
  exit 1
}

awk 'NF != 1 || $1 !~ /^[0-9]+([.][0-9]+)?$/ { exit 1 }' "$output"

sample_total=$(wc -l <"$output")
(( sample_total >= 20 )) || {
  echo "speed test cadence was too low: $sample_total samples in 3 seconds" >&2
  exit 1
}

# Give process reaping a beat, then assert the private process group is empty.
sleep 0.2
if pgrep -g "$group_pid" >/dev/null 2>&1; then
  echo "speed test worker survived its wrapper" >&2
  exit 1
fi

printf 'ok — %s samples; final %s Mbps\n' "$sample_total" "$(tail -n 1 "$output")"
