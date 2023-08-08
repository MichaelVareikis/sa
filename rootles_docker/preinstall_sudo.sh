#!/bin/bash
set -ex
[ `id -u` == 0 ] || { echo "Run as root user"; exit 1; }
source /etc/os-release
if [ $ID == "ubuntu" ]; then
    echo "Detected OS - $NAME $VERSION"
    apt update
    apt-get install -y dbus-user-session iptables uidmap
fi
if [ $ID == "rhel" ]; then
    echo "Detected OS - $NAME $VERSION"
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
    setenforce 0 && getenforce && sestatus
    dnf install -y fuse-overlayfs iptables
fi

modules=( "ip_tables" "iptable_nat" "nf_conntrack" "nf_conntrack_ipv4" "nf_nat_ipv4" "nf_nat" )
for mod in ${modules[@]}; do  modprobe $mod && echo $mod |  tee -a /etc/modules-load.d/modules.conf ||:; done

if [ -d /etc/sysctl.d ]; then
    log_state "Setting sysctl parameters"
    max_conn=20000
    current_max_conn_value=$(sysctl net.core.somaxconn 2> /dev/null | awk '{print $NF}' || : )
    (($current_max_conn_value > $max_conn)) 2> /dev/null && max_conn=$current_max_conn_value || :
    cat << EOF > /etc/sysctl.d/99-axonius.conf
    kernel.pid_max=64000
    net.core.somaxconn=$max_conn
    kernel.threads-max=200000
    kernel.panic=10
    net.ipv4.conf.all.accept_redirects=0
    net.ipv4.conf.default.accept_redirects=0
    net.ipv4.conf.all.secure_redirects=0
    net.ipv4.conf.default.secure_redirects=0
    net.ipv4.conf.all.forwarding=1
    net.ipv4.ip_forward=1
    vm.overcommit_memory=1
    vm.max_map_count=262144
EOF
    sysctl --load /etc/sysctl.d/99-axonius.conf
fi

#### KEEP LEGACY SUPPORT
function silent {
    $@ &> /dev/null || :
}

silent systemctl disable postfix 
silent systemctl mask postfix 

# TODO ???: dissable chisel
silent unlink /usr/local/bin/chise 
silent unlink /var/chef/cache/cookbooks/chef-repo/files/chisel_1.6.0_linux_amd64