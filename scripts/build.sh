#!/usr/bin/env bash
# Builds the root and stub binaries for linux/amd64 (the target platform
# per the spec: "x86 statically linked... ELF executable binary").
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${REPO_ROOT}/dist"

mkdir -p "${DIST_DIR}"

for svc in root stub; do
  echo "==> building ${svc}"
  (
    cd "${REPO_ROOT}/services/${svc}"
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o "${DIST_DIR}/${svc}" .
  )
  echo "==> built ${DIST_DIR}/${svc}"
done

echo "==> done. Binaries are in ${DIST_DIR}/"
