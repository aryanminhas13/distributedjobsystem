#!/bin/sh
set -eu

JOBS="${JOBS:-4000}"
BASE_URL="${BASE_URL:-http://localhost:8080}"

metric() {
  key="$1"
  curl -sf "$BASE_URL/api/metrics" | sed -n "s/.*\"$key\":\([0-9.]*\).*/\1/p"
}

wait_for_drain() {
  while :; do
    queued="$(metric queued)"
    running="$(metric running)"
    [ "$queued" = "0" ] && [ "$running" = "0" ] && break
    printf '  queued=%s running=%s\r' "$queued" "$running"
    sleep 1
  done
  printf '\n'
}

benchmark() {
  workers="$1"
  echo "Preparing $JOBS jobs for $workers worker(s)..."
  docker compose up -d --scale worker=0
  wait_for_drain
  completed_before="$(metric completed)"

  docker run --rm -i \
    -v "$PWD/loadtest:/scripts" \
    grafana/k6 run --quiet \
    -e JOBS="$JOBS" \
    -e WORKERS="$workers" \
    -e BASE_URL=http://host.docker.internal:8080 \
    /scripts/worker-batch.js

  started="$(date +%s)"
  docker compose up -d --scale worker="$workers"
  wait_for_drain
  finished="$(date +%s)"
  completed_after="$(metric completed)"
  processed=$((completed_after - completed_before))
  elapsed=$((finished - started))
  [ "$elapsed" -gt 0 ] || elapsed=1
  throughput="$(awk "BEGIN { printf \"%.2f\", $processed / $elapsed }")"
  echo "$workers worker(s): $processed jobs in ${elapsed}s = $throughput jobs/s"
  eval "elapsed_$workers=$elapsed"
  eval "throughput_$workers=$throughput"
}

benchmark 1
benchmark 8

ratio="$(awk "BEGIN { printf \"%.2f\", $throughput_8 / $throughput_1 }")"
echo
echo "RESULT: 1 worker = $throughput_1 jobs/s"
echo "RESULT: 8 workers = $throughput_8 jobs/s"
echo "RESULT: scaling = ${ratio}x"
