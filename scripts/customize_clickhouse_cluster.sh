#!/bin/bash

# Idempotently parameterize the ClickHouse `{cluster}` server-macro into a Liquibase
# parameter (${ANALYTICS_DB_CLUSTER_NAME}) so analytics migrations run on managed
# ClickHouse (e.g. Alibaba Cloud) which does not expose a `cluster` macro.
#
# Run after every upstream sync/rebase to parameterize newly-added migrations.
# Idempotent: files already using the parameter are left untouched (pattern no longer matches).
#
# Usage: scripts/customize_clickhouse_cluster.sh

set -eu

DIR="apps/opik-backend/src/main/resources/liquibase/db-app-analytics/migrations"

# GNU sed (Linux/CI) uses `-i`; BSD sed (macOS) needs `-i ''`.
if sed --version >/dev/null 2>&1; then
  sedi() { sed -i "$@"; }
else
  sedi() { sed -i '' "$@"; }
fi

changed=0
while IFS= read -r f; do
  if grep -q "ON CLUSTER '{cluster}'" "$f"; then
    sedi "s/ON CLUSTER '{cluster}'/ON CLUSTER '\${ANALYTICS_DB_CLUSTER_NAME}'/g" "$f"
    echo "  parameterized: $(basename "$f")"
    changed=$((changed + 1))
  fi
done < <(find "$DIR" -name '*.sql' | sort)

residual=$(grep -rl "ON CLUSTER '{cluster}'" "$DIR" 2>/dev/null | wc -l | tr -d ' ')
echo "Done. Parameterized ${changed} file(s). Residual raw '{cluster}': ${residual}"
[ "$residual" = "0" ]
