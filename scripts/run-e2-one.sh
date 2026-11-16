#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${BASE_URL:?Set BASE_URL to the ALB URL}"
: "${STRATEGY:?Set STRATEGY to none, target, step, or scheduled}"
: "${RUN_NUMBER:?Set RUN_NUMBER to 1, 2, or 3}"
mkdir -p "$ROOT/results/raw"

k6 run -e BASE_URL="$BASE_URL" \
  --summary-export "$ROOT/results/raw/e2_strategy_${STRATEGY}_run_${RUN_NUMBER}.json" \
  "$ROOT/loadtest/k6/holiday-spike.js"
