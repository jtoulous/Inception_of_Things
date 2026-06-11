#!/bin/bash
set -euo pipefail
SERVER_IP="$1"
NODE_IP="$2"
TOKEN="$3"

# Name of the private-network interface (the one holding our static IP).
IFACE="$(ip -o -4 addr show | awk -v p="${NODE_IP}/" 'index($4, p) == 1 {print $2; exit}')"

# --- Rocky/RHEL prep for K3s (provisioner runs as root) ---
setenforce 0 2>/dev/null || true                                       # SELinux -> permissive (now)
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config 2>/dev/null || true
systemctl disable --now firewalld 2>/dev/null || true                  # firewalld blocks K3s ports
mkdir -p /etc/NetworkManager/conf.d                                    # stop NM managing CNI ifaces
cat > /etc/NetworkManager/conf.d/k3s.conf <<'EOF'
[keyfile]
unmanaged-devices=interface-name:cni0;interface-name:flannel*
EOF
systemctl reload NetworkManager 2>/dev/null || true

echo ">>> Installing K3s agent on ${NODE_IP}, joining ${SERVER_IP} (iface ${IFACE})..."
curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_SELINUX_RPM=true \
    K3S_URL="https://${SERVER_IP}:6443" \
    K3S_TOKEN="${TOKEN}" \
    INSTALL_K3S_EXEC="agent \
        --node-ip=${NODE_IP} \
        --flannel-iface=${IFACE}" sh -
