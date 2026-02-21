# C:\CITA\LabTools\src\Menu\DevOpsLabInstallOpsMenu.ps1
# DevOps Lab Repository - Install Operations Submenu

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Import-Module (Join-Path $PSScriptRoot "..\UI\ConsoleUI.psm1") -Force -ErrorAction Stop

$script:RepoTarget = "labs\k8s-baremetal-lab\bootstrap.ps1"

function Wait-Menu {
    Write-Host ""
    Read-Host "Press Enter to continue" | Out-Null
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

function Show-DevOpsLabInstallOpsMenu {
    param(
        [string]$StatusText = "Ready",
        [string]$StatusColor = "DarkGray"
    )

    Show-AppHeader -Breadcrumb "Main > DevOps / CLI Tools > Lab Repository - Install Operations"
    Show-CurrentContext -RepoPath $script:RepoPath

    Write-Host "  Lab Repository - Install Operations" -ForegroundColor Cyan
    Write-Host "  [1] Install core platform (Cluster + MetalLB + Ingress)"
    Write-Host "      Bootstrap or repair core cluster platform services." -ForegroundColor DarkGray
    Write-Host "  [2] Repair / Reinstall MetalLB (IP pool/range)"
    Write-Host "      Re-apply VIP pool/range and MetalLB components." -ForegroundColor DarkGray
    Write-Host "  [3] Install / Reinstall Portainer Admin UI (Ingress, NodePort IP, or LoadBalancer IP)"
    Write-Host "      Deploy Portainer with your preferred exposure mode." -ForegroundColor DarkGray
    Write-Host "  [4] Deploy / Update CITA Web Demo (namespace + ConfigMap + LoadBalancer)"
    Write-Host "      Publish student HTML demo workload and service." -ForegroundColor DarkGray
    Write-Host "  [5] Scale CITA Web Demo (2/4/5/custom replicas)"
    Write-Host "      Adjust replica count for the CITA demo deployment." -ForegroundColor DarkGray
    Write-Host "  [6] Scale any deployed app (interactive selector)"
    Write-Host "      Select and scale any deployment in the cluster." -ForegroundColor DarkGray
    Write-Host "  [7] Install / Update app via Helm (interactive)"
    Write-Host "      Install or upgrade Helm chart-based applications." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [0] Back"
    Write-Host ""

    Write-StatusLine -StatusText $StatusText -StatusColor $StatusColor
    Write-Host ""
}

$script:lastStatusText  = "[Ready] Ready"
$script:lastStatusColor = "DarkGray"
$script:MainMenuPath = Join-Path $PSScriptRoot "DevOpsToolsMenu.ps1"
$script:RepoPath = Resolve-DevOpsRepoPath -TargetRelativePath $script:RepoTarget

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
            $script:lastStatusText  = "[Warning] Invalid selection"
            $script:lastStatusColor = "Yellow"
            Start-Sleep -Seconds 1
            continue
        }
    }

    if ($choice -eq "0") { continue }

    if (-not (Test-Path $script:MainMenuPath)) {
        $script:lastStatusText  = "[Error] Main DevOps menu script not found"
        $script:lastStatusColor = "Red"
        Wait-Menu
        continue
    }

    $mapped = $optionMap[$choice]
    if ([string]::IsNullOrWhiteSpace($mapped)) {
        $script:lastStatusText  = "[Warning] Invalid selection"
        $script:lastStatusColor = "Yellow"
        continue
    }

    $script:lastStatusText  = "[Running] Executing action..."
    $script:lastStatusColor = "Cyan"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:MainMenuPath -RunOption $mapped
    if ($LASTEXITCODE -eq 0) {
        $script:lastStatusText  = "[Ready] Action completed"
        $script:lastStatusColor = "Green"
    }
    else {
        $script:lastStatusText  = "[Warning] Action finished with non-zero exit code"
        $script:lastStatusColor = "Yellow"
    }
}

Clear-Host
return
