#!/bin/sh
# Runs inside the Discourse container (see import.sh). Re-runs the import until it exits cleanly, as every
# phase skips what is already imported, and ends tmp/import.log with "EXIT <code>".
cd /src || exit 1
run=1
while [ $run -le 10 ]; do
    echo "=== RUN $run $(date +%H:%M)" >> tmp/import.log
    bundle exec ruby script/import_scripts/ipboard4_bench.rb >> tmp/import.log 2>&1
    code=$?
    echo "=== RUN $run exited with $code at $(date +%H:%M)" >> tmp/import.log
    [ $code -eq 0 ] && break
    run=$((run + 1))
done
echo "EXIT $code" >> tmp/import.log
