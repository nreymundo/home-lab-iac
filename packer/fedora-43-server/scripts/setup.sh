#!/bin/bash
set -euo pipefail

echo "==> Packer: Building K3s-ready Fedora 43 base image"

echo "==> 1. System Update"
dnf upgrade -y

# Enable NTP (chrony already installed via Kickstart)
systemctl enable chronyd
systemctl start chronyd

echo "==> 2. K3s Prerequisites: Kernel Modules"
# Required by K3s and should be in the base image
cat <<EOF | tee /etc/modules-load.d/k3s.conf
overlay
br_netfilter
EOF

# Load them now (will auto-load on boot)
modprobe overlay
modprobe br_netfilter

echo "==> 3. K3s Prerequisites: Sysctl Configuration"
# Kernel parameters for Kubernetes networking
cat <<EOF | tee /etc/sysctl.d/k3s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

echo "==> 4. K3s Prerequisites: Disable Swap"
# K3s requires swap to be disabled
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

echo "==> 5. VM Template Preparation"
# Reset machine-id so each VM clone gets unique ID and DHCP IP
truncate -s 0 /etc/machine-id

# Clear cloud-init state so it runs on first boot
cloud-init clean --logs --seed

echo "==> 6. Cleanup"
dnf autoremove -y
dnf clean all
rm -rf /tmp/*
rm -rf /var/tmp/*

# Clear bash history
rm -f /root/.bash_history
> /home/fedora/.bash_history
history -c

echo "==> Fedora base image preparation complete!"
echo "==> This image is ready for Ansible provisioning with k3s_server or k3s_agent roles"
