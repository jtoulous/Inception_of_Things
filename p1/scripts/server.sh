#!/bin/bash
set -euo pipefail
NODE_IP="$1"
TOKEN="$2"

# Private-network interface name varies by box/provider - find it by IP.
IFACE="$(ip -o -4 addr show | grep -w "$NODE_IP" | awk '{print $2}')"

# --- CentOS prep for K3s (provisioner runs as root) ---
setenforce 0 2>/dev/null || true                                        # SELinux -> permissive
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config 2>/dev/null || true
systemctl disable --now firewalld 2>/dev/null || true                   # firewalld blocks K3s ports
mkdir -p /etc/NetworkManager/conf.d                                     # stop NM managing CNI ifaces
cat > /etc/NetworkManager/conf.d/k3s.conf <<'EOF'
[keyfile]
unmanaged-devices=interface-name:cni0;interface-name:flannel*
EOF
systemctl reload NetworkManager 2>/dev/null || true

echo ">>> Installing K3s server (controller) on ${NODE_IP} (iface ${IFACE})..."
curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_SELINUX_RPM=true INSTALL_K3S_EXEC="server \
  --node-ip=${NODE_IP} \
  --flannel-iface=${IFACE} \
  --write-kubeconfig-mode=644 \
  --tls-san=${NODE_IP} \
  --token=${TOKEN} \
  --disable=traefik \
  --disable=servicelb \
  --disable=metrics-server" sh -

# Make kubectl usable for the vagrant user (idempotent: retries re-provision)
grep -q KUBECONFIG /home/vagrant/.bashrc \
    || echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> /home/vagrant/.bashrc
