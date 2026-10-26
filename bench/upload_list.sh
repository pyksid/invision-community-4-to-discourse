#!/bin/sh
# Prints the UPLOADS_DIR-relative paths of the avatars (custom photos) and cover photos of the members
# imported into the bench Discourse, to copy them from the production server, e.g.:
#   bench/upload_list.sh > ~/ipb-dump/files.txt
#   ssh user@server "docker exec -i CONTAINER tar -C /path/to/uploads -cf - -T -" < ~/ipb-dump/files.txt \
#       | tar -C ~/ipb-dump/uploads -xf -
# Only paths are read from the IPB database, never personal data.
set -e
IPB_CONTAINER=${IPB_CONTAINER:-ipb-local}
CONTAINER=${CONTAINER:-discourse_dev}
TABLE_PREFIX=${TABLE_PREFIX:-ips_}
ids=$(mktemp)
trap 'rm -f "$ids"' EXIT

docker exec -u postgres "$CONTAINER" psql discourse_development -Atc \
    "SELECT value FROM user_custom_fields WHERE name = 'import_id' AND value ~ '^[0-9]+$'" > "$ids"

docker exec -i "$IPB_CONTAINER" mariadb -uroot -p"${DB_PW:-local}" "${DB_NAME:-ipb}" -N -e "
    SELECT member_id, pp_main_photo FROM ${TABLE_PREFIX}core_members WHERE pp_photo_type = 'custom' AND pp_main_photo <> ''
    UNION ALL
    SELECT member_id, pp_cover_photo FROM ${TABLE_PREFIX}core_members WHERE pp_cover_photo <> ''" |
    awk -F'\t' 'NR == FNR { imported[$1] = 1; next } ($1 in imported) { print $2 }' "$ids" - | sort -u
