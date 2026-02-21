# C:\CITA\LabTools\src\Menu\DCToolsMenu.ps1
$ErrorActionPreference = "SilentlyContinue"

# Shared UI
Import-Module (Join-Path $PSScriptRoot "..\UI\ConsoleUI.psm1") -Force

function Wait-MenuContinue {
    Write-Host ""
    Read-Host "Press Enter to continue" | Out-Null
}

function Show-DCMenu {
    param(
        [string]$StatusText = "[Ready] Ready",
        [string]$StatusColor = "DarkGray"
    )

    Show-AppHeader -Breadcrumb "Main > Domain Controller Tools"

    Write-Host "  [1] Install AD DS role (no promotion)"
    Write-Host "  [2] Install DNS role"
    Write-Host "  [3] Install DHCP role"
    Write-Host "  [4] Install Core DC roles (AD DS | DNS | DHCP)"
    Write-Host ""
    Write-Host "  [0] Back"
    Write-Host ""

    Write-StatusLine -StatusText $StatusText -StatusColor $StatusColor

    Write-Host "Keys: 1-4 Select  |  0 Back"
    Write-Host ""
}

function Invoke-RoleInstall {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("ADDS","DNS","DHCP","CORE_DC")]
        [string]$Mode
    )

    try {
        $script:lastStatusText  = "[Running] Running role install ($Mode)..."
        $script:lastStatusColor = "Cyan"

        & $rolesScript -Mode $Mode -ErrorAction Stop

        $script:lastStatusText  = "[Ready] Role install completed ($Mode)"
        $script:lastStatusColor = "Green"
    }
    catch {
        Write-Host ""
        Write-Host "Error: Role installation failed." -ForegroundColor Red
        Write-Host ("Details: {0}" -f $_.Exception.Message)

        $script:lastStatusText  = "[Error] Role install failed ($Mode)"
        $script:lastStatusColor = "Red"
    }
    finally {
        Wait-MenuContinue
    }
}

$rolesScript = Join-Path $PSScriptRoot "..\Tasks\Install-Roles.ps1"

$back = $false
$script:lastStatusText  = "[Ready] Ready"
$script:lastStatusColor = "DarkGray"

do {
    Show-DCMenu -StatusText $script:lastStatusText -StatusColor $script:lastStatusColor
    $choice = Read-Host "Select an option"

    switch ($choice) {
        "1" { Invoke-RoleInstall -Mode ADDS }
        "2" { Invoke-RoleInstall -Mode DNS }
        "3" { Invoke-RoleInstall -Mode DHCP }
        "4" { Invoke-RoleInstall -Mode CORE_DC }  # kept your fixed option
        "0" { $back = $true }
        default {
            $script:lastStatusText  = "[Warning] Invalid selection"
            $script:lastStatusColor = "Yellow"
            Start-Sleep 1
        }
    }

} while (-not $back)

Clear-Host
return
