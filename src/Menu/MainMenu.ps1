# C:\CITA\LabTools\Menu\mainmenu.ps1
# (Repo-root aware update check using git -C so it works regardless of shortcut "Start in")

$versionPath = Join-Path $PSScriptRoot '..\VERSION.txt'
$version = if (Test-Path $versionPath) {
    (Get-Content $versionPath -ErrorAction SilentlyContinue | Select-Object -First 1)
} else {
    "Unknown"
}

# Repo root = parent of Menu folder (C:\CITA\LabTools)
$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-UpdateStatus {
    try {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return "NO_GIT" }
        if (-not (Test-Path (Join-Path $repoRoot ".git"))) { return "NOT_REPO" }

        $isRepo = git -C $repoRoot rev-parse --is-inside-work-tree 2>$null
        if ($LASTEXITCODE -ne 0 -or $isRepo.Trim() -ne "true") { return "NOT_REPO" }

        # Fetch remote silently (fast)
        git -C $repoRoot fetch --quiet 2>$null | Out-Null

        $branch = (git -C $repoRoot rev-parse --abbrev-ref HEAD 2>$null).Trim()
        if (-not $branch) { return "UNKNOWN" }

        $counts = (git -C $repoRoot rev-list --left-right --count "HEAD...origin/$branch" 2>$null).Trim()
        if (-not $counts) { return "UNKNOWN" }

        $parts = $counts -split "`t"
        if ($parts.Count -lt 2) { return "UNKNOWN" }

        $behind = 0
        if (-not [int]::TryParse($parts[1], [ref]$behind)) { return "UNKNOWN" }

        if ($behind -gt 0) { return "UPDATE_AVAILABLE" }
        return "UP_TO_DATE"
    }
    catch {
        return "UNKNOWN"
    }
}

function Show-MainMenu {
    Clear-Host
    Write-Host "CITA Lab Tools - Infrastructure Assistant"
    Write-Host "Version: $version"

    $status = Get-UpdateStatus
    switch ($status) {
        "UPDATE_AVAILABLE" { Write-Host "Status: UPDATE AVAILABLE - Run Maintenance & Updates." -ForegroundColor Yellow }
        "UP_TO_DATE"       { Write-Host "Status: Up to date." -ForegroundColor Green }
        "NO_GIT"           { Write-Host "Status: Git not installed." -ForegroundColor DarkGray }
        "NOT_REPO"         { Write-Host "Status: Not a Git repository." -ForegroundColor DarkGray }
        default            { Write-Host "Status: Update check unavailable." -ForegroundColor DarkGray }
    }

    Write-Host "----------------------------------------"
    Write-Host ""
    Write-Host "1) Server Tools"
    Write-Host "2) Domain Controller Tools"
    Write-Host "3) Member Server Tools"
    Write-Host "4) Windows Client Tools"
    Write-Host "5) Troubleshooting & Validation"
    Write-Host "6) Maintenance & Updates"
    Write-Host "0) Exit"
    Write-Host ""
}

$exit = $false
do {
    Show-MainMenu
    $choice = Read-Host "Select an option"

    switch ($choice) {
        "1" { & (Join-Path $PSScriptRoot "ServerToolsMenu.ps1") }
        "2" { & (Join-Path $PSScriptRoot "DCToolsMenu.ps1") }
        "3" { & (Join-Path $PSScriptRoot "MemberServerMenu.ps1") }
        "4" { & (Join-Path $PSScriptRoot "ClientToolsMenu.ps1") }
        "5" { & (Join-Path $PSScriptRoot "TroubleshootingMenu.ps1") }
        "6" { & (Join-Path $PSScriptRoot "MaintenanceMenu.ps1") }
        "0" { $exit = $true; continue }
        default {
            Write-Host ""
            Write-Host "Invalid selection. Please try again."
            Start-Sleep 1
        }
    }

    if (-not $exit) { Clear-Host }

} while (-not $exit)

Clear-Host
