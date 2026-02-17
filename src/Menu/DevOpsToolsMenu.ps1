# C:\CITA\LabTools\src\Menu\DevOpsToolsMenu.ps1
$ErrorActionPreference = "SilentlyContinue"

# Shared UI
Import-Module (Join-Path $PSScriptRoot "..\UI\ConsoleUI.psm1") -Force

function Pause-Menu {
    Write-Host ""
    Read-Host "Press Enter to continue" | Out-Null
}

function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p  = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Get-WingetPath {
    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Invoke-ActionSafe {
    param(
        [Parameter(Mandatory=$true)][scriptblock]$Action,
        [Parameter(Mandatory=$true)][string]$SuccessText
    )

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
        Pause-Menu
    }
}

function Install-WingetPackage {
    param(
        [Parameter(Mandatory=$true)][string]$Id
    )
    winget install -e --id $Id --accept-package-agreements --accept-source-agreements
}

function Show-DevOpsMenu {
    param(
        [string]$StatusText = "Ready",
        [string]$StatusColor = "DarkGray"
    )

    Show-AppHeader -Breadcrumb "Main > DevOps / CLI Tools"

    Write-Host "  [1] Upgrade all Winget packages (winget upgrade --all)"
    Write-Host "  [2] Install talosctl (sidero.talosctl)"
    Write-Host "  [3] Install kubectl (kubernetes.kubectl)"
    Write-Host "  [4] Install helm (Helm.Helm)"
    Write-Host "  [5] Install DevOps bundle (talosctl + kubectl + helm)"
    Write-Host ""
    Write-Host "  [0] Back"
    Write-Host ""

    Write-Host "Status: " -NoNewline
    Write-Host $StatusText -ForegroundColor $StatusColor

    Write-Host "Keys: 1-5 Select  |  0 Back"
    Write-Host ""
}

$back = $false
$script:lastStatusText  = "Ready"
$script:lastStatusColor = "DarkGray"

do {
    Show-DevOpsMenu -StatusText $script:lastStatusText -StatusColor $script:lastStatusColor
    $choice = Read-Host "Select an option"

    switch ($choice) {

        "1" {
            Invoke-ActionSafe -SuccessText "Winget upgrade completed (or started)" -Action {
                Clear-Host

                $winget = Get-WingetPath
                if (-not $winget) { throw "winget not found. Install App Installer (Microsoft Store) or ensure winget is available." }

                if (-not (Test-IsAdmin)) {
                    Write-Host "Warning: Not running as Administrator. Some upgrades may fail." -ForegroundColor Yellow
                    Write-Host ""
                }

                winget upgrade --all --accept-package-agreements --accept-source-agreements
            }
        }

        "2" {
            Invoke-ActionSafe -SuccessText "talosctl install completed (or already installed)" -Action {
                Clear-Host

                $winget = Get-WingetPath
                if (-not $winget) { throw "winget not found. Install App Installer (Microsoft Store) or ensure winget is available." }

                if (-not (Test-IsAdmin)) {
                    Write-Host "Warning: Not running as Administrator. Install may fail." -ForegroundColor Yellow
                    Write-Host ""
                }

                Install-WingetPackage -Id "sidero.talosctl"
            }
        }

        "3" {
            Invoke-ActionSafe -SuccessText "kubectl install completed (or already installed)" -Action {
                Clear-Host

                $winget = Get-WingetPath
                if (-not $winget) { throw "winget not found. Install App Installer (Microsoft Store) or ensure winget is available." }

                if (-not (Test-IsAdmin)) {
                    Write-Host "Warning: Not running as Administrator. Install may fail." -ForegroundColor Yellow
                    Write-Host ""
                }

                Install-WingetPackage -Id "kubernetes.kubectl"
            }
        }

        "4" {
            Invoke-ActionSafe -SuccessText "helm install completed (or already installed)" -Action {
                Clear-Host

                $winget = Get-WingetPath
                if (-not $winget) { throw "winget not found. Install App Installer (Microsoft Store) or ensure winget is available." }

                if (-not (Test-IsAdmin)) {
                    Write-Host "Warning: Not running as Administrator. Install may fail." -ForegroundColor Yellow
                    Write-Host ""
                }

                Install-WingetPackage -Id "Helm.Helm"
            }
        }

        "5" {
            Invoke-ActionSafe -SuccessText "DevOps bundle install completed" -Action {
                Clear-Host

                $winget = Get-WingetPath
                if (-not $winget) { throw "winget not found. Install App Installer (Microsoft Store) or ensure winget is available." }

                if (-not (Test-IsAdmin)) {
                    Write-Host "Warning: Not running as Administrator. Some installs may fail." -ForegroundColor Yellow
                    Write-Host ""
                }

                Write-Host "Installing DevOps bundle..." -ForegroundColor Cyan
                Write-Host ""

                Write-Host "1/3 Installing talosctl..." -ForegroundColor Gray
                Install-WingetPackage -Id "sidero.talosctl"
                Write-Host ""

                Write-Host "2/3 Installing kubectl..." -ForegroundColor Gray
                Install-WingetPackage -Id "kubernetes.kubectl"
                Write-Host ""

                Write-Host "3/3 Installing helm..." -ForegroundColor Gray
                Install-WingetPackage -Id "Helm.Helm"
                Write-Host ""

                Write-Host "Bundle complete." -ForegroundColor Green
            }
        }

        "0" { $back = $true }

        default {
            $script:lastStatusText  = "Invalid selection"
            $script:lastStatusColor = "Yellow"
            Start-Sleep 1
        }
    }

} while (-not $back)

Clear-Host
return
