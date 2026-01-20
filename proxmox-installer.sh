#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "❌ Error: Harus dijalankan sebagai root!"
    exit 1
fi

echo "==========================================="
echo "    🌟 Alxzy Proxmox VE Installer 🌟"
echo "    No-Subscription + SSL Fix + NAT Setup"
echo "==========================================="
sleep 2

if ! grep -qi "debian" /etc/os-release; then
    echo "❌ Error: OS harus Debian 12!"
    exit 1
fi

apt update && apt upgrade -y
apt install curl wget gnupg2 ca-certificates dnsutils -y

PUB_IP=$(curl -4 -s ifconfig.me)
HOSTNAME=$(hostname)

sed -i "/$HOSTNAME/d" /etc/hosts
echo "$PUB_IP $HOSTNAME.proxmox.com $HOSTNAME" >> /etc/hosts

if [ -f /etc/cloud/cloud.cfg ]; then
    sed -i 's/manage_etc_hosts: true/manage_etc_hosts: false/' /etc/cloud/cloud.cfg || true
fi

echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-install-repo.list

wget -q https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg -O- | gpg --dearmor -o /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg

apt update

export DEBIAN_FRONTEND=noninteractive
apt install proxmox-default-kernel -y
apt install proxmox-ve postfix open-iscsi -y

apt install --reinstall ca-certificates -y
update-ca-certificates -f

if [ -f /etc/apt/sources.list.d/pve-enterprise.list ]; then
    rm /etc/apt/sources.list.d/pve-enterprise.list
fi

if ! grep -q "vmbr1" /etc/network/interfaces; then
cat <<EOF >> /etc/network/interfaces

auto vmbr1
iface vmbr1 inet static
    address 192.168.11.1
    netmask 255.255.255.0
    bridge-ports none
    bridge-stp off
    bridge-fd 0
EOF
fi

ifup vmbr1 || true

PUB_IFACE=$(ip route | awk '/default/ {print $5}' | head -n1)
VM_SUBNET="192.168.11.0/24"

echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-proxmox-forward.conf
sysctl -p /etc/sysctl.d/99-proxmox-forward.conf

export DEBIAN_FRONTEND=noninteractive
apt-get install -y iptables-persistent netfilter-persistent

iptables -t nat -A POSTROUTING -s $VM_SUBNET -o $PUB_IFACE -j MASQUERADE
iptables -A FORWARD -i vmbr1 -o $PUB_IFACE -j ACCEPT
iptables -A FORWARD -i $PUB_IFACE -o vmbr1 -m state --state RELATED,ESTABLISHED -j ACCEPT

netfilter-persistent save

pvecm updatecerts -f || true
systemctl restart pveproxy || true

echo "-------------------------------------------------------"
echo "🎉 Alxzy Proxmox Installer SELESAI"
echo "🌍 Akses: https://$PUB_IP:8006"
echo "-------------------------------------------------------"
sleep 5
reboot
