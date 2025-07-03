#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
$WarningPreference = 'Continue'
$VerbosePreference = 'Continue'
Set-PSDebug -Trace 1

# Delete Kubernetes resources
kubectl delete -f ./07-services.yaml -n telemetry --ignore-not-found
kubectl delete -f ./06-otel-collector-daemonset-apps.yaml -n telemetry --ignore-not-found
kubectl delete -f ./05-otel-collector-daemonset-infra.yaml -n telemetry --ignore-not-found
kubectl delete -f ./04-otel-collector-cluster.yaml -n telemetry --ignore-not-found
kubectl delete -f ./03-deployments.yaml -n telemetry --ignore-not-found
kubectl delete -f ./02-persistence.yaml -n telemetry --ignore-not-found
kubectl delete -f ./01-configmaps.yaml -n telemetry --ignore-not-found
kubectl delete -f ./00-rbac.yaml -n telemetry --ignore-not-found

# Uninstall Grafana helm chart
helm uninstall grafana --namespace telemetry

# Delete the telemetry namespace
kubectl delete namespace telemetry --ignore-not-found