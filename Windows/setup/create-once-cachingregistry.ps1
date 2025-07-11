#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
$WarningPreference = 'Continue'
$VerbosePreference = 'Continue'
Set-PSDebug -Trace 1

# Set variables
$REGISTRYDATA_DIR = (Get-Item (New-Item -Path (Join-Path $PSScriptRoot "../data/registry") -ItemType Directory -Force)).FullName

# Get current Kubernetes images for v1.33.x
Write-Information "Getting latest Kubernetes stable version..."
#$K8S_VERSION = (Invoke-WebRequest -Uri "https://dl.k8s.io/release/stable-1.33.txt" -UseBasicParsing).Content.Trim()
$K8S_VERSION = "v1.33.2"
Write-Information "Caching Kubernetes images for version: $K8S_VERSION"

# List of images to pull and cache
$IMAGES = @(
    "docker.io/jpillora/dnsmasq:latest"
    "registry.k8s.io/kube-apiserver:$K8S_VERSION"
    "registry.k8s.io/kube-controller-manager:$K8S_VERSION"
    "registry.k8s.io/kube-scheduler:$K8S_VERSION"
    "registry.k8s.io/kube-proxy:$K8S_VERSION"
    "registry.k8s.io/pause:3.10"
    "registry.k8s.io/etcd:3.5.10-0"
    "registry.k8s.io/coredns/coredns:v1.11.1"
    "quay.io/tigera/operator:v1.38.1"
    "quay.io/calico/typha:v3.30.1"
    "quay.io/calico/ctl:v3.30.1"
    "quay.io/calico/node:v3.30.1"
    "quay.io/calico/cni:v3.30.1"
    "quay.io/calico/apiserver:v3.30.1"
    "quay.io/calico/kube-controllers:v3.30.1"
    "quay.io/calico/dikastes:v3.30.1"
    "quay.io/calico/pod2daemon-flexvol:v3.30.1"
    "quay.io/calico/csi:v3.30.1"
    "quay.io/calico/node-driver-registrar:v3.30.1"
    "quay.io/metallb/controller:v0.15.2"
    "quay.io/metallb/speaker:v0.15.2"
    "registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.5.0"
    "registry.k8s.io/ingress-nginx/controller:v1.10.6"
    "registry.k8s.io/ingress-nginx/controller-chroot:v1.10.6"
    "quay.io/ceph/ceph:v19.2.2"
    "docker.io/rook/ceph:v1.17.5"
    "quay.io/cephcsi/cephcsi:v3.14.0"
    "registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.13.0"
    "registry.k8s.io/sig-storage/csi-provisioner:v5.2.0"
    "registry.k8s.io/sig-storage/csi-snapshotter:v8.2.1"
    "registry.k8s.io/sig-storage/csi-attacher:v4.8.1"
    "registry.k8s.io/sig-storage/csi-resizer:v1.13.2"
    "quay.io/csiaddons/k8s-sidecar:v0.12.0"
    "docker.io/otel/opentelemetry-collector-contrib:0.128.0"
    "docker.io/grafana/grafana:12.0.1-ubuntu"
    "docker.io/bats/bats:v1.4.1"
    "docker.io/curlimages/curl:8.9.1"
    "docker.io/library/busybox:1.31.1"
    "docker.io/kiwigrid/k8s-sidecar:1.30.0"
    "docker.io/grafana/grafana-image-renderer:3.12.6"
    "docker.io/prom/prometheus:v3.4.1"
    "docker.io/grafana/loki:main-1427b01"
    "docker.io/grafana/tempo:main-9da00a2"
)

# Pull all images
foreach ($image in $IMAGES) 
{
    podman image exists $image
    if ($LASTEXITCODE) 
    {
        Write-Information "Pulling image $image..."
        podman pull $image
    }
    else {
        Write-Information "Image $image already exists locally."
    }
}

# Cache registry image
$REGISTRY_IMAGE = "docker.io/library/registry:2"
podman image exists $REGISTRY_IMAGE
if ($LASTEXITCODE) {
    Write-Information "Pulling registry image..."
    podman pull $REGISTRY_IMAGE
}
else {
    Write-Information "Registry image already exists locally."
}

# Create a directory for the registry data
if (-not (Test-Path -Path $REGISTRYDATA_DIR)) 
{
    Write-Information "Creating registry data directory: $REGISTRYDATA_DIR"
    New-Item -ItemType Directory -Path $REGISTRYDATA_DIR -Force
}

# Stop any existing registry container
Write-Information "Setting up local registry on port 5001..."
try {
    podman container rm -f local-registry
    Write-Information "Removed existing local-registry container."
}
catch {
    Write-Information "No existing local-registry container found."
}

# Start a new registry container
Write-Information "Starting new registry container..."
podman run -d --name local-registry `
    -p 5001:5000 `
    -v "$REGISTRYDATA_DIR`:/var/lib/registry" `
    --restart always `
    $REGISTRY_IMAGE

# Wait for registry to start
Write-Information "Waiting for registry to start..."
Start-Sleep -Seconds 3

# Tag and push all the images to the local registry
Write-Information "Pushing images to local registry..."
foreach ($image in $IMAGES) 
{
    # Create a local registry tag
    $imageParts = $image.Split('/', [System.StringSplitOptions]::RemoveEmptyEntries)
    $imageName = if ($imageParts.Count -gt 1) { $imageParts[1..($imageParts.Count - 1)] -join '/' } else { $imageParts[0] }
    $local_tag = "cachingregistry:5001/$imageName"
    
    # Tag and push the image
    Write-Information "Tagging $image as $local_tag"
    podman tag $image $local_tag
    
    Write-Information "Pushing $local_tag to local registry..."
    podman push --tls-verify=false $local_tag
    if ($LASTEXITCODE)
    {
        throw "Failed to push image $image"
    }
    Write-Information "Successfully pushed $image as $local_tag"
}

# Push registry image itself
$local_registry_tag = "cachingregistry:5001/registry:2"
Write-Information "Tagging and pushing registry image itself..."
podman tag $REGISTRY_IMAGE $local_registry_tag
podman push --tls-verify=false $local_registry_tag
if ($LASTEXITCODE)
{
    throw "Failed to push image $REGISTRY_IMAGE"
}
Write-Information "Successfully pushed registry image as $local_registry_tag"

Write-Information "All images have been cached in the local registry."
