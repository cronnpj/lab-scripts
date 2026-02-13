function Show-ClientMenu {
    Clear-Host
    Write-Host "Windows Client Tools"
    Write-Host "---------------------"
    Write-Host ""
    Write-Host "1) Join to Domain"
    Write-Host "2) Rename Computer"
    Write-Host "3) Force Group Policy Update"
    Write-Host "4) Show GPO Results (summary)"
    Write-Host "5) Show Azure AD / Hybrid Status"
    Write-Host "6) Force Intune Sync"
    Write-Host "7) Networking Tools (ipconfig /all)"
    Write-Host "8) System Health Check (SFC)"
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
    Show-ClientMenu
    $choice = Read-Host "Select an option"

    switch ($choice) {
        "1" {
            & (Join-Path $PSScriptRoot "..\Tasks\Join-Domain.ps1")
            Pause-Menu
        }
        "2" {
            & (Join-Path $PSScriptRoot "..\Tasks\Rename-Computer.ps1")
            Pause-Menu
        }
        "3" {
            Clear-Host
            gpupdate /force
            Pause-Menu
        }
        "4" {
            Clear-Host
            gpresult /r
            Pause-Menu
        }
        "5" {
            Clear-Host
            dsregcmd /status
            Pause-Menu
        }
        "6" {
            Clear-Host
            Write-Host "Opening Work/School account settings to support sync..."
            Start-Process "ms-settings:workplace"
            Pause-Menu
        }
        "7" {
            Clear-Host
            ipconfig /all
            Pause-Menu
        }
        "8" {
            Clear-Host
            Write-Host "Running SFC..."
            sfc /scannow
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

# Clean return to parent menu
Clear-Host
