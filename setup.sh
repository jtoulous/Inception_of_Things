#!/usr/bin/env bash
#
# setup.sh - provision a fresh Debian 13 (Trixie) VM ("iot") to run the
#            Inception-of-Things project nested:
#            base build tools + Vagrant + KVM/libvirt + kubectl.
#            The K3s nodes run via Vagrant's libvirt/KVM provider (nested
#            VirtualBox-in-VirtualBox was tried and proved unstable: E1000
#            crashes, guru meditations, freezes under k3s load).
#
# MANUAL prerequisites (host-side / VirtualBox GUI - cannot be scripted from
# inside the guest, see SETUP.md):
#   1. Create the Debian 13 VM in VirtualBox.
#   2. Settings -> System -> Processor -> ENABLE "Nested VT-x/AMD-V"
#      (required: the K3s VMs run nested inside this one).
#   3. Devices -> Insert Guest Additions CD image, then run the installer.
#   4. (optional) Add a shared folder: auto-mount + make permanent.
#
# Run as your normal user (it calls sudo when needed):  ./setup.sh
#
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi
REAL_USER="${SUDO_USER:-$USER}"

# --- sanity: this script targets Debian -----------------------------------
. /etc/os-release
if [ "${ID:-}" != "debian" ]; then
  echo "WARNING: this script is written for Debian (found ID='${ID:-unknown}')." >&2
fi
CODENAME="${VERSION_CODENAME:-trixie}"
ARCH="$(dpkg --print-architecture)"

# --- sanity: nested virtualization must be exposed to this VM ---------------
if ! grep -qEm1 'vmx|svm' /proc/cpuinfo; then
  echo "ERROR: no vmx/svm flag in /proc/cpuinfo." >&2
  echo "Enable Nested VT-x/AMD-V for this VM in the HOST VirtualBox settings." >&2
  exit 1
fi

# --- base requirements (headers/dkms so kernel modules can build) ----------
echo ">>> Installing base requirements..."
$SUDO apt-get update
$SUDO apt-get install -y \
  curl wget gnupg ca-certificates \
  git make build-essential dkms \
  linux-headers-amd64 "linux-headers-$(uname -r)"

# --- Vagrant repo (Debian's own vagrant is too old) --------------------------
echo ">>> Adding HashiCorp repository (${CODENAME})..."
curl -fsSL https://apt.releases.hashicorp.com/gpg \
  | $SUDO gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${CODENAME} main" \
  | $SUDO tee /etc/apt/sources.list.d/hashicorp.list >/dev/null

# --- install Vagrant + KVM/libvirt + plugin build deps -----------------------
echo ">>> Installing Vagrant, qemu/libvirt and vagrant-libvirt build deps..."
$SUDO apt-get update
$SUDO apt-get install -y vagrant \
  qemu-system-x86 qemu-utils libvirt-daemon-system libvirt-clients \
  dnsmasq-base ebtables bridge-utils \
  ruby-dev pkg-config libvirt-dev libxml2-dev libxslt1-dev zlib1g-dev
$SUDO systemctl enable --now libvirtd
$SUDO usermod -aG libvirt,kvm "$REAL_USER"
$SUDO modprobe kvm_intel 2>/dev/null || $SUDO modprobe kvm_amd 2>/dev/null || true

# --- vagrant-libvirt plugin (compiles a native gem) --------------------------
echo ">>> Installing the vagrant-libvirt plugin..."
vagrant plugin list 2>/dev/null | grep -q vagrant-libvirt \
  || vagrant plugin install vagrant-libvirt

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
virsh --version || true
kubectl version --client || true
echo
echo ">>> Reboot (applies the libvirt/kvm group membership), then: cd p1 && make build"
