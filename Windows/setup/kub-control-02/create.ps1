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

$VM_NAME = "kub-control-02"

# Create the VM
multipass launch `
  --name "$VM_NAME" `
  --cpus 4 `
  --memory 3G `
  --disk 10G `
  24.10

# Transfer and execute initialization scripts
multipass transfer ./machine-init-common.sh $VM_NAME`:/home/ubuntu/machine-init-common.sh
multipass transfer ./machine-init-kubnode.sh $VM_NAME`:/home/ubuntu/machine-init.sh
multipass exec $VM_NAME -- chmod +x /home/ubuntu/machine-init-common.sh
multipass exec $VM_NAME -- chmod +x /home/ubuntu/machine-init.sh
multipass exec $VM_NAME -- /home/ubuntu/machine-init-common.sh
multipass exec $VM_NAME -- `
    env HOST_IP=$HostIP `
    /home/ubuntu/machine-init.sh

# Mount external storage
multipass stop $VM_NAME
multipass mount -t native -v "$HostMountRoot/data/$VM_NAME" $VM_NAME`:"/home/ubuntu/ext-data"
multipass mount -t native -v "$HostMountRoot/data/common" $VM_NAME`:"/home/ubuntu/ext-common"
multipass start $VM_NAME
