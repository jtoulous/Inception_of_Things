### Setup debian vm via oracle

### Install guest additions:

Devices -> Inset guest additions cd image
Navigate through cd image then install it

### Add shared folder, make it auto mount + make permanent

### Install Vagrant:

```bash
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
```
```bash
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
```
```bash
sudo apt update && sudo apt install vagrant
```
### Install kubectl:

```bash
sudo apt install curl
```
```bash
curl -LO https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl
```
```bash
chmod +x ./kubectl
```
```bash
sudo mv ./kubectl /usr/local/bin/kubectl
```

### Install requirements:

```bash
sudo apt update
```
```bash
sudo apt install -y git make build-essential dkms linux-headers-$(uname -r) pkg-config
```

### Install libvirt provider:

```bash
sudo apt install -y qemu-system-x86 libvirt-daemon-system libvirt-clients virtinst dnsmasq libvirt-dev
```
```bash
sudo systemctl enable --now libvirtd
```
```bash
sudo usermod -aG libvirt,kvm $USER
```
```bash
vagrant plugin install vagrant-libvirt
```
