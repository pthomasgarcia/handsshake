# shellcheck shell=bash
set -euo pipefail

check_health() {
    echo "Health Check:"
    local ssh_dir="$HOME/.ssh"
    local default_key="$ssh_dir/id_rsa"
    local status="OK"

    # Check .ssh directory
    if [[ -d "$ssh_dir" ]]; then
        echo "  [OK] $ssh_dir exists."
    else
        echo "  [WARNING] $ssh_dir does not exist."
        status="WARNING"
    fi

    # Check permissions
    if [[ -d "$ssh_dir" ]]; then
        local perms
        perms=$(stat -c "%a" "$ssh_dir")
        if [[ "$perms" -eq 700 ]]; then
             echo "  [OK] $ssh_dir permissions are 700."
        else
             echo "  [WARNING] $ssh_dir permissions are $perms (expected 700)."
             status="WARNING"
        fi
    fi

    # Check default key
    if [[ -f "$default_key" ]]; then
        echo "  [OK] Default key $default_key exists."
    else
        echo "  [WARNING] Default key $default_key not found."
        status="WARNING"
    fi
    
    echo "Overall Status: $status"
    return 0
}
