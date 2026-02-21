# C:\CITA\LabTools\src\Menu\DevOpsQuickChecksMenu.ps1
# DevOps Quick Checks / Utilities Submenu

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Import-Module (Join-Path $PSScriptRoot "..\UI\ConsoleUI.psm1") -Force -ErrorAction Stop

$script:RepoUrl  = "https://github.com/cronnpj/lab-scripts.git"
$script:Branch   = "main"
$script:Target   = "labs\k8s-baremetal-lab\bootstrap.ps1"

function Wait-Menu {
    Write-Host ""
    Read-Host "Press Enter to continue" | Out-Null
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

function Show-Versions {
    if (Test-Cmd talosctl) { Write-Host ("talosctl: " + (& talosctl version 2>$null | Out-String).Trim()) -ForegroundColor Gray }
    else { Write-Host "talosctl: (not installed)" -ForegroundColor DarkYellow }

    if (Test-Cmd kubectl) {
        $kubectlVersion = (& kubectl version --client --short 2>$null | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($kubectlVersion)) { $kubectlVersion = (& kubectl version --client 2>$null | Out-String).Trim() }
        if ([string]::IsNullOrWhiteSpace($kubectlVersion)) { $kubectlVersion = (& kubectl version 2>$null | Out-String).Trim() }
        if ([string]::IsNullOrWhiteSpace($kubectlVersion)) { $kubectlVersion = (& kubectl --client version 2>$null | Out-String).Trim() }
        if ([string]::IsNullOrWhiteSpace($kubectlVersion)) { $kubectlVersion = "installed (version output unavailable)" }
        Write-Host ("kubectl:  " + $kubectlVersion) -ForegroundColor Gray
    }
    else { Write-Host "kubectl:  (not installed)" -ForegroundColor DarkYellow }

    if (Test-Cmd helm) { Write-Host ("helm:    " + (& helm version --short 2>$null | Out-String).Trim()) -ForegroundColor Gray }
    else { Write-Host "helm:    (not installed)" -ForegroundColor DarkYellow }

    if (Test-Cmd git) { Write-Host ("git:     " + (& git --version 2>$null | Out-String).Trim()) -ForegroundColor Gray }
    else { Write-Host "git:     (not installed)" -ForegroundColor DarkYellow }
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

function Assert-RepoPresent {
    param(
        [Parameter(Mandatory)][string]$RepoUrl,
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][string]$Branch
    )

    if (Test-Path (Join-Path $RepoPath ".git")) { return }

    if (-not (Test-Cmd git)) {
        throw "git not found. Install Git first from DevOps > Install / Update Tools."
    }

    $parent = Split-Path -Parent $RepoPath
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

    if (-not (Test-Path $RepoPath)) {
        Write-Host "Cloning repo..." -ForegroundColor Cyan
        git clone --branch $Branch --single-branch $RepoUrl $RepoPath | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Failed to clone repo to $RepoPath" }
        return
    }

    throw "Repo path exists but is not a git repo: $RepoPath"
}

function Assert-KubeconfigReady {
    param([Parameter(Mandatory)][string]$RepoPath)

    if (-not (Test-Cmd kubectl)) {
        throw "kubectl not found. Install it from DevOps > Install / Update Tools."
    }

    $kubeconfig = Resolve-KubeconfigPath -RepoPath $RepoPath
    if (-not (Test-Path $kubeconfig)) {
        throw "kubeconfig not found at $kubeconfig. Run option [9] in DevOps first."
    }

    $nodesCheck = & kubectl --kubeconfig $kubeconfig get nodes -o name 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($nodesCheck | Out-String).Trim())) {
        throw "Cluster is not reachable with current kubeconfig. Run option [9] in DevOps first."
    }

    return $kubeconfig
}

function Show-DevOpsQuickChecksMenu {
    param(
        [string]$StatusText = "Ready",
        [string]$StatusColor = "DarkGray"
    )

    Show-AppHeader -Breadcrumb "Main > DevOps / CLI Tools > Quick Checks / Utilities"
    Show-CurrentContext -RepoPath $script:RepoPath

    Write-Host "  Quick Checks / Utilities" -ForegroundColor Cyan
    Write-Host "  [1] Show installed versions (git/kubectl/talosctl/helm)"
    Write-Host "      Confirm required CLI tools and versions." -ForegroundColor DarkGray
    Write-Host "  [2] kubectl get nodes/pods (uses repo kubeconfig if present)"
    Write-Host "      Snapshot cluster health across core resources." -ForegroundColor DarkGray
    Write-Host "  [3] Open repo folder in File Explorer"
    Write-Host "      Open local lab repo location for quick edits." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [0] Back"
    Write-Host ""

    Write-StatusLine -StatusText $StatusText -StatusColor $StatusColor
    Write-Host ""
}

$script:lastStatusText  = "[Ready] Ready"
$script:lastStatusColor = "DarkGray"
$script:RepoPath = Resolve-DevOpsRepoPath -TargetRelativePath $script:Target

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

$back = $false
while (-not $back) {
    Show-DevOpsQuickChecksMenu -StatusText $script:lastStatusText -StatusColor $script:lastStatusColor
    $choice = Read-Host "Select an option"

    switch ($choice) {
        "1" {
            Invoke-ActionSafe -SuccessText "Versions displayed" -Action {
                Show-Versions
            }
        }
        "2" {
            Invoke-ActionSafe -SuccessText "kubectl checks completed" -Action {
                Assert-RepoPresent -RepoUrl $script:RepoUrl -RepoPath $script:RepoPath -Branch $script:Branch
                $kubeconfig = Assert-KubeconfigReady -RepoPath $script:RepoPath

                Write-Host "Using kubeconfig: $kubeconfig" -ForegroundColor Gray
                Write-Host ""
                Write-Host "=== Section 1: Nodes ===" -ForegroundColor Cyan
                kubectl --kubeconfig $kubeconfig get nodes -o wide

                Write-Host ""
                Write-Host "=== Section 2: Pods (all namespaces) ===" -ForegroundColor Cyan
                kubectl --kubeconfig $kubeconfig get pods -A

                Write-Host ""
                Write-Host "=== Section 3: Services (all namespaces) ===" -ForegroundColor Cyan
                kubectl --kubeconfig $kubeconfig get svc -A

                Write-Host ""
                Write-Host "=== Section 4: Ingress (all namespaces) ===" -ForegroundColor Cyan
                kubectl --kubeconfig $kubeconfig get ingress -A

                Write-Host ""
                Write-Host "=== Section 5: ingress-nginx controller service ===" -ForegroundColor Cyan
                kubectl --kubeconfig $kubeconfig -n ingress-nginx get svc ingress-nginx-controller -o wide
            }
        }
        "3" {
            Invoke-ActionSafe -SuccessText "Opened repo folder" -Action {
                Assert-RepoPresent -RepoUrl $script:RepoUrl -RepoPath $script:RepoPath -Branch $script:Branch
                Start-Process explorer.exe $script:RepoPath
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
