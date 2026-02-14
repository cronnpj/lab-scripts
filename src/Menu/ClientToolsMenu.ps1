# C:\CITA\LabTools\src\Menu\ClientToolsMenu.ps1
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

function Invoke-ActionSafe {
    param(
        [Parameter(Mandatory=$true)][scriptblock]$Action,
        [Parameter(Mandatory=$true)][string]$SuccessText
    )

    try {
        & $Action
        $script:lastStatusText  = $SuccessText
        $script:lastStatusColor = "Green"
    }
    catch {
        $script:lastStatusText  = "Action failed"
        $script:lastStatusColor = "Red"
        Write-Host ""
        Write-Host "Error: Action failed." -ForegroundColor Red
        Write-Host $_.Exception.Message
    }
    finally {
        Pause-Menu
    }
}

function Show-ClientMenu {
    param(
        [string]$StatusText = "Ready",
        [string]$StatusColor = "DarkGray"
    )

    Show-AppHeader -Breadcrumb "Main > Windows Client Tools"

    Write-Host "Identity / Enrollment"
    Write-Host "  [1]  Join existing domain"
    Write-Host "  [2]  Show Join Status (Domain + Entra ID / Hybrid)"
    Write-Host "  [3]  Open Work/School Accounts (Enrollment)"
    Write-Host "  [4]  Force Intune Sync (best-effort)"
    Write-Host ""

    Write-Host "Policy / Management"
    Write-Host "  [5]  Force Group Policy Update (gpupdate /force)"
    Write-Host "  [6]  Show GPO Results (gpresult /r)"
    Write-Host "  [7]  Export GPO Report to Desktop (HTML)"
    Write-Host ""

    Write-Host "Networking"
    Write-Host "  [8]  Show IP Configuration (ipconfig /all)"
    Write-Host "  [9]  Flush DNS Cache"
    Write-Host "  [10] Renew DHCP Lease (release/renew)"
    Write-Host "  [11] Quick Connectivity Tests (GW/DNS/Internet)"
    Write-Host ""

    Write-Host "Client Actions"
    Write-Host "  [12] Rename computer"
    Write-Host ""

    Write-Host "Client Maintenance"
    Write-Host "  [14] Restart Windows Update Services"
    Write-Host "  [15] System File Check (SFC)"
    Write-Host ""

    Write-Host "  [0] Back"
    Write-Host ""

    Write-Host "Status: " -NoNewline
    Write-Host $StatusText -ForegroundColor $StatusColor

    Write-Host "Keys: 1-15 Select  |  0 Back"
    Write-Host ""
}

# Task paths (unchanged from your original intent)
$joinDomainScript   = Join-Path $PSScriptRoot "..\Tasks\Join-Domain.ps1"
$renameScript       = Join-Path $PSScriptRoot "..\Tasks\Rename-Computer.ps1"

$joinStatusScript   = Join-Path $PSScriptRoot "..\Tasks\Client\Get-JoinStatus.ps1"
$gpoReportScript    = Join-Path $PSScriptRoot "..\Tasks\Client\GPO-Report.ps1"
$testConnScript     = Join-Path $PSScriptRoot "..\Tasks\Client\Test-Connectivity.ps1"

$back = $false
$script:lastStatusText  = "Ready"
$script:lastStatusColor = "DarkGray"

do {
    Show-ClientMenu -StatusText $script:lastStatusText -StatusColor $script:lastStatusColor
    $choice = Read-Host "Select an option"

    switch ($choice) {

        # Identity / Enrollment
        "1"  { Invoke-TaskSafe   -Path $joinDomainScript -SuccessText "Join domain completed" }
        "2"  { Invoke-TaskSafe   -Path $joinStatusScript -SuccessText "Join status displayed" }
        "3"  { Invoke-ActionSafe -Action { Start-Process "ms-settings:workplace" } -SuccessText "Opened Work/School Accounts" }
        "4"  {
            Invoke-ActionSafe -Action {
                Clear-Host
                Write-Host "Opening Work/School settings. Use Sync if available."
                Start-Process "ms-settings:workplace"
            } -SuccessText "Opened enrollment settings"
        }

        # Policy / Management
        "5"  { Invoke-ActionSafe -Action { Clear-Host; gpupdate /force } -SuccessText "Group Policy update completed" }
        "6"  { Invoke-ActionSafe -Action { Clear-Host; gpresult /r } -SuccessText "GPO results displayed" }
        "7"  { Invoke-TaskSafe   -Path $gpoReportScript -SuccessText "GPO report exported" }

        # Networking
        "8"  { Invoke-ActionSafe -Action { Clear-Host; ipconfig /all } -SuccessText "IP configuration displayed" }
        "9"  { Invoke-ActionSafe -Action { Clear-Host; ipconfig /flushdns; Write-Host "DNS cache flushed." } -SuccessText "DNS cache flushed" }
        "10" {
            Invoke-ActionSafe -Action {
                Clear-Host
                Write-Host "Renewing DHCP lease (may not apply to static IP systems)..."
                ipconfig /release
                ipconfig /renew
                ipconfig /all
            } -SuccessText "DHCP renew completed"
        }
        "11" { Invoke-TaskSafe   -Path $testConnScript -SuccessText "Connectivity tests completed" }

        # Client Actions
        "12" { Invoke-TaskSafe   -Path $renameScript -SuccessText "Rename computer completed" }

        # Client Maintenance
        "14" {
            Invoke-ActionSafe -Action {
                Clear-Host
                Write-Host "Restarting Windows Update services..."
                Restart-Service wuauserv -Force
                Restart-Service bits -Force
                Get-Service wuauserv, bits | Format-Table Status, Name, DisplayName -AutoSize | Out-Host
            } -SuccessText "Windows Update services restarted"
        }
        "15" { Invoke-ActionSafe -Action { Clear-Host; sfc /scannow } -SuccessText "SFC completed (or started)" }

        "0"  { $back = $true }
        default {
            $script:lastStatusText  = "Invalid selection"
            $script:lastStatusColor = "Yellow"
            Start-Sleep 1
        }
    }

} while (-not $back)

Clear-Host
return
