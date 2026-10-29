#!/bin/sh
set -eu

RESOURCE_GROUP="${RESOURCE_GROUP:?Set RESOURCE_GROUP to the deployed Azure resource group}"
START_DATE="${START_DATE:-$(date -u -v-1d +%Y-%m-%d 2>/dev/null || date -u -d '1 day ago' +%Y-%m-%d)}"
END_DATE="${END_DATE:-$(date -u +%Y-%m-%d)}"
JOBS_COMPLETED="${JOBS_COMPLETED:?Set JOBS_COMPLETED for the same measurement window}"
SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
SCOPE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"
BODY="{\"type\":\"ActualCost\",\"timeframe\":\"Custom\",\"timePeriod\":{\"from\":\"${START_DATE}T00:00:00Z\",\"to\":\"${END_DATE}T23:59:59Z\"},\"dataset\":{\"granularity\":\"None\",\"aggregation\":{\"totalCost\":{\"name\":\"PreTaxCost\",\"function\":\"Sum\"}}}}"
COST="$(az rest --method post --uri "https://management.azure.com${SCOPE}/providers/Microsoft.CostManagement/query?api-version=2023-11-01" --body "$BODY" --query 'properties.rows[0][0]' -o tsv)"
PER_100K="$(awk "BEGIN { printf \"%.4f\", ($COST / $JOBS_COMPLETED) * 100000 }")"

echo "Window: $START_DATE to $END_DATE"
echo "Actual Azure cost: $COST"
echo "Completed jobs: $JOBS_COMPLETED"
echo "Cost per 100,000 jobs: $PER_100K"
