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
