# C:\CITA\LabTools\src\Menu\DevOpsLabInstallOpsMenu.ps1
# DevOps Lab Repository - Install Operations Submenu

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Import-Module (Join-Path $PSScriptRoot "..\UI\ConsoleUI.psm1") -Force -ErrorAction Stop

function Wait-Menu {
    Write-Host ""
    Read-Host "Press Enter to continue" | Out-Null
}

function Show-DevOpsLabInstallOpsMenu {
    param(
        [string]$StatusText = "Ready",
        [string]$StatusColor = "DarkGray"
    )

    Show-AppHeader -Breadcrumb "Main > DevOps / CLI Tools > Lab Repository - Install Operations"

    Write-Host "  Lab Repository - Install Operations" -ForegroundColor Cyan
    Write-Host "  [1] Install core platform (Cluster + MetalLB + Ingress)"
    Write-Host "  [2] Repair / Reinstall MetalLB (IP pool/range)"
    Write-Host "  [3] Install / Reinstall Portainer Admin UI (Ingress, NodePort IP, or LoadBalancer IP)"
    Write-Host "  [4] Deploy / Update CITA Web Demo (namespace + ConfigMap + LoadBalancer)"
    Write-Host "  [5] Scale CITA Web Demo (2/4/5/custom replicas)"
    Write-Host "  [6] Scale any deployed app (interactive selector)"
    Write-Host "  [7] Install / Update app via Helm (interactive)"
    Write-Host ""
    Write-Host "  [0] Back"
    Write-Host ""

    Write-Host "Status: " -NoNewline
    Write-Host $StatusText -ForegroundColor $StatusColor
    Write-Host ""
}

$script:lastStatusText  = "Ready"
$script:lastStatusColor = "DarkGray"
$script:MainMenuPath = Join-Path $PSScriptRoot "DevOpsToolsMenu.ps1"

$optionMap = @{
    "1" = "91"
    "2" = "92"
    "3" = "93"
    "4" = "94"
    "5" = "95"
    "6" = "96"
    "7" = "97"
}

$back = $false
while (-not $back) {
    Show-DevOpsLabInstallOpsMenu -StatusText $script:lastStatusText -StatusColor $script:lastStatusColor
    $choice = Read-Host "Select an option"

    switch ($choice) {
        "0" { $back = $true }
        "1" { }
        "2" { }
        "3" { }
        "4" { }
        "5" { }
        "6" { }
        "7" { }
        default {
            $script:lastStatusText  = "Invalid selection"
            $script:lastStatusColor = "Yellow"
            Start-Sleep -Seconds 1
            continue
        }
    }

    if ($choice -eq "0") { continue }

    if (-not (Test-Path $script:MainMenuPath)) {
        $script:lastStatusText  = "Main DevOps menu script not found"
        $script:lastStatusColor = "Red"
        Wait-Menu
        continue
    }

    $mapped = $optionMap[$choice]
    if ([string]::IsNullOrWhiteSpace($mapped)) {
        $script:lastStatusText  = "Invalid selection"
        $script:lastStatusColor = "Yellow"
        continue
    }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:MainMenuPath -RunOption $mapped
    if ($LASTEXITCODE -eq 0) {
        $script:lastStatusText  = "Action completed"
        $script:lastStatusColor = "Green"
    }
    else {
        $script:lastStatusText  = "Action finished with non-zero exit code"
        $script:lastStatusColor = "Yellow"
    }
}

Clear-Host
return
