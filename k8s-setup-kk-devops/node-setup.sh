#!/bin/bash
# Kubernetes Worker Node Setup Script with kubeconfig setup for non-root user
# Prerequisites:
# - Ubuntu 20.04+
# - 1GB RAM, 1 Core (t2.micro instance on AWS)


# ----------------- CONFIG -----------------
NON_ROOT_USER="ubuntu"   # Change this to your actual username
#MASTER_JOIN_COMMAND=""   # IMPORTANT ---> Fill this with the join command from master output
MASTER_JOIN_COMMAND="kubeadm join 172.31.93.113:6443 --token fxrt5n.8mmq5giqdvmrp15f --discovery-token-ca-cert-hash sha256:0b22a18cd1330bef13dc3fd3968f2b38d100433fd3ced449be23b13421212e18"
# Example: kubeadm join 192.168.1.10:6443 --token abcdef.0123456789abcdef --discovery-token-ca-cert-hash sha256:xyz
# -------------------------------------------

set -e

log_message() { echo -e "\e[32m[INFO] $1\e[0m"; }
log_error() { echo -e "\e[31m[ERROR] $1\e[0m" >&2; exit 1; }

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root. Please use sudo."
    fi
    log_message "Running as root user."
}

disable_swap() {
    if [ "$(swapon --show)" ]; then
        log_message "Disabling swap..."
        swapoff -a
        sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    else
        log_message "Swap is already disabled."
    fi
}

load_kernel_modules() {
    log_message "Loading kernel modules..."
    cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
    modprobe overlay
    modprobe br_netfilter
}

configure_sysctl() {
    log_message "Configuring sysctl..."
    cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
    sysctl --system
}

install_containerd() {
    log_message "Installing containerd..."
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg lsb-release
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y containerd.io
    containerd config default | tee /etc/containerd/config.toml
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    systemctl restart containerd
    systemctl enable containerd
}

install_kubernetes() {
    log_message "Installing Kubernetes..."
    apt-get update -y
    apt-get install -y apt-transport-https ca-certificates curl
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
    apt-get update -y
    apt-get install -y kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl
    systemctl enable kubelet
}

join_cluster() {
    if [ -z "$MASTER_JOIN_COMMAND" ]; then
        log_error "MASTER_JOIN_COMMAND is not set. Please paste the join command from the master node."
    fi
    log_message "Joining the Kubernetes cluster..."
    eval "$MASTER_JOIN_COMMAND"
}

log_message "Starting Kubernetes Worker Node Setup..."
check_root
disable_swap
load_kernel_modules
configure_sysctl
install_containerd
install_kubernetes
join_cluster
log_message "Kubernetes Worker Node setup complete."