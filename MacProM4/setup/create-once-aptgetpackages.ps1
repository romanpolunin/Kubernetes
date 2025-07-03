#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
$WarningPreference = 'Continue'
$VerbosePreference = 'Continue'
Set-PSDebug -Trace 1

# Define directories
$CACHE_DIR = (Get-Item (New-Item -Path (Join-Path $PSScriptRoot "../data/common") -ItemType Directory -Force)).FullName

# Create directory structure for cached files
New-Item -Path "$CACHE_DIR/files" -ItemType Directory -Force

# Download binary files and cache them
$FILES_TO_CACHE = @(
    "https://github.com/opencontainers/runc/releases/download/v1.1.12/runc.arm64"
    "https://github.com/containerd/containerd/releases/download/v2.1.1/containerd-2.1.1-linux-arm64.tar.gz"
    "https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key"
)

foreach ($file_url in $FILES_TO_CACHE) {
    $file_name = Split-Path -Path $file_url -Leaf
    Write-Information "Downloading $file_url to $CACHE_DIR/files/$file_name"
    Invoke-WebRequest -Uri $file_url -OutFile "$CACHE_DIR/files/$file_name"
}

# Download calico manifest and update it to point to our own local repository
Write-Information "Downloading Calico manifest and updating repository references"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/projectcalico/calico/v3.30.1/manifests/tigera-operator.yaml" `
    -OutFile "$CACHE_DIR/files/tigera-operator.yaml"
(Get-Content -Path "$CACHE_DIR/files/tigera-operator.yaml") -replace "quay.io", "cachingregistry:5001" `
    | Set-Content -Path "$CACHE_DIR/files/tigera-operator.yaml"

# Create directory for Kubernetes packages
$APT_GET_PACKAGES_DIR = "$CACHE_DIR/apt-get-packages"
New-Item -Path $APT_GET_PACKAGES_DIR -ItemType Directory -Force

# Download Kubernetes packages if not already cached
Write-Information "Downloading apt-get packages for caching..."

# Create a temporary Docker container with Ubuntu 24.10 to download packages
# This is needed because we're running on macOS but need Linux packages
Write-Information "Running Podman container to download Kubernetes packages"
podman run --rm -v "$APT_GET_PACKAGES_DIR`:/packages" 'ubuntu:24.10' bash -c @'
  set -ex
  apt-get update && apt-get install -y curl apt-transport-https gnupg
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | gpg --dearmor -o /usr/share/keyrings/kubernetes-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
  apt-get update
  cd /packages
  
  # Create a temporary directory for apt cache
  mkdir -p /tmp/apt-cache
  
  # Download packages with all dependencies
  apt-get install -y --download-only --reinstall -o Dir::Cache::archives=/tmp/apt-cache \
      kubelet=1.33.* kubeadm=1.33.* kubectl=1.33.* \
      haproxy=2.9.* apt-transport-https=* ca-certificates=* curl=8* 
  
  # Copy all downloaded .deb files to our packages directory
  cp -f /tmp/apt-cache/*.deb /packages/
  
  # Display the downloaded packages
  ls -la /packages
'@

Write-Information "Packages downloaded to $APT_GET_PACKAGES_DIR"
