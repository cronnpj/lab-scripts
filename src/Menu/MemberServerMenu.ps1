function Show-MemberServerMenu {
    Clear-Host
    Write-Host "Member Server Tools"
    Write-Host "-------------------"
    Write-Host ""
    Write-Host "1) Join existing domain"
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
    Show-MemberServerMenu
    $choice = Read-Host "Select an option"

    switch ($choice) {
        "1" {
            & (Join-Path $PSScriptRoot "..\Tasks\Join-Domain.ps1")
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
