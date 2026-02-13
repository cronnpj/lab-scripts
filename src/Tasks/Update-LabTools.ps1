# src\Tasks\Update-LabTools.ps1
$ErrorActionPreference = "Stop"

# =========================
# CONFIG - CHANGE IF NEEDED
# =========================
$RepoUrl  = "https://github.com/cronnpj/lab-scripts.git"
$RepoPath = "C:\CITA\_LabToolsRepo"     # optional clone cache (preferred if present)
$DestPath = "C:\CITA\LabTools"          # runtime/deployed path (may itself be a git repo on Win11)
$SrcRel   = "src"                       # deployable folder in repo

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
        # Path exists but isn't a repo -> move it aside and re-clone
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $moved = "${Path}_OLD_$stamp"
        Write-Host "WARNING: $Path exists but is not a git repo."
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
        throw "Deployable folder not found: It's expecting '$SrcRel' inside repo: $RepoRoot"
    }

    # Backup current deployed tools
    $backupRoot = "C:\CITA\_LabToolsBackup"
    if (-not (Test-Path $backupRoot)) { New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null }

    $timestamp  = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = Join-Path $backupRoot $timestamp

    Write-Host "Backing up current LabTools to: $backupPath"
    New-Item -Path $backupPath -ItemType Directory -Force | Out-Null
    robocopy $DestPath $backupPath /E /NFL /NDL /NJH /NJS /NP | Out-Null

    Write-Host "Deploying latest LabTools into: $DestPath"
    # /MIR is cleaner than /E /PURGE, but either works; /MIR mirrors and removes extras
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

    # Decide where to pull from:
    # Prefer RepoPath if it exists OR if DestPath is not a repo.
    $useRepoCache = $true
    if (Is-GitRepo $DestPath) {
        # Win11 case: runtime is already a repo — simplest is to pull in place and skip deploy
        # but we still support deploy-from-src if you want consistency.
        $useRepoCache = $false
    }

    if ($useRepoCache) {
        Clone-Or-Pull $RepoPath
        Deploy-FilesFromRepo $RepoPath
    }
    else {
        # Pull in-place for Win11 repo model (fastest + avoids copying over running files)
        Write-Host "Runtime folder is a git repo. Pulling updates in-place: $DestPath"
        Clone-Or-Pull $DestPath

        # If your actual runnable scripts live in src\, you may want to deploy src\ -> root
        # But since your Win11 layout shows build/dist/src, your menu may be in Menu\ under src
        # If you are running from C:\CITA\LabTools\Menu\..., you likely already deployed once.
        # So we do NOT robocopy by default here.
        Write-Host ""
        Write-Host "Update complete (in-place repo pull)."
        Write-Host "Tip: If you want the runtime to always be a deployed copy, use the repo-cache model on this machine too."
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
    Write-Host $_ | Out-String
}
finally {
    Pause-Menu
}
