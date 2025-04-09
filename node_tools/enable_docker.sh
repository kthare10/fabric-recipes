#!/bin/bash

set -e

# Get the script directory
script_dir="$(cd "$(dirname "$0")" && pwd)"

# Determine IPv6 or IPv4
if ping6 -c 1 google.com &> /dev/null; then
    man_ip_type=ipv6
else
    man_ip_type=ipv4
fi

# Determine OS and VERSION
os_id=$(grep "^ID=" /etc/os-release | cut -d= -f2 | tr -d '"')
os_version_id=$(grep "^VERSION_ID=" /etc/os-release | cut -d= -f2 | tr -d '"')

# Construct image variable automatically
case "$os_id" in
    ubuntu)
        if [[ "$os_version_id" == 20.* ]]; then
            image="default_ubuntu_20"
        elif [[ "$os_version_id" == 22.* ]]; then
            image="default_ubuntu_22"
        elif [[ "$os_version_id" == 24.* ]]; then
            image="default_ubuntu_24"
        fi
        ;;
    rocky)
        if [[ "$os_version_id" == 8* ]]; then
            image="default_rocky_8"
        elif [[ "$os_version_id" == 9* ]]; then
            image="default_rocky_9"
        fi
        ;;
    *)
        echo "Unsupported OS: $os_id $os_version_id"
        exit 1
        ;;
esac

echo "Detected image: $image"

# Begin installation
if [[ $image == "default_ubuntu_20" ]]; then
    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    sudo apt-get update
    sudo mkdir -p /etc/docker
    sudo cp ${script_dir}/docker/daemon.json /etc/docker/daemon.json
    sudo apt-get install -y docker-ce
    sudo usermod -aG docker ubuntu
    sudo apt-get install -y openvswitch-switch
    sudo systemctl enable --now openvswitch-switch
    sudo apt-get install -y build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev wget python3.9 python3.9-full tcpdump iftop python3-pip
    python3.9 -m pip install docker rpyc --user

elif [[ $image == "default_ubuntu_22" || $image == "default_ubuntu_24" ]]; then
    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    sudo apt-get update
    sudo mkdir -p /etc/docker
    sudo cp ${script_dir}/docker/daemon.json /etc/docker/daemon.json
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io
    sudo usermod -aG docker ubuntu
    sudo apt-get install -y openvswitch-switch
    sudo systemctl enable --now openvswitch-switch
    sudo apt-get install -y build-essential checkinstall libncursesw5-dev libssl-dev libsqlite3-dev tk-dev libgdbm-dev libc6-dev libbz2-dev wget tcpdump iftop python3-pip
    python3 -m pip install docker rpyc --user

elif [[ $image == "default_rocky_8" ]]; then
    sudo dnf install -y epel-release
    sudo dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
    sudo dnf install -y docker-ce docker-ce-cli containerd.io
    sudo mkdir -p /etc/docker
    sudo cp ${script_dir}/docker/daemon.json /etc/docker/daemon.json
    sudo systemctl start docker
    sudo usermod -aG docker rocky
    sudo dnf install -y https://repos.fedorapeople.org/repos/openstack/openstack-yoga/rdo-release-yoga-1.el8.noarch.rpm
    sudo dnf install -y openvswitch libibverbs tcpdump net-tools python3.9 vim iftop
    pip3.9 install docker rpyc --user
    sudo systemctl enable --now openvswitch
    sudo sysctl --system
    sudo firewall-cmd --zone=public --add-port=5201/tcp --permanent
    sudo firewall-cmd --zone=public --add-port=5201/udp --permanent
    sudo firewall-cmd --reload

elif [[ $image == "default_rocky_9" ]]; then
    sudo dnf install -y epel-release
    sudo dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
    sudo dnf install -y docker-ce docker-ce-cli containerd.io
    sudo mkdir -p /etc/docker
    sudo cp ${script_dir}/docker/daemon.json /etc/docker/daemon.json
    sudo systemctl start docker
    sudo usermod -aG docker rocky
    sudo dnf install -y centos-release-nfv-openvswitch
    sudo dnf install -y openvswitch3.3 libibverbs tcpdump net-tools python vim iftop
    pip3.9 install docker rpyc --user
    sudo systemctl enable --now openvswitch
    sudo sysctl --system
    sudo firewall-cmd --zone=public --add-port=5201/tcp --permanent
    sudo firewall-cmd --zone=public --add-port=5201/udp --permanent
    sudo firewall-cmd --reload

else
    echo "Invalid or unsupported image type: $image"
    exit 1
fi
