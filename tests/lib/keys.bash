# shellcheck shell=bash

# tests/lib/keys.bash

create_test_key() {
    local key_path="$1"
    local comment="${2:-}"
    local -a key_args=()

    # SECONDARY SAFETY GUARD: Never write to real HOME
    local resolved_path
    resolved_path=$(realpath "$key_path" 2>/dev/null || echo "$key_path")
    if [[ "$resolved_path" == "$REAL_HOME_FOR_GUARD"* ]]; then
        echo "FATAL SECURITY ERROR: create_test_key attempted to write to real HOME: $resolved_path" >&2
        exit 100
    fi
    
    # Path depth guard
    if [[ "$resolved_path" == "/etc/"* ]] || [[ "$resolved_path" == "/usr/"* ]] || [[ "$resolved_path" == "/var/"* ]]; then
        echo "FATAL SECURITY ERROR: create_test_key attempted to write to system directory: $resolved_path" >&2
        exit 102
    fi

    # Determine key type from filename pattern
    local base_name
    base_name=$(basename "$key_path")

    case "$base_name" in
    *ed25519*)
        key_args=(-t ed25519)
        ;;
    *ecdsa*)
        key_args=(-t ecdsa -b 521)
        ;;
    *rsa* | *)
        key_args=(-t rsa -b 2048)
        ;;
    esac

    if [[ -n "$comment" ]]; then
        ssh-keygen "${key_args[@]}" -f "$key_path" -N "" -C "$comment" >/dev/null 2>&1
    else
        ssh-keygen "${key_args[@]}" -f "$key_path" -N "" >/dev/null 2>&1
    fi
}

generate_test_identity() {
    local slug="$1"
    local algo="${2:-rsa}"
    local comment="handsshake-test-$slug"
    
    # Policy-driven pathing: Use dedicated identities folder
    local identities_dir="$BATS_TMPDIR/identities"
    mkdir -p "$identities_dir"
    
    local key_path="$identities_dir/hsh-test-$slug-$algo.identity"
    create_test_key "$key_path" "$comment"
    
    echo "$key_path"
}

verify_key_recorded() {
    local key_path="$1"
    run grep -Fq "$key_path" "$STATE_DIR/added_keys.list"
    assert_success
}

verify_key_not_recorded() {
    local key_path="$1"
    run grep -Fq "$key_path" "$STATE_DIR/added_keys.list"
    assert_failure
}

setup_readonly() {
    local path="$1"
    chmod 555 "$path"
}

teardown_readonly() {
    local path="$1"
    chmod 755 "$path" 2>/dev/null || true
}

safe_cp() {
    local src="$1"
    local dest="$2"
    local resolved_dest
    resolved_dest=$(realpath "$dest" 2>/dev/null || echo "$dest")
    if [[ "$resolved_dest" == "$REAL_HOME_FOR_GUARD"* ]]; then
        echo "FATAL SECURITY ERROR: safe_cp attempted to write to real HOME: $resolved_dest" >&2
        exit 101
    fi
    cp "$src" "$dest"
}
