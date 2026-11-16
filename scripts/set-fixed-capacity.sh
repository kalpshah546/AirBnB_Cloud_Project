#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <autoscaling-group-name> <instance-count>" >&2
  exit 2
fi
ASG="$1"
COUNT="$2"
[[ "$COUNT" =~ ^[1-9][0-9]*$ ]] || { echo "Count must be a positive integer" >&2; exit 2; }
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name "$ASG" \
  --min-size "$COUNT" --desired-capacity "$COUNT" --max-size "$COUNT"
echo "ASG $ASG fixed at $COUNT instances."
