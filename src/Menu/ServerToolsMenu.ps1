function Show-ServerToolsMenu {
    Clear-Host
    Write-Host "Server Tools"
    Write-Host "-------------"
    Write-Host ""
    Write-Host "1) Rename computer"
    Write-Host "2) Configure static IP"
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
    Show-ServerToolsMenu
    $choice = Read-Host "Select an option"

    switch ($choice) {
        "1" {
            & (Join-Path $PSScriptRoot "..\Tasks\Rename-Computer.ps1")
            Pause-Menu
        }
        "2" {
            & (Join-Path $PSScriptRoot "..\Tasks\Set-StaticIP.ps1")
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
