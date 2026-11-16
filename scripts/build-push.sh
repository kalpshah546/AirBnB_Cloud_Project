#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGION="${AWS_REGION:-ap-south-1}"
PROJECT="${PROJECT_NAME:-airbnb-soa-poc}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"

for service in search listing booking monolith; do
  repo="${PROJECT}-${service}"
  if ! aws ecr describe-repositories --repository-names "$repo" --region "$REGION" >/dev/null 2>&1; then
    echo "ECR repository $repo does not exist. Run the Terraform ECR bootstrap first." >&2
    exit 1
  fi
  echo "Building ${service}..."
  # linux/amd64 matches the x86_64 Amazon Linux AMI; --provenance=false keeps a plain image manifest.
  docker build --platform linux/amd64 --provenance=false \
    -f "${ROOT}/services/${service}/Dockerfile" -t "${REGISTRY}/${repo}:latest" "$ROOT"
  docker push "${REGISTRY}/${repo}:latest"
done

echo "Images pushed to ${REGISTRY}. On an existing deployment, run ./scripts/refresh-asgs.sh to replace instances and pull the new :latest images."
