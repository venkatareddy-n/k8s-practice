#!/bin/bash
# Kubernetes Master Node Setup Script
# Prerequisites:
# Ubuntu 20.04+
# master (4GB RAM , 2 Core) t2.medium

# ------------------------------------------------------------------------------
# This script installs Kubernetes (kubeadm, kubelet, kubectl) on an Ubuntu server
# with containerd as the container runtime and configures Weave Net as the CNI plugin.
# It includes system validation, CRI configuration, and networking setup.

# Kubernetes Master Node Setup Script with kubeconfig setup for non-root user

# ----------------- CONFIG -----------------
NON_ROOT_USER="ubuntu"   # Change this to your actual username
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

initialize_master_node() {
    log_message "Initializing master node..."
    kubeadm init --cri-socket /run/containerd/containerd.sock

    log_message "Setting up kubeconfig for root..."
    mkdir -p /root/.kube
    cp /etc/kubernetes/admin.conf /root/.kube/config
    chown root:root /root/.kube/config

    if id "$NON_ROOT_USER" &>/dev/null; then
        log_message "Setting up kubeconfig for $NON_ROOT_USER..."
        mkdir -p /home/$NON_ROOT_USER/.kube
        cp /etc/kubernetes/admin.conf /home/$NON_ROOT_USER/.kube/config
        chown $NON_ROOT_USER:$NON_ROOT_USER /home/$NON_ROOT_USER/.kube/config
    fi
}

install_weave_net() {
    log_message "Installing Weave Net CNI..."
    kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml
}

display_join_command() {
    log_message "Cluster join command:"
    kubeadm token create --print-join-command
}

log_message "Starting Kubernetes Master Node Setup..."
check_root
disable_swap
load_kernel_modules
configure_sysctl
install_containerd
install_kubernetes
initialize_master_node
install_weave_net
display_join_command
log_message "Kubernetes Master Node setup complete."
