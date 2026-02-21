# C:\CITA\LabTools\src\Menu\DevOpsLabAdvancedOpsMenu.ps1
# DevOps Lab Repository - Advanced Operations Submenu

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Import-Module (Join-Path $PSScriptRoot "..\UI\ConsoleUI.psm1") -Force -ErrorAction Stop

$script:RepoTarget = "labs\k8s-baremetal-lab\bootstrap.ps1"

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

function Show-DevOpsLabAdvancedOpsMenu {
    param(
        [string]$StatusText = "Ready",
        [string]$StatusColor = "DarkGray"
    )

    Show-AppHeader -Breadcrumb "Main > DevOps / CLI Tools > Lab Repository - Advanced Operations"
    Show-CurrentContext -RepoPath $script:RepoPath

    Write-Host "  Lab Repository - Advanced Operations" -ForegroundColor Cyan
    Write-Host "  [1] Wipe + Rebuild cluster (student reset mode)"
    Write-Host "      Recreate cluster from scratch in guided mode." -ForegroundColor DarkGray
    Write-Host "  [2] Nuke local generated files (kubeconfig + student-overrides)"
    Write-Host "      Remove local generated artifacts for clean regeneration." -ForegroundColor DarkGray
    Write-Host "  [3] Repo lab-safe reset (discard local changes)"
    Write-Host "      Hard reset repo state to remote branch HEAD." -ForegroundColor DarkGray
    Write-Host "  [4] Add new worker node to existing cluster"
    Write-Host "      Join an additional Talos worker to the cluster." -ForegroundColor DarkGray
    Write-Host "  [5] Reset CITA Web Demo only (delete namespace cita-web)"
    Write-Host "      Remove demo namespace without rebuilding cluster." -ForegroundColor DarkGray
    Write-Host "  [6] Open kubectl prompt (new window, repo kubeconfig)"
    Write-Host "      Open shell with KUBECONFIG preset for kubectl." -ForegroundColor DarkGray
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
