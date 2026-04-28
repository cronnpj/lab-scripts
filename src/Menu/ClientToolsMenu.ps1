# C:\CITA\LabTools\src\Menu\ClientToolsMenu.ps1
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
        Clear-Host
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

function Assert-WingetAvailable {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw "winget.exe is not available on this system. Install App Installer from Microsoft Store and try again."
    }
}

function Open-NewTerminalTabOrWindow {
    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($wt) {
        Start-Process -FilePath $wt.Source -ArgumentList @("-w", "0", "new-tab")
        return
    }

    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($pwsh) {
        Start-Process -FilePath $pwsh.Source -ArgumentList @("-NoLogo")
        return
    }

    Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @("-NoLogo")
}

function Open-WingetShell {
    Assert-WingetAvailable

    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    $fallbackPs = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

    $shellExe = if ($pwsh) { $pwsh.Source } else { $fallbackPs }
    $wingetIntroCommand = @'
Clear-Host
Write-Host "Winget quick commands:" -ForegroundColor Cyan
Write-Host "  winget search <app>"
Write-Host "  winget show <id>"
Write-Host "  winget list"
Write-Host "  winget install <id>"
Write-Host "  winget uninstall <id>"
Write-Host "  winget upgrade"
Write-Host "  winget upgrade --all"
Write-Host ""
Write-Host "Example: winget search vscode" -ForegroundColor DarkGray
'@

    $encodedIntroCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($wingetIntroCommand))
    $shellArgs = @("-NoLogo", "-NoExit", "-EncodedCommand", $encodedIntroCommand)

    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($wt) {
        $wtArgs = @("-w", "0", "new-tab", "--title", "Winget", "--", $shellExe) + $shellArgs
        Start-Process -FilePath $wt.Source -ArgumentList $wtArgs
        return
    }

    Start-Process -FilePath $shellExe -ArgumentList $shellArgs
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

    Write-Host "vmPing shortcut targets:" -ForegroundColor DarkGray
    Write-Host "  User Desktop: $userDesktop" -ForegroundColor DarkGray
    Write-Host "  Public Desktop: $publicDesktop" -ForegroundColor DarkGray

    $publicShortcutReady = $false

    if ($publicShortcutPath) {
        if (Test-Path $publicShortcutPath) {
            Write-Host "Shortcut already exists, skipping: $publicShortcutPath" -ForegroundColor DarkGray
            $publicShortcutReady = $true
        }
        elseif (Test-IsAdministrator) {
            try {
                & $createShortcut $publicShortcutPath
                Write-Host "Created shortcut: $publicShortcutPath" -ForegroundColor Green
                $publicShortcutReady = $true
            }
            catch {
                Write-Host "Could not create shortcut at '$publicShortcutPath' (continuing):" -ForegroundColor Yellow
                Write-Host $_.Exception.Message -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "Public Desktop shortcut requires elevation. Attempting elevated creation..." -ForegroundColor Yellow

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
                    $publicShortcutReady = $true
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

    if ($publicShortcutReady) {
        if ($userShortcutPath -and (Test-Path $userShortcutPath)) {
            try {
                Remove-Item -Path $userShortcutPath -Force
                Write-Host "Removed duplicate user shortcut (Public shortcut preferred): $userShortcutPath" -ForegroundColor Green
            }
            catch {
                Write-Host "Could not remove duplicate user shortcut at '$userShortcutPath' (continuing):" -ForegroundColor Yellow
                Write-Host $_.Exception.Message -ForegroundColor Yellow
            }
        }

        return
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
}

function Show-ClientMenu {
    param(
        [string]$StatusText = "Ready",
        [string]$StatusColor = "Green"
    )

    Show-AppHeader -Breadcrumb "Main > Windows Client Tools" -StatusText $StatusText -StatusColor $StatusColor

    Write-MenuItem "1" "Identity & Enrollment   (6 options)"
    Write-Host "      Domain join, join status, work/school enrollment, Intune sync, Autopilot registration" -ForegroundColor DarkGray
    Write-MenuItem "2" "Policy & Management    (3 options)"
    Write-Host "      GP update, policy results, GPO report export" -ForegroundColor DarkGray
    Write-MenuItem "3" "Network Tools          (4 options)"
    Write-Host "      IP config, DNS flush, DHCP renew, connectivity checks" -ForegroundColor DarkGray
    Write-MenuItem "4" "System Actions         (4 options)"
    Write-Host "      Rename, timezone/clock sync, update services, SFC scan" -ForegroundColor DarkGray
    Write-MenuItem "5" "VM & Image Prep        (5 options)"
    Write-Host "      SDelete, template prep, Horizon Tool, VirtIO tools, Sysprep" -ForegroundColor DarkGray
    Write-MenuItem "6" "Utilities              (7 options)"
    Write-Host "      vmPing, Debloat, winget, winget upgrade --all, new terminal tab, wallpaper, lab files" -ForegroundColor DarkGray
    Write-Host ""
    Write-MenuItem "0" "Back" "DarkGray"
    Write-Host ""


    Write-MenuKeysLine "1-6"
    Write-Host ""
}

function Show-IdentityEnrollmentMenu {
    Show-AppHeader -Breadcrumb "Main > Windows Client Tools > Identity & Enrollment"

    Write-MenuItem "1" "Join existing domain"
    Write-MenuItem "2" "Show Join Status (Domain + Entra ID / Hybrid)"
    Write-MenuItem "3" "Open Work/School Accounts (Enrollment)"
    Write-MenuItem "4" "Force Intune Sync (best-effort)"
    Write-MenuItem "5" "Register device in Autopilot (CSV export)"
    Write-MenuItem "6" "Register device in Autopilot (upload directly to Intune)"
    Write-Host ""
    Write-MenuItem "0" "Back" "DarkGray"
    Write-Host ""
    Write-MenuKeysLine "1-6"
    Write-Host ""
}

function Show-PolicyManagementMenu {
    Show-AppHeader -Breadcrumb "Main > Windows Client Tools > Policy & Management"

    Write-MenuItem "1" "Force Group Policy Update (gpupdate /force)"
    Write-MenuItem "2" "Show GPO Results (gpresult /r)"
    Write-MenuItem "3" "Export GPO Report to Desktop (HTML)"
    Write-Host ""
    Write-MenuItem "0" "Back" "DarkGray"
    Write-Host ""
    Write-MenuKeysLine "1-3"
    Write-Host ""
}

function Show-NetworkToolsMenu {
    Show-AppHeader -Breadcrumb "Main > Windows Client Tools > Network Tools"

    Write-MenuItem "1" "Show IP Configuration (ipconfig /all)"
    Write-MenuItem "2" "Flush DNS Cache"
    Write-MenuItem "3" "Renew DHCP Lease (release/renew)"
    Write-MenuItem "4" "Quick Connectivity Tests (GW/DNS/Internet)"
    Write-Host ""
    Write-MenuItem "0" "Back" "DarkGray"
    Write-Host ""
    Write-MenuKeysLine "1-4"
    Write-Host ""
}

function Show-SystemActionsMenu {
    Show-AppHeader -Breadcrumb "Main > Windows Client Tools > System Actions"

    Write-MenuItem "1" "Rename computer"
    Write-MenuItem "2" "Set timezone to Eastern + resync clock"
    Write-MenuItem "3" "Restart Windows Update Services"
    Write-MenuItem "4" "System File Check (SFC)"
    Write-Host ""
    Write-MenuItem "0" "Back" "DarkGray"
    Write-Host ""
    Write-MenuKeysLine "1-4"
    Write-Host ""
}

function Show-VMImagePrepMenu {
    Show-AppHeader -Breadcrumb "Main > Windows Client Tools > VM & Image Prep"

    Write-MenuItem "1" "Run SDelete free-space overwrite"
    Write-MenuItem "2" "Run VM template prep checklist"
    Write-MenuItem "3" "Launch VMware Horizon OS Optimization Tool"
    Write-MenuItem "4" "Install VirtIO guest tools (Proxmox VM)"
    Write-MenuItem "5" "Run Sysprep (removes Winget first, then launches Sysprep)"
    Write-Host ""
    Write-MenuItem "0" "Back" "DarkGray"
    Write-Host ""
    Write-MenuKeysLine "1-5"
    Write-Host ""
}

function Show-UtilitiesMenu {
    Show-AppHeader -Breadcrumb "Main > Windows Client Tools > Utilities"

    Write-MenuItem "1" "Launch vmPing (MISC)"
    Write-MenuItem "2" "Run Win11Debloat (official upstream script)"
    Write-MenuItem "3" "Open winget command shell"
    Write-MenuItem "4" "Run winget upgrade --all"
    Write-MenuItem "5" "Open new terminal tab"
    Write-MenuItem "6" "Apply CITA desktop wallpaper (disables Spotlight)"
    Write-MenuItem "7" "Copy CITA 120 Lab 9 files to Public Desktop"
    Write-Host ""
    Write-MenuItem "0" "Back" "DarkGray"
    Write-Host ""
    Write-MenuKeysLine "1-7"
    Write-Host ""
}

# Task paths
$joinDomainScript   = Join-Path $PSScriptRoot "..\Tasks\Join-Domain.ps1"
$renameScript       = Join-Path $PSScriptRoot "..\Tasks\Rename-Computer.ps1"
$timezoneScript     = Join-Path $PSScriptRoot "..\Tasks\Set-EasternTimeAndResync.ps1"

$joinStatusScript   = Join-Path $PSScriptRoot "..\Tasks\Client\Get-JoinStatus.ps1"
$autopilotScript    = Join-Path $PSScriptRoot "..\Tasks\Client\Register-AutopilotDevice.ps1"
$gpoReportScript    = Join-Path $PSScriptRoot "..\Tasks\Client\GPO-Report.ps1"
$testConnScript     = Join-Path $PSScriptRoot "..\Tasks\Client\Test-Connectivity.ps1"
$win11DebloatScript = Join-Path $PSScriptRoot "..\Tasks\Run-Win11Debloat.ps1"
$sdeleteScript      = Join-Path $PSScriptRoot "..\Tasks\Run-SDelete.ps1"
$templatePrepScript = Join-Path $PSScriptRoot "..\Tasks\Run-TemplatePrepChecklist.ps1"
$horizonOptScript   = Join-Path $PSScriptRoot "..\Tasks\Run-HorizonOptimizationTool.ps1"
$wallpaperScript    = Join-Path $PSScriptRoot "..\Tasks\Client\Set-DesktopWallpaper.ps1"
$cita120L9Script    = Join-Path $PSScriptRoot "..\Tasks\Client\Copy-CITA120L9Files.ps1"
$vmPingPath         = Join-Path $PSScriptRoot "..\MISC\vmPing\vmPing.exe"

$back = $false
$script:lastStatusText  = "[Ready] Ready"
$script:lastStatusColor = "Green"

function Invoke-IdentityEnrollmentMenu {
    $backSub = $false
    do {
        Show-IdentityEnrollmentMenu
        $choice = Read-MenuChoice

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
            "5"  { Invoke-TaskSafe -Path $autopilotScript -SuccessText "Autopilot CSV export completed" -ShowPause:$false }
            "6"  {
                Invoke-ActionSafe -Action {
                    & $autopilotScript -Online
                } -SuccessText "Autopilot online registration completed" -ShowPause:$false
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
        $choice = Read-MenuChoice

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
        $choice = Read-MenuChoice

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
        $choice = Read-MenuChoice

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

function Invoke-VMImagePrepMenu {
    $backSub = $false
    do {
        Show-VMImagePrepMenu
        $choice = Read-MenuChoice

        switch ($choice) {
            "1" { Invoke-TaskSafe -Path $sdeleteScript -SuccessText "SDelete flow completed" -ShowPause:$false }
            "2" { Invoke-TaskSafe -Path $templatePrepScript -SuccessText "Template prep checklist completed" -ShowPause:$false }
            "3" { Invoke-TaskSafe -Path $horizonOptScript -SuccessText "Horizon Optimization Tool flow completed" -ShowPause:$false }
            "4" {
                Invoke-ActionSafe -Action {
                    Clear-Host
                    Assert-WingetAvailable
                    winget install RedHat.VirtIO --source winget --scope machine
                } -SuccessText "VirtIO guest tools install completed"
            }
            "5" {
                Invoke-ActionSafe -Action {
                    Clear-Host
                    $sysprepExePath = Join-Path $env:WINDIR "System32\Sysprep\Sysprep.exe"
                    if (-not (Test-Path $sysprepExePath)) {
                        throw "Sysprep.exe not found at '$sysprepExePath'."
                    }
                    Write-Host "Removing Winget AppxPackage (all users)..." -ForegroundColor Cyan
                    Get-AppxPackage -AllUsers -Name "*Winget*" | Remove-AppxPackage -AllUsers
                    Write-Host "Removing Winget provisioned package..." -ForegroundColor Cyan
                    Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like "*Winget*" } | Remove-AppxProvisionedPackage -Online
                    Write-Host "Winget removal complete. Launching Sysprep..." -ForegroundColor Green
                    Write-Host "Use: Enter System Out-of-Box Experience (OOBE) + Generalize + Shutdown." -ForegroundColor DarkGray
                    Start-Process -FilePath $sysprepExePath | Out-Null
                } -SuccessText "Sysprep launched"
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

function Invoke-UtilitiesMenu {
    $backSub = $false
    do {
        Show-UtilitiesMenu
        $choice = Read-MenuChoice

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
            "3" {
                Invoke-ActionSafe -Action {
                    Open-WingetShell
                } -SuccessText "Winget shell opened"
            }
            "4" {
                Invoke-ActionSafe -Action {
                    Clear-Host
                    Assert-WingetAvailable
                    winget upgrade --all --scope machine
                } -SuccessText "winget upgrade --all completed"
            }
            "5" {
                Invoke-ActionSafe -Action {
                    Open-NewTerminalTabOrWindow
                } -SuccessText "Terminal tab/window opened"
            }
            "6" { Invoke-TaskSafe -Path $wallpaperScript -SuccessText "Desktop wallpaper applied" }
            "7" { Invoke-TaskSafe -Path $cita120L9Script -SuccessText "CITA 120 Lab 9 files copied to Public Desktop" }
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
        "I5" { Invoke-TaskSafe -Path $autopilotScript -SuccessText "Autopilot CSV export completed" -ShowPause:$false }
        "I6" {
            Invoke-ActionSafe -Action {
                & $autopilotScript -Online
            } -SuccessText "Autopilot online registration completed" -ShowPause:$false
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

        "V1" { Invoke-TaskSafe -Path $sdeleteScript -SuccessText "SDelete flow completed" -ShowPause:$false }
        "V2" { Invoke-TaskSafe -Path $templatePrepScript -SuccessText "Template prep checklist completed" -ShowPause:$false }
        "V3" { Invoke-TaskSafe -Path $horizonOptScript -SuccessText "Horizon Optimization Tool flow completed" -ShowPause:$false }
        "V4" {
            Invoke-ActionSafe -Action {
                Clear-Host
                Assert-WingetAvailable
                winget install RedHat.VirtIO --source winget --scope machine
            } -SuccessText "VirtIO guest tools install completed"
        }
        "V5" {
            Invoke-ActionSafe -Action {
                Clear-Host
                $sysprepExePath = Join-Path $env:WINDIR "System32\Sysprep\Sysprep.exe"
                if (-not (Test-Path $sysprepExePath)) {
                    throw "Sysprep.exe not found at '$sysprepExePath'."
                }
                Write-Host "Removing Winget AppxPackage (all users)..." -ForegroundColor Cyan
                Get-AppxPackage -AllUsers -Name "*Winget*" | Remove-AppxPackage -AllUsers
                Write-Host "Removing Winget provisioned package..." -ForegroundColor Cyan
                Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like "*Winget*" } | Remove-AppxProvisionedPackage -Online
                Write-Host "Winget removal complete. Launching Sysprep..." -ForegroundColor Green
                Write-Host "Use: Enter System Out-of-Box Experience (OOBE) + Generalize + Shutdown." -ForegroundColor DarkGray
                Start-Process -FilePath $sysprepExePath | Out-Null
            } -SuccessText "Sysprep launched"
        }

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
        "U3" {
            Invoke-ActionSafe -Action {
                Open-WingetShell
            } -SuccessText "Winget shell opened"
        }
        "U4" {
            Invoke-ActionSafe -Action {
                Clear-Host
                Assert-WingetAvailable
                winget upgrade --all --scope machine
            } -SuccessText "winget upgrade --all completed"
        }
        "U5" {
            Invoke-ActionSafe -Action {
                Open-NewTerminalTabOrWindow
            } -SuccessText "Terminal tab/window opened"
        }
        "U6" { Invoke-TaskSafe -Path $wallpaperScript -SuccessText "Desktop wallpaper applied" }
        "U7" { Invoke-TaskSafe -Path $cita120L9Script -SuccessText "CITA 120 Lab 9 files copied to Public Desktop" }

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
    $choice = Read-MenuChoice

    switch ($choice) {
        "1"  { Invoke-IdentityEnrollmentMenu }
        "2"  { Invoke-PolicyManagementMenu }
        "3"  { Invoke-NetworkToolsMenu }
        "4"  { Invoke-SystemActionsMenu }
        "5"  { Invoke-VMImagePrepMenu }
        "6"  { Invoke-UtilitiesMenu }

        "0"  { $back = $true }
        default {
            $script:lastStatusText  = "[Warning] Invalid selection"
            $script:lastStatusColor = "Yellow"
            Start-Sleep 1
        }
    }

} while (-not $back)

return
