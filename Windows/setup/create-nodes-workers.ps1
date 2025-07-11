#!/usr/bin/env pwsh
param(
    [Parameter()]
    [string]$HostMountRoot = "D:\Code\Kubernetes\Windows",
    [Parameter()]
    [string]$HostIP = "172.20.80.1"
)

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
$WarningPreference = 'Continue'
$VerbosePreference = 'Continue'
Set-PSDebug -Trace 1

$KUB_CONTROL_PLANE_LB = (multipass exec kub-control-lb -- ip -4 addr show eth0 | Select-String -Pattern 'inet ([0-9.]+)' | ForEach-Object { $_.Matches.Groups[1].Value })

# Try to extract existing certificate key from kubeadm-certs secret if it exists
$EXISTING_CERT_KEY = multipass exec kub-control-01 -- sudo bash -c 'kubectl -n kube-system get secret kubeadm-certs -o jsonpath="{.data.certificate-key}" 2>/dev/null | base64 -d'

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

# Create and configure worker nodes
foreach ($i in @("01", "02", "03", "04")) {
    # Create directory for worker data
    New-Item -ItemType Directory -Force -Path "$HostMountRoot/data/kub-worker-$i"
    
    # Create worker VM
    & ./kub-worker/create.ps1 -hostmountroot $HostMountRoot -hostip $HostIP -vm_name "kub-worker-$i"
    
    # Get worker IP
    $KUB_WORKER_IP = (multipass exec "kub-worker-$i" -- ip -4 addr show eth0 | 
                      Select-String -Pattern 'inet ([0-9.]+)' | ForEach-Object { $_.Matches.Groups[1].Value })
    
    # Transfer worker installation script
    multipass transfer ./kub-worker/install-k8s-worker.sh "kub-worker-$i`:/home/ubuntu/"
    
    # Execute worker installation
    multipass exec "kub-worker-$i" -- `
        env HOST_IP=$HostIP `
        env KUB_CONTROL_PLANE_LB=$KUB_CONTROL_PLANE_LB `
        env KUB_CERT_KEY=$KUB_CERT_KEY `
        env KUB_JOIN_TOKEN=$KUB_JOIN_TOKEN `
        env KUB_CERT_HASH=$KUB_CERT_HASH `
        env KUB_WORKER_IP=$KUB_WORKER_IP `
        env LOCAL_REGISTRY_HOST=$HostIP `
        env LOCAL_REGISTRY_PORT=5001 `
        ./install-k8s-worker.sh "kub-worker-$i"
}

kubectl wait --for=condition=Ready nodes --all --timeout=60s
kubectl run dnstest --image=busybox:1.28 --rm -it --restart=Never -- nslookup grafana.com