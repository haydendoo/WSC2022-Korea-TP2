#!/usr/bin/env bash
# refund-notifier.sh - Request Exception Handling for WSC2022 TP53 Day 2.
#
# Per the spec: "Throughout the day at random intervals, you will receive
# a request... identifies a customer request for a refund on a Unicorn
# Rental purchase... Every time one of these requests is received, you
# should send it to the audit system using an HTTP POST call."
#
# The root/stub services write each refund/exception request as an object
# in your S3 bucket (the "Bucket" config value, matching the "Request
# Exception Logs" arrow in the spec's architecture diagram); this script
# polls that bucket, and for every object it hasn't already reported, POSTs
# it to your GameDay's audit endpoint:
#
#   curl -i -H "Accept: application/json" -X POST \
#     -d '{"id": "PARTICIPANT_ID", "order":"REQUEST_UUID"}' \
#     <audit endpoint URL>
#
# PARTICIPANT_ID and the audit endpoint URL are shown on your dashboard -
# PARTICIPANT_ID is how the audit endpoint knows which participant to
# credit, so it must be the exact value shown there.
#
# The order UUID is read from each object's CONTENT (not its key) since
# the spec describes the UUID as "an example content of this object", and
# key-naming is not guaranteed.
#
# Requires: aws cli (configured/authenticated), curl.

set -euo pipefail

DEFAULT_INTERVAL=30
DEFAULT_STATE_FILE="${HOME}/.unicorn-gameday/refund-notifier.state"

usage() {
  cat <<EOF
refund-notifier.sh - poll an S3 bucket for refund/exception requests and
report each one to your GameDay's audit endpoint.

USAGE:
  refund-notifier.sh --bucket BUCKET --id PARTICIPANT_ID --endpoint URL [options]

REQUIRED:
  -b, --bucket BUCKET      S3 bucket that receives refund/exception records
  -p, --id PARTICIPANT_ID  Your participant ID, shown on your dashboard -
                           identifies which participant to credit
  -e, --endpoint URL        Audit endpoint URL, shown on your dashboard

OPTIONS:
  -i, --interval SECONDS   Poll interval in seconds (default: ${DEFAULT_INTERVAL})
  -s, --state-file PATH    File tracking already-reported object keys
                           (default: ${DEFAULT_STATE_FILE})
      --once                Poll once and exit, instead of looping forever
      --dry-run             Print what would be sent, without calling curl
                            or updating the state file
  -h, --help                Show this help message and exit

EXAMPLE:
  refund-notifier.sh --bucket unicorn-us-es-ws-1903 \\
    --id 3f9c2b3e-1a2d-4e5f-8a9b-0c1d2e3f4a5b \\
    --endpoint https://gameday.example.com/api/gameday/refund
EOF
}

BUCKET=""
PARTICIPANT_ID=""
ENDPOINT=""
INTERVAL="${DEFAULT_INTERVAL}"
STATE_FILE="${DEFAULT_STATE_FILE}"
RUN_ONCE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--bucket) BUCKET="$2"; shift 2 ;;
    -p|--id) PARTICIPANT_ID="$2"; shift 2 ;;
    -e|--endpoint) ENDPOINT="$2"; shift 2 ;;
    -i|--interval) INTERVAL="$2"; shift 2 ;;
    -s|--state-file) STATE_FILE="$2"; shift 2 ;;
    --once) RUN_ONCE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -z "${BUCKET}" ]] && { echo "error: --bucket is required" >&2; exit 1; }
[[ -z "${PARTICIPANT_ID}" ]] && { echo "error: --id is required" >&2; exit 1; }
[[ -z "${ENDPOINT}" ]] && { echo "error: --endpoint is required" >&2; exit 1; }

command -v aws >/dev/null 2>&1 || { echo "error: aws cli not found on PATH" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "error: curl not found on PATH" >&2; exit 1; }

mkdir -p "$(dirname "${STATE_FILE}")"
touch "${STATE_FILE}"

log() { printf '%s %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"; }

already_reported() {
  grep -qxF "$1" "${STATE_FILE}"
}

report_order() {
  local key="$1" order_id="$2"
  local payload
  payload=$(printf '{"id": "%s", "order":"%s"}' "${PARTICIPANT_ID}" "${order_id}")

  if "${DRY_RUN}"; then
    log "[dry-run] would POST ${payload} to ${ENDPOINT} (key=${key})"
    return 0
  fi

  local http_code
  http_code=$(curl -s -o /tmp/refund-notifier-response.txt -w '%{http_code}' \
    -H "Accept: application/json" -X POST -d "${payload}" "${ENDPOINT}")

  if [[ "${http_code}" =~ ^2 ]]; then
    log "reported order ${order_id} (key=${key}) -> HTTP ${http_code}: $(cat /tmp/refund-notifier-response.txt 2>/dev/null)"
    echo "${key}" >> "${STATE_FILE}"
  else
    log "WARN: failed to report order ${order_id} (key=${key}) -> HTTP ${http_code}: $(cat /tmp/refund-notifier-response.txt 2>/dev/null)"
  fi
}

poll_once() {
  local keys
  keys=$(aws s3api list-objects-v2 --bucket "${BUCKET}" --query 'Contents[].Key' --output text 2>/dev/null || true)

  if [[ -z "${keys}" || "${keys}" == "None" ]]; then
    return 0
  fi

  local key order_id
  for key in ${keys}; do
    already_reported "${key}" && continue

    if aws s3api get-object --bucket "${BUCKET}" --key "${key}" /tmp/refund-notifier-object.txt >/dev/null 2>&1; then
      order_id=$(tr -d '[:space:]' < /tmp/refund-notifier-object.txt)
    else
      order_id=""
    fi

    if [[ -z "${order_id}" ]]; then
      log "WARN: could not read content of s3://${BUCKET}/${key}, skipping"
      continue
    fi

    report_order "${key}" "${order_id}"
  done
}

log "watching s3://${BUCKET} for refund/exception requests (id=${PARTICIPANT_ID} endpoint=${ENDPOINT})"

if "${RUN_ONCE}"; then
  poll_once
else
  while true; do
    poll_once
    sleep "${INTERVAL}"
  done
fi
