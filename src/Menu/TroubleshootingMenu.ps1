# C:\CITA\LabTools\src\Menu\TroubleshootingMenu.ps1
param(
    [string]$RunOption
)

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

function Show-TroubleshootingMenu {
    param(
        [string]$StatusText = "[Ready] Ready",
        [string]$StatusColor = "DarkGray"
    )

    Show-AppHeader -Breadcrumb "Main > Troubleshooting & Validation"

    Write-MenuItem "1" "Show server role install status"
    Write-MenuItem "2" "System snapshot"
    Write-Host ""
    Write-MenuItem "0" "Back" "DarkGray"
    Write-Host ""

    Write-StatusLine -StatusText $StatusText -StatusColor $StatusColor

    Write-MenuKeysLine "1-2"
    Write-Host ""
}

$installStatusScript = Join-Path $PSScriptRoot "..\Tasks\Install-Status.ps1"
$snapshotScript      = Join-Path $PSScriptRoot "..\Tasks\System-Snapshot.ps1"

$back = $false
$script:lastStatusText  = "[Ready] Ready"
$script:lastStatusColor = "DarkGray"

if (-not [string]::IsNullOrWhiteSpace($RunOption)) {
    switch ($RunOption) {
        "T1" { Invoke-TaskSafe -Path $installStatusScript -SuccessText "Install status displayed" }
        "T2" { Invoke-TaskSafe -Path $snapshotScript      -SuccessText "System snapshot completed" }
        default {
            $script:lastStatusText  = "[Warning] Invalid search action"
            $script:lastStatusColor = "Yellow"
            Wait-MenuContinue
        }
    }

    Clear-Host
    return
}

do {
    Show-TroubleshootingMenu -StatusText $script:lastStatusText -StatusColor $script:lastStatusColor
    $choice = Read-MenuChoice

    switch ($choice) {
        "1" { Invoke-TaskSafe -Path $installStatusScript -SuccessText "Install status displayed" }
        "2" { Invoke-TaskSafe -Path $snapshotScript      -SuccessText "System snapshot completed" }
        "0" { $back = $true }
        default {
            $script:lastStatusText  = "[Warning] Invalid selection"
            $script:lastStatusColor = "Yellow"
            Start-Sleep 1
        }
    }

} while (-not $back)

return