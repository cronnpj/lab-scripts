$ErrorActionPreference = "Stop"

$mainMenuPath = Join-Path $PSScriptRoot "Menu\MainMenu.ps1"
if (-not (Test-Path $mainMenuPath)) {
    throw "Main menu script not found: $mainMenuPath"
}

$wt = Get-Command wt.exe -ErrorAction SilentlyContinue
if ($wt) {
    try {
        $wtArgs = @(
            "-w", "new",
            "new-tab",
            "--title", "CITA-LabTools",
            "--",
            "powershell.exe",
            "-NoLogo",
            "-NoExit",
            "-ExecutionPolicy", "Bypass",
            "-File", $mainMenuPath
        )

        Start-Process -FilePath $wt.Source -ArgumentList $wtArgs
        return
    }
    catch {
        # Fall back to direct PowerShell launch when wt invocation fails
    }
}

# Fallback when Windows Terminal is not available
& powershell.exe -NoLogo -ExecutionPolicy Bypass -File $mainMenuPath
