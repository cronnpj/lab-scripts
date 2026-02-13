function Show-MaintenanceMenu {
    Clear-Host
    Write-Host "Maintenance & Updates"
    Write-Host "---------------------"
    Write-Host ""
    Write-Host "1) Update Lab Tools from GitHub"
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
    Show-MaintenanceMenu
    $choice = Read-Host "Select an option"

    switch ($choice) {
        "1" {
            & (Join-Path $PSScriptRoot "..\Tasks\Update-LabTools.ps1")
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
