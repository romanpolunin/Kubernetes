#!/bin/bash
set -ex

# 1. Update system 
# Load Kubernetes kernel modules
cat <<MODS | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
MODS
sudo modprobe overlay
sudo modprobe br_netfilter

# Sysctl params for networking
cat <<SYSCTL | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
# Additional settings for bridge networking
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
SYSCTL
sudo sysctl --system

# 2. Disable swap (required by Kubernetes)
sudo swapoff -a
sudo sed -i '/ swap /s/^/#/' /etc/fstab

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
  bridges:
    br-pod:
      interfaces: []
      addresses: []
      optional: true
      parameters:
        stp: false
        forward-delay: 0
"

echo "$NETWORK_CONFIG" | sudo tee /etc/netplan/99-custom-network.yaml
sudo chmod 600 /etc/netplan/99-custom-network.yaml
sudo chown root:root /etc/netplan/99-custom-network.yaml

#sudo netplan apply

# Show network interfaces status
ip addr show