#!/bin/bash
# ==========================================
# Proxmox NAT Port Mapper (Universal Version)
# ==========================================
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Error: Harus dijalankan sebagai root!"
    exit 1
fi

TARGET_IP="${1:-}"
PORT_START="${2:-}"

if [ -z "$TARGET_IP" ] || [ -z "$PORT_START" ]; then
    echo "Usage: $0 <TARGET_IP> <PORT_START>"
    exit 1
fi

# 1. Pastikan IP Forwarding aktif di sistem
sysctl -w net.ipv4.ip_forward=1 > /dev/null

# 2. Fungsi untuk membersihkan rule lama agar tidak duplikat
clean_rule() {
    local table=$1
    local chain=$2
    shift 2
    iptables -t "$table" -D "$chain" "$@" 2>/dev/null || true
}

echo "🛠️ Configuring NAT for $TARGET_IP..."

# --- SSH (Port 22) ---
clean_rule nat PREROUTING -p tcp --dport "$PORT_START" -j DNAT --to-destination "$TARGET_IP:22"
iptables -t nat -A PREROUTING -p tcp --dport "$PORT_START" -j DNAT --to-destination "$TARGET_IP:22"

clean_rule FORWARD -p tcp -d "$TARGET_IP" --dport 22 -j ACCEPT
iptables -I FORWARD 1 -p tcp -d "$TARGET_IP" --dport 22 -j ACCEPT

# --- HTTP & HTTPS (Port 80 & 443) ---
# Port + 1 -> 80
clean_rule nat PREROUTING -p tcp --dport $((PORT_START + 1)) -j DNAT --to-destination "$TARGET_IP:80"
iptables -t nat -A PREROUTING -p tcp --dport $((PORT_START + 1)) -j DNAT --to-destination "$TARGET_IP:80"

# Port + 2 -> 443
clean_rule nat PREROUTING -p tcp --dport $((PORT_START + 2)) -j DNAT --to-destination "$TARGET_IP:443"
iptables -t nat -A PREROUTING -p tcp --dport $((PORT_START + 2)) -j DNAT --to-destination "$TARGET_IP:443"

# --- Additional Ports (3 - 9) ---
for i in {3..9}; do
    EXT_PORT=$((PORT_START + i))
    
    clean_rule nat PREROUTING -p tcp --dport "$EXT_PORT" -j DNAT --to-destination "$TARGET_IP:$EXT_PORT"
    iptables -t nat -A PREROUTING -p tcp --dport "$EXT_PORT" -j DNAT --to-destination "$TARGET_IP:$EXT_PORT"
    
    clean_rule FORWARD -p tcp -d "$TARGET_IP" --dport "$EXT_PORT" -j ACCEPT
    iptables -I FORWARD 1 -p tcp -d "$TARGET_IP" --dport "$EXT_PORT" -j ACCEPT
done

# --- Masquerade (Agar VPS bisa internetan) ---
# Dibuat universal tanpa -o (interface) agar tidak salah deteksi
clean_rule nat POSTROUTING -s "$TARGET_IP" -j MASQUERADE
iptables -t nat -A POSTROUTING -s "$TARGET_IP" -j MASQUERADE

# 3. Simpan perubahan (jika ada tool persistent)
if command -v netfilter-persistent &>/dev/null; then
    netfilter-persistent save &>/dev/null
fi

echo "✅ SUCCESS: Mapped $PORT_START-$((PORT_START + 9)) to $TARGET_IP"
