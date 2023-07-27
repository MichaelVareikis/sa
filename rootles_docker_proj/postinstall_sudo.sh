#!/bin/bash
set -ex
[ ! hash rootlesskit &> /dev/null ] && { echo "rootlesskit not found, make sure you have docker rootless installed"; exit 1; }
sudo setcap cap_net_bind_service=ep $(which rootlesskit)
systemctl --user restart docker
