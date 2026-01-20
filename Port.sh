#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    exit 1
fi

detect_iface() {
    ip route | awk '/default/ {print $5; exit}'
}

detect_public_ip() {
    curl -s ifconfig.me
}

IFACE=$(detect_iface)
PUBLIC_IP=$(detect_public_ip)
TARGET_IP="${1:-}"
PORT_START="${2:-}"

if [ -z "$TARGET_IP" ] || [ -z "$PORT_START" ]; then
    exit 1
fi

iptables -t nat -C POSTROUTING -s "$TARGET_IP" -o "$IFACE" -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -s "$TARGET_IP" -o "$IFACE" -j MASQUERADE

iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport "$PORT_START" -j DNAT --to-destination "$TARGET_IP:22"
iptables -A FORWARD -p tcp -d "$TARGET_IP" --dport 22 -j ACCEPT

iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport $((PORT_START + 1)) -j DNAT --to-destination "$TARGET_IP:80"
iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport $((PORT_START + 2)) -j DNAT --to-destination "$TARGET_IP:443"

for i in {3..9}; do
    EXT_PORT=$((PORT_START + i))
    iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport "$EXT_PORT" -j DNAT --to-destination "$TARGET_IP:$EXT_PORT"
    iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport "$EXT_PORT" -j DNAT --to-destination "$TARGET_IP:$EXT_PORT"
done

if command -v netfilter-persistent &>/dev/null; then
    netfilter-persistent save &>/dev/null
fi

echo "✅ Port $PORT_START s/d $((PORT_START + 9)) mapped to $TARGET_IP"