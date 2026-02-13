Clear-Host

function Show-ClientMenu {
    Clear-Host
    Write-Host "Windows Client Tools"
    Write-Host "---------------------"
    Write-Host ""
    Write-Host "1) Join to Domain"
    Write-Host "2) Rename Computer"
    Write-Host "3) Force Group Policy Update"
    Write-Host "4) Show GPO Results"
    Write-Host "5) Show Azure AD / Hybrid Status"
    Write-Host "6) Force Intune Sync"
    Write-Host "7) Networking Tools"
    Write-Host "8) System Health Check"
    Write-Host ""
    Write-Host "0) Back"
    Write-Host ""
}

$back = $false
do {
    Show-ClientMenu
    $choice = Read-Host "Select an option"

    switch ($choice) {
        "1" { & (Join-Path $PSScriptRoot "..\Tasks\Join-Domain.ps1") }
        "2" { & (Join-Path $PSScriptRoot "..\Tasks\Rename-Computer.ps1") }
        "3" { gpupdate /force; Pause }
        "4" { gpresult /r; Pause }
        "5" { dsregcmd /status; Pause }
        "6" { 
            Write-Host "Forcing Intune Sync..."
            Start-Process "ms-settings:workplace"
            Pause 
        }
        "7" { ipconfig /all; Pause }
        "8" { 
            Write-Host "Running SFC..."
            sfc /scannow
            Pause
        }
        "0" { $back = $true }
        default { Write-Host "Invalid selection."; Start-Sleep 1 }
    }

} while (-not $back)
