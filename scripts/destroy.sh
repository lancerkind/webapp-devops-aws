#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../terraform"

pushd "$TF_DIR" >/dev/null
  echo "Planning destroy..."
  terraform init -input=false
  terraform plan -destroy -out=tfdestroy || true
  echo "Applying destroy (auto-approve)..."
  terraform destroy -auto-approve
popd >/dev/null

echo "Destroy complete. Note: S3 bucket versions/objects may need manual deletion if destroy fails."
