#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
$WarningPreference = 'Continue'
$VerbosePreference = 'Continue'
Set-PSDebug -Trace 1


helm repo add rook-release https://charts.rook.io/release
helm repo update

# provision Rook operator
helm upgrade --install --namespace rook-ceph --create-namespace `
  rook-ceph rook-release/rook-ceph -f helm-values-operator.yaml

kubectl label namespace rook-ceph pod-security.kubernetes.io/enforce=privileged

# enable use of loop devices, if not already configured in the operator helm
# kubectl -n rook-ceph patch configmap rook-ceph-operator-config \
#  --type merge -p '{"data":{"ROOK_CEPH_ALLOW_LOOP_DEVICES":"true"}}'

$HOST_MOUNT_ROOT="$HOME/code/Kubernetes-Local"
foreach ($i in @("01", "02", "03", "04"))
{
    $VM_NAME="kub-worker-$i"

    # allocate a sparse file for the "block device" we are going to feed to Ceph
    truncate -s 20g "$HOST_MOUNT_ROOT/data/$VM_NAME/osd1.img"
    dd if=/dev/zero of="$HOST_MOUNT_ROOT/data/$VM_NAME/osd1.img" bs=1m count=10 conv=notrunc  

    multipass exec $VM_NAME -- sudo losetup /dev/loop10 /home/ubuntu/ext-data/osd1.img
}

# create the cluster itself
helm upgrade --install --namespace rook-ceph `
  rook-ceph-cluster rook-release/rook-ceph-cluster -f helm-values-cluster.yaml

kubectl wait --for=condition=ready cephcluster -n rook-ceph --all=true --timeout=600s
kubectl wait --for=condition=ready pod -n rook-ceph --all=true --field-selector=status.phase!=Succeeded --timeout=600s

# retrieve dashboard admin user password
kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath="{['data']['password']}" `
  | base64 --decode