#!/bin/bash

# Function to display messages
function print_message() {
    echo -e "\n###############################"
    echo -e "$1"
    echo -e "###############################\n"
}

# Define Load Balancer IP or the actual master node IP (to be set after getting the join command from master)
MASTER_IP="172.22.226.168"  # <-- Change this to the actual master node IP or Load Balancer IP
JOIN_COMMAND="kubeadm join 172.22.226.168:6443 --token vlr9wh.mx5aowlbmwz0rqda \
        --discovery-token-ca-cert-hash sha256:ae8ed55aacd9a808e6cf430a2f834ca697edbf35122262e0638311aa06ce403b \
        --node-labels=node-role.kubernetes.io/worker=worker"  # <-- Replace with the actual join command received from master

# Step 1: Clean Up Previous Kubernetes Installations
print_message "Checking and cleaning up any previous Kubernetes setup..."

if [ -f /etc/kubernetes/admin.conf ]; then
    print_message "Previous Kubernetes installation detected. Resetting..."
    sudo kubeadm reset -f
    sudo rm -rf /etc/kubernetes/ /var/lib/etcd ~/.kube
    sudo systemctl restart containerd kubelet
    print_message "Previous installation removed."
fi

# Step 2: Disable Swap
print_message "Disabling swap (Kubernetes requires swap to be off)..."
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Step 3: Configure Containerd
print_message "Configuring containerd for Kubernetes..."
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null

# Enable CRI and SystemdCgroup
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

# Step 6: Install Dependencies
print_message "Updating system and installing dependencies..."
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg software-properties-common

# Step 7: Install Docker
print_message "Installing Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io
sudo systemctl enable --now docker

# Step 8: Install Kubernetes
print_message "Installing Kubernetes components..."
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet

# Step 9: Join the Node to the Kubernetes Cluster
print_message "Joining the worker node to the cluster..."
if [ -z "$JOIN_COMMAND" ]; then
    print_message "The join command is not set. Please provide the 'kubeadm join' command from the master node."
    exit 1
fi

# Execute the kubeadm join command
sudo $JOIN_COMMAND

if [ $? -ne 0 ]; then
    print_message "Failed to join the node to the cluster. Please check the logs."
    exit 1
fi

# Step 10: Verify Installation
print_message "Verifying Kubernetes worker node installation..."
kubectl get nodes

print_message "Kubernetes worker node successfully joined the cluster!"
