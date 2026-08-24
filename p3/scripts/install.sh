#!/bin/bash
set -euo pipefail

SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO="sudo"
USER_NAME="${SUDO_USER:-$(id -un)}"

# Debian runs apt jobs of its own after boot; wait them out instead of failing
APT="-o DPkg::Lock::Timeout=300"

if ! command -v docker >/dev/null; then
    echo ">>> Installing Docker..."
    $SUDO apt-get $APT update -qq
    $SUDO apt-get $APT install -y -qq ca-certificates curl
    $SUDO install -m 0755 -d /etc/apt/keyrings
    $SUDO curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    $SUDO chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release; echo "$VERSION_CODENAME") stable" \
        | $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null
    $SUDO apt-get $APT update -qq
    $SUDO apt-get $APT install -y -qq docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin
else
    echo ">>> Docker already installed"
fi

# k3d drives the Docker socket; without this every k3d call would need sudo
$SUDO usermod -aG docker "$USER_NAME"

if ! command -v k3d >/dev/null; then
    echo ">>> Installing k3d..."
    curl -sfL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | $SUDO bash
else
    echo ">>> k3d already installed"
fi

if ! command -v kubectl >/dev/null; then
    echo ">>> Installing kubectl..."
    KVER="$(curl -Ls https://dl.k8s.io/release/stable.txt)"
    curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl"
    $SUDO install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
    rm -f /tmp/kubectl
else
    echo ">>> kubectl already installed"
fi

echo
echo ">>> Done:"
docker --version
k3d --version
kubectl version --client | head -1
