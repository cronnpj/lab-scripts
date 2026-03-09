$ErrorActionPreference = "Stop"

function Wait-MenuContinue {
    Write-Host ""
    Read-Host "Press Enter to continue" | Out-Null
}

function Test-IsAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$sdeleteFolder = Join-Path $PSScriptRoot "..\MISC\SDelete"
$sdelete64Path = Join-Path $sdeleteFolder "sdelete64.exe"
$sdeletePath = $sdelete64Path

try {
    Write-Host "SDelete (Sysinternals) - Free Space Zeroing" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Recommended for VM templating: use -z to zero free space." -ForegroundColor Yellow
    Write-Host "This helps thin-provisioned image reclaim and template hygiene." -ForegroundColor Yellow
    Write-Host ""

    if (-not (Test-IsAdministrator)) {
        throw "SDelete requires an elevated PowerShell session (Run as Administrator)."
    }

    if (-not (Test-Path $sdeletePath)) {
        throw "SDelete executable not found. Place sdelete64.exe in src\MISC\SDelete\ and try again."
    }

    $driveInput = Read-Host "Drive to process (default C:)"
    if ([string]::IsNullOrWhiteSpace($driveInput)) {
        $driveInput = "C:"
    }

    $drive = $driveInput.Trim().ToUpper()
    if ($drive.EndsWith("\\")) {
        $drive = $drive.TrimEnd("\\")
    }
    if (-not ($drive -match "^[A-Z]:$")) {
        throw "Invalid drive format '$driveInput'. Use format like C:"
    }
    if (-not (Test-Path "$drive\\")) {
        throw "Drive '$drive' was not found."
    }

    Write-Host ""
    Write-Host "Mode:" -ForegroundColor Cyan
    Write-Host "  [1] -z (zero free space, recommended for VM templates)"
    Write-Host "  [2] -c (random overwrite, stronger privacy but no compression gain)"
    $modeChoice = Read-Host "Select mode (default 1)"

    $modeFlag = "-z"
    if ($modeChoice -eq "2") {
        $modeFlag = "-c"
    }

    Write-Host ""
    Write-Host ("Command: {0} -accepteula {1} {2}" -f (Split-Path $sdeletePath -Leaf), $modeFlag, $drive) -ForegroundColor DarkGray
    $confirm = Read-Host "Proceed? (Y/N)"
    if ($confirm -notmatch '^(y|yes)$') {
        Write-Host "Cancelled. No changes were made." -ForegroundColor DarkYellow
        return
    }

    & $sdeletePath -accepteula $modeFlag $drive

    Write-Host ""
    Write-Host "SDelete completed." -ForegroundColor Green
    if ($modeFlag -eq "-z") {
        Write-Host "Next step for Proxmox templates: shut down, then convert/sparsify if desired." -ForegroundColor DarkGray
    }
}
catch {
    Write-Host "SDelete run failed." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
finally {
    Wait-MenuContinue
}