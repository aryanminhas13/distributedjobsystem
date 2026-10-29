# Simulated incident: worker termination during execution

**Date:** 2026-10-28  
**Type:** controlled resilience exercise  
**Severity:** SEV-3 simulation  
**Status:** resolved

## Summary

A single worker was terminated while processing a 45-second job. The Redis consumer-group message remained pending and the PostgreSQL job remained `running`. A replacement worker reclaimed the message after the 30-second idle lease and completed it. No acknowledged job was lost.

## Customer impact

One synthetic job experienced elevated completion latency. Submission and read APIs remained available. No production customers or data were involved.

## Timeline

- T+00s: one-worker topology established and synthetic job accepted.
- T+03s: active worker terminated.
- T+04s: replacement worker started.
- T+30s: pending-message lease became eligible for reclamation.
- T+31-76s: replacement worker reclaimed and completed the job.
- T+77s: platform restored to eight workers.

## Root cause

The worker process was intentionally terminated after claiming a Redis Stream message and before acknowledgment. This reproduces an infrastructure eviction, OOM termination, or node loss.

## What worked

- Redis Streams retained the unacknowledged message.
- The replacement worker's reclaim loop recovered the job.
- PostgreSQL preserved job and attempt state.
- No manual replay was required.

## What could improve

- The fixed 30-second reclaim lease adds recovery latency.
- Long jobs can exceed the lease and risk duplicate processing because workers do not renew ownership.
- Handlers must therefore remain idempotent.

## Actions

1. Add a renewable execution lease/heartbeat for jobs longer than 30 seconds.
2. Alert on jobs whose `running` duration exceeds their expected execution time.
3. Add idempotency keys to external side effects.
4. Run the drill after changes to worker delivery or autoscaling.
