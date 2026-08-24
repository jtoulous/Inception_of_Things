# =============================================================================
#  Inception-of-Things - the host virtual machine
# =============================================================================
#  The subject requires the whole project to run inside a virtual machine, and
#  lets us pick the tooling freely. This Makefile builds that VM.
#
#  Hypervisor: QEMU/KVM driven by libvirt on the *session* URI (qemu:///session),
#  so everything runs as your own user - no root, no group membership needed.
#  VirtualBox is deliberately avoided: the K3s nodes are themselves VMs, and
#  nesting KVM inside VirtualBox is unstable (random freezes, and SSH dropped
#  in the middle of a provisioning run). KVM nests inside KVM natively.
#
#      make build     create the VM, provision it, share this repo into it
#      make connect   open a shell on the VM over SSH
#      make fclean    destroy the VM and everything it created
# =============================================================================

VM_NAME    := iot
VMS_DIR    := $(HOME)/goinfre/vms
VM_DIR     := $(VMS_DIR)/$(VM_NAME)

RAM        := 6144
VCPUS      := 6
DISK_SIZE  := 30G

# Debian's cloud image boots straight into a working system, so there is no
# installer to click through - cloud-init does the first-boot setup below.
# "generic", not "genericcloud": the latter ships Debian's cut-down -cloud
# kernel, which has no 9p modules, so the shared folder cannot mount.
IMG_URL    := https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2
BASE_IMG   := $(VMS_DIR)/$(notdir $(IMG_URL))

DISK       := $(VM_DIR)/$(VM_NAME).qcow2
SEED       := $(VM_DIR)/seed.iso
DOMAIN_XML := $(VM_DIR)/domain.xml
CI_DIR     := $(VM_DIR)/cloud-init

VIRSH      := virsh -c qemu:///session

# The guest account mirrors the host one. Matching UID *and* GID is what makes
# the 9p share work in both directions: it is exported in passthrough mode, so
# host and guest have to agree on the numeric owner of every file.
VM_USER    := $(shell id -un)
VM_UID     := $(shell id -u)
VM_GID     := $(shell id -g)

SHARE_TAG  := iotshare
SHARE_DIR  := /home/$(VM_USER)/$(notdir $(CURDIR))

SSH_PORT   := 2222
SSH_KEY    := $(HOME)/.ssh/id_ed25519
SSH_OPTS   := -p $(SSH_PORT) -i $(SSH_KEY) -o StrictHostKeyChecking=no \
              -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR
SSH        := ssh $(SSH_OPTS) $(VM_USER)@127.0.0.1

# Poll until sshd answers (~3 min ceiling). First boot has to grow the root
# filesystem and run cloud-init, so it is slower than later ones.
WAIT_SSH = printf '>>> waiting for ssh'; \
           for i in $$(seq 1 90); do \
               $(SSH) -o ConnectTimeout=3 true 2>/dev/null && { echo ' ok'; exit 0; }; \
               printf '.'; sleep 2; \
           done; \
           echo ' timeout'; \
           echo '    the VM is up but unreachable - watch it boot with:'; \
           echo '    $(VIRSH) console $(VM_NAME)'; \
           exit 1

.PHONY: build connect fclean

# --- build -------------------------------------------------------------------
build: $(DOMAIN_XML)
	@$(VIRSH) domstate $(VM_NAME) 2>/dev/null | grep -q running \
	    || { echo ">>> starting $(VM_NAME) ($(RAM)MB, $(VCPUS) vcpu)..."; \
	         $(VIRSH) start $(VM_NAME) >/dev/null; }
	@$(WAIT_SSH)
	@echo ">>> waiting for cloud-init..."
	@$(SSH) 'sudo cloud-init status --wait >/dev/null 2>&1 || true'
	@$(SSH) 'test -d $(SHARE_DIR)/p1' \
	    || { echo '>>> ERROR: the 9p share did not mount at $(SHARE_DIR)'; exit 1; }
	@if $(SSH) 'command -v vagrant >/dev/null 2>&1'; then \
	    echo ">>> already provisioned"; \
	 else \
	    echo ">>> provisioning (setup.sh)..."; \
	    $(SSH) 'cd $(SHARE_DIR) && ./setup.sh' || exit 1; \
	    echo ">>> rebooting to apply the libvirt/kvm group membership..."; \
	    $(SSH) 'sudo systemctl reboot' 2>/dev/null || true; \
	    sleep 5; \
	    $(WAIT_SSH); \
	 fi
	@echo
	@echo "    VM '$(VM_NAME)' ready - $(RAM)MB / $(VCPUS) vcpu, nested KVM on"
	@echo "    this repo is shared at $(SHARE_DIR)"
	@echo "    next:  make connect   then   cd $(SHARE_DIR)/p1 && make build"

# --- connect -----------------------------------------------------------------
connect:
	@$(VIRSH) domstate $(VM_NAME) 2>/dev/null | grep -q running \
	    || { echo ">>> $(VM_NAME) is not running - run 'make build' first"; exit 1; }
	@$(SSH) -t 'cd $(SHARE_DIR) 2>/dev/null; exec $$SHELL -l'

# --- fclean ------------------------------------------------------------------
# Removes only what build created. The base cloud image is left in place as a
# download cache, and so is anything else already sitting in $(VM_DIR) - the
# old VirtualBox disk still lives there until you delete it yourself.
fclean:
	@echo ">>> destroying $(VM_NAME)..."
	-@$(VIRSH) destroy $(VM_NAME) 2>/dev/null
	-@$(VIRSH) undefine $(VM_NAME) 2>/dev/null
	@rm -rf $(DISK) $(SEED) $(DOMAIN_XML) $(CI_DIR)
	-@rmdir $(VM_DIR) 2>/dev/null
	@echo "    gone (kept the image cache: $(BASE_IMG))"

# --- artifacts ---------------------------------------------------------------
$(VM_DIR):
	@mkdir -p $@

$(BASE_IMG):
	@mkdir -p $(VMS_DIR)
	@echo ">>> downloading the Debian 13 cloud image..."
	@curl -fL --retry 3 -o $@.part $(IMG_URL)
	@mv $@.part $@

# A full copy, not a qcow2 overlay: the VM stays self-contained, so deleting
# the cache above can never break a built VM.
$(DISK): $(BASE_IMG) | $(VM_DIR)
	@if [ -e $@ ]; then \
	    echo ">>> keeping the existing VM disk (make fclean to start over)"; \
	    touch $@; \
	 else \
	    echo ">>> creating the VM disk ($(DISK_SIZE))..."; \
	    cp --reflink=auto $(BASE_IMG) $@; \
	    qemu-img resize -q $@ $(DISK_SIZE); \
	 fi

# cloud-init NoCloud seed: a tiny ISO labelled "cidata" that the cloud image
# reads on first boot. It creates the account, installs the SSH key and mounts
# the shared repo.
$(SEED): Makefile | $(VM_DIR)
	@test -f $(SSH_KEY).pub || { echo ">>> generating $(SSH_KEY)..."; \
	    ssh-keygen -t ed25519 -N '' -f $(SSH_KEY) -q; }
	@mkdir -p $(CI_DIR)
	@printf '%s\n' \
	    'instance-id: $(VM_NAME)' \
	    'local-hostname: $(VM_NAME)' \
	    > $(CI_DIR)/meta-data
	@printf '%s\n' \
	    '#cloud-config' \
	    'hostname: $(VM_NAME)' \
	    'manage_etc_hosts: true' \
	    'ssh_pwauth: false' \
	    '' \
	    'users:' \
	    '  - name: $(VM_USER)' \
	    '    uid: "$(VM_UID)"' \
	    '    shell: /bin/bash' \
	    '    groups: [sudo]' \
	    '    sudo: "ALL=(ALL) NOPASSWD:ALL"' \
	    '    lock_passwd: true' \
	    '    ssh_authorized_keys:' \
	    '      - __SSH_PUBKEY__' \
	    '' \
	    'packages:' \
	    '  - qemu-guest-agent' \
	    '' \
	    'runcmd:' \
	    '  # cloud-init picks the GID itself, so line it up with the host after' \
	    '  # the fact - the 9p share is exported in passthrough mode.' \
	    '  - [ sh, -c, "groupmod -g $(VM_GID) $(VM_USER)" ]' \
	    '  - [ sh, -c, "chown -R $(VM_UID):$(VM_GID) /home/$(VM_USER)" ]' \
	    '  - [ sh, -c, "mkdir -p $(SHARE_DIR)" ]' \
	    '  - [ sh, -c, "echo \"$(SHARE_TAG) $(SHARE_DIR) 9p trans=virtio,version=9p2000.L,rw,msize=512000,nofail 0 0\" >> /etc/fstab" ]' \
	    '  - [ sh, -c, "mount -a || true" ]' \
	    > $(CI_DIR)/user-data
	@sed -i "s|__SSH_PUBKEY__|$$(cat $(SSH_KEY).pub)|" $(CI_DIR)/user-data
	@genisoimage -quiet -output $@ -volid cidata -joliet -rock \
	    $(CI_DIR)/user-data $(CI_DIR)/meta-data

# SELinux confinement is turned off for this domain: a session libvirt cannot
# relabel images, and svirt_t has no business reaching into /goinfre. qemu then
# runs as you, so it can open exactly the files you can.
# host-passthrough is what exposes VMX to the guest; without it the nested K3s
# nodes have no KVM to run on. The NIC is user-mode (passt) because a session
# libvirt cannot create bridges - it only needs outbound traffic plus the SSH
# forward, since 192.168.56.0/24 lives entirely inside the VM.
$(DOMAIN_XML): $(DISK) $(SEED) | $(VM_DIR)
	@echo ">>> defining the libvirt domain..."
	@printf '%s\n' \
	    '<domain type="kvm">' \
	    '  <name>$(VM_NAME)</name>' \
	    '  <memory unit="MiB">$(RAM)</memory>' \
	    '  <vcpu placement="static">$(VCPUS)</vcpu>' \
	    '  <os>' \
	    '    <type arch="x86_64" machine="q35">hvm</type>' \
	    '    <boot dev="hd"/>' \
	    '  </os>' \
	    '  <features><acpi/><apic/></features>' \
	    '  <cpu mode="host-passthrough" check="none" migratable="off"/>' \
	    '  <clock offset="utc">' \
	    '    <timer name="rtc" tickpolicy="catchup"/>' \
	    '    <timer name="pit" tickpolicy="delay"/>' \
	    '    <timer name="hpet" present="no"/>' \
	    '  </clock>' \
	    '  <on_poweroff>destroy</on_poweroff>' \
	    '  <on_reboot>restart</on_reboot>' \
	    '  <on_crash>destroy</on_crash>' \
	    '  <devices>' \
	    '    <disk type="file" device="disk">' \
	    '      <driver name="qemu" type="qcow2" discard="unmap"/>' \
	    '      <source file="$(DISK)"/>' \
	    '      <target dev="vda" bus="virtio"/>' \
	    '    </disk>' \
	    '    <disk type="file" device="cdrom">' \
	    '      <driver name="qemu" type="raw"/>' \
	    '      <source file="$(SEED)"/>' \
	    '      <target dev="sda" bus="sata"/>' \
	    '      <readonly/>' \
	    '    </disk>' \
	    '    <interface type="user">' \
	    '      <backend type="passt"/>' \
	    '      <portForward proto="tcp">' \
	    '        <range start="$(SSH_PORT)" to="22"/>' \
	    '      </portForward>' \
	    '      <model type="virtio"/>' \
	    '    </interface>' \
	    '    <filesystem type="mount" accessmode="passthrough">' \
	    '      <driver type="path" wrpolicy="immediate"/>' \
	    '      <source dir="$(CURDIR)"/>' \
	    '      <target dir="$(SHARE_TAG)"/>' \
	    '    </filesystem>' \
	    '    <console type="pty"><target type="serial" port="0"/></console>' \
	    '    <channel type="unix">' \
	    '      <target type="virtio" name="org.qemu.guest_agent.0"/>' \
	    '    </channel>' \
	    '    <memballoon model="virtio"/>' \
	    '    <rng model="virtio"><backend model="random">/dev/urandom</backend></rng>' \
	    '  </devices>' \
	    '  <seclabel type="none" model="selinux"/>' \
	    '</domain>' \
	    > $@
	@uuid=$$($(VIRSH) domuuid $(VM_NAME) 2>/dev/null | tr -d '[:space:]'); \
	 if [ -n "$$uuid" ]; then \
	    sed -i "s|<name>$(VM_NAME)</name>|&\n  <uuid>$$uuid</uuid>|" $@; \
	 fi
	@$(VIRSH) define $@ >/dev/null
