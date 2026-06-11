SERVER = rsterinS
WORKER = rsterinSW
BOX    = bento/rockylinux-9

# Keep Vagrant's state (incl. the generated SSH key) off the vboxsf share:
# vboxsf forces fixed perms/ownership that SSH rejects. Use the VM's real home.
export VAGRANT_DOTFILE_PATH := $(HOME)/.vagrant
export VAGRANT_DEFAULT_PROVIDER := virtualbox

build: free-vtx
	vagrant up

# VirtualBox needs VT-x for itself: stop libvirt and unload the KVM modules
# (leftovers from the libvirt provider attempts) or VBox VMs will not start.
free-vtx:
	@sudo systemctl stop libvirtd virtqemud 2>/dev/null || true
	@sudo modprobe -r kvm_intel kvm_amd kvm 2>/dev/null || true

connect:
	vagrant ssh $(SERVER)

status:
	vagrant ssh $(SERVER) -c "KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl get nodes -o wide" 2>&1 | tee status.log

clean:
	vagrant destroy -f

fclean: clean
	vagrant box remove $(BOX) --all --force 2>/dev/null || true
	@for vm in $(SERVER) $(WORKER); do \
		VBoxManage controlvm "$$vm" poweroff 2>/dev/null || true; \
		VBoxManage unregistervm "$$vm" --delete 2>/dev/null || true; \
	done
	rm -rf $(VAGRANT_DOTFILE_PATH) .vagrant *.log *.png

# clean (not fclean): rebuilding shouldn't re-download the box each time.
re: clean build

.PHONY: build free-vtx connect status clean fclean re
