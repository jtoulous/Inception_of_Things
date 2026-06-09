# K3S INSTALL
if ! command -v k3s &> /dev/null; then
    curl -sfL https://get.k3s.io | sh -
    echo "K3s installé"
else
    echo "K3s déjà installé, skip"
fi


# KUBECTL INSTALL
if ! command -v kubectl &> /dev/null; then
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    mv kubectl /usr/local/bin/kubectl
    echo "Kubectl installé"
else
    echo "Kubectl déjà installé, skip"
fi

#VAGRANT INSTALL
if ! command -v vagrant &> /dev/null; then
    apt-get update -qq
    apt-get install -y -qq wget unzip
    wget -q https://releases.hashicorp.com/vagrant/2.4.1/vagrant_2.4.1_linux_amd64.zip -O /tmp/vagrant.zip
    unzip /tmp/vagrant.zip -d /usr/local/bin
    chmod +x /usr/local/bin/vagrant
    rm /tmp/vagrant.zip
    echo "Vagrant installé"
else
    echo "Vagrant déjà installé, skip"
fi