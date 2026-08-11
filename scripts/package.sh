#!/usr/bin/env bash
# Assembles dist/ - the package handed to participants: the root/stub
# binaries, their example configs, database/schema.sql, and
# refund-notifier.sh (Request Exception Handling). This mirrors what the
# spec calls "the Readme file of this game event" that bundles the
# binaries and the refund script.
#
# Also builds local Docker images for both services when Docker is
# available (not part of dist/ itself - dist/ matches what the spec
# describes participants receiving, which does not include container
# images).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${REPO_ROOT}/dist"

"${REPO_ROOT}/scripts/build.sh"

echo "==> assembling dist/"
mkdir -p "${DIST_DIR}/config" "${DIST_DIR}/database" "${DIST_DIR}/scripts"

cp "${REPO_ROOT}/config/root.example.json" "${DIST_DIR}/config/root.example.json"
cp "${REPO_ROOT}/config/stub.example.json" "${DIST_DIR}/config/stub.example.json"
cp "${REPO_ROOT}/database/schema.sql" "${DIST_DIR}/database/schema.sql"
cp "${REPO_ROOT}/scripts/refund-notifier.sh" "${DIST_DIR}/scripts/refund-notifier.sh"
chmod +x "${DIST_DIR}/scripts/refund-notifier.sh" "${DIST_DIR}/root" "${DIST_DIR}/stub"

cat > "${DIST_DIR}/README.md" <<'EOF'
# Unicorn Service - Day 2 Distribution Package

This is what you were given at the start of the competition: the `root`
and `stub` server binaries, their example configuration, the database
schema, and the refund/exception-handling script. See the Day 2 Test
Project PDF for the full task description.

## Contents

- `root`, `stub` - x86-64 Linux binaries. Run with `--help` for usage.
  Both read configuration from AWS AppConfig by default
  (`--appconfig-application` / `--appconfig-environment` /
  `--appconfig-profile`), or from a local JSON file (`--config`) shaped
  like `config/*.example.json`.
- `config/root.example.json`, `config/stub.example.json` - the
  configuration shape each service expects.
- `database/schema.sql` - creates the `unicorndb` database and the
  `unicorns` table the `stub` service requires.
- `scripts/refund-notifier.sh` - watches your S3 refund bucket and
  reports each refund/exception request to the audit endpoint. Run:

  ```
  ./scripts/refund-notifier.sh --bucket <your-bucket> --id <PARTICIPANT_ID> --endpoint <audit endpoint URL>
  ```

  `PARTICIPANT_ID` and the audit endpoint URL are shown on your dashboard.
EOF

echo "==> dist/ ready:"
find "${DIST_DIR}" -maxdepth 2 -type f | sort

if command -v docker >/dev/null 2>&1; then
  echo "==> building docker images"
  docker build -t unicorn-gameday/root:latest "${REPO_ROOT}/services/root"
  docker build -t unicorn-gameday/stub:latest "${REPO_ROOT}/services/stub"
  echo "==> built images unicorn-gameday/root:latest and unicorn-gameday/stub:latest"
else
  echo "==> docker not found, skipping image build (dist/ is still ready)"
fi
