#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
check_restore_target
backup_dir="${BACKUP_DIR:-/backups}"
keep="${KEEP_BACKUPS:-3}"
[[ $keep =~ ^[1-9][0-9]{0,3}$ ]] || die 'KEEP_BACKUPS must be between 1 and 9999'
mkdir -p -- "$backup_dir"
backup_dir="$(cd -- "$backup_dir" && pwd)"
exec 9>"$backup_dir/.backup.lock"
flock -n 9 || die 'Another backup is running'
stage="$(mktemp -d "$backup_dir/.pending.XXXXXX")"
cleanup() { rm -rf -- "$stage"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
start=$SECONDS
log 'BACKUP_START'
pg_dump --no-password --format=custom --file="$stage/database.dump"
hash="$(sha256sum -- "$stage/database.dump")"
printf '%s\n' "${hash%% *}" >"$stage/database.sha256"
# Promotion and retention happen only after a real restoration and data check.
bash "$LAB_ROOT/scripts/verify.sh" "$stage"
printf 'verified_at=%s\nduration_seconds=%s\n' "$(date -u +%FT%TZ)" "$((SECONDS-start))" >"$stage/VERIFIED"
name="backup_$(date -u +%Y%m%dT%H%M%S%N)_${stage##*.}"
mv -- "$stage" "$backup_dir/$name"
log "BACKUP_OK name=$name bytes=$(stat -c %s "$backup_dir/$name/database.dump") duration_seconds=$((SECONDS-start))"
shopt -s nullglob
verified=()
for candidate in "$backup_dir"/backup_*; do
    base="${candidate##*/}"
    if [[ $base =~ ^backup_[0-9]{8}T[0-9]{15}_[[:alnum:]]{6}$ &&
          -d $candidate && ! -L $candidate && -f $candidate/VERIFIED &&
          -f $candidate/database.dump && -f $candidate/database.sha256 ]]; then
        verified+=("$candidate")
    fi
done
# Timestamp names sort chronologically in the C locale.
if (( ${#verified[@]} > keep )); then
    mapfile -t verified < <(printf '%s\n' "${verified[@]}" | LC_ALL=C sort)
    for (( i=0; i<${#verified[@]}-keep; i++ )); do
        log "RETENTION_DELETE name=${verified[i]##*/}"
        rm -rf -- "${verified[i]}"
    done
fi
