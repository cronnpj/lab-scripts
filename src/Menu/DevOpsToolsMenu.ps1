# C:\CITA\LabTools\src\Menu\DevOpsToolsMenu.ps1
# DevOps / CLI Tools Menu (cleaned + consistent)

param(
    [string]$RunOption
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Import-Module (Join-Path $PSScriptRoot "..\UI\ConsoleUI.psm1") -Force -ErrorAction Stop

# =========================
# Small UX helpers
# =========================
function Wait-Menu {
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

function Assert-Admin {
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
        Write-Host $_.Exception.ToString()
    }
    finally {
        $ErrorActionPreference = $prev
        Wait-Menu
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

    winget install -e --id $Id --accept-package-agreements --accept-source-agreements --silent --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        throw "winget install failed for id: $Id"
    }
}

# =========================
# Git + Repo management
# =========================
function Test-GitInstalled { return [bool](Get-Command git -ErrorAction SilentlyContinue) }

function Install-GitIfMissing {
    if (Test-GitInstalled) { return }

    if (-not (Test-IsAdmin)) {
        throw "Git is not installed. Installing Git via winget requires Administrator rights. Re-run this menu as Administrator, or install Git manually and retry."
    }

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

function Repair-RepoState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoUrl,
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][string]$Branch,
        [bool]$AutoResetIfDirty = $false
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
        else { throw "Repo has local changes. Run option [18] to reset, or stash/commit your changes." }
    }
}

function Sync-RepoContent {
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
    if ($LASTEXITCODE -ne 0) { throw "git fetch failed." }

    git -C $RepoPath checkout $Branch
    if ($LASTEXITCODE -ne 0) { throw "git checkout '$Branch' failed. Branch may not exist locally." }

    git -C $RepoPath pull origin $Branch
    if ($LASTEXITCODE -ne 0) { throw "git pull origin '$Branch' failed." }
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
    $code = $LASTEXITCODE

    if ($code -ne 0) {
        throw "Target exited with code $code"
    }
}

function Invoke-RepoBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoUrl,
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][string]$TargetRelativePath,
        [string]$Branch = "main",
        [string[]]$Arguments = @(),
        [bool]$AutoResetIfDirty = $false
    )

    Install-GitIfMissing
    Repair-RepoState -RepoUrl $RepoUrl -RepoPath $RepoPath -Branch $Branch -AutoResetIfDirty:$AutoResetIfDirty
    Sync-RepoContent -RepoUrl $RepoUrl -RepoPath $RepoPath -Branch $Branch

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
        [bool]$AutoResetIfDirty = $false
    )

    Install-GitIfMissing
    Repair-RepoState -RepoUrl $RepoUrl -RepoPath $RepoPath -Branch $Branch -AutoResetIfDirty:$AutoResetIfDirty
    Sync-RepoContent -RepoUrl $RepoUrl -RepoPath $RepoPath -Branch $Branch

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

    $preferredRoot = "C:\CITA_StudentRepos\lab-scripts"
    $runtimeRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $candidates = @(
        $preferredRoot,
        $runtimeRoot
    )

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

function Assert-RepoReady {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [string]$HintOption = "[9]"
    )

    if (-not (Test-Path -Path $RepoPath -PathType Container)) {
        throw "Prerequisite check failed: lab repo not found at $RepoPath. Run option $HintOption first."
    }

    $gitDir = Join-Path $RepoPath ".git"
    if (-not (Test-Path -Path $gitDir -PathType Container)) {
        throw "Prerequisite check failed: '$RepoPath' exists but is not a git repo. Run option $HintOption first to (re)install the lab repo."
    }
}

function Initialize-RepoPrereqs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoUrl,
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][string]$Branch,
        [bool]$AutoResetIfDirty = $false,
        [bool]$SkipSync = $false,
        [bool]$AllowDirty = $false,
        [string]$HintOption = "[9]"
    )

    Install-GitIfMissing
    if (-not $AllowDirty) {
        Repair-RepoState -RepoUrl $RepoUrl -RepoPath $RepoPath -Branch $Branch -AutoResetIfDirty:$AutoResetIfDirty
    }

    if ((-not $SkipSync) -or (-not (Test-Path $RepoPath)) -or (-not (Test-Path (Join-Path $RepoPath ".git")))) {
        Sync-RepoContent -RepoUrl $RepoUrl -RepoPath $RepoPath -Branch $Branch
    }

    if (-not $AllowDirty) {
        Repair-RepoState -RepoUrl $RepoUrl -RepoPath $RepoPath -Branch $Branch -AutoResetIfDirty:$AutoResetIfDirty
    }

    Assert-RepoReady -RepoPath $RepoPath -HintOption $HintOption
}

function Assert-KubeconfigReady {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [switch]$RequireReachable,
        [string]$HintOption = "[9]"
    )

    if (-not (Test-Cmd kubectl)) {
        throw "kubectl not found. Install it from option [3]."
    }

    $kubeconfig = Resolve-KubeconfigPath -RepoPath $RepoPath
    if (-not (Test-Path $kubeconfig)) {
        throw "Prerequisite check failed: kubeconfig not found at $kubeconfig. Run option $HintOption first."
    }

    if ($RequireReachable) {
        $nodesCheck = & kubectl --kubeconfig $kubeconfig get nodes -o name 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($nodesCheck | Out-String).Trim())) {
            throw "Prerequisite check failed: cluster is not reachable with current kubeconfig. Run option $HintOption first."
        }
    }

    return $kubeconfig
}

function New-CitaWebDemoAssets {
    param([Parameter(Mandatory)][string]$RepoPath)

    $demoDir  = Join-Path $RepoPath "labs\k8s-baremetal-lab\05-web-demo"
    $htmlPath = Join-Path $demoDir "index.html"
    $yamlPath = Join-Path $demoDir "cita-web.yaml"

    if (-not (Test-Path $demoDir)) {
        New-Item -ItemType Directory -Path $demoDir -Force | Out-Null
    }

    if (-not (Test-Path $htmlPath)) {
        $today = Get-Date -Format "yyyy-MM-dd"
        $starterHtml = @"
<!doctype html>
<html>
    <head>
        <meta charset="utf-8" />
        <title>CITA 360</title>
    </head>
    <body>
        <h1>CITA 360 Kubernetes Demo</h1>
        <p>Name: YOUR NAME HERE</p>
        <p>Section: YOUR SECTION HERE</p>
        <p>Updated: $today</p>
    </body>
</html>
"@
        Set-Content -Path $htmlPath -Value $starterHtml -Encoding utf8
    }

    if (-not (Test-Path $yamlPath)) {
        $citaYaml = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: cita-web
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: nginx
        image: nginx:stable
        ports:
        - containerPort: 80
        volumeMounts:
        - name: web-content
          mountPath: /usr/share/nginx/html
      volumes:
      - name: web-content
        configMap:
          name: cita-html
---
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: cita-web
spec:
  selector:
    app: web
  ports:
  - port: 80
    targetPort: 80
  type: LoadBalancer
"@
        Set-Content -Path $yamlPath -Value $citaYaml -Encoding utf8
    }

    return @{
        DemoDir  = $demoDir
        HtmlPath = $htmlPath
        YamlPath = $yamlPath
    }
}

function Remove-CitaWebDemo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [switch]$Force
    )

    $kubeconfig = Assert-KubeconfigReady -RepoPath $RepoPath -RequireReachable -HintOption "[9]"

    $existsOut = & kubectl --kubeconfig $kubeconfig get namespace cita-web -o name 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($existsOut | Out-String).Trim())) {
        Write-Host "CITA web demo namespace (cita-web) does not exist. Nothing to remove." -ForegroundColor DarkYellow
        return
    }

    if (-not $Force) {
        Write-Host "" 
        Write-Host "This will delete namespace 'cita-web' and all demo resources inside it." -ForegroundColor Yellow
        $confirm = (Read-Host "Type DELETE to confirm").Trim()
        if ($confirm -ne "DELETE") {
            Write-Host "Cancelled. Demo reset was not performed." -ForegroundColor DarkYellow
            return
        }
    }

    Write-Host "Deleting namespace cita-web..." -ForegroundColor Cyan
    & kubectl --kubeconfig $kubeconfig delete namespace cita-web --wait=true

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to delete namespace cita-web."
    }

    Write-Host "CITA web demo reset complete. Namespace cita-web removed." -ForegroundColor Green
}

# =========================
# Menu
# =========================
$script:RepoUrl  = "https://github.com/cronnpj/lab-scripts.git"
$script:Branch   = "main"
$script:Target   = "labs\k8s-baremetal-lab\bootstrap.ps1"
$script:RepoPath = Resolve-DevOpsRepoPath -TargetRelativePath $script:Target
$script:InstallUpdateMenuPath = Join-Path $PSScriptRoot "DevOpsInstallUpdateMenu.ps1"
$script:QuickChecksMenuPath = Join-Path $PSScriptRoot "DevOpsQuickChecksMenu.ps1"
$script:LabInstallOpsMenuPath = Join-Path $PSScriptRoot "DevOpsLabInstallOpsMenu.ps1"

$script:lastStatusText  = "Ready"
$script:lastStatusColor = "DarkGray"

function Show-DevOpsMenu {
    param(
        [string]$StatusText  = "Ready",
        [string]$StatusColor = "DarkGray"
    )

    Show-AppHeader -Breadcrumb "Main > DevOps / CLI Tools"

    Write-Host "  Install / Update Tools" -ForegroundColor Cyan
    Write-Host "  [1]  Open Install / Update Tools submenu"
    Write-Host ""
    Write-Host "  Quick Checks / Utilities" -ForegroundColor Cyan
    Write-Host "  [6]  Open Quick Checks / Utilities submenu"
    Write-Host ""
    Write-Host "  Lab Repository - Install Operations" -ForegroundColor Cyan
    Write-Host "  [9]  Open Lab Repository - Install Operations submenu"
    Write-Host ""
    Write-Host "  Lab Repository - Advanced Operations" -ForegroundColor Cyan
    Write-Host "  [16] Wipe + Rebuild cluster (student reset mode)"
    Write-Host "  [17] Nuke local generated files (kubeconfig + student-overrides)"
    Write-Host "  [18] Repo lab-safe reset (discard local changes)"
    Write-Host "  [19] Add new worker node to existing cluster"
    Write-Host "  [20] Reset CITA Web Demo only (delete namespace cita-web)"
    Write-Host "  [21] Open kubectl prompt (new window, repo kubeconfig)"
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
    if (-not [string]::IsNullOrWhiteSpace($RunOption)) {
        $choice = $RunOption
        $RunOption = ""
    }
    else {
        $choice = Read-Host "Select an option"
    }

    switch ($choice) {

        # === Install / Update Tools ===
        "1" {
            Invoke-ActionSafe -SuccessText "Returned from Install / Update Tools submenu" -Action {
                if (-not (Test-Path $script:InstallUpdateMenuPath)) {
                    throw "Install submenu not found: $($script:InstallUpdateMenuPath)"
                }

                & $script:InstallUpdateMenuPath
            }
        }

        "2" {
            Set-Status -Text "Use option [1] Install / Update Tools submenu" -Color "Yellow"
            Write-Host "This top-level option has moved. Use option [1] to open Install / Update Tools submenu." -ForegroundColor Yellow
            Wait-Menu
        }

        "3" {
            Set-Status -Text "Use option [1] Install / Update Tools submenu" -Color "Yellow"
            Write-Host "This top-level option has moved. Use option [1] to open Install / Update Tools submenu." -ForegroundColor Yellow
            Wait-Menu
        }

        "4" {
            Set-Status -Text "Use option [1] Install / Update Tools submenu" -Color "Yellow"
            Write-Host "This top-level option has moved. Use option [1] to open Install / Update Tools submenu." -ForegroundColor Yellow
            Wait-Menu
        }

        "5" {
            Set-Status -Text "Use option [1] Install / Update Tools submenu" -Color "Yellow"
            Write-Host "This top-level option has moved. Use option [1] to open Install / Update Tools submenu." -ForegroundColor Yellow
            Wait-Menu
        }

        # === Quick Checks / Utilities ===
        "6" {
            Invoke-ActionSafe -SuccessText "Returned from Quick Checks / Utilities submenu" -Action {
                if (-not (Test-Path $script:QuickChecksMenuPath)) {
                    throw "Quick checks submenu not found: $($script:QuickChecksMenuPath)"
                }

                & $script:QuickChecksMenuPath
            }
        }

        "7" {
            Set-Status -Text "Use option [6] Quick Checks / Utilities submenu" -Color "Yellow"
            Write-Host "This top-level option has moved. Use option [6] to open Quick Checks / Utilities submenu." -ForegroundColor Yellow
            Wait-Menu
        }

        "8" {
            Set-Status -Text "Use option [6] Quick Checks / Utilities submenu" -Color "Yellow"
            Write-Host "This top-level option has moved. Use option [6] to open Quick Checks / Utilities submenu." -ForegroundColor Yellow
            Wait-Menu
        }

        # === Lab Repository - Basic Operations ===
        "9" {
            Invoke-ActionSafe -SuccessText "Returned from Lab Install Operations submenu" -Action {
                if (-not (Test-Path $script:LabInstallOpsMenuPath)) {
                    throw "Lab install operations submenu not found: $($script:LabInstallOpsMenuPath)"
                }

                & $script:LabInstallOpsMenuPath
            }
        }

        "91" {
            Invoke-ActionSafe -SuccessText "Option 9 platform workflow completed" -Action {
                Initialize-RepoPrereqs -RepoUrl $script:RepoUrl -RepoPath $script:RepoPath -Branch $script:Branch -AutoResetIfDirty:$true
                if (-not (Test-Cmd kubectl)) { throw "kubectl not found. Install it from option [3]." }

                $defaultControlPlaneIp = "192.168.1.3"
                $defaultWorkerIps = @("192.168.1.5","192.168.1.6")
                $defaultWorkersText = ($defaultWorkerIps -join ",")

                Write-Host ""
                Write-Host "Cluster node IP configuration:" -ForegroundColor Cyan

                $controlPlaneIp = (Read-Host "Control-plane IP [$defaultControlPlaneIp]").Trim()
                if ([string]::IsNullOrWhiteSpace($controlPlaneIp)) { $controlPlaneIp = $defaultControlPlaneIp }

                $workersInput = (Read-Host "Worker IPs (comma-separated) [$defaultWorkersText]").Trim()
                $workerIps = @()
                if ([string]::IsNullOrWhiteSpace($workersInput)) {
                    $workerIps = @($defaultWorkerIps)
                }
                else {
                    $workerIps = @($workersInput -split "\\s*,\\s*" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                }

                if ($workerIps.Count -lt 1) {
                    throw "At least one worker IP is required."
                }

                $kubeconfig = Resolve-KubeconfigPath -RepoPath $script:RepoPath
                $clusterExists = $false

                if (Test-Path $kubeconfig) {
                    $nativePrefVar = Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue
                    $hadNativePref = ($null -ne $nativePrefVar)
                    $previousNativePref = $false

                    if ($hadNativePref) {
                        $previousNativePref = [bool]$global:PSNativeCommandUseErrorActionPreference
                        $global:PSNativeCommandUseErrorActionPreference = $false
                    }

                    try {
                        $nodesRaw = & kubectl --kubeconfig $kubeconfig --request-timeout=8s get nodes -o name 2>$null
                        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($nodesRaw | Out-String).Trim())) {
                            $clusterExists = $true
                        }
                    }
                    catch {
                        $clusterExists = $false
                    }
                    finally {
                        if ($hadNativePref) {
                            $global:PSNativeCommandUseErrorActionPreference = $previousNativePref
                        }
                    }
                }

                Write-Host ""
                if ($clusterExists) {
                    Write-Host "Cluster status: Existing cluster detected." -ForegroundColor Green
                    Write-Host "Mode: add-ons only (skip cluster rebuild/bootstrap)." -ForegroundColor Green
                }
                else {
                    Write-Host "Cluster status: No reachable existing cluster detected." -ForegroundColor Yellow
                    Write-Host "Mode: full cluster workflow (build + add-ons)." -ForegroundColor Yellow
                }

                Write-Host ""
                Write-Host "Ingress action for this run:" -ForegroundColor Cyan
                Write-Host "  [E] Ensure ingress (install if missing, skip if already installed)"
                Write-Host "  [R] Reinstall ingress"
                Write-Host "  [S] Skip ingress"

                $ingressChoice = (Read-Host "Select ingress action [E/R/S] (default E)").Trim().ToUpper()
                if ([string]::IsNullOrWhiteSpace($ingressChoice)) { $ingressChoice = "E" }
                if ($ingressChoice -notin @("E","R","S")) {
                    throw "Invalid ingress selection: $ingressChoice"
                }

                $bootstrapArgs = @("-ControlPlaneIP", $controlPlaneIp, "-WorkerIPs") + $workerIps + @("-InstallMetalLB")
                if ($ingressChoice -eq "E" -or $ingressChoice -eq "R") {
                    $bootstrapArgs += "-InstallIngress"
                }
                if ($ingressChoice -eq "R") {
                    $bootstrapArgs += "-ReinstallIngress"
                }
                if ($clusterExists) {
                    $bootstrapArgs = @("-AddonsOnly") + $bootstrapArgs
                }

                Write-Host ""
                $runPathText = if ($clusterExists) { "Add-ons only" } else { "Full cluster workflow" }
                $ingressModeText = switch ($ingressChoice) {
                    "E" { "Ensure ingress" }
                    "R" { "Reinstall ingress" }
                    "S" { "Skip ingress" }
                    default { "Unknown" }
                }
                Write-Host "Plan: $runPathText | Ingress: $ingressModeText" -ForegroundColor Cyan
                Write-Host "Executing bootstrap with args: $($bootstrapArgs -join ' ')" -ForegroundColor DarkGray

                Invoke-RepoTarget `
                    -RepoPath $script:RepoPath `
                    -TargetRelativePath $script:Target `
                    -Arguments $bootstrapArgs

                Write-Host ""
                Write-Host "Summary: Completed option [9] using '$runPathText' with '$ingressModeText'." -ForegroundColor Green
            }
        }

        "92" {
            Invoke-ActionSafe -SuccessText "MetalLB installed / VIP pool applied" -Action {
                Initialize-RepoPrereqs -RepoUrl $script:RepoUrl -RepoPath $script:RepoPath -Branch $script:Branch

                Invoke-RepoTarget `
                    -RepoPath $script:RepoPath `
                    -TargetRelativePath $script:Target `
                    -Arguments @("-AddonsOnly","-InstallMetalLB")
            }
        }

        "93" {
            Invoke-ActionSafe -SuccessText "Portainer install completed" -Action {
                Initialize-RepoPrereqs -RepoUrl $script:RepoUrl -RepoPath $script:RepoPath -Branch $script:Branch
                $kubeconfig = Assert-KubeconfigReady -RepoPath $script:RepoPath -RequireReachable -HintOption "[9]"

                Write-Host ""
                Write-Host "Portainer publish mode:" -ForegroundColor Cyan
                Write-Host "  [I] Ingress host mode (domain/hosts entry)"
                Write-Host "  [P] IP-only mode (NodePort, no DNS/hosts required)"
                Write-Host "  [L] IP-only mode (LoadBalancer VIP via MetalLB)"

                $portainerMode = (Read-Host "Select mode [I/P/L] (default I)").Trim().ToUpper()
                if ([string]::IsNullOrWhiteSpace($portainerMode)) { $portainerMode = "I" }
                if ($portainerMode -notin @("I","P","L")) {
                    throw "Invalid Portainer mode selection: $portainerMode"
                }

                $invokeArgs = @("-AddonsOnly","-InstallPortainer")
                if ($portainerMode -eq "I") {
                    $baseDomain = (Read-Host "Enter Portainer base domain [lab.local]").Trim()
                    if ([string]::IsNullOrWhiteSpace($baseDomain)) { $baseDomain = "lab.local" }
                    $invokeArgs += @("-InstallIngress","-PortainerDomain",$baseDomain)
                }
                elseif ($portainerMode -eq "L") {
                    $invokeArgs += "-PortainerLoadBalancer"
                }

                try {
                    Invoke-RepoTarget `
                        -RepoPath $script:RepoPath `
                        -TargetRelativePath $script:Target `
                        -Arguments $invokeArgs
                }
                catch {
                    Write-Host "" 
                    Write-Host "Portainer install failed." -ForegroundColor Red
                    if ($portainerMode -eq "I") {
                        Write-Host "Most common cause: ingress not installed/healthy or cluster not ready." -ForegroundColor Yellow
                    }
                    elseif ($portainerMode -eq "P") {
                        Write-Host "Most common cause: cluster/service not ready yet." -ForegroundColor Yellow
                    }
                    else {
                        Write-Host "Most common cause: MetalLB VIP pending or service not ready yet." -ForegroundColor Yellow
                    }
                    Write-Host "Next steps:" -ForegroundColor Yellow
                    if ($portainerMode -eq "I") {
                        Write-Host "  1) Run option [9] and choose ingress = Ensure or Reinstall" -ForegroundColor Yellow
                        Write-Host "  2) Verify ingress controller: kubectl --kubeconfig $kubeconfig -n ingress-nginx get svc ingress-nginx-controller" -ForegroundColor Yellow
                        Write-Host "  3) Retry option [11]" -ForegroundColor Yellow
                    }
                    elseif ($portainerMode -eq "P") {
                        Write-Host "  1) Verify Portainer pods/services: kubectl --kubeconfig $kubeconfig -n portainer get pods,svc" -ForegroundColor Yellow
                        Write-Host "  2) Retry option [11] in IP mode" -ForegroundColor Yellow
                    }
                    else {
                        Write-Host "  1) Verify MetalLB + Portainer service: kubectl --kubeconfig $kubeconfig -n metallb-system get pods; kubectl --kubeconfig $kubeconfig -n portainer get svc portainer" -ForegroundColor Yellow
                        Write-Host "  2) Retry option [11] in LoadBalancer mode" -ForegroundColor Yellow
                    }
                    throw
                }
            }
        }

        "94" {
            Invoke-ActionSafe -SuccessText "CITA web demo deployed / updated" -Action {
                Initialize-RepoPrereqs -RepoUrl $script:RepoUrl -RepoPath $script:RepoPath -Branch $script:Branch -SkipSync:$true -AllowDirty:$true
                $kubeconfig = Assert-KubeconfigReady -RepoPath $script:RepoPath -RequireReachable -HintOption "[9]"

                $assets = New-CitaWebDemoAssets -RepoPath $script:RepoPath

                Write-Host "Using kubeconfig: $kubeconfig" -ForegroundColor Gray
                Write-Host "Using index.html: $($assets.HtmlPath)" -ForegroundColor Gray
                Write-Host "Using manifest:   $($assets.YamlPath)" -ForegroundColor Gray
                Write-Host "" 
                Write-Host "Step 1/7 - Ensure namespace exists: cita-web" -ForegroundColor Cyan

                kubectl --kubeconfig $kubeconfig create namespace cita-web --dry-run=client -o yaml | kubectl --kubeconfig $kubeconfig apply -f -

                Write-Host "" 
                Write-Host "Step 2/7 - Create or update ConfigMap from index.html (cita-html)" -ForegroundColor Cyan

                kubectl --kubeconfig $kubeconfig create configmap cita-html --from-file=index.html=$($assets["HtmlPath"]) -n cita-web --dry-run=client -o yaml | kubectl --kubeconfig $kubeconfig apply -f -

                Write-Host "" 
                Write-Host "Step 3/7 - Apply workload manifest (Deployment + LoadBalancer Service)" -ForegroundColor Cyan

                kubectl --kubeconfig $kubeconfig apply -f $($assets.YamlPath) -n cita-web

                Write-Host "" 
                Write-Host "Step 4/7 - Restart deployment so pods pick up the updated HTML content" -ForegroundColor Cyan

                kubectl --kubeconfig $kubeconfig rollout restart deployment/web -n cita-web

                Write-Host "" 
                Write-Host "Step 5/7 - Wait for deployment rollout to finish" -ForegroundColor Cyan

                kubectl --kubeconfig $kubeconfig -n cita-web rollout status deployment/web --timeout=180s

                Write-Host "" 
                Write-Host "Step 6/7 - Show pods and service status" -ForegroundColor Cyan
                Write-Host "" 
                Write-Host "=== cita-web status ===" -ForegroundColor Cyan
                kubectl --kubeconfig $kubeconfig get pods -n cita-web
                kubectl --kubeconfig $kubeconfig get svc -n cita-web

                Write-Host ""
                Write-Host "Step 7/7 - Wait for service EXTERNAL-IP (up to 3 minutes)" -ForegroundColor Cyan

                $externalIp = ""
                $deadline = (Get-Date).AddMinutes(3)
                while ((Get-Date) -lt $deadline) {
                    $ip = (& kubectl --kubeconfig $kubeconfig -n cita-web get svc web -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null | Out-String).Trim()
                    $hostname = ""
                    if ([string]::IsNullOrWhiteSpace($ip)) {
                        $hostname = (& kubectl --kubeconfig $kubeconfig -n cita-web get svc web -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null | Out-String).Trim()
                    }

                    if (-not [string]::IsNullOrWhiteSpace($ip)) {
                        $externalIp = $ip
                        break
                    }
                    if (-not [string]::IsNullOrWhiteSpace($hostname)) {
                        $externalIp = $hostname
                        break
                    }
                    Start-Sleep -Seconds 5
                }

                if (-not [string]::IsNullOrWhiteSpace($externalIp)) {
                    Write-Host "EXTERNAL-IP assigned: $externalIp" -ForegroundColor Green
                    Write-Host "Open in browser: http://$externalIp" -ForegroundColor Green
                }
                else {
                    Write-Host "EXTERNAL-IP not assigned yet (timeout reached)." -ForegroundColor Yellow
                }

                Write-Host "" 
                Write-Host "Next step: watch for an EXTERNAL-IP on service/web" -ForegroundColor Yellow
                Write-Host "Command: kubectl --kubeconfig $kubeconfig get svc -n cita-web" -ForegroundColor Yellow
                Write-Host "Then browse to: http://<EXTERNAL-IP>" -ForegroundColor Yellow
            }
        }

        "95" {
            Invoke-ActionSafe -SuccessText "CITA web demo scaled" -Action {
                Initialize-RepoPrereqs -RepoUrl $script:RepoUrl -RepoPath $script:RepoPath -Branch $script:Branch
                $kubeconfig = Assert-KubeconfigReady -RepoPath $script:RepoPath -RequireReachable -HintOption "[9]"

                Write-Host "" 
                Write-Host "Scale CITA Web Demo (namespace: cita-web, deployment: web)" -ForegroundColor Cyan
                Write-Host "  [1] 2 replicas"
                Write-Host "  [2] 4 replicas"
                Write-Host "  [3] 5 replicas"
                Write-Host "  [4] Custom"

                $scaleChoice = (Read-Host "Select replica target").Trim()
                $replicas = 0

                switch ($scaleChoice) {
                    "1" { $replicas = 2 }
                    "2" { $replicas = 4 }
                    "3" { $replicas = 5 }
                    "4" {
                        $custom = (Read-Host "Enter custom replica count (integer >= 1)").Trim()
                        if (-not [int]::TryParse($custom, [ref]$replicas) -or $replicas -lt 1) {
                            throw "Invalid replica count: $custom"
                        }
                    }
                    default { throw "Invalid selection: $scaleChoice" }
                }

                Write-Host "" 
                Write-Host "Scaling deployment/web in cita-web to $replicas replicas..." -ForegroundColor Cyan
                kubectl --kubeconfig $kubeconfig scale deployment web --replicas=$replicas -n cita-web

                Write-Host "" 
                Write-Host "Pods (wide):" -ForegroundColor Cyan
                kubectl --kubeconfig $kubeconfig get pods -o wide -n cita-web
            }
        }

        "96" {
            Invoke-ActionSafe -SuccessText "Selected deployment scaled" -Action {
                Initialize-RepoPrereqs -RepoUrl $script:RepoUrl -RepoPath $script:RepoPath -Branch $script:Branch
                $kubeconfig = Assert-KubeconfigReady -RepoPath $script:RepoPath -RequireReachable -HintOption "[9]"

                $raw = kubectl --kubeconfig $kubeconfig get deployments -A -o json
                if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) {
                    throw "Failed to list deployments. Verify cluster connectivity."
                }

                $obj = $raw | ConvertFrom-Json
                if (-not $obj.items -or $obj.items.Count -eq 0) {
                    throw "No deployments found in the cluster."
                }

                $items = @($obj.items | Sort-Object { $_.metadata.namespace }, { $_.metadata.name })
                Write-Host "" 
                Write-Host "Select a deployment to scale:" -ForegroundColor Cyan

                for ($i = 0; $i -lt $items.Count; $i++) {
                    $ns = $items[$i].metadata.namespace
                    $name = $items[$i].metadata.name
                    $cur = $items[$i].spec.replicas
                    Write-Host ("  [{0}] {1}/{2} (current replicas: {3})" -f ($i + 1), $ns, $name, $cur)
                }

                $pickRaw = (Read-Host "Enter selection number").Trim()
                $pick = 0
                if (-not [int]::TryParse($pickRaw, [ref]$pick) -or $pick -lt 1 -or $pick -gt $items.Count) {
                    throw "Invalid selection: $pickRaw"
                }

                $selected = $items[$pick - 1]
                $selNs = $selected.metadata.namespace
                $selName = $selected.metadata.name

                $repRaw = (Read-Host "Enter replica count (integer >= 1)").Trim()
                $targetReplicas = 0
                if (-not [int]::TryParse($repRaw, [ref]$targetReplicas) -or $targetReplicas -lt 1) {
                    throw "Invalid replica count: $repRaw"
                }

                Write-Host "" 
                Write-Host "Scaling $selNs/$selName to $targetReplicas replicas..." -ForegroundColor Cyan
                kubectl --kubeconfig $kubeconfig scale deployment $selName --replicas=$targetReplicas -n $selNs

                Write-Host "" 
                Write-Host "Pods in namespace $selNs (wide):" -ForegroundColor Cyan
                kubectl --kubeconfig $kubeconfig get pods -o wide -n $selNs
            }
        }

        "97" {
            Invoke-ActionSafe -SuccessText "Helm app install / update completed" -Action {
                if (-not (Test-Cmd helm)) { throw "helm not found. Install it from option [4]." }
                Initialize-RepoPrereqs -RepoUrl $script:RepoUrl -RepoPath $script:RepoPath -Branch $script:Branch

                Write-Host "" 
                Write-Host "Helm install examples:" -ForegroundColor Cyan
                Write-Host "  Repo name: bitnami" -ForegroundColor Gray
                Write-Host "  Repo URL:  https://charts.bitnami.com/bitnami" -ForegroundColor Gray
                Write-Host "  Chart ref: bitnami/nginx" -ForegroundColor Gray
                Write-Host "  --set:     service.type=LoadBalancer,replicaCount=2" -ForegroundColor Gray
                Write-Host "  Repo name: prometheus-community" -ForegroundColor Gray
                Write-Host "  Repo URL:  https://prometheus-community.github.io/helm-charts" -ForegroundColor Gray
                Write-Host "  Chart ref: prometheus-community/prometheus" -ForegroundColor Gray

                $kubeconfig = Assert-KubeconfigReady -RepoPath $script:RepoPath -RequireReachable -HintOption "[9]"

                $repoName = (Read-Host "Helm repo name (optional, e.g. bitnami)").Trim()
                $repoUrl  = (Read-Host "Helm repo URL (optional, e.g. https://charts.bitnami.com/bitnami)").Trim()

                if ((-not [string]::IsNullOrWhiteSpace($repoName)) -or (-not [string]::IsNullOrWhiteSpace($repoUrl))) {
                    if ([string]::IsNullOrWhiteSpace($repoName) -or [string]::IsNullOrWhiteSpace($repoUrl)) {
                        throw "If adding a repo, provide both repo name and repo URL."
                    }
                    Write-Host "" 
                    Write-Host "Adding/updating Helm repo $repoName ..." -ForegroundColor Cyan
                    helm repo add $repoName $repoUrl --force-update | Out-Null
                }

                Write-Host "" 
                Write-Host "Updating Helm repo index..." -ForegroundColor Cyan
                helm repo update | Out-Null

                $chartRef = (Read-Host "Chart reference (e.g. bitnami/nginx)").Trim()
                if ([string]::IsNullOrWhiteSpace($chartRef)) {
                    throw "Chart reference cannot be blank."
                }

                $defaultRelease = ($chartRef -replace '[^a-zA-Z0-9-]', '-')
                if ($defaultRelease.Length -gt 40) { $defaultRelease = $defaultRelease.Substring(0,40) }
                $defaultRelease = $defaultRelease.Trim('-').ToLower()
                if ([string]::IsNullOrWhiteSpace($defaultRelease)) { $defaultRelease = "app" }

                $releaseName = (Read-Host "Release name [$defaultRelease]").Trim()
                if ([string]::IsNullOrWhiteSpace($releaseName)) { $releaseName = $defaultRelease }

                $namespace = (Read-Host "Namespace [default]").Trim()
                if ([string]::IsNullOrWhiteSpace($namespace)) { $namespace = "default" }

                $exposeLb = (Read-Host "Expose service through MetalLB? (y/N)").Trim().ToLower()
                $enableIngress = (Read-Host "Enable Ingress (ingress-nginx)? (y/N)").Trim().ToLower()

                $valuesFile = (Read-Host "Values file path (optional)").Trim()
                $extraSet   = (Read-Host "Optional --set values (comma-separated, e.g. service.type=LoadBalancer,replicaCount=2)").Trim()

                $autoSetParts = New-Object System.Collections.Generic.List[string]
                if ($exposeLb -eq "y" -or $exposeLb -eq "yes") {
                    $autoSetParts.Add("service.type=LoadBalancer")
                }
                if ($enableIngress -eq "y" -or $enableIngress -eq "yes") {
                    $autoSetParts.Add("ingress.enabled=true")
                }

                if ($autoSetParts.Count -gt 0) {
                    $autoSet = ($autoSetParts -join ",")
                    if ([string]::IsNullOrWhiteSpace($extraSet)) {
                        $extraSet = $autoSet
                    }
                    else {
                        $extraSet = "$extraSet,$autoSet"
                    }

                    Write-Host "" 
                    Write-Host "Auto exposure values added: $autoSet" -ForegroundColor DarkGray
                }

                $helmArgs = @(
                    "upgrade", "--install", $releaseName, $chartRef,
                    "--namespace", $namespace, "--create-namespace"
                )

                if (-not [string]::IsNullOrWhiteSpace($valuesFile)) {
                    if (-not (Test-Path $valuesFile)) {
                        throw "Values file not found: $valuesFile"
                    }
                    $helmArgs += @("-f", $valuesFile)
                }

                if (-not [string]::IsNullOrWhiteSpace($extraSet)) {
                    $helmArgs += @("--set", $extraSet)
                }

                Write-Host "" 
                Write-Host "Installing/updating Helm release..." -ForegroundColor Cyan
                Write-Host "helm $($helmArgs -join ' ')" -ForegroundColor DarkGray

                & helm @helmArgs
                if ($LASTEXITCODE -ne 0) {
                    throw "Helm install/update failed."
                }

                Write-Host "" 
                Write-Host "Release status:" -ForegroundColor Cyan
                helm status $releaseName -n $namespace

                Write-Host "" 
                Write-Host "Namespace resources:" -ForegroundColor Cyan
                kubectl --kubeconfig $kubeconfig get pods -n $namespace
                kubectl --kubeconfig $kubeconfig get svc -n $namespace

                Write-Host "" 
                Write-Host "Ingress resources (namespace):" -ForegroundColor Cyan
                kubectl --kubeconfig $kubeconfig get ingress -n $namespace

                Write-Host "" 
                Write-Host "Exposure check tips:" -ForegroundColor Yellow
                Write-Host "- For LoadBalancer services, wait for EXTERNAL-IP: kubectl --kubeconfig $kubeconfig get svc -n $namespace" -ForegroundColor Yellow
                Write-Host "- For ingress, confirm host/path and resolve DNS/hosts to ingress IP." -ForegroundColor Yellow
                Write-Host "- Some charts use chart-specific values; if service/ingress is not exposed, re-run option [15] with the chart's documented values." -ForegroundColor Yellow
            }
        }

        "16" {
            Invoke-ActionSafe -SuccessText "Wipe + rebuild executed" -Action {
                Initialize-RepoPrereqs -RepoUrl $script:RepoUrl -RepoPath $script:RepoPath -Branch $script:Branch -AutoResetIfDirty:$true
                Invoke-RepoTarget -RepoPath $script:RepoPath -TargetRelativePath $script:Target -Arguments @("-WipeAndRebuild","-Interactive")
            }
        }

        "17" {
            Invoke-ActionSafe -SuccessText "Local generated files removed" -Action {
                Initialize-RepoPrereqs -RepoUrl $script:RepoUrl -RepoPath $script:RepoPath -Branch $script:Branch -AutoResetIfDirty:$true

                $kube = Join-Path $script:RepoPath "kubeconfig"
                $ovr  = Join-Path $script:RepoPath "01-talos\student-overrides"

                Remove-Item -Force -ErrorAction SilentlyContinue $kube
                if (Test-Path $ovr) { Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $ovr }

                Write-Host "Removed: $kube" -ForegroundColor Gray
                Write-Host "Removed: $ovr"  -ForegroundColor Gray
            }
        }

        "18" {
            Invoke-ActionSafe -SuccessText "Repo reset to origin completed" -Action {
                Initialize-RepoPrereqs -RepoUrl $script:RepoUrl -RepoPath $script:RepoPath -Branch $script:Branch -AutoResetIfDirty:$true
                if (-not (Test-Path (Join-Path $script:RepoPath ".git"))) { throw "Repo not found: $($script:RepoPath)" }
                Reset-RepoToOrigin -RepoPath $script:RepoPath -Branch $script:Branch
            }
        }

        "19" {
            Invoke-ActionSafe -SuccessText "Worker add operation completed" -Action {
                Initialize-RepoPrereqs -RepoUrl $script:RepoUrl -RepoPath $script:RepoPath -Branch $script:Branch
                if (-not (Test-Cmd talosctl)) { throw "talosctl not found. Install it from option [2]." }

                $workerIp = (Read-Host "Enter NEW worker IP address").Trim()
                if ([string]::IsNullOrWhiteSpace($workerIp)) { throw "Worker IP cannot be blank." }

                $workerCfg = Resolve-WorkerConfigPath -RepoPath $script:RepoPath
                if (-not (Test-Path $workerCfg)) {
                    throw "worker.yaml not found at: $workerCfg`nRun option [9] first to generate Talos configs."
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

                $kubeconfig = $null
                $hasKubectl = Test-Cmd kubectl
                if ($hasKubectl) {
                    $kubeconfig = Resolve-KubeconfigPath -RepoPath $script:RepoPath
                }
                if ($hasKubectl -and $kubeconfig -and (Test-Path $kubeconfig)) {
                    Write-Host "Waiting briefly, then checking node registration..." -ForegroundColor Gray
                    Start-Sleep -Seconds 12
                    kubectl --kubeconfig $kubeconfig get nodes -o wide
                }
                else {
                    Write-Host "Worker config applied. Install/locate kubeconfig to verify node join with kubectl." -ForegroundColor DarkYellow
                }
            }
        }

        "20" {
            Invoke-ActionSafe -SuccessText "CITA web demo reset completed" -Action {
                Initialize-RepoPrereqs -RepoUrl $script:RepoUrl -RepoPath $script:RepoPath -Branch $script:Branch
                Remove-CitaWebDemo -RepoPath $script:RepoPath
            }
        }

        "21" {
            Invoke-ActionSafe -SuccessText "Opened kubectl prompt" -Action {
                Initialize-RepoPrereqs -RepoUrl $script:RepoUrl -RepoPath $script:RepoPath -Branch $script:Branch -SkipSync:$true -AllowDirty:$true
                $kubeconfig = Assert-KubeconfigReady -RepoPath $script:RepoPath -RequireReachable -HintOption "[9]"

                $escapedKubeconfig = $kubeconfig.Replace("'", "''")
                $promptCommand = @"
$env:KUBECONFIG = '$escapedKubeconfig'
Clear-Host
Write-Host 'Kubernetes shell ready.' -ForegroundColor Green
Write-Host 'KUBECONFIG: $escapedKubeconfig' -ForegroundColor Gray
Write-Host 'Try: kubectl get nodes -o wide' -ForegroundColor Cyan
Write-Host 'Type exit to close this window.' -ForegroundColor DarkGray
"@

                Start-Process powershell.exe -ArgumentList @(
                    "-NoLogo",
                    "-NoExit",
                    "-NoProfile",
                    "-ExecutionPolicy", "Bypass",
                    "-Command", $promptCommand
                )
            }
        }

        "0" { $back = $true }

        default {
            Set-Status -Text "Invalid selection" -Color "Red"
            Wait-Menu
        }
    }

    if ([string]::IsNullOrWhiteSpace($RunOption) -and -not [string]::IsNullOrWhiteSpace($choice) -and ($choice -in @("91","92","93","94","95","96","97"))) {
        $back = $true
    }

} while (-not $back)

Clear-Host
return
