#!/bin/sh
set -eu

LOCATION="${LOCATION:-canadacentral}"
RESOURCE_GROUP="${TF_STATE_RESOURCE_GROUP:-rg-djobs-tfstate}"
STORAGE_ACCOUNT="${TF_STATE_STORAGE_ACCOUNT:-djobstfstate$(date +%s | tail -c 7)}"
CONTAINER="${TF_STATE_CONTAINER:-tfstate}"

az account show >/dev/null
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --tags workload=distributed-job-platform managed_by=bootstrap >/dev/null
az storage account create --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" --location "$LOCATION" --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 --allow-blob-public-access false >/dev/null
az storage container create --name "$CONTAINER" --account-name "$STORAGE_ACCOUNT" --auth-mode login >/dev/null

printf '%s\n' \
  "resource_group_name  = \"$RESOURCE_GROUP\"" \
  "storage_account_name = \"$STORAGE_ACCOUNT\"" \
  "container_name       = \"$CONTAINER\"" \
  'key                  = "prod.tfstate"' \
  'use_azuread_auth      = true' > infra/backend.hcl

echo "Created encrypted Terraform state backend in $STORAGE_ACCOUNT/$CONTAINER"
echo "Next: terraform -chdir=infra init -backend-config=backend.hcl"
