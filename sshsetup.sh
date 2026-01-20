#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "❌ Error: Harus dijalankan sebagai root!"
    exit 1
fi

echo "==========================================="
echo "    🛡️ Alxzy SSH Access Fixer 🛡️"
echo "    Ensuring Root & Password Access"
echo "==========================================="

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_D_DIR="/etc/ssh/sshd_config.d"

if ! dpkg -l | grep -q openssh-server; then
    apt update && apt install -y openssh-server
fi

cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.$(date +%s)"

if [ -d "$SSHD_D_DIR" ]; then
    echo "Cleaning configuration in $SSHD_D_DIR..."
    find "$SSHD_D_DIR" -type f -exec sed -i 's/^#\?\s*PasswordAuthentication .*/PasswordAuthentication yes/' {} +
    find "$SSHD_D_DIR" -type f -exec sed -i 's/^#\?\s*PermitRootLogin .*/PermitRootLogin yes/' {} +
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

if ! grep -q "^Subsystem\s\+sftp" "$SSHD_CONFIG"; then
    sed -i '/Subsystem\s\+sftp/d' "$SSHD_CONFIG"
    echo "Subsystem sftp /usr/lib/openssh/sftp-server" >> "$SSHD_CONFIG"
fi

echo "🔄 Restarting SSH service..."
systemctl daemon-reload
if systemctl is-active --quiet ssh; then
    systemctl restart ssh
elif systemctl is-active --quiet sshd; then
    systemctl restart sshd
fi

echo "✅ SSH Alxzy Fix Berhasil! Root login & Password aktif."
