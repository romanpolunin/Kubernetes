#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
$WarningPreference = 'Continue'
$VerbosePreference = 'Continue'
Set-PSDebug -Trace 1

# Add and update Grafana Helm repo
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Create telemetry namespace if it doesn't exist
kubectl create namespace telemetry --dry-run=client -o yaml | kubectl apply -f -

# Install Grafana with custom values for Rook+Ceph persistence and ingress
helm upgrade --install grafana grafana/grafana --namespace telemetry -f ./helm-values-grafana.yaml

# Display admin password
Write-Host "Grafana admin password:"
kubectl get secret --namespace telemetry grafana -o jsonpath="{.data.admin-password}" `
    | ForEach-Object { [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($_)) }

# Display ingress information
Write-Host "Grafana can be accessed via:"
kubectl get ingress -n telemetry

# Apply YAML files
kubectl apply -f ./00-rbac.yaml
kubectl apply -f ./01-configmaps.yaml
kubectl apply -f ./02-persistence.yaml
kubectl apply -f ./03-deployments.yaml
kubectl apply -f ./04-otel-collector-cluster.yaml
kubectl apply -f ./05-otel-collector-daemonset-apps.yaml
kubectl apply -f ./06-otel-collector-daemonset-infra.yaml
kubectl apply -f ./07-services.yaml

kubectl wait --for=condition=ready pod -n telemetry --all=true --timeout=300s
