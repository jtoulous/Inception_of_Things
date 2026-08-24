#!/usr/bin/env bash
#
# setup.sh - provision the "iot" VM for Inception-of-Things.
#
# Runs INSIDE the VM; `make build` at the repo root calls it over SSH. It
# installs the strict minimum the project needs: Vagrant with the libvirt/KVM
# provider, and kubectl. The K3s nodes are libvirt guests nested inside here.
#
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO="sudo"
USER_NAME="${SUDO_USER:-$(id -un)}"

. /etc/os-release
CODENAME="${VERSION_CODENAME:-trixie}"
ARCH="$(dpkg --print-architecture)"

# Vagrant needs KVM, which needs the CPU flag to reach this VM. If it is
# missing, the domain lacks <cpu mode="host-passthrough"/> - see the Makefile.
grep -qE 'vmx|svm' /proc/cpuinfo || {
    echo "ERROR: no vmx/svm flag - this VM is not getting nested virtualization." >&2
    exit 1
}

echo ">>> Base tools (build-essential also builds the vagrant-libvirt gem)..."
$SUDO apt-get update -qq
$SUDO apt-get install -y curl ca-certificates gnupg build-essential

echo ">>> HashiCorp repository (Debian's own vagrant package is too old)..."
curl -fsSL https://apt.releases.hashicorp.com/gpg \
    | $SUDO gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
curl -fsI "https://apt.releases.hashicorp.com/dists/${CODENAME}/Release" >/dev/null 2>&1 \
    || { echo "    no ${CODENAME} suite upstream, falling back to bookworm"; CODENAME=bookworm; }
echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${CODENAME} main" \
    | $SUDO tee /etc/apt/sources.list.d/hashicorp.list >/dev/null

echo ">>> Vagrant, qemu/libvirt, and the headers ruby-libvirt compiles against..."
$SUDO apt-get update -qq
$SUDO apt-get install -y vagrant \
    qemu-system-x86 qemu-utils libvirt-daemon-system libvirt-clients dnsmasq-base \
    ruby-dev pkg-config libvirt-dev
$SUDO systemctl enable --now libvirtd
$SUDO usermod -aG libvirt,kvm "$USER_NAME"

echo ">>> vagrant-libvirt plugin..."
vagrant plugin list 2>/dev/null | grep -q vagrant-libvirt \
    || vagrant plugin install vagrant-libvirt

echo ">>> kubectl..."
KVER="$(curl -Ls https://dl.k8s.io/release/stable.txt)"
curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl"
$SUDO install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
rm -f /tmp/kubectl

echo
echo ">>> Done:"
vagrant --version
virsh --version
kubectl version --client 2>/dev/null | head -1
