# Setting up the `iot` VM (fresh install)

The whole project runs inside a Debian 13 (Trixie) VirtualBox VM; the K3s
nodes are nested VMs inside it, managed by Vagrant with the **libvirt/KVM**
provider. (Nested VirtualBox-in-VirtualBox was tried first and proved
unstable: E1000 emulation crashes, guru meditations at boot, and guest
freezes within minutes of k3s load. KVM handles nesting natively.)

### Create the Debian VM in VirtualBox (on the host)

- Debian 13 (Trixie), ≥ 6 GB RAM, ≥ 8 vCPUs recommended.
- Settings -> System -> Processor: enable **Nested VT-x/AMD-V**
  (the K3s nodes run nested inside this VM — without it nothing works).

### Install guest additions

Devices -> Insert Guest Additions CD image,
navigate into the mounted CD, then run the installer.

### Add a shared folder (auto-mount + permanent)

Share the project directory from the host, then inside the VM:

```bash
sudo adduser $USER vboxsf
```
```bash
newgrp vboxsf
```

The project appears under `/media/sf_<share-name>`.

### Install everything else (Vagrant, KVM/libvirt, kubectl)

From the repo root, inside the VM:

```bash
./setup.sh
```
```bash
sudo reboot   # applies the libvirt/kvm group membership
```

The script installs base build tools, HashiCorp Vagrant (Debian's own is too
old), qemu/libvirt + the `vagrant-libvirt` plugin, and kubectl. It is
idempotent — safe to re-run if a step fails.

### Build the cluster

```bash
cd /media/sf_<share-name>/p1
```
```bash
make build    # boots + provisions both nodes
```
```bash
make status   # kubectl get nodes from the server - expect both nodes Ready
```

`make connect` opens a shell on the server node. If something misbehaves,
`bash scripts/diag.sh` (inside the VM) collects VM states and hypervisor
logs into `p1/` where they can be inspected from the host.
