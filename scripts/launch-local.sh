#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
docker compose up --build -d
echo "Local API: http://localhost:8080"
echo "Health:    http://localhost:8080/health"
echo "Search:    http://localhost:8080/search?city=Goa"
echo "Listing:   http://localhost:8080/listings/1"
echo "Monolith:  http://localhost:8080/monolith/search?city=Goa"
