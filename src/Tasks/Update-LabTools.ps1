# src\Tasks\Update-LabToolsFromGitHub.ps1
# Works in BOTH environments:
# - If C:\CITA\_LabToolsRepo is a git repo => repo-cache + deploy model (server side)
# - Else if C:\CITA\LabTools is a git repo => in-place pull model (Win11 side)
# Always shows errors and pauses (no silent window close)

$ErrorActionPreference = "Stop"

# =========================
# CONFIG - CHANGE IF NEEDED
# =========================
$RepoUrl  = "https://github.com/cronnpj/lab-scripts.git"
$RepoPath = "C:\CITA\_LabToolsRepo"   # local clone cache (server model)
$DestPath = "C:\CITA\LabTools"        # runtime path (win11 may be a repo)
$SrcRel   = "src"                     # deployable folder in repo-cache model

function Pause-Menu {
    Write-Host ""
    Read-Host "Press Enter to continue"
}

function Assert-IsAdmin {
    $current = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $current.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This updater must be run as Administrator."
    }
}

function Ensure-Git {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "git is not installed. Install Git for Windows first (winget install --id Git.Git -e)."
    }
}

function Ensure-Folders {
    if (-not (Test-Path "C:\CITA")) {
        New-Item -Path "C:\CITA" -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path $DestPath)) {
        New-Item -Path $DestPath -ItemType Directory -Force | Out-Null
    }
}

function Is-GitRepo([string]$Path) {
    if (-not (Test-Path $Path)) { return $false }
    $out = git -C $Path rev-parse --is-inside-work-tree 2>$null
    return ($LASTEXITCODE -eq 0 -and $out.Trim() -eq "true")
}

function Clone-Or-Pull([string]$Path) {
    if (-not (Test-Path $Path)) {
        Write-Host "Cloning repo to $Path ..."
        git clone $RepoUrl $Path | Out-Host
        return
    }

    if (-not (Is-GitRepo $Path)) {
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $moved = "${Path}_BROKEN_$stamp"
        Write-Host "WARNING: '$Path' exists but is not a git repo."
        Write-Host "Moving it to: $moved"
        Move-Item -Path $Path -Destination $moved -Force

        Write-Host "Cloning repo to $Path ..."
        git clone $RepoUrl $Path | Out-Host
        return
    }

    Write-Host "Pulling latest changes in $Path ..."
    git -C $Path fetch --all | Out-Host
    git -C $Path pull | Out-Host
}

function Deploy-FilesFromRepo([string]$RepoRoot) {
    $src = Join-Path $RepoRoot $SrcRel
    if (-not (Test-Path $src)) {
        throw "Deployable folder not found: $src"
    }

    # Backup current deployed tools
    $backupRoot = "C:\CITA\_LabToolsBackup"
    if (-not (Test-Path $backupRoot)) {
        New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null
    }

    $timestamp  = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = Join-Path $backupRoot $timestamp

    Write-Host "Backing up current LabTools to: $backupPath"
    New-Item -Path $backupPath -ItemType Directory -Force | Out-Null
    robocopy $DestPath $backupPath /E /NFL /NDL /NJH /NJS /NP | Out-Null

    Write-Host "Deploying latest LabTools into: $DestPath"
    robocopy $src $DestPath /MIR /NFL /NDL /NJH /NJS /NP | Out-Null

    $verFile = Join-Path $DestPath "VERSION.txt"
    $ver = if (Test-Path $verFile) { (Get-Content $verFile | Select-Object -First 1).Trim() } else { "unknown" }

    Write-Host ""
    Write-Host "Update complete. Deployed version: $ver"
    Write-Host "Backup saved at: $backupPath"
}

# =========
# RUN
# =========
try {
    Assert-IsAdmin
    Ensure-Git
    Ensure-Folders

    # Deterministic model selection:
    # 1) If RepoPath is a repo => ALWAYS use repo-cache+deploy model (server)
    # 2) Else if DestPath is a repo => in-place pull model (Win11)
    # 3) Else => create RepoPath and use repo-cache+deploy
    $repoCacheIsRepo = Test-Path (Join-Path $RepoPath ".git")
    $destIsRepo      = Is-GitRepo $DestPath

    if ($repoCacheIsRepo) {
        Write-Host "Repo-cache detected. Using repo-cache + deploy model."
        Clone-Or-Pull $RepoPath
        Deploy-FilesFromRepo $RepoPath
    }
    elseif ($destIsRepo) {
        Write-Host "Runtime folder is a git repo. Pulling updates in-place: $DestPath"
        Clone-Or-Pull $DestPath
        Write-Host ""
        Write-Host "Update complete (in-place repo pull)."
    }
    else {
        Write-Host "No repo detected yet. Creating repo-cache and deploying."
        Clone-Or-Pull $RepoPath
        Deploy-FilesFromRepo $RepoPath
    }

    Write-Host ""
    Write-Host "You can now re-launch the menu shortcut."
}
catch {
    Write-Host ""
    Write-Host "UPDATE FAILED:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Details:"
    Write-Host ($_ | Out-String)
}
finally {
    Pause-Menu
}
