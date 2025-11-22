#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../terraform"

# Require remote backend secrets to be set; do not run with local backend
if [[ -z "${TF_STATE_BUCKET:-}" || -z "${TF_LOCK_TABLE:-}" ]]; then
  echo "[destroy][ERROR] Required backend env vars are missing: TF_STATE_BUCKET and/or TF_LOCK_TABLE." >&2
  echo "[destroy] Skipping Terraform commands. Set github secrets TF_STATE_BUCKET and TF_LOCK_TABLE (and AWS_REGION) per README, then retry." >&2
  exit 1
fi

pushd "$TF_DIR" >/dev/null
  echo "Planning destroy..."
  INIT_FLAGS=("-input=false")
  BACKEND_REGION="${AWS_REGION:-${TF_VAR_aws_region:-us-east-1}}"
  STATE_KEY_VALUE="${TF_STATE_KEY:-global/terraform.tfstate}"
  INIT_FLAGS+=(
    "-backend-config=bucket=${TF_STATE_BUCKET}"
    "-backend-config=key=${STATE_KEY_VALUE}"
    "-backend-config=region=${BACKEND_REGION}"
    "-backend-config=dynamodb_table=${TF_LOCK_TABLE}"
    "-backend-config=encrypt=true"
  )
  echo "Using S3 backend bucket=${TF_STATE_BUCKET}, key=${STATE_KEY_VALUE}, region=${BACKEND_REGION}, table=${TF_LOCK_TABLE}"

  terraform init "${INIT_FLAGS[@]}"
  terraform plan -destroy -out=tfdestroy || true
  echo "Applying destroy (auto-approve)..."
  terraform destroy -auto-approve || true
popd >/dev/null

echo "Destroy complete. Note: S3 bucket versions/objects may need manual deletion if destroy fails."
