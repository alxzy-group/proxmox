#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "❌ Error: Harus dijalankan sebagai root!"
    exit 1
fi

echo "==========================================="
echo "    🌟 Alxzy Port Forwarding Manager 🌟"
echo "    NAT & Port Mapping Anti-Collision"
echo "==========================================="

detect_iface() {
    ip route | awk '/default/ {print $5; exit}'
}

detect_public_ip() {
    curl -s ifconfig.me
}

log_action() {
    echo "$(date '+%F %T') $1" >> /var/log/portsetup.log
}

find_random_free_port() {
    local START=$1
    local END=$2
    while :; do
        local PORT=$((RANDOM % (END-START+1) + START))
        if ss -ltn | awk '{print $4}' | grep -q ":$PORT$"; then
            continue
        fi
        if iptables -t nat -L PREROUTING -n | grep -q ":$PORT "; then
            continue
        fi
        if grep -q ",$PORT," "$DB_FILE" 2>/dev/null; then
            continue
        fi
        echo $PORT
        return
    done
}

save_rules() {
    if command -v netfilter-persistent &>/dev/null; then
        netfilter-persistent save &>/dev/null
        log_action "netfilter-persistent save"
    fi
}

DB_FILE="/etc/portsetup.db"
RANGE_NORMAL_START=1000
RANGE_NORMAL_END=2500
RANGE_MC_START=10000
RANGE_MC_END=10500

IFACE=$(detect_iface)
PUBLIC_IP=$(detect_public_ip)
TARGET_IP="${1:-}"

if [ -z "$TARGET_IP" ]; then
    echo "Usage: $0 <IP-privat>"
    exit 1
fi

if ! [[ "$TARGET_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "❌ Error: Format IP tidak valid!"
    exit 1
fi

if [[ "$TARGET_IP" =~ ^10\. ]] || \
   [[ "$TARGET_IP" =~ ^192\.168\. ]] || \
   ([[ "$TARGET_IP" =~ ^172\. ]] && \
    [[ "$(echo "$TARGET_IP" | cut -d. -f2)" -ge 16 ]] && \
    [[ "$(echo "$TARGET_IP" | cut -d. -f2)" -le 31 ]]); then
    echo "✅ IP privat terdeteksi: $TARGET_IP"
else
    echo "❌ Error: IP bukan dalam rentang privat (10.x, 172.16-31.x, 192.168.x)!"
    exit 1
fi

PORTS_NORMAL=(22 3000 3300 4000 5000 5173 5432 6379 8000 8080 8800 8888 3030)
PORT_MC=25565

echo "Interface: $IFACE | IP Publik: $PUBLIC_IP"
touch "$DB_FILE"

if ! iptables -t nat -C POSTROUTING -s "$TARGET_IP" -o "$IFACE" -j MASQUERADE 2>/dev/null; then
    iptables -t nat -A POSTROUTING -s "$TARGET_IP" -o "$IFACE" -j MASQUERADE
fi

for TARGET_PORT in "${PORTS_NORMAL[@]}"; do
    EXIST_LINE=$(grep ",$TARGET_IP,$TARGET_PORT," "$DB_FILE" 2>/dev/null | head -n1)
    if [ -n "$EXIST_LINE" ]; then
        EXIST_FREE_PORT=$(echo "$EXIST_LINE" | cut -d',' -f2)
        echo "➡ $PUBLIC_IP:$EXIST_FREE_PORT → $TARGET_IP:$TARGET_PORT (existing)"
        continue
    fi

    FREE_PORT=$(find_random_free_port $RANGE_NORMAL_START $RANGE_NORMAL_END)
    if [ -n "$FREE_PORT" ]; then
        iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport "$FREE_PORT" -j DNAT --to-destination "$TARGET_IP:$TARGET_PORT"
        iptables -A FORWARD -p tcp -d "$TARGET_IP" --dport "$TARGET_PORT" -j ACCEPT
        iptables -A FORWARD -p tcp -s "$TARGET_IP" --sport "$TARGET_PORT" -j ACCEPT

        echo "$PUBLIC_IP,$FREE_PORT,$TARGET_IP,$TARGET_PORT,$IFACE" >> "$DB_FILE"
        log_action "ADD $PUBLIC_IP:$FREE_PORT → $TARGET_IP:$TARGET_PORT"
        echo "➡ $PUBLIC_IP:$FREE_PORT → $TARGET_IP:$TARGET_PORT (new)"
    fi
done

EXIST_LINE_MC=$(grep ",$TARGET_IP,$PORT_MC," "$DB_FILE" 2>/dev/null | head -n1)
if [ -n "$EXIST_LINE_MC" ]; then
    EXIST_FREE_PORT_MC=$(echo "$EXIST_LINE_MC" | cut -d',' -f2)
    echo "➡ $PUBLIC_IP:$EXIST_FREE_PORT_MC → $TARGET_IP:$PORT_MC (existing)"
else
    FREE_PORT_MC=$(find_random_free_port $RANGE_MC_START $RANGE_MC_END)
    if [ -n "$FREE_PORT_MC" ]; then
        iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport "$FREE_PORT_MC" -j DNAT --to-destination "$TARGET_IP:$PORT_MC"
        iptables -A FORWARD -p tcp -d "$TARGET_IP" --dport "$PORT_MC" -j ACCEPT
        iptables -A FORWARD -p tcp -s "$TARGET_IP" --sport "$PORT_MC" -j ACCEPT

        echo "$PUBLIC_IP,$FREE_PORT_MC,$TARGET_IP,$PORT_MC,$IFACE" >> "$DB_FILE"
        log_action "ADD $PUBLIC_IP:$FREE_PORT_MC → $TARGET_IP:$PORT_MC"
        echo "➡ $PUBLIC_IP:$FREE_PORT_MC → $TARGET_IP:$PORT_MC (new)"
    fi
fi

save_rules
echo "==========================================="
echo "✅ Seluruh port telah dikonfigurasi!"
