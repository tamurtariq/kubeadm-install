# **Kubernetes Installation Script**

This script automates the process of installing and initializing a **Kubernetes cluster** using **containerd** as the container runtime. It includes steps for **cleaning up previous installations**, **disabling swap**, **installing Docker**, **kubeadm**, and **kubelet**, and finally, **setting up a network plugin (Flannel)**.


## **Prerequisites**

- A fresh **Ubuntu** machine (recommended: Ubuntu 20.04/22.04)
- **Root privileges** or the ability to use `sudo`
- An internet connection for downloading required packages
- Container runtime: **containerd** (as used in this script)

---

## **Script Overview**

### **Key Steps:**
1. **Check for Previous Kubernetes Installations:**
   - Cleans up previous installations, if any, using `kubeadm reset`.
2. **Swap Disablement:**
   - Ensures swap is disabled (Kubernetes requires this).
3. **Containerd Configuration:**
   - Configures containerd to work with Kubernetes as the container runtime.
4. **Install Dependencies:**
   - Installs necessary dependencies such as Docker and Kubernetes tools.
5. **Install Kubernetes Components:**
   - Installs `kubeadm`, `kubelet`, and `kubectl`.
6. **Initialize Kubernetes Cluster:**
   - Initializes the Kubernetes cluster with the given settings.
7. **Set Up Kubernetes Config:**
   - Configures `kubectl` to interact with the cluster locally.
8. **Install Flannel Network Plugin:**
   - Deploys the Flannel network plugin to the cluster.
9. **Verify Installation:**
   - Checks the status of the nodes to verify successful installation.

---

## **How to Use**

### **1. Download the Script:**

```bash
curl -o install_k8s.sh https://your-repository-link/install_k8s.sh
chmod +x install_k8s.sh
```

### **2. Run the Script:**
Execute the script with **root privileges** to install Kubernetes:

```bash
sudo ./install_k8s.sh
```

### **3. Check the Status of the Cluster:**

Once the script finishes, verify that the Kubernetes nodes are successfully running by using the following command:

```bash
kubectl get nodes
```

---

## **Script Flow**

### **1. Clean Previous Kubernetes Installation**
The script first checks if there is an existing Kubernetes installation. If it finds one, it resets it using `kubeadm reset` and deletes configuration directories.

```bash
if [ -f /etc/kubernetes/admin.conf ]; then
    sudo kubeadm reset -f
    sudo rm -rf /etc/kubernetes/
    sudo rm -rf /var/lib/etcd
    sudo rm -rf ~/.kube
    sudo systemctl restart containerd
    sudo systemctl restart kubelet
fi
```

### **2. Disable Swap**
Since Kubernetes does not support swap, this step ensures that swap is turned off and disables it permanently by modifying `/etc/fstab`.

```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
```

### **3. Configure containerd as the CRI**
The script configures containerd to be the default container runtime for Kubernetes by modifying `/etc/containerd/config.toml`.

```bash
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/\(disabled_plugins = \[.*\)"cri"/\1/' /etc/containerd/config.toml
sudo systemctl restart containerd
```

### **4. Install Dependencies**
This step ensures that necessary packages such as `apt-transport-https`, `curl`, `gpg`, and `software-properties-common` are installed, followed by the installation of Docker and Kubernetes tools.

### **5. Initialize the Cluster**
The script initializes the Kubernetes cluster with `kubeadm init`, specifying containerd as the container runtime and configuring the pod network CIDR.

```bash
sudo kubeadm init --cri-socket /run/containerd/containerd.sock --pod-network-cidr=10.244.0.0/16
```

### **6. Set Up kubeconfig**
The script automatically configures `kubectl` to interact with the new cluster locally by copying the admin config to the user's home directory and setting appropriate permissions.

### **7. Install Flannel Network Plugin**
Flannel is installed to manage pod networking in the cluster.

```bash
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
```

### **8. Verify Installation**
After everything is set up, the script verifies the node status by checking the Kubernetes node information.

```bash
kubectl get nodes
```

---

## **Troubleshooting**

- If the script encounters errors related to `kubeadm init` or containerd, ensure that containerd is properly installed and running:
  
  ```bash
  sudo systemctl status containerd
  ```

- If the script fails during Flannel installation, check the Flannel logs:

  ```bash
  kubectl logs -n kube-system -l app=flannel
  ```

---

## **Contributing**

Feel free to fork the repository and submit pull requests with any improvements or fixes. Make sure to follow the contribution guidelines and include tests for any new features.

---