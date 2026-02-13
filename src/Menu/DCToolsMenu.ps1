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

function Invoke-RoleInstall {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("ADDS","DNS","DHCP","CORE_DC")]
        [string]$Mode
    )

    try {
        & $rolesScript -Mode $Mode -ErrorAction Stop
    }
    catch {
        Write-Host ""
        Write-Host "Error: Role installation failed."
        Write-Host ("Details: {0}" -f $_.Exception.Message)
    }
    finally {
        Pause-Menu
    }
}

$rolesScript = Join-Path $PSScriptRoot "..\Tasks\Install-Roles.ps1"

$back = $false
do {
    Show-DCMenu
    $choice = Read-Host "Select an option"

    switch ($choice) {
        "1" { Invoke-RoleInstall -Mode ADDS }
        "2" { Invoke-RoleInstall -Mode DNS }
        "3" { Invoke-RoleInstall -Mode DHCP }
        "4" { Invoke-RoleInstall -Mode CORE_DC }   # <-- FIXED
        "0" { $back = $true }
        default {
            Write-Host ""
            Write-Host "Invalid selection."
            Start-Sleep 1
        }
    }

} while (-not $back)

Clear-Host
return
