# C:\CITA\LabTools\src\Menu\DevOpsToolsMenu.ps1
# DevOps / CLI Tools Menu (cleaned + consistent)

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

Import-Module (Join-Path $PSScriptRoot "..\UI\ConsoleUI.psm1") -Force

# =========================
# Small UX helpers
# =========================
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

function Require-Admin {
    if (-not (Test-IsAdmin)) {
        throw "This action requires Administrator. Right-click PowerShell and choose 'Run as administrator'."
    }
}

function Set-Status {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Color
    )
    $script:lastStatusText  = $Text
    $script:lastStatusColor = $Color
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
        Set-Status -Text $SuccessText -Color "Green"
    }
    catch {
        Set-Status -Text "Action failed" -Color "Red"
        Write-Host ""
        Write-Host "Error: Action failed." -ForegroundColor Red
        Write-Host $_.Exception.Message
    }
    finally {
        $ErrorActionPreference = $prev
        Pause-Menu
    }
}

# =========================
# winget
# =========================
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

    # Keeps catalog fresh; helps prevent "not found" issues on some machines.
    try { winget source update | Out-Null } catch {}

    winget install -e --id $Id --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "winget install failed for id: $Id"
    }
}

# =========================
# Git + Repo management
# =========================
function Test-GitInstalled { return [bool](Get-Command git -ErrorAction SilentlyContinue) }

function Ensure-GitInstalled {
    if (Test-GitInstalled) { return }

    if (-not (Get-WingetPath)) { throw "winget not found." }

    Write-Host "Installing Git via winget..." -ForegroundColor Yellow
    Install-WingetPackage -Id "Git.Git"

    # Refresh PATH for current session
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")

    if (-not (Test-GitInstalled)) {
        throw "Git installed but not available in this session. Restart PowerShell."
    }
}

function Get-RepoRemoteUrl {
    param([Parameter(Mandatory)][string]$RepoPath)
    $r = (git -C $RepoPath remote get-url origin 2>$null)
    if ($null -eq $r) { return "" }
    return $r.Trim()
}

function Test-RepoDirty {
    param([Parameter(Mandatory)][string]$RepoPath)
    $status = (git -C $RepoPath status --porcelain 2>$null)
    return -not [string]::IsNullOrWhiteSpace($status)
}

function Reset-RepoToOrigin {
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][string]$Branch
    )

    Write-Host "WARNING: Lab-safe reset will discard local changes in:" -ForegroundColor DarkYellow
    Write-Host "  $RepoPath" -ForegroundColor DarkYellow
    Write-Host "Resetting repo to origin/$Branch..." -ForegroundColor Yellow

    git -C $RepoPath fetch --all --prune
    git -C $RepoPath checkout $Branch
    git -C $RepoPath reset --hard "origin/$Branch"
    git -C $RepoPath clean -fd
}

function Ensure-RepoHealthy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoUrl,
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][string]$Branch,
        [switch]$AutoResetIfDirty
    )

    if (-not (Test-Path $RepoPath)) { return } # nothing to "heal" yet

    $gitDir = Join-Path $RepoPath ".git"
    if (-not (Test-Path $gitDir)) {
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $moved = "${RepoPath}_OLD_$stamp"
        Write-Host "Folder exists but is not a git repo. Renaming..." -ForegroundColor Yellow
        Move-Item -Path $RepoPath -Destination $moved -Force
        return
    }

    $remote = Get-RepoRemoteUrl -RepoPath $RepoPath
    if ($remote -and ($remote -ne $RepoUrl)) {
        Write-Host "Fixing origin remote..." -ForegroundColor Yellow
        git -C $RepoPath remote set-url origin $RepoUrl
    }

    if (Test-RepoDirty -RepoPath $RepoPath) {
        if ($AutoResetIfDirty) { Reset-RepoToOrigin -RepoPath $RepoPath -Branch $Branch }
        else { throw "Repo has local changes." }
    }
}

function Ensure-RepoPresentAndUpdated {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoUrl,
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][string]$Branch
    )

    $parent = Split-Path -Parent $RepoPath
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][string]$TargetRelativePath,
        [string[]]$Arguments = @()
    )

    $target = Join-Path $RepoPath $TargetRelativePath
    if (-not (Test-Path $target)) { throw "Target not found: $target" }

    Write-Host "Launching: $TargetRelativePath" -ForegroundColor Cyan
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $target @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "Target exited with code $LASTEXITCODE"
    }
}

function Bootstrap-RepoAndRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoUrl,
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][string]$TargetRelativePath,
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

function Update-RepoOnly {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoUrl,
        [Parameter(Mandatory)][string]$RepoPath,
        [string]$Branch = "main",
        [switch]$AutoResetIfDirty
    )

    Ensure-GitInstalled
    Ensure-RepoHealthy -RepoUrl $RepoUrl -RepoPath $RepoPath -Branch $Branch -AutoResetIfDirty:$AutoResetIfDirty
    Ensure-RepoPresentAndUpdated -RepoUrl $RepoUrl -RepoPath $RepoPath -Branch $Branch

    Write-Host ""
    Write-Host "Repo update complete." -ForegroundColor Green
    Write-Host "Path:   $RepoPath" -ForegroundColor Gray
    Write-Host "Branch: $Branch"   -ForegroundColor Gray
    Write-Host "HEAD:   $(& git -C $RepoPath rev-parse --short HEAD 2>$null)" -ForegroundColor Gray
}

# =========================
# Quick checks
# =========================
function Test-Cmd {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Show-Versions {
    if (Test-Cmd talosctl) { Write-Host ("talosctl: " + (& talosctl version 2>$null | Out-String).Trim()) -ForegroundColor Gray }
    else { Write-Host "talosctl: (not installed)" -ForegroundColor DarkYellow }

    if (Test-Cmd kubectl) { Write-Host ("kubectl:  " + (& kubectl version --client --short 2>$null | Out-String).Trim()) -ForegroundColor Gray }
    else { Write-Host "kubectl:  (not installed)" -ForegroundColor DarkYellow }

    if (Test-Cmd helm)    { Write-Host ("helm:    " + (& helm version --short 2>$null | Out-String).Trim()) -ForegroundColor Gray }
    else { Write-Host "helm:    (not installed)" -ForegroundColor DarkYellow }

    if (Test-Cmd git)     { Write-Host ("git:     " + (& git --version 2>$null | Out-String).Trim()) -ForegroundColor Gray }
    else { Write-Host "git:     (not installed)" -ForegroundColor DarkYellow }
}

# =========================
# Menu
# =========================
$script:RepoUrl  = "https://github.com/cronnpj/k8s-baremetal-lab.git"
$script:RepoPath = "C:\CITA_StudentRepos\k8s-baremetal-lab"
$script:Branch   = "main"
$script:Target   = "bootstrap.ps1"

$script:lastStatusText  = "Ready"
$script:lastStatusColor = "DarkGray"

function Show-DevOpsMenu {
    param(
        [string]$StatusText  = "Ready",
        [string]$StatusColor = "DarkGray"
    )

    Show-AppHeader -Breadcrumb "Main > DevOps / CLI Tools"

    Write-Host "  Install / Update tools"
    Write-Host "  [1]  Upgrade all Winget packages"
    Write-Host "  [2]  Install talosctl"
    Write-Host "  [3]  Install kubectl"
    Write-Host "  [4]  Install helm"
    Write-Host "  [5]  Install DevOps bundle (talosctl + kubectl + helm)"
    Write-Host ""
    Write-Host "  Lab repo (k8s-baremetal-lab)"
    Write-Host "  [6]  Update + Run bootstrap (normal)"
    Write-Host "  [18] Update repo only (no bootstrap)"
    Write-Host "  [7]  Run bootstrap (no repo update)  (uses existing local repo)"
    Write-Host "  [8]  Nuke local generated files (kubeconfig + student-overrides)"
    Write-Host "  [9]  Repo status (clean/dirty + origin)"
    Write-Host "  [10] Repo lab-safe reset (discard changes)"
    Write-Host "  [14] Run bootstrap (interactive prompts)"
    Write-Host "  [15] Wipe + Rebuild cluster (student reset mode)"
    Write-Host "  [16] Install Kubernetes Dashboard (Ingress + token)"
    Write-Host "  [17] Install / Reinstall MetalLB (VIP pool)"
    Write-Host ""
    Write-Host "  Quick checks / utilities"
    Write-Host "  [11] Show installed versions (git/kubectl/talosctl/helm)"
    Write-Host "  [12] kubectl get nodes/pods (uses repo kubeconfig if present)"
    Write-Host "  [13] Open repo folder in File Explorer"
    Write-Host ""
    Write-Host "  [0]  Back"
    Write-Host ""

    Write-Host "Status: " -NoNewline
    Write-Host $StatusText -ForegroundColor $StatusColor
    Write-Host ""
}

$back = $false
do {
    Show-DevOpsMenu -StatusText $script:lastStatusText -StatusColor $script:lastStatusColor
    $choice = Read-Host "Select an option"

    switch ($choice) {

        "1" {
            Invoke-ActionSafe -SuccessText "Winget upgrade completed" -Action {
                Require-Admin
                winget upgrade --all --accept-package-agreements --accept-source-agreements
            }
        }

        "2" {
            Invoke-ActionSafe -SuccessText "talosctl install completed (or already installed)" -Action {
                Require-Admin
                Install-WingetPackage -Id "Sidero.talosctl"
            }
        }

        "3" {
            Invoke-ActionSafe -SuccessText "kubectl install completed (or already installed)" -Action {
                Require-Admin
                Install-WingetPackage -Id "Kubernetes.kubectl"
            }
        }

        "4" {
            Invoke-ActionSafe -SuccessText "helm install completed (or already installed)" -Action {
                Require-Admin
                Install-WingetPackage -Id "Helm.Helm"
            }
        }

        "5" {
            Invoke-ActionSafe -SuccessText "DevOps bundle installed" -Action {
                Require-Admin
                Install-WingetPackage -Id "Sidero.talosctl"
                Install-WingetPackage -Id "Kubernetes.kubectl"
                Install-WingetPackage -Id "Helm.Helm"
            }
        }

        "6" {
            Invoke-ActionSafe -SuccessText "k8s-baremetal-lab updated and bootstrap executed" -Action {
                Bootstrap-RepoAndRun `
                    -RepoUrl $script:RepoUrl `
                    -RepoPath $script:RepoPath `
                    -Branch $script:Branch `
                    -TargetRelativePath $script:Target `
                    -AutoResetIfDirty
            }
        }

        "18" {
            Invoke-ActionSafe -SuccessText "Repo updated (no bootstrap)" -Action {
                Update-RepoOnly `
                    -RepoUrl $script:RepoUrl `
                    -RepoPath $script:RepoPath `
                    -Branch $script:Branch `
                    -AutoResetIfDirty
            }
        }

        "7" {
            Invoke-ActionSafe -SuccessText "bootstrap executed (no repo update)" -Action {
                Ensure-GitInstalled
                if (-not (Test-Path $script:RepoPath)) { throw "Repo not present: $($script:RepoPath). Run option [6] or [18] first." }
                Invoke-RepoTarget -RepoPath $script:RepoPath -TargetRelativePath $script:Target
            }
        }

        "14" {
            Invoke-ActionSafe -SuccessText "bootstrap executed (interactive)" -Action {
                Ensure-GitInstalled
                if (-not (Test-Path $script:RepoPath)) { throw "Repo not present: $($script:RepoPath). Run option [6] or [18] first." }
                Invoke-RepoTarget -RepoPath $script:RepoPath -TargetRelativePath $script:Target -Arguments @("-Interactive")
            }
        }

        "15" {
            Invoke-ActionSafe -SuccessText "Wipe + rebuild executed" -Action {
                Ensure-GitInstalled
                if (-not (Test-Path $script:RepoPath)) { throw "Repo not present: $($script:RepoPath). Run option [6] or [18] first." }
                Invoke-RepoTarget -RepoPath $script:RepoPath -TargetRelativePath $script:Target -Arguments @("-WipeAndRebuild","-Interactive")
            }
        }

        "16" {
            Invoke-ActionSafe -SuccessText "Dashboard installed (Ingress + token)" -Action {
                Ensure-GitInstalled
                if (-not (Test-Path $script:RepoPath)) { throw "Repo not present: $($script:RepoPath). Run option [6] or [18] first." }

                Invoke-RepoTarget `
                    -RepoPath $script:RepoPath `
                    -TargetRelativePath $script:Target `
                    -Arguments @("-DashboardOnly","-InstallDashboard")
            }
        }

        "17" {
            Invoke-ActionSafe -SuccessText "MetalLB installed / VIP pool applied" -Action {
                Ensure-GitInstalled
                if (-not (Test-Path $script:RepoPath)) { throw "Repo not present: $($script:RepoPath). Run option [6] or [18] first." }

                Invoke-RepoTarget `
                    -RepoPath $script:RepoPath `
                    -TargetRelativePath $script:Target `
                    -Arguments @("-AddonsOnly","-InstallMetalLB")
            }
        }

        "8" {
            Invoke-ActionSafe -SuccessText "Local generated files removed" -Action {
                if (-not (Test-Path $script:RepoPath)) { throw "Repo not present: $($script:RepoPath). Run option [6] or [18] first." }

                $kube = Join-Path $script:RepoPath "kubeconfig"
                $ovr  = Join-Path $script:RepoPath "01-talos\student-overrides"

                Remove-Item -Force -ErrorAction SilentlyContinue $kube
                if (Test-Path $ovr) { Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $ovr }

                Write-Host "Removed: $kube" -ForegroundColor Gray
                Write-Host "Removed: $ovr"  -ForegroundColor Gray
            }
        }

        "9" {
            Invoke-ActionSafe -SuccessText "Repo status displayed" -Action {
                Ensure-GitInstalled

                if (-not (Test-Path $script:RepoPath)) {
                    Write-Host "Repo not present yet: $($script:RepoPath)" -ForegroundColor DarkYellow
                    return
                }
                if (-not (Test-Path (Join-Path $script:RepoPath ".git"))) {
                    Write-Host "Folder exists but is not a git repo: $($script:RepoPath)" -ForegroundColor DarkYellow
                    return
                }

                $remote = Get-RepoRemoteUrl -RepoPath $script:RepoPath
                $dirty  = Test-RepoDirty -RepoPath $script:RepoPath
                $branch = (& git -C $script:RepoPath rev-parse --abbrev-ref HEAD 2>$null)

                Write-Host "RepoPath: $($script:RepoPath)"
                Write-Host "Origin:   $remote"
                Write-Host "Branch:   $branch"
                Write-Host ("Dirty:    " + $dirty) -ForegroundColor ($(if ($dirty) { "DarkYellow" } else { "Green" }))

                if ($dirty) {
                    Write-Host ""
                    Write-Host "Changed files:" -ForegroundColor DarkYellow
                    git -C $script:RepoPath status --porcelain
                }
            }
        }

        "10" {
            Invoke-ActionSafe -SuccessText "Repo reset to origin completed" -Action {
                Ensure-GitInstalled
                if (-not (Test-Path (Join-Path $script:RepoPath ".git"))) { throw "Repo not found: $($script:RepoPath)" }
                Reset-RepoToOrigin -RepoPath $script:RepoPath -Branch $script:Branch
            }
        }

        "11" {
            Invoke-ActionSafe -SuccessText "Versions displayed" -Action { Show-Versions }
        }

        "12" {
            Invoke-ActionSafe -SuccessText "kubectl checks completed" -Action {
                $kubeconfig = Join-Path $script:RepoPath "kubeconfig"
                if (-not (Test-Path $kubeconfig)) {
                    throw "kubeconfig not found at: $kubeconfig (run bootstrap first)"
                }

                Write-Host "Using kubeconfig: $kubeconfig" -ForegroundColor Gray
                kubectl --kubeconfig $kubeconfig get nodes -o wide
                Write-Host ""
                kubectl --kubeconfig $kubeconfig get pods -A
            }
        }

        "13" {
            Invoke-ActionSafe -SuccessText "Opened repo folder" -Action {
                if (-not (Test-Path $script:RepoPath)) { throw "Repo not present: $($script:RepoPath). Run option [6] or [18] first." }
                Start-Process explorer.exe $script:RepoPath
            }
        }

        "0" { $back = $true }

        default {
            Set-Status -Text "Invalid selection" -Color "Red"
            Pause-Menu
        }
    }

} while (-not $back)

Clear-Host
return
