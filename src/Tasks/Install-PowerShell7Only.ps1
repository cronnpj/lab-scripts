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

    $candidates = @(
        "C:\Program Files\PowerShell\7\pwsh.exe",
        (Join-Path $env:LOCALAPPDATA "Programs\PowerShell\7\pwsh.exe")
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }

    return $null
}

function Install-WithWinget {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "winget.exe was not found. Install App Installer from Microsoft Store, then run this task again."
    }

    $baseArgs = @(
        "install",
        "--id", "Microsoft.PowerShell",
        "--exact",
        "--source", "winget",
        "--accept-package-agreements",
        "--accept-source-agreements",
        "--silent"
    )

    Write-Host "Installing PowerShell 7 via winget (machine scope)..." -ForegroundColor Cyan
    $proc = Start-Process -FilePath $winget.Source -ArgumentList ($baseArgs + @("--scope", "machine")) -Wait -PassThru -NoNewWindow

    $successCodes = @(0, 3010, 1641, -1978335189)

    if ($proc.ExitCode -in $successCodes) { return }

    # 0x8A150013 = system configuration does not support machine-scope install (managed/locked machines)
    if ($proc.ExitCode -eq -1978334957) {
        Write-Host "Machine-scope install blocked by system policy. Retrying with user scope..." -ForegroundColor Yellow
        $proc = Start-Process -FilePath $winget.Source -ArgumentList ($baseArgs + @("--scope", "user")) -Wait -PassThru -NoNewWindow
        if ($proc.ExitCode -in $successCodes) { return }
    }

    throw "winget install failed with exit code $($proc.ExitCode)."
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

        $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        $env:Path = "$machinePath;$userPath"

        $pwshPath = Get-InstalledPwshPath
        if (-not $pwshPath) {
            throw "Install completed but pwsh.exe was not found yet. Sign out/in or restart, then rerun shortcut repair."
        }
    }

    $installedVersion = try { (& $pwshPath -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()') } catch { "unknown" }

    Write-Host "PowerShell 7 installation/repair complete." -ForegroundColor Green
    Write-Host "Path: $pwshPath" -ForegroundColor Green
    Write-Host "Version: $installedVersion" -ForegroundColor Green
    Write-Host "Next step (optional): run Create-Shortcuts to point launcher shortcuts to PowerShell 7." -ForegroundColor Cyan
}
catch {
    Write-Host "PowerShell 7 installation/repair failed." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    throw
}
