# MainMenu.ps1

$versionPath = Join-Path $PSScriptRoot '..\VERSION.txt'
$version = if (Test-Path $versionPath) { Get-Content $versionPath -ErrorAction SilentlyContinue } else { "Unknown" }

function Show-MainMenu {
    Clear-Host
    Write-Host "CITA Lab Tools - Infrastructure Assistant"
    Write-Host "Version: $version"
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

    # When a submenu returns, the loop will redraw and Clear-Host will run.
    # This extra Clear-Host is optional, but makes the transition feel snappier.
    if (-not $exit) { Clear-Host }

} while (-not $exit)

Clear-Host
