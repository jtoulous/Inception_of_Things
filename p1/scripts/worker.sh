#!/bin/bash
set -euo pipefail
SERVER_IP="$1"
NODE_IP="$2"
TOKEN="$3"

# Find network interface by ip
IFACE="$(ip -o -4 addr show | grep -w "$NODE_IP" | awk '{print $2}')"

apt-get update -qq && apt-get install -y -qq curl

# Wait for the server's API to accept connections before joining
echo ">>> Waiting for the K3s API at ${SERVER_IP}:6443..."
for _ in $(seq 1 60); do
    timeout 2 bash -c "</dev/tcp/${SERVER_IP}/6443" 2>/dev/null && break
    sleep 3
done

echo ">>> Installing K3s agent (worker) on ${NODE_IP}, joining ${SERVER_IP} (iface ${IFACE})..."
curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_START=true \
    K3S_URL="https://${SERVER_IP}:6443" \
    K3S_TOKEN="${TOKEN}" \
    INSTALL_K3S_EXEC="agent \
    --node-ip=${NODE_IP} \
    --flannel-iface=${IFACE}" sh -

# Start the agent in the background so it registers with the server
systemctl start --no-block k3s-agent
echo ">>> k3s-agent launched; it will register with the server shortly."
