#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${BASE_URL:?Set BASE_URL to the ALB URL}"
: "${STRATEGY:?Set STRATEGY to none, target, step, or scheduled}"
: "${RUN_NUMBER:?Set RUN_NUMBER to 1, 2, or 3}"
# Calibrate from E1: PEAK_RPS should need ~5 search instances at 50% CPU, i.e.
#   PEAK_RPS ~= (5 * 0.5 * max_rps_of_one_instance) / 0.7   (70% of traffic is search)
# Keep NORMAL_RPS at ~10% of PEAK_RPS (the 10x holiday surge). Never change these between compared runs.
NORMAL_RPS="${NORMAL_RPS:-7}"
PEAK_RPS="${PEAK_RPS:-70}"
mkdir -p "$ROOT/results/raw"
echo "E2 strategy=$STRATEGY run=$RUN_NUMBER normal=${NORMAL_RPS}rps peak=${PEAK_RPS}rps start=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  | tee -a "$ROOT/results/raw/e2_run_log.txt"

k6 run -e BASE_URL="$BASE_URL" -e NORMAL_RPS="$NORMAL_RPS" -e PEAK_RPS="$PEAK_RPS" \
  --summary-export "$ROOT/results/raw/e2_strategy_${STRATEGY}_run_${RUN_NUMBER}.json" \
  "$ROOT/loadtest/k6/holiday-spike.js"
echo "E2 strategy=$STRATEGY run=$RUN_NUMBER end=$(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "$ROOT/results/raw/e2_run_log.txt"
