# Distributed Job Orchestration Platform

A runnable job platform with a Go API, Redis Streams queue, PostgreSQL persistence, WebSocket updates, a React dashboard, and horizontally scalable workers.

## Run

```sh
docker compose up --build --scale worker=4
```

Open `http://localhost:5173`. Submit a job from the dashboard; workers simulate execution and stream state and logs in real time.

## API

- `POST /api/jobs` submit `{ "name": "daily-report", "payload": { ... }, "maxAttempts": 3, "runAt": "RFC3339 optional" }`
- `GET /api/jobs`, `GET /api/jobs/:id`, `POST /api/jobs/:id/cancel`
- `GET /api/metrics`, `GET /ws`

The API stores durable job records in Postgres and uses Redis Streams consumer groups for delivery. A reaper periodically reclaims pending messages from failed workers. The worker applies exponential retry backoff and respects cancellation.

## Load test

Run the 100,000+ job profile through Docker:

```sh
docker run --rm -i --network host -v "$PWD/loadtest:/scripts" grafana/k6 run -e BASE_URL=http://host.docker.internal:8080 /scripts/jobs.js
curl http://localhost:8080/api/metrics
```

The profile targets 8,040 submissions/minute for 13 minutes (104,520 jobs), uses 25 ms simulated tasks, and fails if HTTP p95 exceeds 150 ms. The metrics response separately reports `p95DispatchMs`, measured from job creation until a worker starts it. Benchmark results depend on the host and are not claimed until this run succeeds.

Compare worker processing throughput with identical preloaded batches:

```sh
sh loadtest/compare-workers.sh
```

Set `JOBS=8000` for a longer, less startup-sensitive comparison. The script restores the stack to eight workers when it finishes.
