# C:\CITA\LabTools\src\Menu\ServerToolsMenu.ps1
$ErrorActionPreference = "SilentlyContinue"

# Shared UI
if (-not (Get-Module ConsoleUI)) { Import-Module (Join-Path $PSScriptRoot "..\UI\ConsoleUI.psm1") -Force }

function Wait-MenuContinue {
    Write-Host ""
    Read-Host "Press Enter to continue" | Out-Null
}

function Invoke-TaskSafe {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$SuccessText
    )

    if (-not (Test-Path $Path)) {
        $script:lastStatusText  = "[Error] Task not found"
        $script:lastStatusColor = "Red"
        Write-Host ""
        Write-Host "Error: Task script not found:" -ForegroundColor Red
        Write-Host $Path
        Wait-MenuContinue
        return
    }

    try {
        $script:lastStatusText  = "[Running] Running task..."
        $script:lastStatusColor = "Cyan"
        & $Path
        $script:lastStatusText  = "[Ready] $SuccessText"
        $script:lastStatusColor = "Green"
    }
    catch {
        $script:lastStatusText  = "[Error] Task failed"
        $script:lastStatusColor = "Red"
        Write-Host ""
        Write-Host "Error: Task failed." -ForegroundColor Red
        Write-Host $_.Exception.Message
    }
    finally {
        Wait-MenuContinue
    }
}

function Show-ServerToolsMenu {
    param(
        [string]$StatusText = "[Ready] Ready",
        [string]$StatusColor = "Green"
    )

    Show-AppHeader -Breadcrumb "Main > Server Tools" -StatusText $StatusText -StatusColor $StatusColor

    Write-MenuItem "1" "Rename computer"
    Write-MenuItem "2" "Configure static IP"
    Write-MenuItem "3" "Set timezone to Eastern + resync clock"
    Write-Host ""
    Write-MenuItem "0" "Back" "DarkGray"
    Write-Host ""


    Write-MenuKeysLine "1-3"
    Write-Host ""
}

$back = $false
$script:lastStatusText  = "[Ready] Ready"
$script:lastStatusColor = "Green"

$renameScript    = Join-Path $PSScriptRoot "..\Tasks\Rename-Computer.ps1"
$staticIPScript  = Join-Path $PSScriptRoot "..\Tasks\Set-StaticIP.ps1"
$timezoneScript  = Join-Path $PSScriptRoot "..\Tasks\Set-EasternTimeAndResync.ps1"

do {
    Show-ServerToolsMenu -StatusText $script:lastStatusText -StatusColor $script:lastStatusColor
    $choice = Read-MenuChoice

    switch ($choice) {
        "1" { Invoke-TaskSafe -Path $renameScript   -SuccessText "Rename computer completed" }
        "2" { Invoke-TaskSafe -Path $staticIPScript -SuccessText "Static IP task completed" }
        "3" { Invoke-TaskSafe -Path $timezoneScript -SuccessText "Timezone set and clock resynced" }
        "0" { $back = $true }
        default {
            $script:lastStatusText  = "[Warning] Invalid selection"
            $script:lastStatusColor = "Yellow"
            Start-Sleep -Milliseconds 400
        }
    }

} while (-not $back)

return
