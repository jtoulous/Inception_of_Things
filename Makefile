# libvirt on qemu:///session
# make build / connect / fclean / re

VM_NAME    := iot
VMS_DIR    := $(HOME)/goinfre/vms
VM_DIR     := $(VMS_DIR)/$(VM_NAME)
RAM        := 6144
VCPUS      := 6
DISK_SIZE  := 30G

IMG_URL    := https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2
BASE_IMG   := $(VMS_DIR)/$(notdir $(IMG_URL))
DISK       := $(VM_DIR)/$(VM_NAME).qcow2
SEED       := $(VM_DIR)/seed.iso
DOMAIN_XML := $(VM_DIR)/domain.xml
CI_DIR     := $(VM_DIR)/cloud-init
VIRSH      := virsh -c qemu:///session

# The guest account mirrors this one; the 9p share is exported passthrough
VM_USER    := $(shell id -un)
VM_UID     := $(shell id -u)
VM_GID     := $(shell id -g)
SHARE_TAG  := iotshare
SHARE_DIR  := /home/$(VM_USER)/$(notdir $(CURDIR))

NODE_IP      := 192.168.56.110
HTTP_PORT    := 8080
SOCKS_PORT   := 1080
APP_PORT     := 8888
ARGO_PORT    := 8443
ARGO_VM_PORT := 8080

SSH_PORT   := 2222
SSH_KEY    := $(HOME)/.ssh/id_ed25519
SSH_OPTS   := -p $(SSH_PORT) -i $(SSH_KEY) -o StrictHostKeyChecking=no \
              -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR
SSH        := ssh $(SSH_OPTS) $(VM_USER)@127.0.0.1

WAIT_SSH = printf '>>> waiting for ssh'; \
           for i in $$(seq 1 90); do \
               $(SSH) -o ConnectTimeout=3 true 2>/dev/null && { echo ' ok'; exit 0; }; \
               printf '.'; sleep 2; \
           done; \
           echo ' timeout ($(VIRSH) console $(VM_NAME) to watch it boot)'; exit 1

build: $(DOMAIN_XML)
	@$(VIRSH) domstate $(VM_NAME) 2>/dev/null | grep -q running || $(VIRSH) start $(VM_NAME) >/dev/null
	@$(WAIT_SSH)
	@$(SSH) 'sudo cloud-init status --wait >/dev/null 2>&1 || true'
	@$(SSH) 'test -d $(SHARE_DIR)/p1' || { echo '>>> 9p share not mounted at $(SHARE_DIR)'; exit 1; }
	@$(SSH) 'test -e /var/lib/iot-provisioned' \
	    || { $(SSH) 'cd $(SHARE_DIR) && ./setup.sh' || exit 1; \
	         $(SSH) 'sudo systemctl reboot' 2>/dev/null; sleep 5; $(WAIT_SSH); }
	@$(SSH) 'grep -q app1.com /etc/hosts || echo "$(NODE_IP) app1.com app2.com app3.com" | sudo tee -a /etc/hosts >/dev/null'
	@# pkill on its own line: sharing a shell with the ssh below would put a
	@# literal "-L $(HTTP_PORT):..." in this command line and it would match itself
	-@ss -ltn 2>/dev/null | grep -q ":$(ARGO_PORT) " || pkill -f "[L] $(HTTP_PORT):$(NODE_IP):80" 2>/dev/null
	-@ss -ltn 2>/dev/null | grep -q ":$(ARGO_PORT) " || ssh -f -N $(SSH_OPTS) -o ExitOnForwardFailure=yes \
	    -L $(HTTP_PORT):$(NODE_IP):80 -L $(APP_PORT):127.0.0.1:$(APP_PORT) \
	    -L $(ARGO_PORT):127.0.0.1:$(ARGO_VM_PORT) -D $(SOCKS_PORT) $(VM_USER)@127.0.0.1
	@printf '%s\n' '' \
	    "  VM ready - repo shared at $(SHARE_DIR), tunnel open" '' \
	    "  make connect, then   p1, p2   vagrant up" \
	    "                       p3       cd p3/scripts && ./install.sh && ./setup.sh" '' \
	    "  p2   curl -H 'Host: app1.com' http://127.0.0.1:$(HTTP_PORT)      (no Host -> app3)" \
	    "       browser: SOCKS5 on 127.0.0.1:$(SOCKS_PORT) + remote DNS, then http://app1.com" \
	    "  p3   curl http://127.0.0.1:$(APP_PORT)/    https://127.0.0.1:$(ARGO_PORT) (Argo CD)" \
	    "       both need the port-forwards setup.sh leaves running in the VM"

connect:
	@$(SSH) -t 'cd $(SHARE_DIR) 2>/dev/null; exec $$SHELL -l'

fclean:
	-@pkill -f "[L] $(HTTP_PORT):$(NODE_IP):80" 2>/dev/null
	-@$(VIRSH) destroy $(VM_NAME) 2>/dev/null
	-@$(VIRSH) undefine $(VM_NAME) 2>/dev/null
	@rm -rf $(DISK) $(SEED) $(DOMAIN_XML) $(CI_DIR)
	-@rmdir $(VM_DIR) 2>/dev/null

re:
	@$(MAKE) --no-print-directory fclean
	@$(MAKE) --no-print-directory build

$(VM_DIR):
	@mkdir -p $@

$(BASE_IMG):
	@mkdir -p $(VMS_DIR)
	@curl -fL --retry 3 -o $@.part $(IMG_URL) && mv $@.part $@

$(DISK): $(BASE_IMG) | $(VM_DIR)
	@test -e $@ && touch $@ \
	    || { cp --reflink=auto $(BASE_IMG) $@; qemu-img resize -q $@ $(DISK_SIZE); }

$(SEED): Makefile | $(VM_DIR)
	@test -f $(SSH_KEY).pub || ssh-keygen -t ed25519 -N '' -f $(SSH_KEY) -q
	@mkdir -p $(CI_DIR)
	@printf 'instance-id: $(VM_NAME)\nlocal-hostname: $(VM_NAME)\n' > $(CI_DIR)/meta-data
	@printf '%s\n' \
	    '#cloud-config' \
	    'hostname: $(VM_NAME)' \
	    'users:' \
	    '  - name: $(VM_USER)' \
	    '    uid: "$(VM_UID)"' \
	    '    shell: /bin/bash' \
	    '    groups: [sudo]' \
	    '    sudo: "ALL=(ALL) NOPASSWD:ALL"' \
	    '    lock_passwd: true' \
	    '    ssh_authorized_keys: [ "__SSH_PUBKEY__" ]' \
	    'runcmd:' \
	    '  - [ sh, -c, "groupmod -g $(VM_GID) $(VM_USER); chown -R $(VM_UID):$(VM_GID) /home/$(VM_USER)" ]' \
	    '  - [ sh, -c, "mkdir -p $(SHARE_DIR); echo \"$(SHARE_TAG) $(SHARE_DIR) 9p trans=virtio,version=9p2000.L,rw,msize=512000,nofail 0 0\" >> /etc/fstab; mount -a || true" ]' \
	    > $(CI_DIR)/user-data
	@sed -i "s|__SSH_PUBKEY__|$$(cat $(SSH_KEY).pub)|" $(CI_DIR)/user-data
	@genisoimage -quiet -output $@ -volid cidata -joliet -rock $(CI_DIR)/user-data $(CI_DIR)/meta-data

# domain.xml  includes the disk, seed ISO, and other configuration for the VM.
$(DOMAIN_XML): $(DISK) $(SEED) | $(VM_DIR)
	@printf '%s\n' \
	    '<domain type="kvm">' \
	    '  <name>$(VM_NAME)</name>' \
	    '  <memory unit="MiB">$(RAM)</memory><vcpu>$(VCPUS)</vcpu>' \
	    '  <os><type arch="x86_64" machine="q35">hvm</type><boot dev="hd"/></os>' \
	    '  <features><acpi/><apic/></features>' \
	    '  <cpu mode="host-passthrough"/>' \
	    '  <devices>' \
	    '    <disk type="file" device="disk"><driver name="qemu" type="qcow2" discard="unmap"/><source file="$(DISK)"/><target dev="vda" bus="virtio"/></disk>' \
	    '    <disk type="file" device="cdrom"><driver name="qemu" type="raw"/><source file="$(SEED)"/><target dev="sda" bus="sata"/><readonly/></disk>' \
	    '    <interface type="user"><backend type="passt"/><portForward proto="tcp"><range start="$(SSH_PORT)" to="22"/></portForward><model type="virtio"/></interface>' \
	    '    <filesystem type="mount" accessmode="passthrough"><driver type="path" wrpolicy="immediate"/><source dir="$(CURDIR)"/><target dir="$(SHARE_TAG)"/></filesystem>' \
	    '    <console type="pty"><target type="serial" port="0"/></console>' \
	    '  </devices>' \
	    '  <seclabel type="none" model="selinux"/>' \
	    '</domain>' \
	    > $@
	@uuid=$$($(VIRSH) domuuid $(VM_NAME) 2>/dev/null | tr -d '[:space:]'); \
	 [ -z "$$uuid" ] || sed -i "s|<name>$(VM_NAME)</name>|&\n  <uuid>$$uuid</uuid>|" $@
	@$(VIRSH) define $@ >/dev/null

.PHONY: build connect fclean re
