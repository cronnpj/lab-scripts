# C:\CITA\LabTools\src\Menu\DevOpsInstallUpdateMenu.ps1
# DevOps Install / Update Tools Submenu

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Import-Module (Join-Path $PSScriptRoot "..\UI\ConsoleUI.psm1") -Force -ErrorAction Stop

function Wait-Menu {
    Write-Host ""
    Read-Host "Press Enter to continue" | Out-Null
}

function Assert-Admin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($id)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw "This action requires Administrator. Right-click PowerShell and choose 'Run as administrator'."
        }
    }
    catch {
        throw
    }
}

function Get-WingetPath {
    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Install-WingetPackage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)

    $winget = Get-WingetPath
    if (-not $winget) {
        throw "winget not found. Install App Installer (Microsoft Store) or ensure winget is available."
    }

    try { winget source update | Out-Null } catch {}

    winget install -e --id $Id --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "winget install failed for id: $Id"
    }
}

function Invoke-ActionSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [Parameter(Mandatory)][string]$SuccessText
    )

    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Stop"

    try {
        & $Action
        $script:lastStatusText  = $SuccessText
        $script:lastStatusColor = "Green"
    }
    catch {
        $script:lastStatusText  = "Action failed"
        $script:lastStatusColor = "Red"
        Write-Host ""
        Write-Host "Error: Action failed." -ForegroundColor Red
        Write-Host $_.Exception.Message
    }
    finally {
        $ErrorActionPreference = $prev
        Wait-Menu
    }
}

function Show-DevOpsInstallUpdateMenu {
    param(
        [string]$StatusText  = "Ready",
        [string]$StatusColor = "DarkGray"
    )

    Show-AppHeader -Breadcrumb "Main > DevOps / CLI Tools > Install / Update Tools"

    Write-Host "  Install / Update Tools" -ForegroundColor Cyan
    Write-Host "  [1] Upgrade all Winget packages"
    Write-Host "  [2] Install talosctl"
    Write-Host "  [3] Install kubectl"
    Write-Host "  [4] Install helm"
    Write-Host "  [5] Install DevOps bundle (talosctl + kubectl + helm)"
    Write-Host ""
    Write-Host "  [0] Back"
    Write-Host ""

    Write-Host "Status: " -NoNewline
    Write-Host $StatusText -ForegroundColor $StatusColor
    Write-Host ""
}

$script:lastStatusText  = "Ready"
$script:lastStatusColor = "DarkGray"

$back = $false
while (-not $back) {
    Show-DevOpsInstallUpdateMenu -StatusText $script:lastStatusText -StatusColor $script:lastStatusColor
    $choice = Read-Host "Select an option"

    switch ($choice) {
        "1" {
            Invoke-ActionSafe -SuccessText "Winget upgrade completed" -Action {
                Assert-Admin
                winget upgrade --all --accept-package-agreements --accept-source-agreements
            }
        }
        "2" {
            Invoke-ActionSafe -SuccessText "talosctl install completed (or already installed)" -Action {
                Assert-Admin
                Install-WingetPackage -Id "Sidero.talosctl"
            }
        }
        "3" {
            Invoke-ActionSafe -SuccessText "kubectl install completed (or already installed)" -Action {
                Assert-Admin
                Install-WingetPackage -Id "Kubernetes.kubectl"
            }
        }
        "4" {
            Invoke-ActionSafe -SuccessText "helm install completed (or already installed)" -Action {
                Assert-Admin
                Install-WingetPackage -Id "Helm.Helm"
            }
        }
        "5" {
            Invoke-ActionSafe -SuccessText "DevOps bundle installed" -Action {
                Assert-Admin
                Install-WingetPackage -Id "Sidero.talosctl"
                Install-WingetPackage -Id "Kubernetes.kubectl"
                Install-WingetPackage -Id "Helm.Helm"
            }
        }
        "0" { $back = $true }
        default {
            $script:lastStatusText  = "Invalid selection"
            $script:lastStatusColor = "Yellow"
            Start-Sleep -Seconds 1
        }
    }
}

Clear-Host
return
