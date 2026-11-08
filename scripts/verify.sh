#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
[[ $# == 1 ]] || die 'Usage: bash scripts/verify.sh BACKUP_DIRECTORY'
check_restore_target
archive_dir="$(cd -- "$1" && pwd)"
[[ -f $archive_dir/database.dump && -f $archive_dir/database.sha256 ]] || die 'Incomplete backup'
# A digest is data, not an arbitrary filename list interpreted by sha256sum -c.
digest="$(cat -- "$archive_dir/database.sha256")"
[[ $digest =~ ^[a-f0-9]{64}$ ]] || die 'Invalid checksum format'
actual="$(sha256sum -- "$archive_dir/database.dump")"
[[ ${actual%% *} == "$digest" ]] || die 'Checksum mismatch'
pg_restore --list "$archive_dir/database.dump" >/dev/null
restore_db="verify_$(date -u +%Y%m%d%H%M%S)_${RANDOM}_${RANDOM}"
created=false
cleanup() {
    local rc=$?
    trap - EXIT
    if [[ $created == true ]]; then
        if ! restore_cmd dropdb --if-exists "$restore_db"; then
            log "ERROR: cleanup failed for $restore_db on restore-db"
            rc=1
        fi
    fi
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
restore_cmd createdb --template=template0 "$restore_db"
created=true
restore_cmd pg_restore --dbname="$restore_db" --no-owner --no-acl \
    --exit-on-error --single-transaction "$archive_dir/database.dump"
restore_cmd psql -X --no-password --dbname="$restore_db" --set=ON_ERROR_STOP=1 \
    --file="$LAB_ROOT/sql/verify.sql" >/dev/null
log "RESTORE_OK database=$restore_db devices=2 tickets=3"
