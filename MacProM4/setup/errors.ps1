#!/usr/bin/env pwsh
# Script to find recent errors in Kubernetes logs within a namespace
param(
    [Parameter(Position=0, HelpMessage="Time range to search logs (e.g., 1h, 30m, 5m)")]
    [string]$Since = "1h",
    
    [Parameter(Position=1, HelpMessage="Kubernetes namespace to search")]
    [string]$Namespace = "default"
)

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
$WarningPreference = 'Continue'
$VerbosePreference = 'Continue'
Set-PSDebug -Trace 0

Write-Information "=== Finding recent errors in Kubernetes logs ($Namespace namespace) ==="

# Check if namespace exists
$namespaceExists = kubectl get namespace $Namespace 2>$null
if (-not $namespaceExists) {
    Write-Warning "$Namespace namespace does not exist!"
    Write-Information "Usage: ./errors.ps1 -Since 1h -Namespace telemetry"
    exit 1
}

# Get all pods in the specified namespace
Write-Information "Collecting pods in $Namespace namespace..."
$pods = kubectl get pods -n $Namespace -o jsonpath='{.items[*].metadata.name}'

if (-not $pods) {
    Write-Warning "No pods found in $Namespace namespace."
    exit 0
}

# Set the time range for recent logs
Write-Information "Searching for errors in logs from the last $Since"

# Check each pod for errors
foreach ($pod in $pods.Split()) {
    Write-Information "Checking pod: $pod" 
    
    # Get errors from pod logs
    $errors = kubectl logs -n $Namespace $pod --all-containers --since=$Since 2>$null | 
              Select-String -Pattern 'error|exception|fail|critical|warn' -CaseSensitive:$false | 
              Where-Object { $_ -notmatch "level=info" }
    
    if ($errors) {
        Write-Information "Found errors in pod $pod`:"
        $errors | Select-Object -First 20 | ForEach-Object { Write-Warning $_ }
        
        # If there are more than 20 errors, show count of remaining ones
        $errorCount = $errors.Count
        if ($errorCount -gt 20) {
            $remaining = $errorCount - 20
            Write-Warning "...and $remaining more errors/warnings (use kubectl logs -n $Namespace $pod to see all)"
        }
        Write-Information ""
    }
    else {
        Write-Information "No errors found."
    }
}

Write-Information "=== Log check complete ===" 
