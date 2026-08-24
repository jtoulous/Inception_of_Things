#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO="sudo"
USER_NAME="${SUDO_USER:-$(id -un)}"
CODENAME="$(. /etc/os-release; echo "$VERSION_CODENAME")"
APT="-o DPkg::Lock::Timeout=300"

grep -qE 'vmx|svm' /proc/cpuinfo \
    || { echo "ERROR: no vmx/svm - this VM has no nested virtualization" >&2; exit 1; }

$SUDO apt-get $APT update -qq
$SUDO apt-get $APT install -y curl ca-certificates gnupg build-essential

curl -fsSL https://apt.releases.hashicorp.com/gpg \
    | $SUDO gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${CODENAME} main" \
    | $SUDO tee /etc/apt/sources.list.d/hashicorp.list >/dev/null

$SUDO apt-get $APT update -qq
$SUDO apt-get $APT install -y vagrant qemu-system-x86 qemu-utils \
    libvirt-daemon-system libvirt-clients dnsmasq-base ruby-dev pkg-config libvirt-dev
$SUDO systemctl enable --now libvirtd
$SUDO usermod -aG libvirt,kvm "$USER_NAME"

vagrant plugin list 2>/dev/null | grep -q vagrant-libvirt || vagrant plugin install vagrant-libvirt

KVER="$(curl -Ls https://dl.k8s.io/release/stable.txt)"
curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl"
$SUDO install -m 0755 /tmp/kubectl /usr/local/bin/kubectl && rm -f /tmp/kubectl

$SUDO touch /var/lib/iot-provisioned
