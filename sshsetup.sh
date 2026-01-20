#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    exit 1
fi

SSHD_CONFIG="/etc/ssh/sshd_config"

if ! dpkg -l | grep -q openssh-server; then
    apt update && apt install -y openssh-server
fi

update_config() {
    local key=$1
    local value=$2
    if grep -q "^#\?\s*$key" "$SSHD_CONFIG"; then
        sed -i "s|^#\?\s*$key.*|$key $value|" "$SSHD_CONFIG"
    else
        echo "$key $value" >> "$SSHD_CONFIG"
    fi
}

update_config "Port" "22"
update_config "PermitRootLogin" "yes"
update_config "PasswordAuthentication" "yes"
update_config "PubkeyAuthentication" "yes"

systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null

echo "✅ SSH Configured on Port 22"