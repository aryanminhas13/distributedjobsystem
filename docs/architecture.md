# Production architecture

```text
Internet
   |
Azure Container Apps ingress
   |
Dashboard (public) ---> API (environment-internal, 2-10 replicas)
                              |             |
                       PostgreSQL       Azure Managed Redis
                       durable state    Streams + DLQ
                              ^             |
                              +--- Workers (2-20 replicas)

Container Apps managed identity ---> Key Vault
Container Apps managed OTEL agent ---> Application Insights / Log Analytics
ACR ---> API, worker, and dashboard images
```

## Reliability model

- PostgreSQL is the source of truth for job state and immutable audit records.
- Redis Streams provides consumer-group delivery. Messages are acknowledged only after processing.
- A worker reclaims messages idle for 30 seconds, allowing recovery after a replica dies.
- Exponential backoff retries transient failures. Jobs that exhaust attempts are written to `jobs:dlq` and remain queryable in PostgreSQL.
- An administrator explicitly replays a DLQ job through `POST /api/dlq/{id}/replay`; the action is audited.
- API and dashboard scale on concurrent HTTP requests; workers scale on CPU with a nonzero minimum so the queue always has a consumer.

## Security model

- A user-assigned managed identity pulls images from ACR and reads only Key Vault secrets.
- PostgreSQL, Redis, and RBAC tokens are referenced from Key Vault; they are not embedded in Container App definitions.
- Viewer, operator, and administrator bearer tokens provide application-level RBAC. Production deployments should put Entra ID or an API gateway in front of the public dashboard before adding real users.
- Mutations record actor, role, action, target, metadata, and timestamp in `audit_logs`.
- TLS is required for the public endpoint, PostgreSQL, and Redis.

## Known next hardening steps

The default Terraform is intentionally affordable for a portfolio deployment. Before handling sensitive or regulated data, move PostgreSQL, Redis, and Key Vault behind private endpoints; use zone-redundant PostgreSQL and Redis; use Entra workload/user identities instead of long-lived role tokens; and add a secondary-region data replication and traffic failover strategy.
