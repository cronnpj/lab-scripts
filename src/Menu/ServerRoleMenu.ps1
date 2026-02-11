# src\Menu\ServerRoleMenu.ps1
$ErrorActionPreference = "Stop"

$root = Join-Path $PSScriptRoot ".."

$versionPath = Join-Path $root "VERSION.txt"
$version = if (Test-Path $versionPath) {
    (Get-Content $versionPath -ErrorAction SilentlyContinue).Trim()
} else {
    "unknown"
}

Import-Module (Join-Path $root "Lib\Logging.psm1") -Force
Import-Module (Join-Path $root "Lib\Validation.psm1") -Force

Initialize-LabLog

try {
    Assert-IsAdmin
} catch {
    Write-Host $_.Exception.Message
    Write-Host "Right-click the shortcut and choose: Run as administrator."
    Pause
    exit 1
}

function Pause-Return {
    Write-Host ""
    Pause
}

function Show-Status {
    $states = Get-RoleInstallState -FeatureNames @("AD-Domain-Services", "DNS", "DHCP")
    Write-Host ""
    Write-Host "Installed Roles/Features:"
    $states | Format-Table -AutoSize
    Write-Host ""
}

function Launch-Updater {
    $updater = Join-Path $root "Tasks\Update-LabToolsFromGitHub.ps1"
    if (-not (Test-Path $updater)) {
        Write-Host "Updater not found:"
        Write-Host $updater
        Pause-Return
        return
    }

    Write-LabLog "Menu: Launch updater from GitHub"

    # Run updater in a separate PowerShell window, so it can safely overwrite files.
    Start-Process powershell.exe -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$updater`""
    )

    Write-Host ""
    Write-Host "Updater launched in a new window."
    Write-Host "After it finishes, re-open 'CITA Lab Tools' to use the updated version."
    Pause-Return
}

# Label the loop so Exit can break out of it cleanly
:MainMenu while ($true) {
    Clear-Host
    Write-Host "CITA Lab Tools - Windows Server Role Installer"
    Write-Host "Version: $version"
    Write-Host "------------------------------------------------"
    Write-Host "1) Install AD DS role (no promotion)"
    Write-Host "2) Install DNS role"
    Write-Host "3) Install DHCP role"
    Write-Host "4) Install Core DC roles (AD DS + DNS + DHCP)"
    Write-Host "5) Show install status"
    Write-Host "6) Open log file"
    Write-Host "7) Update Lab Tools from GitHub (build VM only)"
    Write-Host "0) Exit"
    Write-Host ""

    $choice = Read-Host "Select an option"

    try {
        switch ($choice) {
            "1" {
                Write-LabLog "Menu: Install AD DS (no promotion)"
                & (Join-Path $root "Tasks\Install-Roles.ps1") -Mode "ADDS"
                Pause-Return
            }
            "2" {
                Write-LabLog "Menu: Install DNS"
                & (Join-Path $root "Tasks\Install-Roles.ps1") -Mode "DNS"
                Pause-Return
            }
            "3" {
                Write-LabLog "Menu: Install DHCP"
                & (Join-Path $root "Tasks\Install-Roles.ps1") -Mode "DHCP"
                Pause-Return
            }
            "4" {
                Write-LabLog "Menu: Install CORE_DC"
                & (Join-Path $root "Tasks\Install-Roles.ps1") -Mode "CORE_DC"
                Pause-Return
            }
            "5" {
                Show-Status
                Pause-Return
            }
            "6" {
                $log = Get-LabLogPath
                Write-Host "Opening: $log"
                Start-Process notepad.exe $log
                Pause-Return
            }
            "7" {
                Launch-Updater
                # Exit the menu so the updater can overwrite files safely.
                break MainMenu
            }
            "0" {
                Write-LabLog "Menu: Exit"
                break MainMenu
            }
            default {
                Write-Host "Invalid option."
                Pause-Return
            }
        }
    } catch {
        Write-LabLog "Error: $($_.Exception.Message)" "ERROR"
        Write-Host ""
        Write-Host "ERROR: $($_.Exception.Message)"
        Write-Host "Check the log for details."
        Pause-Return
    }
}
