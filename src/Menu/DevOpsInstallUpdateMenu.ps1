# C:\CITA\LabTools\src\Menu\DevOpsInstallUpdateMenu.ps1
# DevOps Install / Update Tools Submenu

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Import-Module (Join-Path $PSScriptRoot "..\UI\ConsoleUI.psm1") -Force -ErrorAction Stop

$script:RepoTarget = "labs\k8s-baremetal-lab\bootstrap.ps1"

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
        $script:lastStatusText  = "[Running] Executing action..."
        $script:lastStatusColor = "Cyan"
        & $Action
        $script:lastStatusText  = "[Ready] $SuccessText"
        $script:lastStatusColor = "Green"
    }
    catch {
        $script:lastStatusText  = "[Error] Action failed"
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

function Test-Cmd {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Resolve-DevOpsRepoPath {
    param([Parameter(Mandatory)][string]$TargetRelativePath)

    $preferredRoot = "C:\CITA_StudentRepos\lab-scripts"
    $runtimeRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $candidates = @($preferredRoot, $runtimeRoot)

    foreach ($candidate in $candidates) {
        if (-not (Test-Path $candidate)) { continue }
        $target = Join-Path $candidate $TargetRelativePath
        if (Test-Path $target) { return $candidate }
    }

    return $preferredRoot
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

function Show-CurrentContext {
    param([Parameter(Mandatory)][string]$RepoPath)

    $repoText = if (Test-Path -Path $RepoPath -PathType Container) { $RepoPath } else { "Missing" }
    $repoColor = if ($repoText -eq "Missing") { "Yellow" } else { "Gray" }

    $kubeconfigPath = Resolve-KubeconfigPath -RepoPath $RepoPath
    $kubeText = if (Test-Path $kubeconfigPath) { $kubeconfigPath } else { "Not found" }
    $kubeColor = if ($kubeText -eq "Not found") { "Yellow" } else { "Gray" }

    $clusterText = "Unknown"
    $clusterColor = "DarkYellow"
    if ((Test-Cmd kubectl) -and (Test-Path $kubeconfigPath)) {
        $nodesRaw = & kubectl --kubeconfig $kubeconfigPath --request-timeout=3s get nodes -o name 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($nodesRaw | Out-String).Trim())) {
            $clusterText = "Reachable"
            $clusterColor = "Green"
        }
        else {
            $clusterText = "Not reachable"
            $clusterColor = "Yellow"
        }
    }

    Write-Host "Context: " -NoNewline
    Write-Host "Repo: " -NoNewline
    Write-Host $repoText -ForegroundColor $repoColor -NoNewline
    Write-Host " | Kubeconfig: " -NoNewline
    Write-Host $kubeText -ForegroundColor $kubeColor -NoNewline
    Write-Host " | Cluster: " -NoNewline
    Write-Host $clusterText -ForegroundColor $clusterColor
    Write-Host ""
}

function Show-DevOpsInstallUpdateMenu {
    param(
        [string]$StatusText  = "Ready",
        [string]$StatusColor = "DarkGray"
    )

    Show-AppHeader -Breadcrumb "Main > DevOps / CLI Tools > Install / Update Tools"
    Show-CurrentContext -RepoPath $script:RepoPath

    Write-Host "  Install / Update Tools" -ForegroundColor Cyan
    Write-Host "  [1] Upgrade all Winget packages"
    Write-Host "      Update installed tool packages from Winget sources." -ForegroundColor DarkGray
    Write-Host "  [2] Install talosctl"
    Write-Host "      Install Talos CLI for cluster/node operations." -ForegroundColor DarkGray
    Write-Host "  [3] Install kubectl"
    Write-Host "      Install Kubernetes CLI used throughout labs." -ForegroundColor DarkGray
    Write-Host "  [4] Install helm"
    Write-Host "      Install Helm package manager for Kubernetes apps." -ForegroundColor DarkGray
    Write-Host "  [5] Install DevOps bundle (talosctl + kubectl + helm)"
    Write-Host "      Install all core DevOps CLI tools in one step." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [0] Back"
    Write-Host ""

    Write-StatusLine -StatusText $StatusText -StatusColor $StatusColor
    Write-Host ""
}

$script:lastStatusText  = "[Ready] Ready"
$script:lastStatusColor = "DarkGray"
$script:RepoPath = Resolve-DevOpsRepoPath -TargetRelativePath $script:RepoTarget

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
            $script:lastStatusText  = "[Warning] Invalid selection"
            $script:lastStatusColor = "Yellow"
            Start-Sleep -Seconds 1
        }
    }
}

Clear-Host
return
