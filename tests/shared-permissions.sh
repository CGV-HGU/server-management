#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_log_contains() {
    local log_file="$1"
    local expected="$2"

    grep -Fq -- "$expected" "$log_file" || fail "Expected '$expected' in $log_file"
}

file_mode() {
    local path="$1"

    if stat -c '%a' "$path" >/dev/null 2>&1; then
        stat -c '%a' "$path"
    else
        stat -f '%Lp' "$path"
    fi
}

DATA_DIR="$TEST_ROOT/data"
SHARED_DIR="$DATA_DIR/shared"
PRIVATE_DIR="$DATA_DIR/private"
CONFIG_FILE="$TEST_ROOT/etc/default/lab-manage"
INSTALL_PATH="$TEST_ROOT/usr/local/bin/lab-manage"
STUB_DIR="$TEST_ROOT/stubs"
CHMOD_LOG="$TEST_ROOT/chmod.log"
ACL_LOG="$TEST_ROOT/setfacl.log"
SHARED_ACL='u::rwx,g::rwx,m::rwx,o::rwx,d:u::rwx,d:g::rwx,d:m::rwx,d:o::rwx'

mkdir -p "$SHARED_DIR/nested/deeper" "$STUB_DIR" "$(dirname "$INSTALL_PATH")"
printf 'plain\n' > "$SHARED_DIR/plain.txt"
printf '#!/bin/sh\n' > "$SHARED_DIR/executable.sh"
chmod 600 "$SHARED_DIR/plain.txt"
chmod 700 "$SHARED_DIR/executable.sh"

for command_name in useradd userdel usermod passwd getent crontab groupadd mountpoint; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB_DIR/$command_name"
    chmod +x "$STUB_DIR/$command_name"
done

cat > "$STUB_DIR/chmod" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$LAB_MANAGE_TEST_CHMOD_LOG"
exec /bin/chmod "$@"
EOF
chmod +x "$STUB_DIR/chmod"

cat > "$STUB_DIR/setfacl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$LAB_MANAGE_TEST_ACL_LOG"
if [[ -n "${LAB_MANAGE_REAL_SETFACL:-}" ]]; then
    exec "$LAB_MANAGE_REAL_SETFACL" "$@"
fi
EOF
chmod +x "$STUB_DIR/setfacl"

: > "$CHMOD_LOG"
: > "$ACL_LOG"

LAB_MANAGE_REAL_SETFACL="$(command -v setfacl || true)" \
LAB_MANAGE_TEST_CHMOD_LOG="$CHMOD_LOG" \
LAB_MANAGE_TEST_ACL_LOG="$ACL_LOG" \
LAB_MANAGE_TEST_SKIP_ROOT=1 \
LAB_MANAGE_DATA_DIR="$DATA_DIR" \
LAB_MANAGE_CONFIG_FILE="$CONFIG_FILE" \
LAB_MANAGE_INSTALL_PATH="$INSTALL_PATH" \
PATH="$STUB_DIR:$PATH" \
bash "$REPO_ROOT/install.sh" >/dev/null

assert_log_contains "$CHMOD_LOG" "2777"
assert_log_contains "$CHMOD_LOG" "$SHARED_DIR/nested"
assert_log_contains "$CHMOD_LOG" "a+rw"
assert_log_contains "$CHMOD_LOG" "$SHARED_DIR/plain.txt"
assert_log_contains "$ACL_LOG" "$SHARED_ACL"
assert_log_contains "$ACL_LOG" "$SHARED_DIR"
assert_log_contains "$ACL_LOG" "$SHARED_DIR/nested"

[[ ! -x "$SHARED_DIR/plain.txt" ]] || fail "Installer made a regular data file executable"
[[ -x "$SHARED_DIR/executable.sh" ]] || fail "Installer removed an existing executable bit"

if [[ -n "${LAB_MANAGE_REAL_SETFACL:-}" ]]; then
    (
        umask 077
        printf 'new\n' > "$SHARED_DIR/new-file.txt"
        mkdir "$SHARED_DIR/new-directory"
    )
    [[ "$(file_mode "$SHARED_DIR/new-file.txt")" == "666" ]] || fail "Default ACL did not create a mode 666 file"
    [[ "$(file_mode "$SHARED_DIR/new-directory")" == "2777" ]] || fail "Default ACL did not create a mode 2777 directory"
fi

: > "$CHMOD_LOG"
: > "$ACL_LOG"

(
    export LAB_MANAGE_CONFIG_FILE="$TEST_ROOT/missing-runtime-config"
    export LAB_MANAGE_TEST_SKIP_ROOT=1
    export LAB_MANAGE_DATA_DIR="$DATA_DIR"
    export LAB_MANAGE_SHARED_DIR="$SHARED_DIR"
    export LAB_MANAGE_PRIVATE_DIR="$PRIVATE_DIR"
    export LAB_MANAGE_HOME_BASE_DIR="$TEST_ROOT/home"
    export LAB_MANAGE_TEST_CHMOD_LOG="$CHMOD_LOG"
    export LAB_MANAGE_TEST_ACL_LOG="$ACL_LOG"
    export LAB_MANAGE_REAL_SETFACL="$(command -v setfacl || true)"
    export PATH="$STUB_DIR:$PATH"

    # shellcheck source=../lab-manage
    source "$REPO_ROOT/lab-manage"

    mkdir -p "$LAB_MANAGE_HOME_BASE_DIR/testuser"
    ensure_shared_dir
    setup_storage testuser
)

assert_log_contains "$CHMOD_LOG" "2777 $SHARED_DIR"
assert_log_contains "$ACL_LOG" "$SHARED_ACL $SHARED_DIR"
if grep -Fq -- "$SHARED_DIR/nested" "$ACL_LOG"; then
    fail "lab-manage recursively scanned the shared tree"
fi
[[ "$(file_mode "$PRIVATE_DIR/testuser")" == "700" ]] || fail "Private user directory is not mode 700"

echo "PASS: shared and private permission policies"
