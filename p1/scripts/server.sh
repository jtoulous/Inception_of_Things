#!/bin/bash
set -euo pipefail
NODE_IP="$1"
TOKEN="$2"

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

# traefik/servicelb/metrics-server are not needed for p1 and cost ~300MB -
# precious headroom on 1GB nodes inside a 6GB host VM.
echo ">>> Installing K3s server on ${NODE_IP} (iface ${IFACE})..."
curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_SELINUX_RPM=true INSTALL_K3S_EXEC="server \
    --node-ip=${NODE_IP} \
    --flannel-iface=${IFACE} \
    --write-kubeconfig-mode=644 \
    --disable=traefik --disable=servicelb --disable=metrics-server \
    --token=${TOKEN}" sh -

# Let the vagrant user run kubectl without sudo (idempotent across re-provisions).
grep -q KUBECONFIG /home/vagrant/.bashrc \
    || echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> /home/vagrant/.bashrc
