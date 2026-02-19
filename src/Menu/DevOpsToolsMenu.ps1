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

    if (Test-Cmd kubectl) {
        $kubectlVersion = (& kubectl version --client --short 2>$null | Out-String).Trim()

        if ([string]::IsNullOrWhiteSpace($kubectlVersion)) {
            $kubectlVersion = (& kubectl version --client 2>$null | Out-String).Trim()
        }

        if ([string]::IsNullOrWhiteSpace($kubectlVersion)) {
            $kubectlVersion = (& kubectl version 2>$null | Out-String).Trim()
        }

        if ([string]::IsNullOrWhiteSpace($kubectlVersion)) {
            $kubectlVersion = (& kubectl --client version 2>$null | Out-String).Trim()
        }

        if ([string]::IsNullOrWhiteSpace($kubectlVersion)) {
            $kubectlVersion = "installed (version output unavailable)"
        }

        Write-Host ("kubectl:  " + $kubectlVersion) -ForegroundColor Gray
    }
    else { Write-Host "kubectl:  (not installed)" -ForegroundColor DarkYellow }

    if (Test-Cmd helm)    { Write-Host ("helm:    " + (& helm version --short 2>$null | Out-String).Trim()) -ForegroundColor Gray }
    else { Write-Host "helm:    (not installed)" -ForegroundColor DarkYellow }

    if (Test-Cmd git)     { Write-Host ("git:     " + (& git --version 2>$null | Out-String).Trim()) -ForegroundColor Gray }
    else { Write-Host "git:     (not installed)" -ForegroundColor DarkYellow }
}

function Resolve-DevOpsRepoPath {
    param([Parameter(Mandatory)][string]$TargetRelativePath)

    $runtimeRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $candidates = @(
        "C:\CITA_StudentRepos\lab-scripts",
        $runtimeRoot
    )

    foreach ($candidate in $candidates) {
        if (-not (Test-Path $candidate)) { continue }
        $target = Join-Path $candidate $TargetRelativePath
        if (Test-Path $target) { return $candidate }
    }

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }

    return $candidates[0]
}

function Resolve-KubeconfigPath {
    param([Parameter(Mandatory)][string]$RepoPath)

    $candidates = @(
        (Join-Path $RepoPath "labs\k8s-baremetal-lab\kubeconfig"),
        (Join-Path $RepoPath "kubeconfig"),
        "C:\CITA\LabTools\labs\k8s-baremetal-lab\kubeconfig",
        "C:\CITA\LabTools\kubeconfig"
    )

    foreach ($path in $candidates) {
        if (Test-Path $path) { return $path }
    }

    return $candidates[0]
}

function Resolve-TalosConfigPath {
    param([Parameter(Mandatory)][string]$RepoPath)

    $candidates = @(
        (Join-Path $RepoPath "labs\k8s-baremetal-lab\01-talos\student-overrides\talosconfig"),
        (Join-Path $RepoPath "01-talos\student-overrides\talosconfig"),
        "C:\CITA\LabTools\labs\k8s-baremetal-lab\01-talos\student-overrides\talosconfig",
        "C:\CITA\LabTools\01-talos\student-overrides\talosconfig"
    )

    foreach ($path in $candidates) {
        if (Test-Path $path) { return $path }
    }

    return $candidates[0]
}

function Resolve-WorkerConfigPath {
    param([Parameter(Mandatory)][string]$RepoPath)

    $candidates = @(
        (Join-Path $RepoPath "labs\k8s-baremetal-lab\01-talos\student-overrides\worker.yaml"),
        (Join-Path $RepoPath "01-talos\student-overrides\worker.yaml"),
        "C:\CITA\LabTools\labs\k8s-baremetal-lab\01-talos\student-overrides\worker.yaml",
        "C:\CITA\LabTools\01-talos\student-overrides\worker.yaml"
    )

    foreach ($path in $candidates) {
        if (Test-Path $path) { return $path }
    }

    return $candidates[0]
}

# =========================
# Menu
# =========================
$script:RepoUrl  = "https://github.com/cronnpj/lab-scripts.git"
$script:Branch   = "main"
$script:Target   = "labs\k8s-baremetal-lab\bootstrap.ps1"
$script:RepoPath = Resolve-DevOpsRepoPath -TargetRelativePath $script:Target

$script:lastStatusText  = "Ready"
$script:lastStatusColor = "DarkGray"

function Show-DevOpsMenu {
    param(
        [string]$StatusText  = "Ready",
        [string]$StatusColor = "DarkGray"
    )

    Show-AppHeader -Breadcrumb "Main > DevOps / CLI Tools"

    Write-Host "  Install / Update Tools"
    Write-Host "  [1]  Upgrade all Winget packages"
    Write-Host "  [2]  Install talosctl"
    Write-Host "  [3]  Install kubectl"
    Write-Host "  [4]  Install helm"
    Write-Host "  [5]  Install DevOps bundle (talosctl + kubectl + helm)"
    Write-Host ""
    Write-Host "  Quick Checks / Utilities"
    Write-Host "  [6]  Show installed versions (git/kubectl/talosctl/helm)"
    Write-Host "  [7]  kubectl get nodes/pods (uses repo kubeconfig if present)"
    Write-Host "  [8]  Open repo folder in File Explorer"
    Write-Host ""
    Write-Host "  Lab Repository - Install Operations"
    Write-Host "  [9]  Install Kubernetes Cluster (normal)"
    Write-Host "  [10] Install / Reinstall MetalLB (VIP pool)"
    Write-Host "  [11] Install Portainer (IP/NodePort)"
    Write-Host "  [12] Install / Reinstall NGINX Ingress Controller"
    Write-Host ""
    Write-Host "  Lab Repository - Advanced Operations"
    Write-Host "  [13] Install Kubernetes Cluster (interactive prompts)"
    Write-Host "  [14] Wipe + Rebuild cluster (student reset mode)"
    Write-Host "  [15] Nuke local generated files (kubeconfig + student-overrides)"
    Write-Host "  [16] Repo lab-safe reset (discard local changes)"
    Write-Host "  [17] Add new worker node to existing cluster"
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

        # === Install / Update Tools ===
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

        # === Quick Checks / Utilities ===
        "6" {
            Invoke-ActionSafe -SuccessText "Versions displayed" -Action {
                $prev = $ErrorActionPreference
                $ErrorActionPreference = "Continue"
                try {
                    Show-Versions
                }
                finally {
                    $ErrorActionPreference = $prev
                }
            }
        }

        "7" {
            Invoke-ActionSafe -SuccessText "kubectl checks completed" -Action {
                $kubeconfig = Resolve-KubeconfigPath -RepoPath $script:RepoPath
                if (-not (Test-Path $kubeconfig)) {
                    throw "kubeconfig not found at: $kubeconfig (run bootstrap first)"
                }

                Write-Host "Using kubeconfig: $kubeconfig" -ForegroundColor Gray

                Write-Host ""
                Write-Host "=== Section 1: Nodes ===" -ForegroundColor Cyan
                kubectl --kubeconfig $kubeconfig get nodes -o wide
                Pause-Menu

                Write-Host ""
                Write-Host "=== Section 2: Pods (all namespaces) ===" -ForegroundColor Cyan
                kubectl --kubeconfig $kubeconfig get pods -A
                Pause-Menu

                Write-Host ""
                Write-Host "=== Section 3: Services (all namespaces) ===" -ForegroundColor Cyan
                kubectl --kubeconfig $kubeconfig get svc -A
                Pause-Menu

                Write-Host ""
                Write-Host "=== Section 4: Ingress (all namespaces) ===" -ForegroundColor Cyan
                kubectl --kubeconfig $kubeconfig get ingress -A
                Pause-Menu

                Write-Host ""
                Write-Host "=== Section 5: ingress-nginx controller service ===" -ForegroundColor Cyan
                kubectl --kubeconfig $kubeconfig -n ingress-nginx get svc ingress-nginx-controller -o wide
            }
        }

        "8" {
            Invoke-ActionSafe -SuccessText "Opened repo folder" -Action {
                if (-not (Test-Path $script:RepoPath)) { throw "Repo not present: $($script:RepoPath). Run option [9] first." }
                Start-Process explorer.exe $script:RepoPath
            }
        }

        # === Lab Repository - Basic Operations ===
        "9" {
            Invoke-ActionSafe -SuccessText "Kubernetes cluster install executed" -Action {
                Ensure-GitInstalled
                if (-not (Test-Path $script:RepoPath)) { throw "Repo not present: $($script:RepoPath). Run Maintenance update first." }
                Invoke-RepoTarget -RepoPath $script:RepoPath -TargetRelativePath $script:Target
            }
        }

        "10" {
            Invoke-ActionSafe -SuccessText "MetalLB installed / VIP pool applied" -Action {
                Ensure-GitInstalled
                if (-not (Test-Path $script:RepoPath)) { throw "Repo not present: $($script:RepoPath). Run option [9] first." }

                Invoke-RepoTarget `
                    -RepoPath $script:RepoPath `
                    -TargetRelativePath $script:Target `
                    -Arguments @("-AddonsOnly","-InstallMetalLB")
            }
        }

        "11" {
            Invoke-ActionSafe -SuccessText "Portainer installed" -Action {
                Ensure-GitInstalled
            if (-not (Test-Path $script:RepoPath)) { throw "Repo not present: $($script:RepoPath). Run option [9] first." }

                Invoke-RepoTarget `
                    -RepoPath $script:RepoPath `
                    -TargetRelativePath $script:Target `
                    -Arguments @("-PortainerOnly","-InstallPortainer")
            }
        }

        "12" {
            Invoke-ActionSafe -SuccessText "NGINX Ingress Controller installed / reinstalled" -Action {
                Ensure-GitInstalled
            if (-not (Test-Path $script:RepoPath)) { throw "Repo not present: $($script:RepoPath). Run option [9] first." }

                Invoke-RepoTarget `
                    -RepoPath $script:RepoPath `
                    -TargetRelativePath $script:Target `
                    -Arguments @("-AddonsOnly","-InstallNginx")
            }
        }

        "13" {
            Invoke-ActionSafe -SuccessText "Kubernetes cluster install executed (interactive)" -Action {
                Ensure-GitInstalled
                if (-not (Test-Path $script:RepoPath)) { throw "Repo not present: $($script:RepoPath). Run option [9] first." }
                Invoke-RepoTarget -RepoPath $script:RepoPath -TargetRelativePath $script:Target -Arguments @("-Interactive")
            }
        }

        "14" {
            Invoke-ActionSafe -SuccessText "Wipe + rebuild executed" -Action {
                Ensure-GitInstalled
                if (-not (Test-Path $script:RepoPath)) { throw "Repo not present: $($script:RepoPath). Run option [9] first." }
                Invoke-RepoTarget -RepoPath $script:RepoPath -TargetRelativePath $script:Target -Arguments @("-WipeAndRebuild","-Interactive")
            }
        }

        "15" {
            Invoke-ActionSafe -SuccessText "Local generated files removed" -Action {
            if (-not (Test-Path $script:RepoPath)) { throw "Repo not present: $($script:RepoPath). Run option [9] first." }

                $kube = Join-Path $script:RepoPath "kubeconfig"
                $ovr  = Join-Path $script:RepoPath "01-talos\student-overrides"

                Remove-Item -Force -ErrorAction SilentlyContinue $kube
                if (Test-Path $ovr) { Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $ovr }

                Write-Host "Removed: $kube" -ForegroundColor Gray
                Write-Host "Removed: $ovr"  -ForegroundColor Gray
            }
        }

        "16" {
            Invoke-ActionSafe -SuccessText "Repo reset to origin completed" -Action {
                Ensure-GitInstalled
                if (-not (Test-Path (Join-Path $script:RepoPath ".git"))) { throw "Repo not found: $($script:RepoPath)" }
                Reset-RepoToOrigin -RepoPath $script:RepoPath -Branch $script:Branch
            }
        }

        "17" {
            Invoke-ActionSafe -SuccessText "Worker add operation completed" -Action {
                Ensure-GitInstalled
                if (-not (Test-Path $script:RepoPath)) { throw "Repo not present: $($script:RepoPath). Run option [9] first." }
                if (-not (Test-Cmd talosctl)) { throw "talosctl not found. Install it from option [2]." }

                $workerIp = (Read-Host "Enter NEW worker IP address").Trim()
                if ([string]::IsNullOrWhiteSpace($workerIp)) { throw "Worker IP cannot be blank." }

                $workerCfg = Resolve-WorkerConfigPath -RepoPath $script:RepoPath
                if (-not (Test-Path $workerCfg)) {
                    throw "worker.yaml not found at: $workerCfg`nRun option [9] or [13] first to generate Talos configs."
                }

                Write-Host "Checking worker reachability: $workerIp" -ForegroundColor Gray
                if (-not (Test-Connection -ComputerName $workerIp -Count 1 -Quiet)) {
                    throw "Worker node is not reachable: $workerIp"
                }

                Write-Host "Applying worker config to $workerIp (Talos maintenance API)..." -ForegroundColor Yellow
                & talosctl apply-config --insecure --nodes $workerIp --endpoints $workerIp --file $workerCfg
                if ($LASTEXITCODE -ne 0) {
                    throw "talosctl apply-config failed for worker: $workerIp"
                }

                $talosconfig = Resolve-TalosConfigPath -RepoPath $script:RepoPath
                if (Test-Path $talosconfig) {
                    Write-Host "Using talosconfig: $talosconfig" -ForegroundColor DarkGray
                }

                $kubeconfig = Resolve-KubeconfigPath -RepoPath $script:RepoPath
                if ((Test-Path $kubeconfig) -and (Test-Cmd kubectl)) {
                    Write-Host "Waiting briefly, then checking node registration..." -ForegroundColor Gray
                    Start-Sleep -Seconds 12
                    kubectl --kubeconfig $kubeconfig get nodes -o wide
                }
                else {
                    Write-Host "Worker config applied. Install/locate kubeconfig to verify node join with kubectl." -ForegroundColor DarkYellow
                }
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
