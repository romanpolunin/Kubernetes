#!/usr/bin/env pwsh
param(
    [Parameter(Mandatory=$true)]
    [string]$HostMountRoot,
    [Parameter(Mandatory=$true)]
    [string]$HostIP,
    [Parameter(Mandatory=$true)]
    [string]$VM_NAME
)

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
$WarningPreference = 'Continue'
$VerbosePreference = 'Continue'
Set-PSDebug -Trace 1

Write-Information "Creating VM $VM_NAME..."

# Create the VM
multipass launch `
    --name $VM_NAME `
    --cpus 6 `
    --memory 6G `
    --disk 20G `
    24.10

Write-Information "Transferring initialization script..." 
multipass transfer ./machine-init-common.sh $VM_NAME`:/home/ubuntu/machine-init-common.sh
multipass transfer ./machine-init-kubnode.sh $VM_NAME`:/home/ubuntu/machine-init.sh
multipass exec $VM_NAME -- chmod +x /home/ubuntu/machine-init-common.sh
multipass exec $VM_NAME -- chmod +x /home/ubuntu/machine-init.sh
multipass exec $VM_NAME -- /home/ubuntu/machine-init-common.sh
multipass exec $VM_NAME -- `
    env HOST_IP=$HostIP `
    /home/ubuntu/machine-init.sh

Write-Information "Setting up mounts..."
multipass stop $VM_NAME
multipass mount -t native -v "$HostMountRoot/data/$VM_NAME" $VM_NAME`:"/home/ubuntu/ext-data"
multipass mount -t native -v "$HostMountRoot/data/common" $VM_NAME`:"/home/ubuntu/ext-common"
multipass start $VM_NAME

Write-Information "VM $VM_NAME created and initialized successfully."
