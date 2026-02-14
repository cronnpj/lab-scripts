# C:\CITA\LabTools\src\Menu\DCToolsMenu.ps1
$ErrorActionPreference = "SilentlyContinue"

# Shared UI
Import-Module (Join-Path $PSScriptRoot "..\UI\ConsoleUI.psm1") -Force

function Pause-Menu {
    Write-Host ""
    Read-Host "Press Enter to continue" | Out-Null
}

function Show-DCMenu {
    param(
        [string]$StatusText = "Ready",
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

    Write-Host "Status: " -NoNewline
    Write-Host $StatusText -ForegroundColor $StatusColor

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
        $script:lastStatusText  = "Running role install ($Mode)..."
        $script:lastStatusColor = "Gray"

        & $rolesScript -Mode $Mode -ErrorAction Stop

        $script:lastStatusText  = "Role install completed ($Mode)"
        $script:lastStatusColor = "Green"
    }
    catch {
        Write-Host ""
        Write-Host "Error: Role installation failed." -ForegroundColor Red
        Write-Host ("Details: {0}" -f $_.Exception.Message)

        $script:lastStatusText  = "Role install failed ($Mode)"
        $script:lastStatusColor = "Red"
    }
    finally {
        Pause-Menu
    }
}

$rolesScript = Join-Path $PSScriptRoot "..\Tasks\Install-Roles.ps1"

$back = $false
$script:lastStatusText  = "Ready"
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
            $script:lastStatusText  = "Invalid selection"
            $script:lastStatusColor = "Yellow"
            Start-Sleep 1
        }
    }

} while (-not $back)

Clear-Host
return
