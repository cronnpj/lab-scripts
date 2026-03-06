$ErrorActionPreference = "Stop"

function Get-PreferredPowerShellExecutable {
    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($pwsh) {
        return $pwsh.Source
    }

    $winPs = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($winPs) {
        return $winPs.Source
    }

    throw "No supported PowerShell executable was found (pwsh.exe or powershell.exe)."
}

$mainMenuPath = Join-Path $PSScriptRoot "Menu\MainMenu.ps1"
if (-not (Test-Path $mainMenuPath)) {
    throw "Main menu script not found: $mainMenuPath"
}

$preferredShellPath = Get-PreferredPowerShellExecutable

$wt = Get-Command wt.exe -ErrorAction SilentlyContinue
if ($wt) {
    try {
        $wtArgs = @(
            "-w", "new",
            "new-tab",
            "--title", "CITA-LabTools",
            "--",
            $preferredShellPath,
            "-NoLogo",
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
& $preferredShellPath -NoLogo -ExecutionPolicy Bypass -File $mainMenuPath
