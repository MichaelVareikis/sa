#!/bin/bash
set -ex
[ `id -u` == 0 ] || { echo "Run as non root user"; exit 1; }
source /etc/os-release
if [ $ID == "ubuntu" ]; then
    echo "Detected OS - $NAME $VERSION"
    sudo apt update
    sudo apt-get install -y dbus-user-session iptables uidmap
fi
if [ $ID == "rhel" ]; then
    echo "Detected OS - $NAME $VERSION"
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
    setenforce 0 && getenforce && sestatus
    sudo dnf install -y fuse-overlayfs iptables
fi

modules=( "ip_tables" "iptable_nat" "nf_conntrack" "nf_conntrack_ipv4" "nf_nat_ipv4" "nf_nat" )
for mod in ${modules[@]}; do sudo modprobe $mod && echo $mod | sudo tee -a /etc/modules-load.d/modules.conf ||:; done