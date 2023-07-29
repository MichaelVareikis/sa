#!/bin/bash
set -ex
source /etc/os-release
if [ $ID == "ubuntu" ]; then
    echo "Detected OS - $NAME $VERSION"
    sudo apt update
    sudo apt-get install -y dbus-user-session iptables uidmap
    echo "ip_tables" | sudo tee -a /etc/modules-load.d/modules.conf
    sudo modprobe ip_tables
fi
if [ $ID == "rhel" ]; then
    echo "Detected OS - $NAME $VERSION"
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
    setenforce 0 && getenforce && sestatus
    sudo dnf install -y fuse-overlayfs iptables
    echo "ip_tables" | sudo tee -a /etc/modules-load.d/modules.conf
    sudo modprobe ip_tables
fi
