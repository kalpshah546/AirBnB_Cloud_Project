#!/usr/bin/env bash
# One-time setup of deployment tools inside WSL Ubuntu (x86_64).
# Installs: Terraform, AWS CLI v2, AWS Session Manager plugin, k6, python3 + venv with analysis deps.
# Docker comes from Docker Desktop (Settings -> Resources -> WSL integration -> enable your distro).
#
# Usage (from the repo root):  ./scripts/install-tools-wsl.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[[ "$(uname -m)" == "x86_64" ]] || { echo "This script expects x86_64 Linux." >&2; exit 1; }

echo "==> Base packages"
sudo apt-get update -y
sudo apt-get install -y curl unzip git gnupg lsb-release ca-certificates \
  python3 python3-pip python3-venv python-is-python3

if ! command -v terraform >/dev/null 2>&1; then
  echo "==> Terraform (HashiCorp apt repo)"
  curl -fsSL https://apt.releases.hashicorp.com/gpg \
    | sudo gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  sudo apt-get update -y && sudo apt-get install -y terraform
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "==> AWS CLI v2"
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$TMP/awscliv2.zip"
  unzip -q "$TMP/awscliv2.zip" -d "$TMP"
  sudo "$TMP/aws/install" --update
fi

if ! command -v session-manager-plugin >/dev/null 2>&1; then
  echo "==> AWS Session Manager plugin (to open a shell on the k6 load-generator EC2)"
  curl -fsSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" \
    -o "$TMP/session-manager-plugin.deb"
  sudo dpkg -i "$TMP/session-manager-plugin.deb"
fi

if ! command -v k6 >/dev/null 2>&1; then
  echo "==> k6 (Grafana apt repo)"
  sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
    --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
  echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" \
    | sudo tee /etc/apt/sources.list.d/k6.list >/dev/null
  sudo apt-get update -y && sudo apt-get install -y k6
fi

echo "==> Python virtualenv for tests and analysis (.venv)"
python3 -m venv "$ROOT/.venv"
# shellcheck disable=SC1091
source "$ROOT/.venv/bin/activate"
pip install --upgrade pip >/dev/null
pip install -e "${ROOT}[test,analysis]"

echo
echo "==> Installed versions"
terraform version | head -1
aws --version
session-manager-plugin --version
k6 version
python3 --version
if docker info >/dev/null 2>&1; then
  docker --version
else
  echo "WARNING: Docker daemon not reachable from WSL. Start Docker Desktop and enable WSL integration for this distro." >&2
fi

cat <<'NEXT'

Next:
  1. aws configure                       # access key, secret, region ap-south-1, output json
  2. source .venv/bin/activate           # every new terminal, before running analysis scripts
  3. ./scripts/deploy.sh
NEXT
