#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
$WarningPreference = 'Continue'
$VerbosePreference = 'Continue'
Set-PSDebug -Trace 1

# Be nice first - try clean uninstallation
kubectl -n rook-ceph patch cephcluster rook-ceph --type merge `
    -p '{"spec":{"cleanupPolicy":{"confirmation":"yes-really-destroy-data"}}}'
helm uninstall rook-ceph-cluster -n rook-ceph

# Zapping the cluster affinity on block devices
# Have to do this when cycling at cluster level
$HOST_MOUNT_ROOT = "$HOME/code/Kubernetes-Local"
foreach ($i in @('01', '02', '03', '04')) 
{
    $VM_NAME = "kub-worker-$i"
    
    # Detach loop device
    multipass exec $VM_NAME -- sudo losetup -d /dev/loop10
    
    # Remove OSD files
    multipass exec $VM_NAME -- bash -c 'ls -r /var/lib/rook/**/*osd*.* | sudo xargs rm'
    
    # Remove the sparse file for the "block device" we feed to Ceph
    Remove-Item -Force "$HOST_MOUNT_ROOT/data/$VM_NAME/osd1.img" -ErrorAction SilentlyContinue
}

# Wipe out Rook's state
# This is for the case when Rook operator is nuked, but worker VMs are not
foreach ($i in @('01', '02', '03', '04')) 
{
    multipass exec "kub-worker-$i" -- sudo rm -rf /var/lib/rook
}

# Now not so nice - forcefully remove resources
kubectl -n rook-ceph patch cephcluster rook-ceph --type merge -p '{"spec":{"cleanupPolicy":{"confirmation":"yes-really-destroy-data"}}}'
kubectl -n rook-ceph delete cephcluster rook-ceph

# Remove finalizers from Ceph CRDs
$CRDs = kubectl get crd -n rook-ceph | Select-String "ceph.rook.io" `
    | ForEach-Object { ($_ -split '\s+')[0] }

foreach ($CRD in $CRDs) {
    $resources = kubectl get -n rook-ceph $CRD -o name
    foreach ($resource in $resources) 
    {
        kubectl patch -n rook-ceph $resource --type merge -p '{"metadata":{"finalizers": []}}'
    }
}

# List remaining resources
$namespaceResources = kubectl api-resources --verbs=list --namespaced -o name
foreach ($resource in $namespaceResources) {
    kubectl get --show-kind --ignore-not-found -n rook-ceph $resource
}

# Remove finalizers from specific resources
kubectl -n rook-ceph patch configmap rook-ceph-mon-endpoints --type merge -p '{"metadata":{"finalizers": []}}'
kubectl -n rook-ceph patch secrets rook-ceph-mon --type merge -p '{"metadata":{"finalizers": []}}'

# Force deletion of subvolumegroup
kubectl -n rook-ceph annotate cephfilesystemsubvolumegroups.ceph.rook.io my-subvolumegroup rook.io/force-deletion="true"
kubectl -n rook-ceph delete cephfilesystemsubvolumegroups.ceph.rook.io my-subvolumegroup

helm uninstall rook-ceph -n rook-ceph
kubectl delete namespace rook-ceph

Write-Host "Rook-Ceph teardown complete!"