#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT/infra/terraform"
REGION="${AWS_REGION:-ap-south-1}"

if ! command -v terraform >/dev/null 2>&1 || ! command -v aws >/dev/null 2>&1; then
  echo "terraform and aws CLI are required." >&2
  exit 1
fi

mapfile -t groups < <(
  terraform -chdir="$TF_DIR" output -json autoscaling_group_names \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print("\n".join(d[k] for k in ("search","listing","booking","monolith")))'
)

for group in "${groups[@]}"; do
  [[ -n "$group" ]] || continue
  desired="$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$group" --region "$REGION" \
    --query 'AutoScalingGroups[0].DesiredCapacity' --output text)"
  if [[ "$desired" == "0" ]]; then
    echo "Skipping $group because desired capacity is zero."
    continue
  fi
  echo "Starting instance refresh for $group in $REGION..."
  aws autoscaling start-instance-refresh \
    --auto-scaling-group-name "$group" \
    --region "$REGION" \
    --preferences '{"MinHealthyPercentage":50,"MaxHealthyPercentage":200,"InstanceWarmup":180}'
done

echo "Refresh started. Monitor each ASG's Instance refresh tab and wait for healthy ALB targets."
