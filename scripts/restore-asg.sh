#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <asg-name> <min> <desired> <max>" >&2
  exit 2
fi
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name "$1" \
  --min-size "$2" --desired-capacity "$3" --max-size "$4"
echo "Restored $1 capacity: min=$2 desired=$3 max=$4"
