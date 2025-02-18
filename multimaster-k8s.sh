#!/bin/bash

# Function to display messages
function print_message() {
    echo -e "\n###############################"
    echo -e "$1"
    echo -e "###############################\n"
}

# Define Load Balancer IP (Set this to your actual load balancer IP or hostname)
LOAD_BALANCER_IP="192.168.1.100"  # <-- Change this to your HAProxy/Keepalived VIP

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

# Step 9: Initialize Kubernetes Cluster
print_message "Initializing Kubernetes cluster on master node..."
sudo kubeadm init --control-plane-endpoint "$LOAD_BALANCER_IP:6443" --upload-certs --pod-network-cidr=10.244.0.0/16 --cri-socket unix:///run/containerd/containerd.sock

if [ $? -ne 0 ]; then
    print_message "Kubeadm init failed. Please check the logs and retry."
    exit 1
fi

# Step 10: Set up kubeconfig
print_message "Setting up kubeconfig..."
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Step 11: Install Flannel (Try 3 times in case of failure)
print_message "Installing Flannel network plugin..."
for i in {1..3}; do
    kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml && break
    print_message "Retrying Flannel installation..."
    sleep 5
done

# Step 12: Generate Join Command for Additional Masters
print_message "Generating join command for additional masters..."
JOIN_COMMAND=$(kubeadm token create --print-join-command)

if [ -z "$JOIN_COMMAND" ]; then
    print_message "Failed to generate join command. Please check cluster status."
    exit 1
fi

CERT_KEY=$(sudo kubeadm init phase upload-certs --upload-certs | tail -n 1)
MASTER_JOIN_CMD="$JOIN_COMMAND --control-plane --certificate-key $CERT_KEY"

echo "$MASTER_JOIN_CMD" > ~/join-command.txt
print_message "Join command for other masters saved to ~/join-command.txt"

# Step 13: Verify Installation
print_message "Verifying Kubernetes installation..."
kubectl get nodes

print_message "Kubernetes multi-master setup initialized successfully!"

echo -e "To join additional masters, run the following command on each master node:\n"
echo -e "$MASTER_JOIN_CMD\n"
