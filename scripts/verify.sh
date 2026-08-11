#!/usr/bin/env bash
# Sanity-checks the built root/stub binaries: --help works, and GET /
# returns HTTP 200 when run with a local config file (no AWS dependencies
# reachable). This is a smoke test for the practice binaries themselves,
# not a test of any deployed infrastructure.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${REPO_ROOT}/dist"

"${REPO_ROOT}/scripts/build.sh"

WORK_DIR="$(mktemp -d)"
trap 'kill "${ROOT_PID:-0}" "${STUB_PID:-0}" 2>/dev/null || true; rm -rf "${WORK_DIR}"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

check_help() {
  local bin="$1"
  "${DIST_DIR}/${bin}" --help >/dev/null 2>&1 || fail "${bin} --help exited non-zero"
  echo "OK: ${bin} --help"
}

check_health() {
  local bin="$1" port="$2" config="$3" pid_var="$4"
  "${DIST_DIR}/${bin}" --config "${config}" --port "${port}" >"${WORK_DIR}/${bin}.log" 2>&1 &
  local pid=$!
  printf -v "${pid_var}" '%s' "${pid}"

  local code=""
  for _ in $(seq 1 20); do
    code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${port}/" || true)"
    [[ "${code}" == "200" ]] && break
    sleep 0.25
  done

  kill "${pid}" 2>/dev/null || true
  wait "${pid}" 2>/dev/null || true

  [[ "${code}" == "200" ]] || { cat "${WORK_DIR}/${bin}.log" >&2; fail "GET / on ${bin} returned '${code}', expected 200"; }
  echo "OK: ${bin} GET / -> 200"
}

check_help root
check_help stub

cat > "${WORK_DIR}/root.json" <<'EOF'
{"RedisHost":"","RedisPort":"","FsPath":"/tmp/unicorn-gameday-verify/root/","Port":0,"Bucket":""}
EOF
cat > "${WORK_DIR}/stub.json" <<'EOF'
{"DBSecretArn":"","DBName":"","FsPath":"/tmp/unicorn-gameday-verify/stub/","Bucket":"","Port":0}
EOF

check_health root 18180 "${WORK_DIR}/root.json" ROOT_PID
check_health stub 18181 "${WORK_DIR}/stub.json" STUB_PID

echo "==> all checks passed"
