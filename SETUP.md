# Setting up the `iot` VM (fresh install)

The whole project runs inside a Debian 13 (Trixie) VirtualBox VM (`iot`); the
K3s nodes are nested VirtualBox VMs inside it, managed by Vagrant.

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

### Install everything else (VirtualBox, Vagrant, kubectl)

From the repo root, inside the VM:

```bash
./setup.sh
```

The script installs base build tools, HashiCorp Vagrant and Oracle VirtualBox
(Debian packages neither), kubectl (needed in p3), a 2G swapfile (see the
freeze section below), and a `vagrant` wrapper in `~/.bashrc` (see the next
section). It is idempotent — safe to re-run if a step fails. Open a new shell
afterwards so the wrapper is loaded.

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
`bash scripts/diag.sh` (inside the VM) collects VM states, k3s journals from
both nodes, and console screenshots into `p1/` where they can be inspected
from the host.

Note: `make build` first stops libvirtd and unloads the KVM kernel modules if
present (`free-vtx` target) — VirtualBox needs VT-x for itself and refuses to
start VMs while KVM holds it.

### Running `vagrant` directly (not via `make`)

Vagrant stores each machine's generated SSH key in its *dotfile* dir
(`.vagrant/` by default). That dir **must not** sit on the vboxsf share: vboxsf
forces fixed ownership/permissions and SSH then refuses the key (*"private key
must be owned by the user running Vagrant"*). The Makefile already redirects it
to the VM's real disk with `VAGRANT_DOTFILE_PATH=$HOME/.vagrant`, so
`make build` is safe.

For bare `vagrant up` / `vagrant ssh` / `vagrant destroy` to use that **same**
off-share state, `setup.sh` adds this wrapper to `~/.bashrc` (add it by hand if
you skipped setup):

```bash
vagrant() {
    VAGRANT_DOTFILE_PATH="${VAGRANT_DOTFILE_PATH:-$HOME/.vagrant}" command vagrant "$@"
}
```

It stores Vagrant state in `~/.vagrant` on the VM's real disk — the same path
the Makefiles use. Build one part at a time (`make fclean` before switching
parts, so the shared state dir starts clean), and never commit `.vagrant/` to
the share.

### If the `iot` VM freezes when the nodes start

Two nested 1 GB VMs running k3s inside a 6 GB VM is heavy. A freeze is almost
always memory pressure at the moment both nodes get busy. Mitigations, most
effective first:

- **Swap on the `iot` VM** so memory pressure degrades gracefully instead of
  hard-freezing or OOM-killing a node. `setup.sh` does this automatically
  (2G `/swapfile`) — re-run `./setup.sh` if you set the VM up before this was
  added.

- **Leave the host enough RAM.** The `iot` VM is 6 GB and each node takes 1 GB
  plus VirtualBox overhead. Don't size the `iot` VM larger than the host can
  spare (check `free -h` on the host), and close heavy apps on the host first.

- **Tune VirtualBox** (run on the host with the `iot` VM powered off):

  ```bash
  VBoxManage modifyvm iot --largepages on --nestedpaging on --nested-hw-virt on
  ```

- **Run the `iot` VM headless** (no desktop GUI) while building, to free RAM.

- Still locking up? Drop the worker to 512 MB (the subject allows 512 or 1024)
  in `p1/Vagrantfile` to shrink the footprint.
