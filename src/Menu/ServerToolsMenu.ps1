# C:\CITA\LabTools\src\Menu\ServerToolsMenu.ps1
$ErrorActionPreference = "SilentlyContinue"

# Shared UI
Import-Module (Join-Path $PSScriptRoot "..\UI\ConsoleUI.psm1") -Force

function Pause-Menu {
    Write-Host ""
    Read-Host "Press Enter to continue" | Out-Null
}

function Invoke-TaskSafe {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$SuccessText
    )

    if (-not (Test-Path $Path)) {
        $script:lastStatusText  = "Task not found"
        $script:lastStatusColor = "Red"
        Write-Host ""
        Write-Host "Error: Task script not found:" -ForegroundColor Red
        Write-Host $Path
        Pause-Menu
        return
    }

    try {
        & $Path
        $script:lastStatusText  = $SuccessText
        $script:lastStatusColor = "Green"
    }
    catch {
        $script:lastStatusText  = "Task failed"
        $script:lastStatusColor = "Red"
        Write-Host ""
        Write-Host "Error: Task failed." -ForegroundColor Red
        Write-Host $_.Exception.Message
    }
    finally {
        Pause-Menu
    }
}

function Show-ServerToolsMenu {
    param(
        [string]$StatusText = "Ready",
        [string]$StatusColor = "DarkGray"
    )

    Show-AppHeader -Breadcrumb "Main > Server Tools"

    Write-Host "  [1] Rename computer"
    Write-Host "  [2] Configure static IP"
    Write-Host "  [3] Set timezone to Eastern + resync clock"
    Write-Host ""
    Write-Host "  [0] Back"
    Write-Host ""

    Write-Host "Status: " -NoNewline
    Write-Host $StatusText -ForegroundColor $StatusColor

    Write-Host "Keys: 1-3 Select  |  0 Back"
    Write-Host ""
}

$back = $false
$script:lastStatusText  = "Ready"
$script:lastStatusColor = "DarkGray"

$renameScript    = Join-Path $PSScriptRoot "..\Tasks\Rename-Computer.ps1"
$staticIPScript  = Join-Path $PSScriptRoot "..\Tasks\Set-StaticIP.ps1"
$timezoneScript  = Join-Path $PSScriptRoot "..\Tasks\Set-EasternTimeAndResync.ps1"

do {
    Show-ServerToolsMenu -StatusText $script:lastStatusText -StatusColor $script:lastStatusColor
    $choice = Read-Host "Select an option"

    switch ($choice) {
        "1" { Invoke-TaskSafe -Path $renameScript   -SuccessText "Rename computer completed" }
        "2" { Invoke-TaskSafe -Path $staticIPScript -SuccessText "Static IP task completed" }
        "3" { Invoke-TaskSafe -Path $timezoneScript -SuccessText "Timezone set and clock resynced" }
        "0" { $back = $true }
        default {
            $script:lastStatusText  = "Invalid selection"
            $script:lastStatusColor = "Yellow"
            Start-Sleep -Milliseconds 400
        }
    }

} while (-not $back)

Clear-Host
return
