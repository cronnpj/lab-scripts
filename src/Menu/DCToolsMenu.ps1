function Show-DCMenu {
    Clear-Host
    Write-Host "Domain Controller Tools"
    Write-Host "-----------------------"
    Write-Host ""
    Write-Host "1) Install AD DS role (no promotion)"
    Write-Host "2) Install DNS role"
    Write-Host "3) Install DHCP role"
    Write-Host "4) Install Core DC roles (AD DS | DNS | DHCP)"
    Write-Host ""
    Write-Host "0) Back"
    Write-Host ""
}

function Pause-Menu {
    Write-Host ""
    Read-Host "Press Enter to continue"
}

$rolesScript = Join-Path $PSScriptRoot "..\Tasks\Install-Roles.ps1"

$back = $false
do {
    Show-DCMenu
    $choice = Read-Host "Select an option"

    switch ($choice) {
        "1" {
            & $rolesScript -Mode ADDS
            Pause-Menu
        }
        "2" {
            & $rolesScript -Mode DNS
            Pause-Menu
        }
        "3" {
            & $rolesScript -Mode DHCP
            Pause-Menu
        }
        "4" {
            & $rolesScript -Mode CORE
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

# Clean return to MainMenu (caller)
Clear-Host
return
