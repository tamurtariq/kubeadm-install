#!/bin/bash

# Function to display messages
function print_message() {
    echo -e "\n###############################"
    echo -e "$1"
    echo -e "###############################\n"
}

# Step 1: Clean Up Previous Kubernetes Installations
print_message "Checking and cleaning up any previous Kubernetes setup..."

# Check if kubeadm init was previously run
if [ -f /etc/kubernetes/admin.conf ]; then
    print_message "Previous Kubernetes installation detected. Resetting..."
    sudo kubeadm reset -f
    sudo rm -rf /etc/kubernetes/
    sudo rm -rf /var/lib/etcd
    sudo rm -rf ~/.kube
    sudo systemctl restart containerd
    sudo systemctl restart kubelet
    print_message "Previous installation removed."
fi

# Step 2: Disable Swap
print_message "Disabling swap (Kubernetes requires swap to be off)..."
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Step 3: Ensure containerd is properly configured as the CRI runtime
print_message "Configuring containerd for Kubernetes..."
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null

# Enable CRI in containerd
sudo sed -i 's/^disabled_plugins/#disabled_plugins/' /etc/containerd/config.toml
sudo sed -i '/disabled_plugins/s/"cri"//g' /etc/containerd/config.toml
sudo sed -i '/SystemdCgroup = false/c\    SystemdCgroup = true' /etc/containerd/config.toml

# Restart containerd
sudo systemctl restart containerd
sudo systemctl enable --now containerd

# Step 4: Load Kernel Modules
print_message "Loading required kernel modules..."
sudo modprobe overlay
sudo modprobe br_netfilter

# Step 5: Apply sysctl settings
print_message "Applying sysctl settings for Kubernetes networking..."
sudo tee /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system

# Step 6: Update apt and install dependencies
print_message "Updating system and installing dependencies..."
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg software-properties-common

# Step 7: Install Docker (Required for containerd)
print_message "Installing Docker dependencies..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io
sudo systemctl enable --now docker

# Step 8: Install Kubernetes components
print_message "Installing kubelet, kubeadm, and kubectl..."
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet

# Step 9: Initialize Kubernetes Cluster
print_message "Initializing Kubernetes cluster..."
sudo kubeadm init --cri-socket unix:///run/containerd/containerd.sock --pod-network-cidr=10.244.0.0/16

# Step 10: Set up kubeconfig for kubectl
print_message "Setting up kubeconfig..."
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Step 11: Install Flannel network plugin
print_message "Installing Flannel network plugin..."
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml

# Step 12: Verify Installation
print_message "Verifying Kubernetes installation..."
kubectl get nodes

print_message "Kubernetes installation and initialization completed successfully!"
