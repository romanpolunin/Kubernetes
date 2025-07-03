#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
$WarningPreference = 'Continue'
$VerbosePreference = 'Continue'
Set-PSDebug -Trace 1

# Delete Kubernetes resources
kubectl delete -f ./ingress-controller-nginx.yaml --ignore-not-found
kubectl delete -f ./tcp-services-configmap.yaml --ignore-not-found
kubectl delete -f ./metallb-config.yaml --ignore-not-found
kubectl delete -f ./metallb.yaml --ignore-not-found

# Delete the ingress namespaces
kubectl delete namespace ingress-nginx --ignore-not-found
kubectl delete namespace ingress-system --ignore-not-found
kubectl delete namespace metallb-system --ignore-not-found