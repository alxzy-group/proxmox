#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    exit 1
fi

SSHD_CONFIG="/etc/ssh/sshd_config"

apt-get update
apt-get install -y openssh-server

rm -f /etc/ssh/sshd_config.d/*.conf

update_config() {
    local key=$1
    local value=$2
    sed -i "/^#\?\s*$key/d" "$SSHD_CONFIG"
    echo "$key $value" >> "$SSHD_CONFIG"
}

update_config "Port" "22"
update_config "PermitRootLogin" "yes"
update_config "PasswordAuthentication" "yes"
update_config "PubkeyAuthentication" "yes"

if command -v systemctl >/dev/null 2>&1; then
    systemctl restart ssh || systemctl restart sshd
else
    service ssh restart || /etc/init.d/ssh restart
fi
