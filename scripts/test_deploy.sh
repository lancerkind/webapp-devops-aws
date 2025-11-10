#!/usr/bin/env bash
set -euo pipefail

# Test deploy script for Terraform Elastic Beanstalk POC
# - Provisions infra with Terraform
# - Waits for environment to be reachable
# - Curls the homepage until HTTP 200 (or timeout)
# - Destroys infra by default to avoid charges (set SKIP_DESTROY=1 to keep)
#
# Prereqs:
# - Terraform installed
# - AWS credentials configured in environment (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION)
# - Optional: jq installed (fallback to plain parsing if missing)
#
# Usage:
#   ./scripts/test_deploy.sh
#   SKIP_DESTROY=1 ./scripts/test_deploy.sh   # keep resources for inspection
#   TF_VAR_project_name=myproj TF_VAR_environment=dev ./scripts/test_deploy.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
TF_DIR="${ROOT_DIR}/terraform"

# Controls
SKIP_DESTROY="${SKIP_DESTROY:-0}"     # 1 to skip destroy, default 0 (destroy)
APPLY_AUTO_APPROVE="${APPLY_AUTO_APPROVE:-1}"

# Health check settings
MAX_WAIT_SECONDS="${MAX_WAIT_SECONDS:-900}"  # 15 minutes
SLEEP_SECONDS="${SLEEP_SECONDS:-20}"

log() { echo "[test-deploy] $*"; }
err() { echo "[test-deploy][ERROR] $*" >&2; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }

# Require remote backend secrets to be set; do not run with local backend
if [[ -z "${TF_STATE_BUCKET:-}" || -z "${TF_LOCK_TABLE:-}" ]]; then
  err "Required backend env vars are missing: TF_STATE_BUCKET and/or TF_LOCK_TABLE."
  err "Skipping Terraform commands. Set github secrets TF_STATE_BUCKET and TF_LOCK_TABLE (and AWS_REGION) per README, then retry."
  exit 1
fi

# Initialize and apply
log "Running terraform init..."
INIT_FLAGS=("-upgrade" "-input=false")
# Configure S3 backend (required)
BACKEND_REGION="${AWS_REGION:-${TF_VAR_aws_region:-us-east-1}}"
STATE_KEY_VALUE="${TF_STATE_KEY:-global/terraform.tfstate}"
INIT_FLAGS+=(
  "-backend-config=bucket=${TF_STATE_BUCKET}"
  "-backend-config=key=${STATE_KEY_VALUE}"
  "-backend-config=region=${BACKEND_REGION}"
  "-backend-config=dynamodb_table=${TF_LOCK_TABLE}"
  "-backend-config=encrypt=true"
)
log "Using S3 backend bucket=${TF_STATE_BUCKET}, key=${STATE_KEY_VALUE}, region=${BACKEND_REGION}, table=${TF_LOCK_TABLE}"
terraform -chdir="${TF_DIR}" init "${INIT_FLAGS[@]}" 1>/dev/null

log "Running terraform validate..."
terraform -chdir="${TF_DIR}" validate

log "Running terraform plan..."
terraform -chdir="${TF_DIR}" plan -input=false -out=tfplan

log "Applying infrastructure (this may take several minutes)..."
APPLY_FLAGS=("-input=false")
if [[ "${APPLY_AUTO_APPROVE}" == "1" ]]; then
  APPLY_FLAGS+=("-auto-approve")
fi
terraform -chdir="${TF_DIR}" apply "${APPLY_FLAGS[@]}" tfplan || {
  err "terraform apply failed"
  exit 1
}

# Obtain Beanstalk URL from outputs
log "Retrieving Beanstalk environment URL from Terraform outputs..."
URL=""
if have_cmd jq; then
  URL=$(terraform -chdir="${TF_DIR}" output -json beanstalk_environment_url | jq -r '.')
else
  # Fallback: raw output (Terraform 0.12+ supports -raw)
  set +e
  URL=$(terraform -chdir="${TF_DIR}" output -raw beanstalk_environment_url 2>/dev/null)
  CODE=$?
  set -e
  if [[ $CODE -ne 0 || -z "${URL}" ]]; then
    # Last resort: parse standard output
    URL=$(terraform -chdir="${TF_DIR}" output beanstalk_environment_url | awk '{print $NF}')
  fi
fi

if [[ -z "${URL}" ]]; then
  err "Failed to obtain Beanstalk URL from outputs."
  [[ "${SKIP_DESTROY}" == "1" ]] || (log "Destroying due to failure..." && terraform -chdir="${TF_DIR}" destroy -auto-approve || true)
  exit 1
fi

# Ensure scheme
if [[ "${URL}" != http*://* ]]; then
  URL="http://${URL}"
fi

log "Beanstalk URL: ${URL}"

# Health check loop
log "Waiting for environment to become healthy and serve HTTP 200..."
START_TS=$(date +%s)
ATTEMPT=0
until [[ $(($(date +%s) - START_TS)) -ge ${MAX_WAIT_SECONDS} ]]; do
  ATTEMPT=$((ATTEMPT+1))
  set +e
  HTTP_CODE=$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 30 "${URL}")
  CURL_CODE=$?
  set -e
  if [[ ${CURL_CODE} -eq 0 && "${HTTP_CODE}" == "200" ]]; then
    log "Health check succeeded (HTTP 200) on attempt ${ATTEMPT}."
    SUCCESS=1
    break
  else
    log "Attempt ${ATTEMPT}: Not ready yet (curl_code=${CURL_CODE}, http=${HTTP_CODE:-n/a}). Sleeping ${SLEEP_SECONDS}s..."
    sleep "${SLEEP_SECONDS}"
  fi
  SUCCESS=0
done

if [[ "${SUCCESS:-0}" -ne 1 ]]; then
  err "Health check did not succeed within ${MAX_WAIT_SECONDS}s."
  RESULT=1
else
  RESULT=0
fi

# Cleanup
if [[ "${SKIP_DESTROY}" == "1" ]]; then
  log "Skipping destroy (SKIP_DESTROY=1). Remember to clean up to avoid charges."
else
  log "Destroying infrastructure to avoid charges..."
  terraform -chdir="${TF_DIR}" destroy -auto-approve || err "Destroy encountered errors; manual cleanup may be required."
fi

exit ${RESULT}
