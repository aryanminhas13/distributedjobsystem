#!/bin/sh
set -eu

API_URL="${API_URL:-http://localhost:8080}"
echo "Scaling to one worker so the failure target is deterministic..."
docker compose up -d --scale worker=1
JOB="$(curl -fsS -X POST "$API_URL/api/jobs" -H 'Content-Type: application/json' -d '{"name":"chaos-worker-recovery","payload":{"durationMs":45000},"maxAttempts":3}')"
JOB_ID="$(printf '%s' "$JOB" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')"
sleep 3
WORKER_ID="$(docker compose ps -q worker | head -1)"
echo "Killing worker $WORKER_ID while job $JOB_ID is running..."
docker kill "$WORKER_ID" >/dev/null
docker compose up -d --scale worker=1

echo "Waiting for Redis pending-message reclamation (30s lease)..."
for _ in $(seq 1 90); do
  STATUS="$(curl -fsS "$API_URL/api/jobs/$JOB_ID" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')"
  printf 'status=%s\r' "$STATUS"
  [ "$STATUS" = "completed" ] && break
  sleep 1
done
echo
docker compose up -d --scale worker=8
[ "$STATUS" = "completed" ] || { echo "Recovery drill failed: $STATUS" >&2; exit 1; }
echo "Recovery drill passed for job $JOB_ID"
