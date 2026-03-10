# C:\CITA\LabTools\src\Menu\MaintenanceMenu.ps1
$ErrorActionPreference = "SilentlyContinue"

# Shared UI
Import-Module (Join-Path $PSScriptRoot "..\UI\ConsoleUI.psm1") -Force

function Read-MenuContinue {
    Write-Host ""
    Read-Host "Press Enter to continue" | Out-Null
}

function Invoke-TaskSafe {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$SuccessText,
        [bool]$ShowPause = $true
    )

    if (-not (Test-Path $Path)) {
        $script:lastStatusText  = "[Error] Task not found"
        $script:lastStatusColor = "Red"
        Write-Host ""
        Write-Host "Error: Task script not found:" -ForegroundColor Red
        Write-Host $Path
        if ($ShowPause) { Read-MenuContinue }
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
        $errMsg = $_.Exception.Message
        # Only show error if it's not a benign post-update warning
        if ($errMsg -notmatch 'Invalid query|task not found|non-blocking') {
            $script:lastStatusText  = "[Error] Task failed"
            $script:lastStatusColor = "Red"
            Write-Host ""
            Write-Host "Error: Task failed." -ForegroundColor Red
            Write-Host $errMsg
        } else {
            $script:lastStatusText  = "[Ready] $SuccessText"
            $script:lastStatusColor = "Green"
        }
    }
    finally {
        if ($ShowPause) { Read-MenuContinue }
    }
}

function Show-MaintenanceMenu {
    param(
        [string]$StatusText = "[Ready] Ready",
        [string]$StatusColor = "DarkGray"
    )

    Show-AppHeader -Breadcrumb "Main > App Maintenance & Updates"

    Write-Host "  [1] Update Lab Tools from GitHub (+ shortcut repair + terminal background)"
    Write-Host "  [2] Create / Repair Lab Tools shortcuts"
    Write-Host "  [3] Apply Windows Terminal background (repo config)"
    Write-Host "  [4] Report a Problem / Submit Feedback"
    Write-Host "  [5] Install / Repair PS7 + Graph modules (+ optional Graph sign-in) + shortcuts"
    Write-Host "  [6] Install / Repair PS7 only"
    Write-Host ""
    Write-Host "  [0] Back"
    Write-Host ""

    Write-StatusLine -StatusText $StatusText -StatusColor $StatusColor

    Write-Host "Keys: 1-6 Select  |  0 Back"
    Write-Host ""
}

$updateScript = Join-Path $PSScriptRoot "..\Tasks\Update-LabTools.ps1"
$shortcutScript = Join-Path $PSScriptRoot "..\Tasks\Create-Shortcuts.ps1"
$terminalBackgroundScript = Join-Path $PSScriptRoot "..\Tasks\Apply-TerminalBackground.ps1"
$installPowerShell7Script = Join-Path $PSScriptRoot "..\Tasks\Install-PowerShell7.ps1"
$installPowerShell7OnlyScript = Join-Path $PSScriptRoot "..\Tasks\Install-PowerShell7Only.ps1"
$back = $false
$script:lastStatusText  = "[Ready] Ready"
$script:lastStatusColor = "DarkGray"

do {
    Show-MaintenanceMenu -StatusText $script:lastStatusText -StatusColor $script:lastStatusColor
    $choice = Read-Host "Select an option"

    switch ($choice) {
            "1" {
                Invoke-TaskSafe -Path $updateScript -SuccessText "Lab Tools updated from GitHub" -ShowPause:$false
                Invoke-TaskSafe -Path $shortcutScript -SuccessText "Shortcuts created/updated" -ShowPause:$false
                Invoke-TaskSafe -Path $terminalBackgroundScript -SuccessText "Terminal background applied" -ShowPause:$true
                $script:lastStatusText  = "[Ready] All maintenance tasks completed"
                $script:lastStatusColor = "Green"
            }
        "2" { Invoke-TaskSafe -Path $shortcutScript -SuccessText "Shortcuts created/updated" }
        "3" { Invoke-TaskSafe -Path $terminalBackgroundScript -SuccessText "Terminal background applied" }
        "4" {
            try {
                $script:lastStatusText  = "[Running] Opening feedback form..."
                $script:lastStatusColor = "Cyan"
                $formUrl = "https://forms.office.com/r/5pJZNxzxgq"
                Start-Process $formUrl
                $script:lastStatusText  = "[Ready] Feedback form opened"
                $script:lastStatusColor = "Green"
            }
            catch {
                $script:lastStatusText  = "[Error] Unable to open feedback form"
                $script:lastStatusColor = "Red"
                Write-Host ""
                Write-Host "Error: Failed to open feedback form." -ForegroundColor Red
                Write-Host $_.Exception.Message
            }
            finally {
                Read-MenuContinue
            }
        }
        "5" {
            Invoke-TaskSafe -Path $installPowerShell7Script -SuccessText "PowerShell 7 + Graph modules verified" -ShowPause:$false
            Invoke-TaskSafe -Path $shortcutScript -SuccessText "Shortcuts refreshed for preferred shell" -ShowPause:$true
            $script:lastStatusText  = "[Ready] PowerShell 7/Graph module check completed and shortcuts refreshed"
            $script:lastStatusColor = "Green"
        }
        "6" {
            Invoke-TaskSafe -Path $installPowerShell7OnlyScript -SuccessText "PowerShell 7 installation/repair completed"
        }
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
