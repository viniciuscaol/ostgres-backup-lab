#!/usr/bin/env bash
# Shared helpers; scripts are invoked with bash, not sourced by the user.
set -Eeuo pipefail
umask 077
LAB_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export LAB_ROOT
export PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-5}"
log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }
restore_cmd() {
    env PGHOST="${RESTORE_HOST:?}" PGPORT="${RESTORE_PORT:-5432}" \
        PGUSER="${RESTORE_USER:?}" PGPASSWORD="${RESTORE_PASSWORD:?}" \
        PGDATABASE=postgres "$@"
}
check_restore_target() {
    # This lab deliberately allows only its dedicated Compose restore service.
    [[ ${RESTORE_HOST:-} == restore-db && ${RESTORE_PORT:-5432} == 5432 ]] ||
        die 'Restore target must be the dedicated restore-db:5432 lab service'
    [[ ${PGHOST:-} != restore-db ]] || die 'Source cannot be the restore service'
}
