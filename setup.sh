#!/usr/bin/env bash
#
# setup.sh - provision a fresh Debian 13 (Trixie) VM ("iot") to run the
#            Inception-of-Things project nested:
#            base build tools + VirtualBox + Vagrant + kubectl, and free VT-x
#            for the nested VMs. The K3s nodes use the centos/stream9 box
#            (Vagrant downloads it) - nothing to install for them here.
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

# --- sanity: this script targets Debian -----------------------------------
. /etc/os-release
if [ "${ID:-}" != "debian" ]; then
  echo "WARNING: this script is written for Debian (found ID='${ID:-unknown}')." >&2
fi
CODENAME="${VERSION_CODENAME:-trixie}"
ARCH="$(dpkg --print-architecture)"

# --- base requirements (headers/dkms so kernel modules can build) ----------
echo ">>> Installing base requirements..."
$SUDO apt-get update
$SUDO apt-get install -y \
  curl wget gnupg ca-certificates \
  git make build-essential dkms \
  linux-headers-amd64 "linux-headers-$(uname -r)"

# --- VirtualBox repo (Debian 13 dropped the in-repo package) ---------------
echo ">>> Adding Oracle VirtualBox repository (${CODENAME})..."
curl -fsSL https://www.virtualbox.org/download/oracle_vbox_2016.asc \
  | $SUDO gpg --dearmor --yes -o /usr/share/keyrings/oracle-vbox-2016.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/oracle-vbox-2016.gpg] https://download.virtualbox.org/virtualbox/debian ${CODENAME} contrib" \
  | $SUDO tee /etc/apt/sources.list.d/virtualbox.list >/dev/null

# --- Vagrant repo (HashiCorp's 2.4.x supports VirtualBox 7.2) ---------------
echo ">>> Adding HashiCorp repository (${CODENAME})..."
curl -fsSL https://apt.releases.hashicorp.com/gpg \
  | $SUDO gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${CODENAME} main" \
  | $SUDO tee /etc/apt/sources.list.d/hashicorp.list >/dev/null

# --- install VirtualBox + Vagrant ------------------------------------------
echo ">>> Installing VirtualBox and Vagrant..."
$SUDO apt-get update
$SUDO apt-get install -y virtualbox-7.2 vagrant

# --- free VT-x for VirtualBox: blacklist KVM (nested-VM requirement) --------
# Both KVM and VirtualBox want VT-x; only one can hold it. Blacklisting KVM
# lets VirtualBox run the nested K3s VMs (otherwise VERR_VMX_IN_VMX_ROOT_MODE).
echo ">>> Blacklisting KVM so VirtualBox can claim VT-x..."
printf 'blacklist kvm\nblacklist kvm_intel\nblacklist kvm_amd\n' \
  | $SUDO tee /etc/modprobe.d/disable-kvm.conf >/dev/null
$SUDO modprobe -r kvm_intel kvm_amd kvm 2>/dev/null || true

# --- kubectl (latest stable) -----------------------------------------------
echo ">>> Installing kubectl..."
KVER="$(curl -Ls https://dl.k8s.io/release/stable.txt)"
curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl"
$SUDO install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
rm -f /tmp/kubectl

# --- let the invoking user manage VirtualBox -------------------------------
if getent group vboxusers >/dev/null; then
  $SUDO usermod -aG vboxusers "${SUDO_USER:-$USER}"
fi

# --- report ----------------------------------------------------------------
echo
echo ">>> Done. Installed versions:"
vagrant --version
VBoxManage --version || true
kubectl version --client || true
echo
echo ">>> Reboot (for the KVM blacklist + vboxusers group), then: cd p1 && make build"
