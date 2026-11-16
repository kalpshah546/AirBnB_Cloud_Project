#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${CONFIRM_DESTROY:-}" != "YES" ]]; then
  echo "This destroys the AWS PoC (ALB, EC2 ASGs, RDS, Redis, SQS, VPC, ECR)." >&2
  echo "Run with CONFIRM_DESTROY=YES $0 after saving logs/results." >&2
  exit 2
fi
cd "$ROOT/infra/terraform"
terraform destroy -var-file=terraform.tfvars
