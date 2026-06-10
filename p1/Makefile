SERVER = rsterinS
WORKER = rsterinSW
BOX    = generic/rocky9

export VAGRANT_DOTFILE_PATH := $(HOME)/.vagrant-p1
export VAGRANT_DEFAULT_PROVIDER := libvirt

.PHONY: build kvm-ready connect status clean fclean re

build: kvm-ready
	vagrant up

# KVM + the vagrant-libvirt plugin are required - one-time prep: ../setup.sh
kvm-ready:
	@[ -e /dev/kvm ] \
		|| sudo modprobe kvm_intel 2>/dev/null || sudo modprobe kvm_amd 2>/dev/null \
		|| { echo '>>> /dev/kvm unavailable: run ../setup.sh (see SETUP.md), then reboot'; exit 1; }
	@vagrant plugin list 2>/dev/null | grep -q vagrant-libvirt \
		|| { echo '>>> vagrant-libvirt missing: run ../setup.sh (see SETUP.md) first'; exit 1; }

connect:
	vagrant ssh $(SERVER)

status:
	vagrant ssh $(SERVER) -c "KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl get nodes -o wide"

clean:
	vagrant destroy -f

fclean: clean
	rm -rf $(VAGRANT_DOTFILE_PATH)
	rm -rf .vagrant
	vagrant box remove $(BOX) --all --force 2>/dev/null || true
	@for vm in $(SERVER) $(WORKER); do \
		virsh -c qemu:///system destroy "$$vm" 2>/dev/null || true; \
		virsh -c qemu:///system undefine "$$vm" --remove-all-storage 2>/dev/null || true; \
	done

re: fclean build
