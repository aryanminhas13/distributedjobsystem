# Alert runbook

## API error-rate SLO burn

1. Confirm the alert window and affected revision in Application Insights.
2. Split failures by route, status code, and revision.
3. Check PostgreSQL and Redis health and Container Apps replica events.
4. If correlated with a deployment, shift traffic to the prior revision or roll back the image tag.
5. If dependency-related, stop submissions only if durability is at risk; queued work should remain recoverable.
6. Record mitigation time and error-budget impact.

## p95 latency breach

1. Compare HTTP p95 with `p95DispatchMs` to separate API saturation from worker backlog.
2. Inspect CPU, memory, replica counts, database connections, and Redis latency.
3. Raise worker replicas if queued work is growing; raise API replicas if submission latency alone is high.
4. Capture a trace for the slow route before changing capacity.

## DLQ growth

1. Call `GET /api/dlq` with a viewer token and group failures by error/job type.
2. Fix or disable the responsible producer/handler.
3. Replay a single representative job with an admin token.
4. Verify completion and then replay the remaining bounded batch.
5. Never mass-replay while the root cause remains active.

## Worker recovery drill

Run `scripts/chaos-worker-recovery.sh`. It scales locally to one worker, submits a long job, kills the worker, starts a replacement, waits for Redis reclaim, verifies completion, and restores eight workers. For Azure, set `RESOURCE_GROUP` and `WORKER_APP`, then run `scripts/chaos-azure-worker.sh`.
