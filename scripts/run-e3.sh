#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${BASE_URL:?Set BASE_URL to the ALB URL}"
: "${SEARCH_ASG:?Set SEARCH_ASG to the search ASG name}"
: "${LISTING_ASG:?Set LISTING_ASG to the listing ASG name}"
: "${BOOKING_ASG:?Set BOOKING_ASG to the booking ASG name}"
: "${MONOLITH_ASG:?Set MONOLITH_ASG to the monolith ASG name}"
WAIT="${WAIT_SECONDS:-240}"
RUN_NUMBER="${RUN_NUMBER:-1}"
mkdir -p "$ROOT/results/raw"

stop_group() {
  aws autoscaling update-auto-scaling-group --auto-scaling-group-name "$1" --min-size 0 --desired-capacity 0 --max-size "${NORMAL_MAX_CAPACITY:-8}"
}
restore_soa() {
  for asg in "$SEARCH_ASG" "$LISTING_ASG" "$BOOKING_ASG"; do
    aws autoscaling update-auto-scaling-group --auto-scaling-group-name "$asg" --min-size 1 --desired-capacity 1 --max-size "${NORMAL_MAX_CAPACITY:-8}" || true
  done
  aws autoscaling update-auto-scaling-group --auto-scaling-group-name "$MONOLITH_ASG" --min-size 0 --desired-capacity 0 --max-size "${NORMAL_MAX_CAPACITY:-8}" || true
}
trap restore_soa EXIT

# SOA: three separate one-instance service fleets; the monolith fleet is off.
for asg in "$SEARCH_ASG" "$LISTING_ASG" "$BOOKING_ASG"; do
  "$ROOT/scripts/set-fixed-capacity.sh" "$asg" 1
  aws autoscaling wait group-in-service --auto-scaling-group-names "$asg"
done
stop_group "$MONOLITH_ASG"
sleep "$WAIT"
k6 run -e BASE_URL="$BASE_URL" \
  --summary-export "$ROOT/results/raw/e3_soa_run_${RUN_NUMBER}.json" \
  "$ROOT/loadtest/k6/search-isolation.js"

# Monolith: keep the total starting fleet at three instances to match the SOA run.
for asg in "$SEARCH_ASG" "$LISTING_ASG" "$BOOKING_ASG"; do stop_group "$asg"; done
"$ROOT/scripts/set-fixed-capacity.sh" "$MONOLITH_ASG" 3
aws autoscaling wait group-in-service --auto-scaling-group-names "$MONOLITH_ASG"
sleep "$WAIT"
k6 run -e BASE_URL="$BASE_URL" -e USE_MONOLITH=true \
  --summary-export "$ROOT/results/raw/e3_monolith_run_${RUN_NUMBER}.json" \
  "$ROOT/loadtest/k6/search-isolation.js"

python3 "$ROOT/analysis/compare_e3.py" \
  "$ROOT/results/raw/e3_soa_run_${RUN_NUMBER}.json" "$ROOT/results/raw/e3_monolith_run_${RUN_NUMBER}.json"
echo "E3 complete; SOA and monolith each used three app instances at test start."
