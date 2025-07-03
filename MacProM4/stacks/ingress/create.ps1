#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
$WarningPreference = 'Continue'
$VerbosePreference = 'Continue'
Set-PSDebug -Trace 1

$INGRESS_IP = "192.168.64.200"

# Create the ingress-system namespace first (without applying the full ingress config)
kubectl create namespace ingress-system --dry-run=client -o yaml | kubectl apply -f -

Write-Information "Installing MetalLB for predictable load balancer IPs..."
#Invoke-WebRequest -Uri "https://raw.githubusercontent.com/metallb/metallb/v0.15.2/config/manifests/metallb-native.yaml" -OutFile "./metallb.yaml"
#(Get-Content -Path "./metallb.yaml") -replace "registry.k8s.io", "cachingregistry:5001" `
#    | Set-Content -Path "./metallb.yaml"
#(Get-Content -Path "./metallb.yaml") -replace "quay.io", "cachingregistry:5001" `
#     | Set-Content -Path "./metallb.yaml"
kubectl apply -f ./metallb.yaml

# Wait for MetalLB to be ready
Write-Information "Waiting for MetalLB to be ready..."
kubectl wait --namespace metallb-system `
  --for=condition=ready pod `
  --selector=app=metallb `
  --timeout=300s

kubectl apply -f ./metallb-config.yaml

Write-Information "Installing Nginx Ingress Controller with LoadBalancer service..."
kubectl create namespace ingress-nginx

Write-Information "Applying Nginx Ingress Controller manifests..."

# Update Nginx ingress controller manifest to point to our own local repository
# ORIGINAL FILE: must apply manual edits to expose ports 4317 and 4318
# sed-based edits below are only for image hashes, but not for ports
# Bash equivalent: curl -L "https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.6/deploy/static/provider/cloud/deploy.yaml" -o ./ingress-controller-nginx.yaml
<# (Get-Content -Path "./ingress-controller-nginx.yaml") `
    -replace "registry.k8s.io", "cachingregistry:5001" `
    -replace "quay.io", "cachingregistry:5001" `
    -replace "aaafd456bda110628b2d4ca6296f38731a3aaf0bf7581efae824a41c770a8fc4", "2c67fe2e6cc5767ea162d1e75a03e98a732436d7dc3f0d4f43dddff162fd9476" `
    -replace "b6fbd102255edb3ba8e5421feebe14fd3e94cf53d199af9e40687f536152189c", "11ce078e0af29604299e59098a384cec834dfb898e1c1bfc6db7caa097352d48" `
    | Set-Content -Path "./ingress-controller-nginx.yaml"

# Enable explicit configuration of some static HTML snippets right in the config
(Get-Content -Path "./ingress-controller-nginx.yaml") `
  -replace 'allow-snippet-annotations: "false"', 'allow-snippet-annotations: "true"' `
  | Set-Content -Path "./ingress-controller-nginx.yaml"

# Configure the static IP address for the cluster ingress
# In PowerShell, we need a different approach than sed for insertion
$content = Get-Content -Path "./ingress-controller-nginx.yaml"
if (-not ($content -match "loadBalancerIP: $INGRESS_IP"))
{
    $newContent = @()
    $found = $false
    foreach ($line in $content) {
        $newContent += $line
        if ($line -match "externalTrafficPolicy: Local" -and -not $found) {
            $newContent += "  loadBalancerIP: $INGRESS_IP  # Specific IP from MetalLB pool"
            $found = $true
        }
    }
    $newContent | Set-Content -Path "./ingress-controller-nginx.yaml"
} #>

kubectl apply -f ./tcp-services-configmap.yaml
kubectl apply -f ./ingress-controller-nginx.yaml

Write-Information "Waiting for Nginx Ingress Controller to be ready..."
kubectl wait --namespace ingress-nginx `
  --for=condition=ready pod `
  --selector=app.kubernetes.io/component=controller `
  --timeout=300s

Write-Information "Nginx Ingress Controller installation complete"
Write-Information "Applying the cluster services ingress resources..."
kubectl apply -f ./cluster-services-ingress.yaml
