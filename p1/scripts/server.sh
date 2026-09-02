#!/bin/bash
set -euo pipefail
NODE_IP="$1"
TOKEN="$2"

# Find network interface by ip
IFACE="$(ip -o -4 addr show | grep -w "$NODE_IP" | awk '{print $2}')"

apt-get update -qq && apt-get install -y -qq curl

echo ">>> Installing K3s server (controller) on ${NODE_IP} (iface ${IFACE})..."
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
    --node-ip=${NODE_IP} \
    --flannel-iface=${IFACE} \
    --write-kubeconfig-mode=644 \
    --tls-san=${NODE_IP} \
    --token=${TOKEN} \
    --disable=traefik \
    --disable=servicelb \
    --disable=metrics-server" sh -

# Make kubectl usable for the vagrant user
grep -q KUBECONFIG /home/vagrant/.bashrc || echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> /home/vagrant/.bashrc
