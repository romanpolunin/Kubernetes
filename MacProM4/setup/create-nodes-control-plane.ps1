#!/usr/bin/env pwsh
param(
    [Parameter()]
    [string]$HostMountRoot = "$HOME/code/Kubernetes-Local",
    [Parameter()]
    [string]$HostIP = "192.168.64.1"
)

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
$WarningPreference = 'Continue'
$VerbosePreference = 'Continue'
Set-PSDebug -Trace 1

# Run create scripts
& ./kub-control-lb/create.ps1 -hostmountroot $HostMountRoot -hostip $HostIP

# Create directories if they don't exist
New-Item -ItemType Directory -Force -Path $HostMountRoot/data/kub-control-01
& ./kub-control-01/create.ps1 -hostmountroot $HostMountRoot -hostip $HostIP

New-Item -ItemType Directory -Force -Path $HostMountRoot/data/kub-control-02
& ./kub-control-02/create.ps1 -hostmountroot $HostMountRoot -hostip $HostIP

# Get IP addresses of VMs
$KUB_CONTROL_PLANE_LB = (multipass exec kub-control-lb -- ip -4 addr show eth0 | Select-String -Pattern 'inet ([0-9.]+)' | ForEach-Object { $_.Matches.Groups[1].Value })
$KUB_CONTROL_PLANE_01 = (multipass exec kub-control-01 -- ip -4 addr show eth0 | Select-String -Pattern 'inet ([0-9.]+)' | ForEach-Object { $_.Matches.Groups[1].Value })
$KUB_CONTROL_PLANE_02 = (multipass exec kub-control-02 -- ip -4 addr show eth0 | Select-String -Pattern 'inet ([0-9.]+)' | ForEach-Object { $_.Matches.Groups[1].Value })

# Transfer and run the control plane LB install script
multipass transfer ./kub-control-lb/install-k8s-control-plane-lb.sh kub-control-lb`:/home/ubuntu/
multipass exec kub-control-lb -- `
    env HOST_IP=$HostIP `
    env KUB_CONTROL_PLANE_LB=$KUB_CONTROL_PLANE_LB `
    env KUB_CONTROL_PLANE_01=$KUB_CONTROL_PLANE_01 `
    env KUB_CONTROL_PLANE_02=$KUB_CONTROL_PLANE_02 `
    ./install-k8s-control-plane-lb.sh

# Wait a few seconds for HAProxy to start up
Start-Sleep -Seconds 5

# Check HAProxy backend status
# Test if all configured backends of HAProxy are healthy
$HAPROXY_STATS_URL = "http://$KUB_CONTROL_PLANE_LB`:80/"
$response = Invoke-WebRequest -Uri $HAPROXY_STATS_URL -UseBasicParsing
if ($response.Content -match "kubernetes-masters") {
    Write-Host "HAProxy stats page is accessible."
} else {
    throw "Failed to access HAProxy stats page or find backend status."
}

# Transfer and run the primary control plane install script
multipass transfer ./kub-control-01/install-k8s-control-plane-primary.sh kub-control-01`:/home/ubuntu/
multipass exec kub-control-01 -- `
    env HOST_IP=$HostIP `
    env KUB_CONTROL_PLANE_LB=$KUB_CONTROL_PLANE_LB `
    env LOCAL_REGISTRY_HOST=$HostIP `
    env LOCAL_REGISTRY_PORT=5001 `
    ./install-k8s-control-plane-primary.sh

# Sleep couple seconds to let cluster propagate the Node state, otherwise wait can fail with NotFound
Start-Sleep -Seconds 2
multipass exec kub-control-01 -- kubectl wait --for=condition=Ready nodes --all --timeout=30s

# Transfer config file
$kubeConfigContent = multipass exec kub-control-01 -- sudo cat /etc/kubernetes/admin.conf
$kubeConfigContent | Out-File -FilePath $HOME/.kube/config -Force

kubectl wait --for=condition=Ready nodes --all --timeout=30s

# Fix file ownership
# Note: In PowerShell we don't need chown, setting the file content already ensures proper ownership

# Wait a few seconds for HAProxy to catch up
Start-Sleep -Seconds 5

# Test if one configured backend of HAProxy is healthy
$BACKEND_STATUS = (Invoke-WebRequest -Uri $HAPROXY_STATS_URL -UseBasicParsing).Content | 
                  Select-String -Pattern 'kubernetes-masters.*UP' -AllMatches | 
                  ForEach-Object { $_.Matches.Value }

if ($BACKEND_STATUS -match "UP") {
    Write-Host "At least one HAProxy backend appears healthy"
} else {
    throw "One or more HAProxy backends may be down."
}

# Try to extract existing certificate key from kubeadm-certs secret if it exists
$EXISTING_CERT_KEY = (multipass exec kub-control-01 -- sudo bash -c 'kubectl -n kube-system get secret kubeadm-certs -o jsonpath="{.data.certificate-key}" 2>/dev/null | base64 -d')

# If no existing cert key found, create a new one
if ([string]::IsNullOrWhiteSpace($EXISTING_CERT_KEY)) {
    $KUB_CERT_KEY = multipass exec kub-control-01 -- sudo kubeadm init phase upload-certs --upload-certs | 
                   Select-Object -Last 1 | ForEach-Object { ($_ -split "\s+")[0] }
} else {
    $KUB_CERT_KEY = $EXISTING_CERT_KEY
    Write-Host "Using existing certificate key from kubeadm-certs secret"
}

# Get join token and certificate hash
$KUB_JOIN_TOKEN = multipass exec kub-control-01 -- sudo kubeadm token list | 
                  Select-String -Pattern 'authentication,signing' | ForEach-Object { ($_ -split "\s+")[0] }
$KUB_CERT_HASH = multipass exec kub-control-01 -- openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | 
                openssl rsa -pubin -outform der 2>/dev/null | 
                openssl dgst -sha256 -hex | ForEach-Object { $_ -replace '^.* ', '' }

# Transfer and run the secondary control plane install script
multipass transfer ./kub-control-02/install-k8s-control-plane-secondary.sh kub-control-02`:/home/ubuntu/
multipass exec kub-control-02 -- `
    env HOST_IP=$HostIP `
    env KUB_CONTROL_PLANE_LB=$KUB_CONTROL_PLANE_LB `
    env KUB_CERT_KEY=$KUB_CERT_KEY `
    env KUB_JOIN_TOKEN=$KUB_JOIN_TOKEN `
    env KUB_CERT_HASH=$KUB_CERT_HASH `
    env LOCAL_REGISTRY_HOST=$HostIP `
    env LOCAL_REGISTRY_PORT=5001 `
    ./install-k8s-control-plane-secondary.sh

# Sleep couple seconds to let cluster propagate the Node state, otherwise wait can miss the second node
Start-Sleep -Seconds 2
kubectl wait --for=condition=Ready nodes --all --timeout=30s

# Wait a few seconds for HAProxy to catch up
Start-Sleep -Seconds 5

# Test if all configured backends of HAProxy are healthy
$BACKEND_STATUS = (Invoke-WebRequest -Uri $HAPROXY_STATS_URL -UseBasicParsing).Content | 
                  Select-String -Pattern 'kubernetes-masters.*DOWN' -AllMatches | 
                  ForEach-Object { $_.Matches.Value }

if ($BACKEND_STATUS -match "DOWN") {
    throw "One or more HAProxy backends may be down."
} else {
    Write-Host "All HAProxy backends appear healthy."
}

Write-Host "Configuring CoreDNS to use locally running forwarder"
kubectl apply -f ./dns/coredns-configmap.yaml
kubectl rollout restart deployment/coredns -n kube-system  
kubectl rollout status deployment/coredns -n kube-system
