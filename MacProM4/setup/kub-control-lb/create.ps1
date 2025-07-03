#!/usr/bin/env pwsh
param(
    [Parameter(Mandatory=$true)]
    [string]$HostMountRoot,
    [Parameter(Mandatory=$true)]
    [string]$HostIP
)

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
$WarningPreference = 'Continue'
$VerbosePreference = 'Continue'
Set-PSDebug -Trace 1

$VM_NAME = "kub-control-lb"

# Create the VM
multipass launch `
  --name "$VM_NAME" `
  --cpus 2 `
  --memory 500M `
  --disk 5G `
  24.10

# Transfer and execute initialization scripts
multipass transfer ./machine-init-common.sh $VM_NAME`:/home/ubuntu/machine-init-common.sh
multipass transfer ./machine-init-other.sh $VM_NAME`:/home/ubuntu/machine-init.sh
multipass exec $VM_NAME -- chmod +x /home/ubuntu/machine-init-common.sh
multipass exec $VM_NAME -- chmod +x /home/ubuntu/machine-init.sh
multipass exec $VM_NAME -- /home/ubuntu/machine-init-common.sh
multipass exec $VM_NAME -- `
    env HOST_IP=$HostIP `
    /home/ubuntu/machine-init.sh

# Mount external storage
multipass stop $VM_NAME
multipass mount -t native -v "$HostMountRoot/data/common" $VM_NAME`:"/home/ubuntu/ext-common"
multipass start $VM_NAME
