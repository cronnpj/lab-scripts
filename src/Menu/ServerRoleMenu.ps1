# src\Menu\ServerRoleMenu.ps1
$ErrorActionPreference = "Stop"

$root = Join-Path $PSScriptRoot ".."

$versionPath = Join-Path $root "VERSION.txt"
$version = if (Test-Path $versionPath) { (Get-Content $versionPath).Trim() } else { "unknown" }

Import-Module (Join-Path $root "Lib\Logging.psm1") -Force
Import-Module (Join-Path $root "Lib\Validation.psm1") -Force

Initialize-LabLog

try { Assert-IsAdmin } catch {
    Write-Host $_.Exception.Message
    Write-Host "Right-click the shortcut and choose: Run as administrator."
    Pause
    exit 1
}

function Pause-Return { Write-Host ""; Pause }

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
        Write-Host "Updater not found: $updater"
        Pause-Return
        return
    }

    Write-LabLog "Menu: Launch updater from GitHub"
    Start-Process powershell.exe -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$updater`""
    )

    Write-Host ""
    Write-Host "Updater launched in a new window."
    Write-Host "After it finishes, re-open 'CITA Server Setup' to use the updated version."
    Pause-Return
}

:MainMenu while ($true) {
    Clear-Host
    Write-Host "CITA Lab Tools - Server Setup Assistant"
    Write-Host "Version: $version"
    Write-Host "------------------------------------------------"
    Write-Host "1) Rename computer"
    Write-Host "2) Configure static IP"
    Write-Host "3) Install AD DS role (no promotion)"
    Write-Host "4) Install DNS role"
    Write-Host "5) Install DHCP role"
    Write-Host "6) Install Core DC roles (AD DS + DNS + DHCP)"
    Write-Host "7) Show install status"
    Write-Host "8) Update Lab Tools from GitHub (build VM only)"
    Write-Host "0) Exit"
    Write-Host ""

    $choice = Read-Host "Select an option"

    try {
        switch ($choice) {
            "1" { & (Join-Path $root "Tasks\Rename-Computer.ps1"); Pause-Return }
            "2" { & (Join-Path $root "Tasks\Set-StaticIP.ps1"); Pause-Return }

            "3" { Write-LabLog "Menu: Install AD DS (no promotion)"; & (Join-Path $root "Tasks\Install-Roles.ps1") -Mode "ADDS"; Pause-Return }
            "4" { Write-LabLog "Menu: Install DNS";                & (Join-Path $root "Tasks\Install-Roles.ps1") -Mode "DNS";  Pause-Return }
            "5" { Write-LabLog "Menu: Install DHCP";               & (Join-Path $root "Tasks\Install-Roles.ps1") -Mode "DHCP"; Pause-Return }
            "6" { Write-LabLog "Menu: Install CORE_DC";            & (Join-Path $root "Tasks\Install-Roles.ps1") -Mode "CORE_DC"; Pause-Return }

            "7" { Show-Status; Pause-Return }

            "8" { Launch-Updater; break MainMenu }

            "0" { Write-LabLog "Menu: Exit"; break MainMenu }

            default { Write-Host "Invalid option."; Pause-Return }
        }
    } catch {
        Write-LabLog "Error: $($_.Exception.Message)" "ERROR"
        Write-Host ""
        Write-Host "ERROR: $($_.Exception.Message)"
        Write-Host "Check the log for details."
        Pause-Return
    }
}