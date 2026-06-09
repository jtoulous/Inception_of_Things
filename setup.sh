#!/usr/bin/env bash
#
# setup.sh - provision a fresh Debian 13 (Trixie) machine with the toolchain
#            needed for the Inception-of-Things project:
#            base build tools + libvirt/KVM + Vagrant (+ vagrant-libvirt) + kubectl.
#
# MANUAL prerequisites (host-side / VirtualBox GUI - cannot be scripted from
# inside the guest, see SETUP.md):
#   1. Create the Debian 13 VM in VirtualBox.
#   2. Devices -> Insert Guest Additions CD image, then run the installer.
#   3. (optional) Add a shared folder: auto-mount + make permanent.
#
# Run as your normal user (it calls sudo when needed):  ./setup.sh
#
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# --- run privileged commands with sudo unless we are already root ----------
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi
TARGET_USER="${SUDO_USER:-$USER}"

# vagrant plugins are per-user: install them for the real user even under sudo
as_user() { if [ "$(id -u)" -eq 0 ]; then su - "$TARGET_USER" -c "$*"; else eval "$*"; fi; }

# --- sanity: this script targets Debian -----------------------------------
. /etc/os-release
if [ "${ID:-}" != "debian" ]; then
  echo "WARNING: this script is written for Debian (found ID='${ID:-unknown}')." >&2
fi
CODENAME="${VERSION_CODENAME:-trixie}"
ARCH="$(dpkg --print-architecture)"

# --- base requirements (headers/dkms for Guest Additions, pkg-config for the
#     vagrant-libvirt native extension) --------------------------------------
echo ">>> Installing base requirements..."
$SUDO apt-get update
$SUDO apt-get install -y \
  curl wget gnupg ca-certificates \
  git make build-essential dkms pkg-config \
  linux-headers-amd64 "linux-headers-$(uname -r)"

# --- libvirt / KVM (the Vagrant provider) ----------------------------------
echo ">>> Installing libvirt / KVM..."
$SUDO apt-get install -y \
  qemu-system-x86 libvirt-daemon-system libvirt-clients \
  virtinst dnsmasq libvirt-dev
$SUDO systemctl enable --now libvirtd
$SUDO usermod -aG libvirt,kvm "$TARGET_USER"

# --- Vagrant repo ----------------------------------------------------------
echo ">>> Adding HashiCorp repository (${CODENAME})..."
curl -fsSL https://apt.releases.hashicorp.com/gpg \
  | $SUDO gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${CODENAME} main" \
  | $SUDO tee /etc/apt/sources.list.d/hashicorp.list >/dev/null

echo ">>> Installing Vagrant..."
$SUDO apt-get update
$SUDO apt-get install -y vagrant

# --- vagrant-libvirt plugin ------------------------------------------------
echo ">>> Installing the vagrant-libvirt plugin..."
if ! as_user "vagrant plugin list" | grep -q vagrant-libvirt; then
  as_user "vagrant plugin install vagrant-libvirt"
fi

# --- kubectl (latest stable) -----------------------------------------------
echo ">>> Installing kubectl..."
KVER="$(curl -Ls https://dl.k8s.io/release/stable.txt)"
curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl"
$SUDO install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
rm -f /tmp/kubectl

# --- report ----------------------------------------------------------------
echo
echo ">>> Done. Installed versions:"
vagrant --version
virsh --version 2>/dev/null && echo "libvirt OK" || true
kubectl version --client || true
echo
echo ">>> Log out/in (or reboot) so the 'libvirt'/'kvm' groups take effect."
