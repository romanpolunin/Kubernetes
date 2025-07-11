#!/bin/bash
set -ex

# 1. Update system
cat <<MODS | sudo tee /etc/modules-load.d/otherstuff.conf
overlay
MODS
sudo modprobe overlay

# Sysctl params for networking
cat <<SYSCTL | sudo tee /etc/sysctl.d/otherstuff.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
SYSCTL
sudo sysctl --system

# 3. Configure network with static IP
echo 'options ipv6 disable=1' | sudo tee /etc/modprobe.d/disable-ipv6.conf
sudo sysctl -p

NETWORK_CONFIG="
network:
  version: 2
  renderer: networkd
  ethernets:
    default:
      set-name: eth0
"

echo "$NETWORK_CONFIG" | sudo tee /etc/netplan/99-custom-network.yaml
sudo chmod 600 /etc/netplan/99-custom-network.yaml
sudo chown root:root /etc/netplan/99-custom-network.yaml

#sudo netplan apply

# Show network interfaces status
ip addr show