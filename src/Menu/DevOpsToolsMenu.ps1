# C:\CITA\LabTools\src\Menu\DevOpsToolsMenu.ps1
$ErrorActionPreference = "SilentlyContinue"

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
        Pause-Menu
    }
}

function Install-WingetPackage {
    param([Parameter(Mandatory=$true)][string]$Id)

    $winget = Get-WingetPath
    if (-not $winget) { throw "winget not found. Install App Installer (Microsoft Store) or ensure winget is available." }

    # Keeps catalog fresh; helps prevent "not found" issues on some machines.
    try { winget source update | Out-Null } catch {}

    winget install -e --id $Id --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "winget install failed for id: $Id"
    }
}

# ======================================================
# Git + Repo Management
# ======================================================

function Test-GitInstalled {
    return [bool](Get-Command git -ErrorAction SilentlyContinue)
}

function Ensure-GitInstalled {
    if (Test-GitInstalled) { return }

    $winget = Get-WingetPath
    if (-not $winget) { throw "winget not found." }

    Write-Host "Installing Git via winget..." -ForegroundColor Yellow
    Install-WingetPackage -Id "Git.Git"

    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")

    if (-not (Test-GitInstalled)) {
        throw "Git installed but not available in this session. Restart PowerShell."
    }
}

function Get-RepoRemoteUrl {
    param([string]$RepoPath)
    return (git -C $RepoPath remote get-url origin 2>$null).Trim()
}

function Test-RepoDirty {
    param([string]$RepoPath)
    $status = (git -C $RepoPath status --porcelain 2>$null)
    return -not [string]::IsNullOrWhiteSpace($status)
}

function Reset-RepoToOrigin {
    param([string]$RepoPath, [string]$Branch)

    Write-Host "Resetting repo to origin/$Branch..." -ForegroundColor Yellow

    git -C $RepoPath fetch --all --prune
    git -C $RepoPath checkout $Branch
    git -C $RepoPath reset --hard "origin/$Branch"
    git -C $RepoPath clean -fd
}

function Ensure-RepoHealthy {
    param(
        [string]$RepoUrl,
        [string]$RepoPath,
        [string]$Branch,
        [switch]$AutoResetIfDirty
    )

    if ((Test-Path $RepoPath) -and -not (Test-Path (Join-Path $RepoPath ".git"))) {
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $moved = "${RepoPath}_OLD_$stamp"
        Write-Host "Folder exists but is not a git repo. Renaming..." -ForegroundColor Yellow
        Move-Item -Path $RepoPath -Destination $moved -Force
    }

    if (Test-Path (Join-Path $RepoPath ".git")) {

        $remote = Get-RepoRemoteUrl -RepoPath $RepoPath
        if ($remote -and ($remote -ne $RepoUrl)) {
            Write-Host "Fixing origin remote..." -ForegroundColor Yellow
            git -C $RepoPath remote set-url origin $RepoUrl
        }

        if (Test-RepoDirty -RepoPath $RepoPath) {
            if ($AutoResetIfDirty) {
                Reset-RepoToOrigin -RepoPath $RepoPath -Branch $Branch
            }
            else {
                throw "Repo has local changes."
            }
        }
    }
}

function Ensure-RepoPresentAndUpdated {
    param([string]$RepoUrl, [string]$RepoPath, [string]$Branch)

    $parent = Split-Path -Parent $RepoPath
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if (-not (Test-Path $RepoPath)) {
        Write-Host "Cloning repo..." -ForegroundColor Cyan
        git clone --branch $Branch --single-branch $RepoUrl $RepoPath
        return
    }

    Write-Host "Updating repo..." -ForegroundColor Cyan
    git -C $RepoPath fetch --all --prune
    git -C $RepoPath checkout $Branch
    git -C $RepoPath pull
}

function Invoke-RepoTarget {
    param(
        [string]$RepoPath,
        [string]$TargetRelativePath,
        [string[]]$Arguments = @()
    )

    $target = Join-Path $RepoPath $TargetRelativePath
    if (-not (Test-Path $target)) { throw "Target not found: $target" }

    Write-Host "Launching bootstrap..." -ForegroundColor Cyan
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $target @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "Bootstrap exited with code $LASTEXITCODE"
    }
}

function Bootstrap-RepoAndRun {
    param(
        [string]$RepoUrl,
        [string]$RepoPath,
        [string]$TargetRelativePath,
        [string]$Branch = "main",
        [string[]]$Arguments = @(),
        [switch]$AutoResetIfDirty
    )

    Ensure-GitInstalled
    Ensure-RepoHealthy -RepoUrl $RepoUrl -RepoPath $RepoPath -Branch $Branch -AutoResetIfDirty:$AutoResetIfDirty
    Ensure-RepoPresentAndUpdated -RepoUrl $RepoUrl -RepoPath $RepoPath -Branch $Branch

    if ((Test-Path (Join-Path $RepoPath ".git")) -and (Test-RepoDirty -RepoPath $RepoPath) -and $AutoResetIfDirty) {
        Reset-RepoToOrigin -RepoPath $RepoPath -Branch $Branch
    }

    Invoke-RepoTarget -RepoPath $RepoPath -TargetRelativePath $TargetRelativePath -Arguments $Arguments
}

# ======================================================
# Menu
# ======================================================

function Show-DevOpsMenu {
    param([string]$StatusText = "Ready", [string]$StatusColor = "DarkGray")

    Show-AppHeader -Breadcrumb "Main > DevOps / CLI Tools"

    Write-Host "  [1] Upgrade all Winget packages"
    Write-Host "  [2] Install talosctl"
    Write-Host "  [3] Install kubectl"
    Write-Host "  [4] Install helm"
    Write-Host "  [5] Install DevOps bundle"
    Write-Host "  [6] Update + Run k8s-baremetal-lab"
    Write-Host ""
    Write-Host "  [0] Back"
    Write-Host ""

    Write-Host "Status: " -NoNewline
    Write-Host $StatusText -ForegroundColor $StatusColor
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
            Invoke-ActionSafe -SuccessText "Winget upgrade completed" -Action {
                winget upgrade --all --accept-package-agreements --accept-source-agreements
            }
        }

        "2" {
            Invoke-ActionSafe -SuccessText "talosctl install completed (or already installed)" -Action {
                Install-WingetPackage -Id "Sidero.talosctl"
            }
        }

        "3" {
            Invoke-ActionSafe -SuccessText "kubectl install completed (or already installed)" -Action {
                Install-WingetPackage -Id "Kubernetes.kubectl"
            }
        }

        "4" {
            Invoke-ActionSafe -SuccessText "helm install completed (or already installed)" -Action {
                Install-WingetPackage -Id "Helm.Helm"
            }
        }

        "5" {
            Invoke-ActionSafe -SuccessText "DevOps bundle installed" -Action {
                Install-WingetPackage -Id "Sidero.talosctl"
                Install-WingetPackage -Id "Kubernetes.kubectl"
                Install-WingetPackage -Id "Helm.Helm"
            }
        }

        "6" {
            Invoke-ActionSafe -SuccessText "k8s-baremetal-lab updated and bootstrap executed" -Action {

                $RepoUrl  = "https://github.com/cronnpj/k8s-baremetal-lab"
                $RepoPath = "C:\CITA\_StudentRepos\k8s-baremetal-lab"
                $Branch   = "main"
                $Target   = "bootstrap.ps1"

                Bootstrap-RepoAndRun `
                    -RepoUrl $RepoUrl `
                    -RepoPath $RepoPath `
                    -Branch $Branch `
                    -TargetRelativePath $Target `
                    -AutoResetIfDirty
            }
        }

        "0" { $back = $true }
        default { Start-Sleep 300 }
    }

} while (-not $back)

Clear-Host
return
