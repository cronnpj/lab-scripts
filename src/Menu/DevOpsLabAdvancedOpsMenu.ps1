# C:\CITA\LabTools\src\Menu\DevOpsLabAdvancedOpsMenu.ps1
# DevOps Lab Repository - Advanced Operations Submenu

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Import-Module (Join-Path $PSScriptRoot "..\UI\ConsoleUI.psm1") -Force -ErrorAction Stop

function Show-DevOpsLabAdvancedOpsMenu {
    param(
        [string]$StatusText = "Ready",
        [string]$StatusColor = "DarkGray"
    )

    Show-AppHeader -Breadcrumb "Main > DevOps / CLI Tools > Lab Repository - Advanced Operations"

    Write-Host "  Lab Repository - Advanced Operations" -ForegroundColor Cyan
    Write-Host "  [1] Wipe + Rebuild cluster (student reset mode)"
    Write-Host "  [2] Nuke local generated files (kubeconfig + student-overrides)"
    Write-Host "  [3] Repo lab-safe reset (discard local changes)"
    Write-Host "  [4] Add new worker node to existing cluster"
    Write-Host "  [5] Reset CITA Web Demo only (delete namespace cita-web)"
    Write-Host "  [6] Open kubectl prompt (new window, repo kubeconfig)"
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
    "1" = "161"
    "2" = "162"
    "3" = "163"
    "4" = "164"
    "5" = "165"
    "6" = "166"
}

$back = $false
while (-not $back) {
    Show-DevOpsLabAdvancedOpsMenu -StatusText $script:lastStatusText -StatusColor $script:lastStatusColor
    $choice = Read-Host "Select an option"

    switch ($choice) {
        "0" { $back = $true }
        "1" { }
        "2" { }
        "3" { }
        "4" { }
        "5" { }
        "6" { }
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
