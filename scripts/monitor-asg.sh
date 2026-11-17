#!/usr/bin/env bash
# Sample ASG/target state every INTERVAL seconds into a CSV (real measurements, UTC timestamps).
# Usage: ASG=airbnb-soa-poc-search-asg TG_ARN=... ./scripts/monitor-asg.sh results/raw/e2_asg_samples.csv
set -uo pipefail
OUT="${1:?output csv}"; ASG="${ASG:?}"; TG_ARN="${TG_ARN:?}"; REGION="${AWS_REGION:-ap-south-1}"; INTERVAL="${INTERVAL:-15}"
mkdir -p "$(dirname "$OUT")"
echo "ts_utc,desired,in_service,pending,terminating,healthy_targets,total_targets" > "$OUT"
while true; do
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  g="$(aws autoscaling describe-auto-scaling-groups --region "$REGION" --auto-scaling-group-names "$ASG" \
    --query 'AutoScalingGroups[0].[DesiredCapacity,length(Instances[?LifecycleState==`InService`]),length(Instances[?starts_with(LifecycleState,`Pending`)]),length(Instances[?starts_with(LifecycleState,`Terminating`)])]' --output text 2>/dev/null | tr '\t' ',')"
  t="$(aws elbv2 describe-target-health --region "$REGION" --target-group-arn "$TG_ARN" \
    --query '[length(TargetHealthDescriptions[?TargetHealth.State==`healthy`]),length(TargetHealthDescriptions)]' --output text 2>/dev/null | tr '\t' ',')"
  echo "$ts,${g:-,,,},${t:-,}" >> "$OUT"
  sleep "$INTERVAL"
done
