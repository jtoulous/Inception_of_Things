# Setting up

The subject requires the whole project to run inside a virtual machine. That
VM is built by the `Makefile` at the root of this repository:

```bash
make build      # create the VM, provision it, share this repo into it
make connect    # open a shell on it
make fclean     # destroy it and everything it created
```

Then, inside the VM:

```bash
cd ~/Inception_of_Things/p1
make build      # boots + provisions both K3s nodes
make status     # expect rsterinS and rsterinSW both Ready
```

Nothing else is needed on the physical host - no root, no manual install, no
ISO to click through.

### What `make build` does

1. Downloads Debian 13 (Trixie) as a **cloud image**, cached in `~/goinfre/vms`.
2. Creates a 30 GB disk from it and a small `cloud-init` seed ISO.
3. Defines a libvirt domain (6 GB, 6 vCPU) on `qemu:///session` and starts it.
4. On first boot `cloud-init` creates your account with your SSH key, and
   mounts this repository inside the VM at `~/Inception_of_Things`.
5. Runs `setup.sh` over SSH: Vagrant + libvirt/KVM + the `vagrant-libvirt`
   plugin + kubectl. Then reboots so the `libvirt`/`kvm` groups take effect.

Re-running `make build` is safe: it keeps the existing disk and only brings the
VM back up. To start over from scratch, `make fclean` first.

### Why QEMU/KVM and not VirtualBox

The K3s nodes are themselves virtual machines, so they run *nested* inside the
project VM. VirtualBox handles that badly: nodes froze at random points, boots
guru-meditated, and `vagrant up` regularly died mid-provisioning on
`The SSH connection was unexpectedly closed by the remote end`. KVM nests
inside KVM natively, which is why the host VM is a libvirt domain here.

The subject allows this explicitly:

> You can use any tools you want to set up your host virtual machine as well as
> the provider used in Vagrant.

### Notes

- **Memory is the real constraint.** The physical host has 15 GB. The VM is
  capped at 6 GB but QEMU only commits what the guest actually touches. If a
  build starts thrashing, close the browser rather than shrinking the nodes.
- The repo is shared over **9p**, which needs Debian's standard kernel - hence
  the `generic` cloud image and not `genericcloud`, whose `-cloud` kernel ships
  no 9p modules.
- SELinux confinement is disabled for this one domain (`<seclabel type="none">`):
  a session libvirt cannot relabel disk images, and `svirt_t` cannot reach into
  `/goinfre`. QEMU therefore runs as you and opens exactly the files you can.
- To watch the VM boot, or if SSH never comes up:
  `virsh -c qemu:///session console iot`
