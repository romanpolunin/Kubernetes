#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
$WarningPreference = 'Continue'
$VerbosePreference = 'Continue'
Set-PSDebug -Trace 1

# Delete control plane VMs
try { multipass delete kub-control-01 } catch { Write-Warning "Could not delete kub-control-01" }
try { multipass delete kub-control-02 } catch { Write-Warning "Could not delete kub-control-02" }

# Delete worker VMs
foreach ($i in @("01", "02", "03", "04")) {
    try { 
        multipass delete "kub-worker-$i"
    } catch { 
        Write-Host "Could not delete kub-worker-$i"
    }
}

# Delete load balancer VM
try { multipass delete kub-control-lb } catch { Write-Host "Could not delete kub-control-lb" }

# Purge deleted VMs
multipass purge

# Remove VM data directories
Remove-Item -Path "../data/kub-*" -Recurse -Force
