# src\Tasks\Install-PowerShell7.ps1
$ErrorActionPreference = "Stop"

function Test-IsElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Elevated {
    if (Test-IsElevated) {
        return
    }

    Write-Host "Elevation required to install PowerShell 7 at machine scope. Prompting for Administrator..." -ForegroundColor Yellow

    $elevatedArgs = "-NoLogo -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $elevatedArgs -WorkingDirectory $PSScriptRoot -Verb RunAs
    exit 0
}

function Get-InstalledPwshPath {
    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($pwsh) {
        return $pwsh.Source
    }

    $defaultPath = "C:\Program Files\PowerShell\7\pwsh.exe"
    if (Test-Path $defaultPath) {
        return $defaultPath
    }

    return $null
}

function Install-WithWinget {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "winget.exe was not found. Install App Installer from Microsoft Store, then run this task again."
    }

    $args = @(
        "install",
        "--id", "Microsoft.PowerShell",
        "--exact",
        "--source", "winget",
        "--scope", "machine",
        "--accept-package-agreements",
        "--accept-source-agreements",
        "--silent"
    )

    Write-Host "Installing PowerShell 7 via winget..." -ForegroundColor Cyan
    $proc = Start-Process -FilePath $winget.Source -ArgumentList $args -Wait -PassThru -NoNewWindow

    if ($proc.ExitCode -notin @(0, 3010, 1641)) {
        throw "winget install failed with exit code $($proc.ExitCode)."
    }
}

function Ensure-GraphModules {
    $requiredModules = @(
        "Microsoft.Graph.Authentication",
        "Microsoft.Graph.Identity.DirectoryManagement"
    )

    if (-not (Get-Command Install-Module -ErrorAction SilentlyContinue)) {
        throw "Install-Module command not found. Install PowerShellGet, then rerun this task."
    }

    try {
        $psGallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if ($psGallery -and $psGallery.InstallationPolicy -ne "Trusted") {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        }
    }
    catch {
        # Non-blocking: repository trust prompt may still appear depending on host policy.
    }

    foreach ($moduleName in $requiredModules) {
        $existing = Get-Module -ListAvailable -Name $moduleName | Select-Object -First 1
        if ($existing) {
            Write-Host "Graph module already installed: $moduleName ($($existing.Version))" -ForegroundColor Green
            continue
        }

        Write-Host "Installing Graph module: $moduleName" -ForegroundColor Cyan
        Install-Module -Name $moduleName -Scope AllUsers -Force -AllowClobber -ErrorAction Stop

        $verify = Get-Module -ListAvailable -Name $moduleName | Select-Object -First 1
        if (-not $verify) {
            throw "Module install reported success, but '$moduleName' is still not discoverable."
        }

        Write-Host "Installed Graph module: $moduleName ($($verify.Version))" -ForegroundColor Green
    }
}

try {
    Ensure-Elevated

    $existingPwsh = Get-InstalledPwshPath
    $pwshPath = $existingPwsh

    if ($existingPwsh) {
        $versionText = try { (& $existingPwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()') } catch { "unknown" }
        Write-Host "PowerShell 7 is already installed at: $existingPwsh" -ForegroundColor Green
        Write-Host "Detected version: $versionText" -ForegroundColor Green
    }
    else {
        Install-WithWinget

        # Refresh PATH for current process before discovery re-check.
        $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        $env:Path = "$machinePath;$userPath"

        $pwshPath = Get-InstalledPwshPath
        if (-not $pwshPath) {
            throw "Install completed but pwsh.exe was not found yet. Sign out/in or restart, then rerun shortcut repair."
        }
    }

    Ensure-GraphModules

    $installedVersion = try { (& $pwshPath -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()') } catch { "unknown" }

    Write-Host "PowerShell 7 installation complete." -ForegroundColor Green
    Write-Host "Path: $pwshPath" -ForegroundColor Green
    Write-Host "Version: $installedVersion" -ForegroundColor Green
    Write-Host "Graph modules verified for tenant lookup." -ForegroundColor Green
    Write-Host "Next step: run Create-Shortcuts to point launcher shortcuts to PowerShell 7." -ForegroundColor Cyan
}
catch {
    Write-Host "PowerShell 7 installation failed." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    throw
}
