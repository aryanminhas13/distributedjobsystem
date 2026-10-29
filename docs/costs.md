# Cost per 100,000 jobs

Cost is normalized against completed jobs for the same UTC measurement window:

```text
cost_per_100k = actual_Azure_cost / completed_jobs * 100000
```

Run:

```sh
RESOURCE_GROUP=rg-name \
JOBS_COMPLETED=104521 \
START_DATE=2026-10-27 \
END_DATE=2026-10-28 \
sh scripts/cost-per-100k.sh
```

Include Container Apps, PostgreSQL, Azure Managed Redis, ACR, Log Analytics, Application Insights, Key Vault, and network costs because the script queries the whole resource group. Use a window long enough to amortize idle/minimum replica costs, and report the job duration/payload profile beside the result.

For cost experiments, tag every resource with `environment`, `workload`, and `managed_by`; the Terraform stack does this automatically. The default B-series PostgreSQL, Balanced B0 Managed Redis, Basic ACR, and small Container Apps replicas are cost-conscious portfolio defaults. PostgreSQL is the main non-HA component in this portfolio configuration.

Terraform also creates a resource-group budget using `monthly_budget_cad`. When `alert_email` is set, Azure sends a notification at 80% of that monthly budget. This guardrail is separate from the per-job calculation: a low total bill can still hide poor unit economics at low throughput.
