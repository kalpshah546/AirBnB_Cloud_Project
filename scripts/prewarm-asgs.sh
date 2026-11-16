#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <prewarm-count> <asg-name> [<asg-name> ...]" >&2
  exit 2
fi
COUNT="$1"
shift
[[ "$COUNT" =~ ^[1-9][0-9]*$ ]] || { echo "Prewarm count must be positive" >&2; exit 2; }

for asg in "$@"; do
  aws autoscaling update-auto-scaling-group \
    --auto-scaling-group-name "$asg" \
    --min-size "$COUNT" --desired-capacity "$COUNT"
  echo "Pre-warmed $asg to at least $COUNT instances."
done

echo "After the spike, restore the normal minimum/desired size with scripts/restore-asg.sh."
