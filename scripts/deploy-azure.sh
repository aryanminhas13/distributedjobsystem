#!/bin/sh
set -eu

command -v az >/dev/null || { echo "Azure CLI is required" >&2; exit 1; }
command -v terraform >/dev/null || { echo "Terraform >=1.8 is required" >&2; exit 1; }
az account show >/dev/null || { echo "Run: az login" >&2; exit 1; }
[ -f infra/backend.hcl ] || { echo "Run scripts/bootstrap-terraform-state.sh first" >&2; exit 1; }
[ -f infra/terraform.tfvars ] || cp infra/terraform.tfvars.example infra/terraform.tfvars

terraform -chdir=infra init -backend-config=backend.hcl
terraform -chdir=infra fmt -check
terraform -chdir=infra validate
terraform -chdir=infra plan -out=deployment.tfplan

echo "Plan created at infra/deployment.tfplan. Review it, then run:"
echo "terraform -chdir=infra apply deployment.tfplan"
