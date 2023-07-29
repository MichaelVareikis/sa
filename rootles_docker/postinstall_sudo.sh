#!/bin/bash
set -e
[ `id -u` == 0 ] && { echo "Run as non root user"; exit 1; }
hash rootlesskit &> /dev/null || { echo "rootlesskit not found, make sure you have docker rootless installed"; exit 1; }
rootlesskit_path=$(which rootlesskit)
cat << EOF 
Running this commands with sudo to allow rootlesskit to bind hosts ports below 1024
sudo setcap cap_net_bind_service=ep $rootlesskit_path
EOF

sudo setcap cap_net_bind_service=ep $rootlesskit_path
systemctl --user restart docker
