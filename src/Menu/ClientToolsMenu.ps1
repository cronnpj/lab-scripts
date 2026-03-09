# C:\CITA\LabTools\src\Menu\ClientToolsMenu.ps1
param(
    [string]$RunOption
)

$ErrorActionPreference = "SilentlyContinue"

# Shared UI
Import-Module (Join-Path $PSScriptRoot "..\UI\ConsoleUI.psm1") -Force

function Wait-MenuContinue {
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
        if ($ShowPause) { Wait-MenuContinue }
        return
    }

    try {
        $script:lastStatusText  = "[Running] Executing task..."
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
        if ($ShowPause) { Wait-MenuContinue }
    }
}

function Invoke-ActionSafe {
    param(
        [Parameter(Mandatory=$true)][scriptblock]$Action,
        [Parameter(Mandatory=$true)][string]$SuccessText,
        [bool]$ShowPause = $true
    )

    try {
        $script:lastStatusText  = "[Running] Executing action..."
        $script:lastStatusColor = "Cyan"
        & $Action
        $script:lastStatusText  = "[Ready] $SuccessText"
        $script:lastStatusColor = "Green"
    }
    catch {
        $script:lastStatusText  = "[Error] Action failed"
        $script:lastStatusColor = "Red"
        Write-Host ""
        Write-Host "Error: Action failed." -ForegroundColor Red
        Write-Host $_.Exception.Message
    }
    finally {
        if ($ShowPause) { Wait-MenuContinue }
    }
}

function Test-IsAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-VmPingDesktopShortcuts {
    param(
        [Parameter(Mandatory=$true)][string]$VmPingExePath
    )

    $shortcutName = "vmPing.lnk"
    $userDesktop = [Environment]::GetFolderPath("Desktop")
    $publicDesktop = [Environment]::GetFolderPath("CommonDesktopDirectory")

    $userShortcutPath = if (-not [string]::IsNullOrWhiteSpace($userDesktop)) { Join-Path $userDesktop $shortcutName } else { $null }
    $publicShortcutPath = if (-not [string]::IsNullOrWhiteSpace($publicDesktop)) { Join-Path $publicDesktop $shortcutName } else { $null }

    $createShortcut = {
        param([string]$ShortcutPath)
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($ShortcutPath)
        $shortcut.TargetPath = $VmPingExePath
        $shortcut.WorkingDirectory = Split-Path -Parent $VmPingExePath
        $shortcut.IconLocation = "$VmPingExePath,0"
        $shortcut.Description = "Launch vmPing"
        $shortcut.Save()
    }

    if ($userShortcutPath) {
        if (Test-Path $userShortcutPath) {
            Write-Host "Shortcut already exists, skipping: $userShortcutPath" -ForegroundColor DarkGray
        }
        else {
            try {
                & $createShortcut $userShortcutPath
                Write-Host "Created shortcut: $userShortcutPath" -ForegroundColor Green
            }
            catch {
                Write-Host "Could not create shortcut at '$userShortcutPath' (continuing):" -ForegroundColor Yellow
                Write-Host $_.Exception.Message -ForegroundColor Yellow
            }
        }
    }

    if ($publicShortcutPath) {
        if (Test-Path $publicShortcutPath) {
            Write-Host "Shortcut already exists, skipping: $publicShortcutPath" -ForegroundColor DarkGray
            return
        }

        if (Test-IsAdministrator) {
            try {
                & $createShortcut $publicShortcutPath
                Write-Host "Created shortcut: $publicShortcutPath" -ForegroundColor Green
            }
            catch {
                Write-Host "Could not create shortcut at '$publicShortcutPath' (continuing):" -ForegroundColor Yellow
                Write-Host $_.Exception.Message -ForegroundColor Yellow
            }

            return
        }

        Write-Host "Public Desktop shortcut requires elevation." -ForegroundColor Yellow
        $elevateChoice = Read-Host "Create Public Desktop vmPing shortcut now (UAC prompt)? (Y/N)"
        if ($elevateChoice -notmatch '^(y|yes)$') {
            Write-Host "Skipped Public Desktop shortcut creation." -ForegroundColor DarkYellow
            return
        }

        $escapedShortcutPath = $publicShortcutPath.Replace("'", "''")
        $escapedVmPingPath = $VmPingExePath.Replace("'", "''")
        $elevatedScript = @"
$ErrorActionPreference = 'Stop'
$shortcutPath = '$escapedShortcutPath'
$targetPath = '$escapedVmPingPath'
$w = New-Object -ComObject WScript.Shell
$s = $w.CreateShortcut($shortcutPath)
$s.TargetPath = $targetPath
$s.WorkingDirectory = Split-Path -Parent $targetPath
$s.IconLocation = "$escapedVmPingPath,0"
$s.Description = 'Launch vmPing'
$s.Save()
"@

        $encodedScript = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($elevatedScript))

        try {
            $elevatedProc = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $encodedScript) -Verb RunAs -Wait -PassThru
            if ($elevatedProc.ExitCode -eq 0 -and (Test-Path $publicShortcutPath)) {
                Write-Host "Created shortcut: $publicShortcutPath" -ForegroundColor Green
            }
            else {
                Write-Host "Public Desktop shortcut was not created (continuing)." -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "Public Desktop shortcut creation was cancelled or failed (continuing)." -ForegroundColor Yellow
            Write-Host $_.Exception.Message -ForegroundColor Yellow
        }
    }
}

function Show-ClientMenu {
    param(
        [string]$StatusText = "Ready",
        [string]$StatusColor = "DarkGray"
    )

    Show-AppHeader -Breadcrumb "Main > Windows Client Tools"

    Write-Host "  [1] Identity & Enrollment   (4 options)"
    Write-Host "      Domain join, join status, work/school enrollment, Intune sync" -ForegroundColor DarkGray
    Write-Host "  [2] Policy & Management    (3 options)"
    Write-Host "      GP update, policy results, GPO report export" -ForegroundColor DarkGray
    Write-Host "  [3] Network Tools          (4 options)"
    Write-Host "      IP config, DNS flush, DHCP renew, connectivity checks" -ForegroundColor DarkGray
    Write-Host "  [4] System Actions         (4 options)"
    Write-Host "      Rename, timezone/clock sync, update services, SFC scan" -ForegroundColor DarkGray
    Write-Host "  [5] Utilities              (4 options)"
    Write-Host "      Launch vmPing, Run Win11Debloat, Run SDelete, Template prep checklist" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [0] Back"
    Write-Host ""

    Write-StatusLine -StatusText $StatusText -StatusColor $StatusColor

    Write-Host "Keys: 1-5 Select  |  0 Back"
    Write-Host ""
}

function Show-IdentityEnrollmentMenu {
    Show-AppHeader -Breadcrumb "Main > Windows Client Tools > Identity & Enrollment"

    Write-Host "  [1] Join existing domain"
    Write-Host "  [2] Show Join Status (Domain + Entra ID / Hybrid)"
    Write-Host "  [3] Open Work/School Accounts (Enrollment)"
    Write-Host "  [4] Force Intune Sync (best-effort)"
    Write-Host ""
    Write-Host "  [0] Back"
    Write-Host ""
    Write-Host "Keys: 1-4 Select  |  0 Back"
    Write-Host ""
}

function Show-PolicyManagementMenu {
    Show-AppHeader -Breadcrumb "Main > Windows Client Tools > Policy & Management"

    Write-Host "  [1] Force Group Policy Update (gpupdate /force)"
    Write-Host "  [2] Show GPO Results (gpresult /r)"
    Write-Host "  [3] Export GPO Report to Desktop (HTML)"
    Write-Host ""
    Write-Host "  [0] Back"
    Write-Host ""
    Write-Host "Keys: 1-3 Select  |  0 Back"
    Write-Host ""
}

function Show-NetworkToolsMenu {
    Show-AppHeader -Breadcrumb "Main > Windows Client Tools > Network Tools"

    Write-Host "  [1] Show IP Configuration (ipconfig /all)"
    Write-Host "  [2] Flush DNS Cache"
    Write-Host "  [3] Renew DHCP Lease (release/renew)"
    Write-Host "  [4] Quick Connectivity Tests (GW/DNS/Internet)"
    Write-Host ""
    Write-Host "  [0] Back"
    Write-Host ""
    Write-Host "Keys: 1-4 Select  |  0 Back"
    Write-Host ""
}

function Show-SystemActionsMenu {
    Show-AppHeader -Breadcrumb "Main > Windows Client Tools > System Actions"

    Write-Host "  [1] Rename computer"
    Write-Host "  [2] Set timezone to Eastern + resync clock"
    Write-Host "  [3] Restart Windows Update Services"
    Write-Host "  [4] System File Check (SFC)"
    Write-Host ""
    Write-Host "  [0] Back"
    Write-Host ""
    Write-Host "Keys: 1-4 Select  |  0 Back"
    Write-Host ""
}

function Show-UtilitiesMenu {
    Show-AppHeader -Breadcrumb "Main > Windows Client Tools > Utilities"

    Write-Host "  [1] Launch vmPing (MISC)"
    Write-Host "  [2] Run Win11Debloat (official upstream script)"
    Write-Host "  [3] Run SDelete free-space overwrite"
    Write-Host "  [4] Run VM template prep checklist"
    Write-Host ""
    Write-Host "  [0] Back"
    Write-Host ""
    Write-Host "Keys: 1-4 Select  |  0 Back"
    Write-Host ""
}

# Task paths (unchanged from your original intent)
$joinDomainScript   = Join-Path $PSScriptRoot "..\Tasks\Join-Domain.ps1"
$renameScript       = Join-Path $PSScriptRoot "..\Tasks\Rename-Computer.ps1"
$timezoneScript     = Join-Path $PSScriptRoot "..\Tasks\Set-EasternTimeAndResync.ps1"

$joinStatusScript   = Join-Path $PSScriptRoot "..\Tasks\Client\Get-JoinStatus.ps1"
$gpoReportScript    = Join-Path $PSScriptRoot "..\Tasks\Client\GPO-Report.ps1"
$testConnScript     = Join-Path $PSScriptRoot "..\Tasks\Client\Test-Connectivity.ps1"
$win11DebloatScript = Join-Path $PSScriptRoot "..\Tasks\Run-Win11Debloat.ps1"
$sdeleteScript      = Join-Path $PSScriptRoot "..\Tasks\Run-SDelete.ps1"
$templatePrepScript = Join-Path $PSScriptRoot "..\Tasks\Run-TemplatePrepChecklist.ps1"
$vmPingPath         = Join-Path $PSScriptRoot "..\MISC\vmPing\vmPing.exe"

$back = $false
$script:lastStatusText  = "[Ready] Ready"
$script:lastStatusColor = "DarkGray"

function Invoke-IdentityEnrollmentMenu {
    $backSub = $false
    do {
        Show-IdentityEnrollmentMenu
        $choice = Read-Host "Select an option"

        switch ($choice) {
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
            "0"  { $backSub = $true }
            default {
                $script:lastStatusText  = "[Warning] Invalid selection"
                $script:lastStatusColor = "Yellow"
                Start-Sleep 1
            }
        }
    } while (-not $backSub)
}

function Invoke-PolicyManagementMenu {
    $backSub = $false
    do {
        Show-PolicyManagementMenu
        $choice = Read-Host "Select an option"

        switch ($choice) {
            "1"  { Invoke-ActionSafe -Action { Clear-Host; gpupdate /force } -SuccessText "Group Policy update completed" }
            "2"  { Invoke-ActionSafe -Action { Clear-Host; gpresult /r } -SuccessText "GPO results displayed" }
            "3"  { Invoke-TaskSafe   -Path $gpoReportScript -SuccessText "GPO report exported" }
            "0"  { $backSub = $true }
            default {
                $script:lastStatusText  = "[Warning] Invalid selection"
                $script:lastStatusColor = "Yellow"
                Start-Sleep 1
            }
        }
    } while (-not $backSub)
}

function Invoke-NetworkToolsMenu {
    $backSub = $false
    do {
        Show-NetworkToolsMenu
        $choice = Read-Host "Select an option"

        switch ($choice) {
            "1"  { Invoke-ActionSafe -Action { Clear-Host; ipconfig /all } -SuccessText "IP configuration displayed" }
            "2"  { Invoke-ActionSafe -Action { Clear-Host; ipconfig /flushdns; Write-Host "DNS cache flushed." } -SuccessText "DNS cache flushed" }
            "3"  {
                Invoke-ActionSafe -Action {
                    Clear-Host
                    Write-Host "Renewing DHCP lease (may not apply to static IP systems)..."
                    ipconfig /release
                    ipconfig /renew
                    ipconfig /all
                } -SuccessText "DHCP renew completed"
            }
            "4"  { Invoke-TaskSafe   -Path $testConnScript -SuccessText "Connectivity tests completed" -ShowPause:$false }
            "0"  { $backSub = $true }
            default {
                $script:lastStatusText  = "[Warning] Invalid selection"
                $script:lastStatusColor = "Yellow"
                Start-Sleep 1
            }
        }
    } while (-not $backSub)
}

function Invoke-SystemActionsMenu {
    $backSub = $false
    do {
        Show-SystemActionsMenu
        $choice = Read-Host "Select an option"

        switch ($choice) {
            "1"  { Invoke-TaskSafe   -Path $renameScript -SuccessText "Rename computer completed" }
            "2"  { Invoke-TaskSafe   -Path $timezoneScript -SuccessText "Timezone set and clock resynced" }
            "3"  {
                Invoke-ActionSafe -Action {
                    Clear-Host
                    Write-Host "Restarting Windows Update services..."
                    Restart-Service wuauserv -Force
                    Restart-Service bits -Force
                    Get-Service wuauserv, bits | Format-Table Status, Name, DisplayName -AutoSize | Out-Host
                } -SuccessText "Windows Update services restarted"
            }
            "4"  { Invoke-ActionSafe -Action { Clear-Host; sfc /scannow } -SuccessText "SFC completed (or started)" }
            "0"  { $backSub = $true }
            default {
                $script:lastStatusText  = "[Warning] Invalid selection"
                $script:lastStatusColor = "Yellow"
                Start-Sleep 1
            }
        }
    } while (-not $backSub)
}

function Invoke-UtilitiesMenu {
    $backSub = $false
    do {
        Show-UtilitiesMenu
        $choice = Read-Host "Select an option"

        switch ($choice) {
            "1" {
                Invoke-ActionSafe -Action {
                    if (-not (Test-Path $vmPingPath)) {
                        throw "vmPing.exe not found at '$vmPingPath'. Place vmPing.exe in src\\MISC\\vmPing\\ and try again."
                    }

                    Ensure-VmPingDesktopShortcuts -VmPingExePath $vmPingPath

                    Start-Process -FilePath $vmPingPath
                } -SuccessText "vmPing launched"
            }
            "2" { Invoke-TaskSafe -Path $win11DebloatScript -SuccessText "Win11Debloat flow completed" -ShowPause:$false }
            "3" { Invoke-TaskSafe -Path $sdeleteScript -SuccessText "SDelete flow completed" -ShowPause:$false }
            "4" { Invoke-TaskSafe -Path $templatePrepScript -SuccessText "Template prep checklist completed" -ShowPause:$false }
            "0"  { $backSub = $true }
            default {
                $script:lastStatusText  = "[Warning] Invalid selection"
                $script:lastStatusColor = "Yellow"
                Start-Sleep 1
            }
        }
    } while (-not $backSub)
}

function Invoke-ClientRunOption {
    param(
        [Parameter(Mandatory=$true)][string]$Option
    )

    switch ($Option) {
        "I1" { Invoke-TaskSafe   -Path $joinDomainScript -SuccessText "Join domain completed" }
        "I2" { Invoke-TaskSafe   -Path $joinStatusScript -SuccessText "Join status displayed" }
        "I3" { Invoke-ActionSafe -Action { Start-Process "ms-settings:workplace" } -SuccessText "Opened Work/School Accounts" }
        "I4" {
            Invoke-ActionSafe -Action {
                Clear-Host
                Write-Host "Opening Work/School settings. Use Sync if available."
                Start-Process "ms-settings:workplace"
            } -SuccessText "Opened enrollment settings"
        }

        "P1" { Invoke-ActionSafe -Action { Clear-Host; gpupdate /force } -SuccessText "Group Policy update completed" }
        "P2" { Invoke-ActionSafe -Action { Clear-Host; gpresult /r } -SuccessText "GPO results displayed" }
        "P3" { Invoke-TaskSafe   -Path $gpoReportScript -SuccessText "GPO report exported" }

        "N1" { Invoke-ActionSafe -Action { Clear-Host; ipconfig /all } -SuccessText "IP configuration displayed" }
        "N2" { Invoke-ActionSafe -Action { Clear-Host; ipconfig /flushdns; Write-Host "DNS cache flushed." } -SuccessText "DNS cache flushed" }
        "N3" {
            Invoke-ActionSafe -Action {
                Clear-Host
                Write-Host "Renewing DHCP lease (may not apply to static IP systems)..."
                ipconfig /release
                ipconfig /renew
                ipconfig /all
            } -SuccessText "DHCP renew completed"
        }
        "N4" { Invoke-TaskSafe -Path $testConnScript -SuccessText "Connectivity tests completed" }

        "S1" { Invoke-TaskSafe -Path $renameScript -SuccessText "Rename computer completed" }
        "S2" { Invoke-TaskSafe -Path $timezoneScript -SuccessText "Timezone set and clock resynced" }
        "S3" {
            Invoke-ActionSafe -Action {
                Clear-Host
                Write-Host "Restarting Windows Update services..."
                Restart-Service wuauserv -Force
                Restart-Service bits -Force
                Get-Service wuauserv, bits | Format-Table Status, Name, DisplayName -AutoSize | Out-Host
            } -SuccessText "Windows Update services restarted"
        }
        "S4" { Invoke-ActionSafe -Action { Clear-Host; sfc /scannow } -SuccessText "SFC completed (or started)" }

        "U1" {
            Invoke-ActionSafe -Action {
                if (-not (Test-Path $vmPingPath)) {
                    throw "vmPing.exe not found at '$vmPingPath'. Place vmPing.exe in src\\MISC\\vmPing\\ and try again."
                }

                Ensure-VmPingDesktopShortcuts -VmPingExePath $vmPingPath

                Start-Process -FilePath $vmPingPath
            } -SuccessText "vmPing launched"
        }
        "U2" { Invoke-TaskSafe -Path $win11DebloatScript -SuccessText "Win11Debloat flow completed" -ShowPause:$false }
        "U3" { Invoke-TaskSafe -Path $sdeleteScript -SuccessText "SDelete flow completed" -ShowPause:$false }
        "U4" { Invoke-TaskSafe -Path $templatePrepScript -SuccessText "Template prep checklist completed" -ShowPause:$false }

        default {
            $script:lastStatusText  = "[Warning] Invalid search action"
            $script:lastStatusColor = "Yellow"
            Wait-MenuContinue
        }
    }
}

if (-not [string]::IsNullOrWhiteSpace($RunOption)) {
    Invoke-ClientRunOption -Option $RunOption
    Clear-Host
    return
}

do {
    Show-ClientMenu -StatusText $script:lastStatusText -StatusColor $script:lastStatusColor
    $choice = Read-Host "Select an option"

    switch ($choice) {
        "1"  { Invoke-IdentityEnrollmentMenu }
        "2"  { Invoke-PolicyManagementMenu }
        "3"  { Invoke-NetworkToolsMenu }
        "4"  { Invoke-SystemActionsMenu }
        "5"  { Invoke-UtilitiesMenu }

        "0"  { $back = $true }
        default {
            $script:lastStatusText  = "[Warning] Invalid selection"
            $script:lastStatusColor = "Yellow"
            Start-Sleep 1
        }
    }

} while (-not $back)

Clear-Host
return
