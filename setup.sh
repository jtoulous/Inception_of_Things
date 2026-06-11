#!/usr/bin/env bash
#
# setup.sh - provision a fresh Debian 13 (Trixie) VM ("iot") to run the
#            Inception-of-Things project: VirtualBox (nested) + Vagrant + kubectl.
#
# MANUAL prerequisites (host-side / VirtualBox GUI - cannot be scripted from
# inside the guest, see SETUP.md):
#   1. Create the Debian 13 VM in VirtualBox (>= 6 GB RAM recommended).
#   2. Settings -> System -> Processor -> ENABLE "Nested VT-x/AMD-V"
#      (required: the K3s node VMs run nested inside this one).
#   3. Devices -> Insert Guest Additions CD image, then run the installer.
#   4. Add the project shared folder: auto-mount + make permanent.
#
# Run as your normal user (it calls sudo when needed):  ./setup.sh
# Idempotent - safe to re-run if a step fails.
#
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi
REAL_USER="${SUDO_USER:-$USER}"

# --- sanity: Debian + nested virtualization exposed to this VM ---------------
. /etc/os-release
if [ "${ID:-}" != "debian" ]; then
  echo "WARNING: this script is written for Debian (found ID='${ID:-unknown}')." >&2
fi
CODENAME="${VERSION_CODENAME:-trixie}"
ARCH="$(dpkg --print-architecture)"

if ! grep -qEm1 'vmx|svm' /proc/cpuinfo; then
  echo "ERROR: no vmx/svm flag in /proc/cpuinfo." >&2
  echo "Enable Nested VT-x/AMD-V for this VM in the HOST VirtualBox settings." >&2
  exit 1
fi

# --- base packages (headers/dkms so the VirtualBox kernel module can build) ---
echo ">>> Installing base requirements..."
$SUDO apt-get update
$SUDO apt-get install -y \
  curl gnupg ca-certificates git make \
  build-essential dkms linux-headers-amd64 "linux-headers-$(uname -r)"

# --- apt repos: Vagrant (HashiCorp) + VirtualBox (Oracle) --------------------
# Debian ships neither: its vagrant is too old and virtualbox is not packaged.
echo ">>> Adding HashiCorp and Oracle VirtualBox repositories (${CODENAME})..."
curl -fsSL https://apt.releases.hashicorp.com/gpg \
  | $SUDO gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${CODENAME} main" \
  | $SUDO tee /etc/apt/sources.list.d/hashicorp.list >/dev/null

curl -fsSL https://www.virtualbox.org/download/oracle_vbox_2016.asc \
  | $SUDO gpg --dearmor --yes -o /usr/share/keyrings/oracle-virtualbox-2016.gpg
echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/oracle-virtualbox-2016.gpg] https://download.virtualbox.org/virtualbox/debian ${CODENAME} contrib" \
  | $SUDO tee /etc/apt/sources.list.d/virtualbox.list >/dev/null

echo ">>> Installing Vagrant and VirtualBox..."
$SUDO apt-get update
$SUDO apt-get install -y vagrant virtualbox-7.2

# --- swap: absorb nested-VM memory spikes ------------------------------------
# Both 1GB nodes peaking at once can exhaust this VM's RAM. Without swap the
# desktop freezes (thrash) and the kernel OOM-kills a node - it dies
# mid-provision and loses its unflushed disk writes. 2G of swap lets the
# kernel evict instead.
if [ "$(awk '/SwapTotal/ {print $2}' /proc/meminfo)" -lt 1500000 ] && [ ! -f /swapfile ]; then
  echo ">>> Adding a 2G swapfile (/swapfile)..."
  $SUDO fallocate -l 2G /swapfile || $SUDO dd if=/dev/zero of=/swapfile bs=1M count=2048
  $SUDO chmod 600 /swapfile
  $SUDO mkswap /swapfile
  $SUDO swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' | $SUDO tee -a /etc/fstab >/dev/null
fi

# --- kubectl (used from this VM in p3 with k3d) -------------------------------
echo ">>> Installing kubectl..."
KVER="$(curl -Ls https://dl.k8s.io/release/stable.txt)"
curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl"
$SUDO install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
rm -f /tmp/kubectl

# --- vagrant: keep the dotfile dir off the vboxsf share ----------------------
# vboxsf forces fixed perms/ownership, so SSH rejects the key Vagrant generates
# under .vagrant/. This wrapper stores Vagrant state in ~/.vagrant (real disk)
# for bare `vagrant` commands; the Makefiles set the same path for `make`.
echo ">>> Adding the vagrant dotfile-path wrapper to ~/.bashrc..."
USER_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
if ! grep -q 'VAGRANT_DOTFILE_PATH' "${USER_HOME}/.bashrc" 2>/dev/null; then
  cat >> "${USER_HOME}/.bashrc" <<'EOF'

# Keep Vagrant state (incl. the generated SSH key) off vboxsf shares.
vagrant() {
    VAGRANT_DOTFILE_PATH="${VAGRANT_DOTFILE_PATH:-$HOME/.vagrant}" command vagrant "$@"
}
EOF
fi

# --- report ------------------------------------------------------------------
echo
echo ">>> Done. Installed versions:"
vagrant --version
VBoxManage --version || true
kubectl version --client || true
echo
echo ">>> Open a new shell (loads the vagrant wrapper), then: cd p1 && make build"
