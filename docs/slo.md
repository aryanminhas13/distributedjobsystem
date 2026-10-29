# Service level objectives

| Service level indicator | Objective | Window | Alert |
|---|---:|---:|---|
| Successful API requests | 99.9% | rolling 30 days | error rate >0.1% for 5 minutes |
| API request latency | p95 <150 ms | rolling 15 minutes | two of three windows over 150 ms |
| Queue dispatch latency | p95 <150 ms | rolling 15 minutes | dashboard/API metric breach |
| Durable completion | 99.9% of accepted jobs complete or enter DLQ | rolling 30 days | growing queued count or missing terminal state |
| DLQ rate | <0.1% of started jobs | rolling 24 hours | DLQ rate exceeds threshold |
| Recovery point | no acknowledged job loss | continuous | reconciliation mismatch |

## Error budget

A 99.9% monthly availability target permits roughly 43.8 minutes of unavailability in a 30-day month. At 50% budget consumption, freeze risky feature releases and prioritize reliability work. At 100%, allow only incident remediation and rollback work until the rolling window recovers.

## Measurement

- OpenTelemetry spans capture HTTP and job-processing operations with trace IDs.
- OpenTelemetry counters record started, completed, retried, and failed jobs.
- Correlated JSON request logs include status, duration, route, and trace ID.
- PostgreSQL computes queue-to-worker p95 dispatch latency.
- Azure Monitor alert rules evaluate Application Insights request failures and latency.

Application Insights accepts traces and logs from the managed Container Apps OpenTelemetry agent. Its managed Application Insights destination does not currently accept OTel metrics, so operational job metrics remain available from `/api/metrics`; use a custom OTLP metrics destination if centralized OTel metric retention is required.
