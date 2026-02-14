# C:\CITA\LabTools\src\Menu\MainMenu.ps1
$ErrorActionPreference = "SilentlyContinue"

# Import shared UI helpers
Import-Module (Join-Path $PSScriptRoot "..\UI\ConsoleUI.psm1") -Force

# Prefer separate repo if it exists, otherwise use runtime root (parent of Menu)
function Resolve-RepoPath {
    $preferred = "C:\CITA\_LabToolsRepo"
    $runtimeRoot = Split-Path -Parent $PSScriptRoot

    # 1) Preferred repo
    $isPreferredRepo = git -C $preferred rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -eq 0 -and $isPreferredRepo.Trim() -eq "true") { return $preferred }

    # 2) Runtime root as repo
    $isRuntimeRepo = git -C $runtimeRoot rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -eq 0 -and $isRuntimeRepo.Trim() -eq "true") { return $runtimeRoot }

    return $null
}

$repoPath = Resolve-RepoPath

function Get-UpdateStatus {
    try {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return "NO_GIT" }
        if (-not $repoPath) { return "NO_REPO" }

        git -C $repoPath fetch --quiet 2>$null | Out-Null

        $branch = (git -C $repoPath rev-parse --abbrev-ref HEAD 2>$null).Trim()
        if (-not $branch) { return "UNKNOWN" }

        $counts = (git -C $repoPath rev-list --left-right --count "HEAD...origin/$branch" 2>$null).Trim()
        if (-not $counts) { return "UNKNOWN" }

        $parts = $counts -split "`t"
        if ($parts.Count -lt 2) { return "UNKNOWN" }

        $behind = 0
        if (-not [int]::TryParse($parts[1], [ref]$behind)) { return "UNKNOWN" }

        if ($behind -gt 0) { return "UPDATE_AVAILABLE" }
        return "UP_TO_DATE"
    }
    catch { return "UNKNOWN" }
}

function Get-StatusLine {
    $status = Get-UpdateStatus
    switch ($status) {
        "UPDATE_AVAILABLE" { return @{ Text = "UPDATE AVAILABLE - Run Maintenance and Updates"; Color = "Yellow" } }
        "UP_TO_DATE"       { return @{ Text = "Up to date"; Color = "Green" } }
        "NO_GIT"           { return @{ Text = "Git not installed"; Color = "DarkGray" } }
        "NO_REPO"          { return @{ Text = "Update check unavailable (repo not detected)"; Color = "DarkGray" } }
        default            { return @{ Text = "Update check unavailable"; Color = "DarkGray" } }
    }
}

function Show-MainMenu {
    $statusObj = Get-StatusLine

    # Shared header
    Show-AppHeader -Breadcrumb "Main Menu"

    Write-Host "  [1] Server Tools"
    Write-Host "  [2] Domain Controller Tools"
    Write-Host "  [3] Member Server Tools"
    Write-Host "  [4] Windows Client Tools"
    Write-Host "  [5] Troubleshooting & Validation"
    Write-Host "  [6] Maintenance & Updates"
    Write-Host "  [0] Exit"
    Write-Host ""

    Write-Host "Status: " -NoNewline
    Write-Host $statusObj.Text -ForegroundColor $statusObj.Color

    Write-Host "Keys: 1-6 Select  |  0 Exit"
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
        "0" { $exit = $true }
        default { Start-Sleep -Milliseconds 300 }
    }

} while (-not $exit)

Clear-Host
