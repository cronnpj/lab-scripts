$ErrorActionPreference = "Stop"

$mainMenuPath = Join-Path $PSScriptRoot "Menu\MainMenu.ps1"
if (-not (Test-Path $mainMenuPath)) {
    throw "Main menu script not found: $mainMenuPath"
}

$wt = Get-Command wt.exe -ErrorAction SilentlyContinue
if ($wt) {
    $wtArgs = @(
        "-w", "new",
        "new-tab",
        "--title", "CITA Lab Tools",
        "powershell.exe",
        "-NoLogo",
        "-NoExit",
        "-ExecutionPolicy", "Bypass",
        "-File", $mainMenuPath
    )

    Start-Process -FilePath $wt.Source -ArgumentList $wtArgs
    return
}

# Fallback when Windows Terminal is not available
& powershell.exe -NoLogo -ExecutionPolicy Bypass -File $mainMenuPath
