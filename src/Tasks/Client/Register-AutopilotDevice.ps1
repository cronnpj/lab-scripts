# src\Tasks\Client\Register-AutopilotDevice.ps1
param(
    [switch]$Online
)

$ErrorActionPreference = "Stop"

function Test-IsAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-GetWindowsAutopilotInfo {
    # Check if already installed as a script
    $scriptPath = (Get-InstalledScript -Name "Get-WindowsAutopilotInfo" -ErrorAction SilentlyContinue)?.InstalledLocation
    if ($scriptPath) {
        $fullPath = Join-Path $scriptPath "Get-WindowsAutopilotInfo.ps1"
        if (Test-Path $fullPath) { return $fullPath }
    }

    Write-Host "Get-WindowsAutopilotInfo not found. Installing from PSGallery..." -ForegroundColor Yellow

    # Ensure NuGet provider is available
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue | Where-Object { $_.Version -ge [Version]"2.8.5.201" })) {
        Write-Host "Installing NuGet provider..." -ForegroundColor DarkGray
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
    }

    Install-Script -Name Get-WindowsAutopilotInfo -Force -Scope CurrentUser

    $scriptPath = (Get-InstalledScript -Name "Get-WindowsAutopilotInfo" -ErrorAction SilentlyContinue)?.InstalledLocation
    if (-not $scriptPath) { throw "Installation succeeded but script path could not be resolved." }

    $fullPath = Join-Path $scriptPath "Get-WindowsAutopilotInfo.ps1"
    if (-not (Test-Path $fullPath)) { throw "Script installed but file not found at: $fullPath" }

    Write-Host "Installed successfully." -ForegroundColor Green
    return $fullPath
}

Clear-Host

if (-not (Test-IsAdministrator)) {
    Write-Host "This task requires administrator privileges." -ForegroundColor Red
    Write-Host "Please re-launch Lab Tools as Administrator and try again."
    Write-Host ""
    Read-Host "Press Enter to continue" | Out-Null
    return
}

Write-Host ""

if ($Online) {
    Write-Host "=== Autopilot Registration: Online Upload ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "This will extract the hardware hash and upload it directly to your Intune tenant." -ForegroundColor DarkGray
    Write-Host "You will be prompted to sign in with Intune admin credentials." -ForegroundColor DarkGray
    Write-Host ""
} else {
    Write-Host "=== Autopilot Registration: CSV Export ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "This will extract the hardware hash and save it as a .csv file." -ForegroundColor DarkGray
    Write-Host "You can then upload the file in Intune: Devices > Enroll Devices > Windows Autopilot." -ForegroundColor DarkGray
    Write-Host ""
}

$scriptFile = Ensure-GetWindowsAutopilotInfo

Write-Host ""
Write-Host "Running Get-WindowsAutopilotInfo..." -ForegroundColor Cyan
Write-Host ""

if ($Online) {
    & $scriptFile -Online
} else {
    $outputPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "AutopilotHWID.csv"
    & $scriptFile -OutputFile $outputPath
    Write-Host ""
    if (Test-Path $outputPath) {
        Write-Host "CSV saved to: $outputPath" -ForegroundColor Green
        Write-Host ""
        $open = Read-Host "Open Desktop folder now? (y/n)"
        if ($open -eq "y" -or $open -eq "Y") {
            Start-Process "explorer.exe" -ArgumentList "/select,`"$outputPath`""
        }
    } else {
        Write-Host "CSV file not found at expected path: $outputPath" -ForegroundColor Yellow
        Write-Host "Check above output for the actual file location."
    }
}

Write-Host ""
Read-Host "Press Enter to continue" | Out-Null
