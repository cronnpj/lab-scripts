function Show-TroubleshootingMenu {
    Clear-Host
    Write-Host "Troubleshooting & Validation"
    Write-Host "----------------------------"
    Write-Host ""
    Write-Host "1) Show install status"
    Write-Host "2) System snapshot"
    Write-Host ""
    Write-Host "0) Back"
    Write-Host ""
}

function Pause-Menu {
    Write-Host ""
    Read-Host "Press Enter to continue"
}

$back = $false
do {
    Show-TroubleshootingMenu
    $choice = Read-Host "Select an option"

    switch ($choice) {
        "1" {
            & (Join-Path $PSScriptRoot "..\Tasks\Install-Status.ps1")
            Pause-Menu
        }
        "2" {
            & (Join-Path $PSScriptRoot "..\Tasks\System-Snapshot.ps1")
            Pause-Menu
        }
        "0" {
            $back = $true
        }
        default {
            Write-Host ""
            Write-Host "Invalid selection."
            Start-Sleep 1
        }
    }

} while (-not $back)

Clear-Host
return
