#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"
Set-PSDebug -Trace 1

$CONFIG_DIR = Join-Path $PSScriptRoot "dns"
$HostIP = "172.20.80.1"
$DNS_PORT = 5354

# Check for existing dnsmasq processes on port 5354
Write-Host "Checking for processes using port $DNS_PORT..."
$portCheck = netstat -an | Select-String -Pattern "\.$DNS_PORT"
if ($portCheck) {
    Write-Host "Found processes using port $DNS_PORT`:"
    lsof -i ":$DNS_PORT" || Write-Host "No process details found using lsof"
}

# Stop and remove any existing dnsmasq container
Write-Host "Stopping and removing existing dnsmasq container..."
try {
    podman stop dnsmasq 2>$null
} catch {
    Write-Host "No container to stop"
}

try {
    podman rm dnsmasq 2>$null
} catch {
    Write-Host "No container to remove"
}

# Run dnsmasq container
podman run -d `
    --name dnsmasq `
    --network bridge `
    --cap-add=NET_ADMIN `
    --privileged `
    --restart=always `
    -p "$($DNS_PORT):$($DNS_PORT)/udp" `
    -p "$($DNS_PORT):$($DNS_PORT)/tcp" `
    -v "${CONFIG_DIR}/dnsmasq.conf:/etc/dnsmasq.conf:ro" `
    "cachingregistry:5001/jpillora/dnsmasq:latest"

# Show container logs
podman logs dnsmasq

# Make sure dig and ifconfig are available under default WSL2 distro
wsl exec sudo apt-get install net-tools

# Testing DNS from host
Write-Host "Testing DNS from localhost:"
wsl exec dig '@127.0.0.1' -p $DNS_PORT google.com +short

Write-Host "Testing DNS from $HostIP`:"
wsl exec dig "@$HostIP" -p $DNS_PORT google.com +short

Write-Host "Container network information:"
$networkInfo = podman inspect dnsmasq | Select-String -Pattern "IPAddress|Networks|Ports" -AllMatches
$networkInfo | ForEach-Object { $_.Line }

Write-Host "Checking host network interfaces:"
$interfaces = wsl exec ifconfig | Select-String -Pattern "^[a-z]|inet " | Where-Object { $_ -notmatch "127.0.0.1" }
$interfaces | ForEach-Object { $_.Line }

Write-Host "Testing container DNS service:"
try {
    podman exec dnsmasq pidof dnsmasq
} catch {
    Write-Host "dnsmasq process not found"
}

try {
    podman exec dnsmasq netstat -tulpn 2>$null
} catch {
    Write-Host "netstat not available"
}
