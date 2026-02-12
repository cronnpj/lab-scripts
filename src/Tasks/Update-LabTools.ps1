# src\Tasks\Update-LabToolsFromGitHub.ps1
$ErrorActionPreference = "Stop"

# =========================
# CONFIG - CHANGE IF NEEDED
# =========================
$RepoUrl  = "https://github.com/cronnpj/lab-scripts.git"   # <-- your repo
$RepoPath = "C:\CITA\_LabToolsRepo"                        # local clone cache
$DestPath = "C:\CITA\LabTools"                             # live deployed path
$SrcRel   = "src"                                          # deployable folder in repo

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

function Clone-Or-Pull {
    if (-not (Test-Path $RepoPath)) {
        New-Item -Path $RepoPath -ItemType Directory -Force | Out-Null
        Write-Host "Cloning repo to $RepoPath ..."
        git clone $RepoUrl $RepoPath
    } else {
        Write-Host "Pulling latest changes in $RepoPath ..."
        git -C $RepoPath fetch --all
        git -C $RepoPath pull
    }
}

function Deploy-Files {
    $src = Join-Path $RepoPath $SrcRel
    if (-not (Test-Path $src)) {
        throw "Deployable folder not found: $src"
    }

    # Backup current deployed tools (quick + simple)
    $backupRoot = "C:\CITA\_LabToolsBackup"
    if (-not (Test-Path $backupRoot)) { New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = Join-Path $backupRoot $timestamp

    Write-Host "Backing up current LabTools to: $backupPath"
    New-Item -Path $backupPath -ItemType Directory -Force | Out-Null
    robocopy $DestPath $backupPath /E /NFL /NDL /NJH /NJS /NP | Out-Null

    Write-Host "Deploying latest LabTools into: $DestPath"
    robocopy $src $DestPath /E /PURGE /NFL /NDL /NJH /NJS /NP | Out-Null

    $verFile = Join-Path $DestPath "VERSION.txt"
    $ver = if (Test-Path $verFile) { (Get-Content $verFile).Trim() } else { "unknown" }

    Write-Host ""
    Write-Host "Update complete. Deployed version: $ver"
    Write-Host "Backup saved at: $backupPath"
}

# ========
# RUN
# ========
Assert-IsAdmin
Ensure-Git
Ensure-Folders
Clone-Or-Pull
Deploy-Files

Write-Host ""
Write-Host "You can now re-launch the menu shortcut."
Pause
