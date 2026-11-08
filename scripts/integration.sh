#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
# Tests use their own backup directory and the disposable Compose fixture.
test_dir="$(mktemp -d /backups/.test.XXXXXX)"
export BACKUP_DIR="$test_dir" KEEP_BACKUPS=2
reset_fixture() {
    psql -X --set=ON_ERROR_STOP=1 -c "UPDATE tickets SET description='Verificar conectividade' WHERE id=3" >/dev/null
}
cleanup() {
    local rc=$?
    trap - EXIT
    reset_fixture || rc=1
    rm -rf -- "$test_dir"
    exit "$rc"
}
trap cleanup EXIT
count() { find "$test_dir" -maxdepth 1 -type d -name 'backup_*' | wc -l; }
expect_failure() {
    if "$@"; then die "Expected failure: $*"; fi
}
assert_clean() {
    [[ -z $(find "$test_dir" -maxdepth 1 -name '.pending.*' -print -quit) ]] || die 'Partial backup leaked'
    [[ $(restore_cmd psql -X -Atc "SELECT count(*) FROM pg_database WHERE datname LIKE 'verify_%'") == 0 ]] || die 'Temporary restore database leaked'
}
for _ in 1 2 3; do bash scripts/backup.sh; done
[[ $(count) == 2 ]] || die 'Retention did not keep exactly two backups'
mapfile -t archives < <(find "$test_dir" -maxdepth 1 -type d -name 'backup_*' | sort)
snapshot="$(printf '%s\n' "${archives[@]}")"
bash scripts/verify.sh "${archives[1]}"
assert_clean

# Arbitrary directories must never be removed by retention.
mkdir "$test_dir/backup_do-not-delete"
printf 'keep me\n' >"$test_dir/backup_do-not-delete/note"
expect_failure env KEEP_BACKUPS=0 bash scripts/backup.sh
expect_failure env PGHOST=127.0.0.1 PGPORT=1 PGCONNECT_TIMEOUT=2 bash scripts/backup.sh
[[ $(find "$test_dir" -maxdepth 1 -type d -name 'backup_20*' | sort) == "$snapshot" ]] || die 'Failure changed retained backups'

# Competing process cannot enter the backup section.
(
    exec 8>"$test_dir/.backup.lock"
    flock -n 8
    expect_failure bash scripts/backup.sh
)

# Real pg_dump succeeds, but changed fixture content must fail restoration validation.
psql -X --set=ON_ERROR_STOP=1 -c "UPDATE tickets SET description='unexpected change' WHERE id=3" >/dev/null
expect_failure bash scripts/backup.sh
reset_fixture
[[ $(find "$test_dir" -maxdepth 1 -type d -name 'backup_20*' | sort) == "$snapshot" ]] || die 'Validation failure pruned backups'
assert_clean

# Checksum failure, then a damaged archive with a recomputed checksum.
corrupt="$test_dir/corrupt"
mkdir "$corrupt"
cp "${archives[1]}"/database.* "$corrupt/"
printf 'broken\n' >>"$corrupt/database.dump"
expect_failure bash scripts/verify.sh "$corrupt"
printf 'not a PostgreSQL archive\n' >"$corrupt/database.dump"
hash="$(sha256sum "$corrupt/database.dump")"
printf '%s\n' "${hash%% *}" >"$corrupt/database.sha256"
expect_failure bash scripts/verify.sh "$corrupt"
expect_failure env RESTORE_HOST=source-db bash scripts/verify.sh "${archives[1]}"
expect_failure env PGHOST=restore-db bash scripts/verify.sh "${archives[1]}"
assert_clean

bash scripts/backup.sh
[[ -f $test_dir/backup_do-not-delete/note ]] || die 'Retention removed an unrelated directory'
[[ $(find "$test_dir" -maxdepth 1 -type d -name 'backup_20*' | wc -l) == 2 ]] || die 'Retention failed after recovery'
psql -X --set=ON_ERROR_STOP=1 --file=sql/verify.sql >/dev/null
assert_clean
log 'TESTS_OK: restore, data, retention, corruption, invalid archive, failed dump, failed validation, lock, isolation, cleanup'
