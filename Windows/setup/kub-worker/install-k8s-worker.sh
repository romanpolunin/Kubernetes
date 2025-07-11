#!/bin/bash
# Kubernetes Worker Node Install Script for Ubuntu 22.10
# Run as root or with sudo

set -ex

# Verify registry is running
ping ${LOCAL_REGISTRY_HOST} -c 2
echo "${LOCAL_REGISTRY_HOST} cachingregistry" | sudo tee -a /etc/hosts
LOCAL_REGISTRY="cachingregistry:${LOCAL_REGISTRY_PORT}"
if curl -s --connect-timeout 5 "http://${LOCAL_REGISTRY}/v2/_catalog" > /dev/null; then
  echo "✅ Local registry at ${LOCAL_REGISTRY} is accessible"
else
  echo "⚠️ Local registry not accessible"
  exit 1
fi

CACHE_DIR="/home/ubuntu/ext-common"
DATA_DIR="/home/ubuntu/ext-data"

# Update package lists
sudo apt-get update -o Dir::Cache::archives=${CACHE_DIR}/apt-get-packages

# Install common stuff
sudo apt-get install -y -o Dir::Cache::archives=${CACHE_DIR}/apt-get-packages \
    apt-transport-https=* ca-certificates=* curl=*

# 3. Install runc (required by containerd)
RUNC_VERSION=1.1.12
RUNC_ARCH=arm64  # Change to amd64 if your VM is x86_64
RUNC_FILENAME="runc.${RUNC_ARCH}"
sudo install -m 755 "${CACHE_DIR}/files/${RUNC_FILENAME}" /usr/local/sbin/runc

# 5. Install containerd
CONTAINERD_VERSION=2.1.1
CONTAINERD_ARCH=arm64
CONTAINERD_FILENAME="containerd-${CONTAINERD_VERSION}-linux-${CONTAINERD_ARCH}.tar.gz"
sudo tar -C /usr/local -xzf "${CACHE_DIR}/files/${CONTAINERD_FILENAME}"

sudo mkdir -p /usr/local/lib/systemd/system
sudo curl -L https://raw.githubusercontent.com/containerd/containerd/main/containerd.service -o /usr/local/lib/systemd/system/containerd.service

sudo mkdir -p /etc/containerd
#mkdir -p ${DATA_DIR}/containerd/root
#sudo chown -R root:root ${DATA_DIR}/containerd
#sudo chmod -R 700 ${DATA_DIR}/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml

# Configure containerd to use local registry
cat <<EOF | sudo tee -a /etc/containerd/config.toml
  [plugins."io.containerd.cri.v1.images".registry.configs]
    [plugins."io.containerd.cri.v1.images".registry.configs."cachingregistry:${LOCAL_REGISTRY_PORT}"]
      [plugins."io.containerd.cri.v1.images".registry.configs."cachingregistry:${LOCAL_REGISTRY_PORT}".auth]
        username = ""
        password = ""
        auth = ""
        identitytoken = ""
      [plugins."io.containerd.cri.v1.images".registry.configs."cachingregistry:${LOCAL_REGISTRY_PORT}".tls] 
        ca_file = ""
        cert_file = "" 
        insecure_skip_verify = true 
        key_file = ""

  [plugins."io.containerd.cri.v1.images".registry.mirrors]
    [plugins."io.containerd.cri.v1.images".registry.mirrors."cachingregistry:${LOCAL_REGISTRY_PORT}"]
      endpoint = ["http://cachingregistry:${LOCAL_REGISTRY_PORT}"]
EOF

# Update containerd config to use externally mounted folder for root and state
#sudo sed -i "s#^root = '.*#root = '${DATA_DIR}/containerd/root'#" /etc/containerd/config.toml
#sudo sed -i "s#^state = '.*#state = '${DATA_DIR}/containerd/state'#" /etc/containerd/config.toml

sudo systemctl daemon-reload
sudo systemctl enable containerd
sudo systemctl start containerd

# 3. Add Kubernetes apt repository
K8S_KEY_FILENAME="kubernetes-archive-keyring.asc"
sudo cp "${CACHE_DIR}/files/Release.key" /usr/share/keyrings/${K8S_KEY_FILENAME}

sudo gpg --dearmor -o /usr/share/keyrings/kubernetes-archive-keyring.gpg /usr/share/keyrings/${K8S_KEY_FILENAME}
sudo rm /usr/share/keyrings/${K8S_KEY_FILENAME}
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /" \
    | sudo tee /etc/apt/sources.list.d/kubernetes.list

# 7. Install kubelet, kubeadm
sudo apt-get update -o Dir::Cache::archives=${CACHE_DIR}/apt-get-packages
sudo apt-get install -y -o Dir::Cache::archives=${CACHE_DIR}/apt-get-packages kubelet=* kubeadm=*

# Hold packages to prevent automatic upgrades, but don't hold kubeadm
sudo apt-mark hold kubelet

# Configure kubelet to use externally mounted folder for root-dir
#sudo mkdir -p ${DATA_DIR}/kubelet
#sudo chown -R root:root ${DATA_DIR}/kubelet
#sudo mkdir -p /etc/systemd/system/kubelet.service.d
#cat <<EOF | sudo tee /etc/systemd/system/kubelet.service.d/10-local-storage.conf
#[Service]
#Environment="KUBELET_EXTRA_ARGS=--root-dir=${DATA_DIR}/kubelet"
#EOF
#sudo systemctl daemon-reload

# 8. Enable and start kubelet
sudo systemctl enable kubelet && sudo systemctl start kubelet

# 6a. Create kubeadm config file to set join parameters
cat <<EOF > /tmp/kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: JoinConfiguration
discovery:
  bootstrapToken:
    apiServerEndpoint: ${KUB_CONTROL_PLANE_LB}:6443
    token: ${KUB_JOIN_TOKEN}
    caCertHashes:
      - sha256:${KUB_CERT_HASH}
nodeRegistration:
  name: $(hostname)
  kubeletExtraArgs:
    node-ip: ${KUB_WORKER_IP}
EOF

# 6. Join existing Kubernetes cluster as a worker node
sudo kubeadm join --config=/tmp/kubeadm-config.yaml

# 7. Clean up - remove kubeadm as it's no longer needed after join
sudo apt-get purge -y kubeadm
sudo apt autoremove -y