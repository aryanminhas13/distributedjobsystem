#!/bin/sh
set -eu

RESOURCE_GROUP="${RESOURCE_GROUP:?Set RESOURCE_GROUP}"
WORKER_APP="${WORKER_APP:?Set WORKER_APP to the worker Container App name}"
REVISION="$(az containerapp revision list --resource-group "$RESOURCE_GROUP" --name "$WORKER_APP" --query '[?properties.active].name | [0]' -o tsv)"
echo "Restarting active worker revision $REVISION"
az containerapp revision restart --resource-group "$RESOURCE_GROUP" --name "$WORKER_APP" --revision "$REVISION"
echo "Watch job recovery with: az containerapp logs show -g $RESOURCE_GROUP -n $WORKER_APP --follow"
