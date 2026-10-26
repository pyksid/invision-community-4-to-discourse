#!/bin/sh
# Copies ipboard4.rb into the Discourse checkout, archives the previous log and runs the import in the
# discourse_dev container, then waits for it to end (with caffeinate on macOS, as a sleeping Mac pauses
# the containers) and prints the summary lines. Usage: bench/import.sh [--no-wait]
set -e
BENCH_DIR=$(cd "$(dirname "$0")" && pwd)
DISCOURSE_DIR=${DISCOURSE_DIR:-$HOME/ipb-dump/discourse}
CONTAINER=${CONTAINER:-discourse_dev}

# A single-file bind mount goes stale when an editor replaces the file, so the script is copied instead
cp "$BENCH_DIR/../ipboard4.rb" "$DISCOURSE_DIR/script/import_scripts/ipboard4_bench.rb"
cp "$BENCH_DIR/run_import.sh" "$DISCOURSE_DIR/tmp/run_import.sh"
chmod +x "$DISCOURSE_DIR/tmp/run_import.sh"
[ -f "$DISCOURSE_DIR/tmp/import.log" ] && mv "$DISCOURSE_DIR/tmp/import.log" "$DISCOURSE_DIR/tmp/import-$(date +%Y%m%d-%H%M%S).log"

docker exec -d -u discourse:discourse -w /src \
    -e IMPORT=1 \
    -e DB_HOST=host.docker.internal -e DB_PORT="${DB_PORT:-3307}" -e DB_USER="${DB_USER:-root}" -e DB_PW="${DB_PW:-local}" \
    -e DB_NAME="${DB_NAME:-ipb}" -e TABLE_PREFIX="${TABLE_PREFIX:-ips_}" -e UPLOADS_DIR=/ipb-uploads \
    -e LD_PRELOAD=/usr/lib/libjemalloc.so -e RUBY_GLOBAL_METHOD_CACHE_SIZE=131072 \
    -e RAILS_DISABLE_ACTIVERECORD_LOGS=1 -e DISCOURSE_DEV_LOG_LEVEL=warn \
    "$CONTAINER" tmp/run_import.sh
echo "Import started, log in $DISCOURSE_DIR/tmp/import.log"

[ "$1" = "--no-wait" ] && exit 0

wait_cmd="until grep -q '^EXIT' '$DISCOURSE_DIR/tmp/import.log' 2>/dev/null; do sleep 30; done"
if command -v caffeinate >/dev/null; then caffeinate -i sh -c "$wait_cmd"; else sh -c "$wait_cmd"; fi

grep -E "imported|processed|archived|fixed|removed|Failed|Error|^=== RUN|^EXIT" "$DISCOURSE_DIR/tmp/import.log" | grep -v "^MySQL Query Error: Table '.*cms_custom_database_1'"
