# Distributed Job Orchestration Platform

A full-stack data platform for scheduling, executing, observing, and recovering background work. The Go control plane uses PostgreSQL as its source of truth, Redis Streams for delivery, horizontally scalable workers, and a React operations dashboard. The repository includes an Azure Container Apps deployment, OpenTelemetry, RBAC, audit logs, dead-letter replay, SLOs, alerts, failure drills, and cost normalization.

## Architecture

```text
Internet -> Container Apps dashboard -> internal Go API -> PostgreSQL
                                      |               -> Azure Managed Redis
                                      +-> worker replicas (autoscaled)

Managed identity -> Key Vault + ACR
OpenTelemetry -> Container Apps managed collector -> Application Insights
```

See [the production architecture](docs/architecture.md), [SLOs](docs/slo.md), and [alert runbook](docs/runbooks/alerts.md).

## Run locally

Docker Desktop is the only prerequisite:

```sh
docker compose up --build --scale worker=4
```

Open `http://localhost:5173`. Local mode intentionally grants administrator access when no role-token environment variables are configured.

To enable local RBAC, add `ADMIN_TOKEN`, `OPERATOR_TOKEN`, and `VIEWER_TOKEN` to the API service and paste the appropriate token into the dashboard. Roles are cumulative:

| Role | Permissions |
|---|---|
| Viewer | list jobs, DLQ, and metrics; receive WebSocket updates |
| Operator | viewer permissions plus submit and cancel jobs |
| Administrator | operator permissions plus DLQ replay and audit-log access |

## API

Authenticated requests use `Authorization: Bearer <token>`. Mutating clients may send `X-Actor-ID`; it is recorded with the resolved role in the immutable audit log.

| Method | Endpoint | Minimum role | Purpose |
|---|---|---|---|
| `POST` | `/api/jobs` | operator | submit or schedule a job |
| `GET` | `/api/jobs`, `/api/jobs/{id}` | viewer | inspect recent work |
| `POST` | `/api/jobs/{id}/cancel` | operator | cancel active work |
| `GET` | `/api/dlq` | viewer | list terminal failures |
| `POST` | `/api/dlq/{id}/replay` | administrator | reset and replay a failed job |
| `GET` | `/api/audit` | administrator | inspect the latest 200 audit events |
| `GET` | `/api/metrics` | viewer | queue depth, outcomes, and p95 dispatch latency |
| `GET` | `/healthz` | public | PostgreSQL and Redis readiness |
| `GET` | `/ws` | viewer | real-time job events |

Example submission:

```sh
curl -X POST http://localhost:8080/api/jobs \
  -H 'Content-Type: application/json' \
  -d '{"name":"daily-report","payload":{"durationMs":250},"maxAttempts":3}'
```

Jobs use exponential retry backoff. After the final attempt, the durable PostgreSQL record is marked failed and a diagnostic entry is appended to `jobs:dlq`. Replay is explicit, administrator-only, and audited.

## Azure deployment

The Terraform stack creates:

- Azure Container Apps for the dashboard, private API, and 2-20 autoscaled workers
- Azure Container Registry and a user-assigned managed identity
- PostgreSQL Flexible Server and Azure Managed Redis
- Key Vault references for database, Redis, and RBAC secrets
- Log Analytics, Application Insights, the managed OpenTelemetry agent, and SLO alert rules
- encrypted remote Terraform state via the bootstrap script

The deploy script stops at a saved plan so infrastructure and spend can be reviewed before creation:

```sh
az login
sh scripts/bootstrap-terraform-state.sh
cp infra/terraform.tfvars.example infra/terraform.tfvars
sh scripts/deploy-azure.sh
terraform -chdir=infra apply deployment.tfplan
terraform -chdir=infra output dashboard_url
```

Applying the plan creates billable Azure resources. Retrieve (rather than print into Terraform output) a role token from Key Vault:

```sh
az keyvault secret show \
  --vault-name "$(terraform -chdir=infra output -raw key_vault_name)" \
  --name operator-token --query value -o tsv
```

## Observability and reliability

- HTTP and worker spans, W3C trace propagation, correlated JSON logs, and job counters use OpenTelemetry.
- Container Apps' managed collector exports traces and logs to Application Insights. `/api/metrics` retains operational job metrics; a custom OTLP destination can centralize OTel metrics.
- Redis consumer groups retain unacknowledged work. Replacement workers reclaim messages after a 30-second lease.
- Azure Monitor alerts enforce API error-rate and p95 latency objectives. The complete SLO/error-budget policy is in [docs/slo.md](docs/slo.md).
- The controlled worker-loss exercise and follow-up actions are recorded in the [incident postmortem](docs/postmortems/2026-10-28-worker-stall-drill.md).

Run the local worker-failure drill only against the disposable local stack:

```sh
sh scripts/chaos-worker-recovery.sh
```

For Azure, `scripts/chaos-azure-worker.sh` restarts the active worker revision after the resource group and app name are explicitly supplied.

## Performance and cost

The checked-in k6 profile targets 8,040 submissions/minute for 13 minutes:

```sh
docker run --rm -i \
  -v "$PWD/loadtest:/scripts" \
  grafana/k6 run \
  -e BASE_URL=http://host.docker.internal:8080 \
  /scripts/jobs.js
```

Measured on the original development machine: 104,521 accepted jobs, zero request failures, 2.42 ms HTTP p95, and 1.342 ms queue-to-worker p95. `loadtest/compare-workers.sh` measured 6.83× processing throughput from one to eight workers. Results depend on the host and should be rerun for reproducibility.

Normalize the actual Azure resource-group bill for the same job window:

```sh
RESOURCE_GROUP=rg-name \
JOBS_COMPLETED=104521 \
START_DATE=2026-10-27 \
END_DATE=2026-10-28 \
sh scripts/cost-per-100k.sh
```

The calculation and reporting rules are documented in [docs/costs.md](docs/costs.md).

## Validation

CI runs Go formatting/tests/vet, the production dashboard build, Docker Compose validation, and Terraform formatting/provider-schema validation. Run the same core checks locally with:

```sh
docker run --rm -v "$PWD/server:/src" -w /src golang:1.25-alpine \
  sh -c 'gofmt -w *.go && go test ./... && go vet ./...'
docker run --rm -v "$PWD/dashboard:/app" -w /app node:22-alpine \
  sh -c 'npm ci && npm run build'
docker compose config --quiet
```
