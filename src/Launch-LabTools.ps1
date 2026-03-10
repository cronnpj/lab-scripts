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

$configPath = Join-Path $PSScriptRoot "config\labtools.json"
$launchInWindowsTerminal = $false

if (Test-Path $configPath) {
    try {
        $config = Get-Content -Path $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $config.launcher -and $null -ne $config.launcher.useWindowsTerminal) {
            $launchInWindowsTerminal = [bool]$config.launcher.useWindowsTerminal
        }
    }
    catch {
        # Use default launcher behavior when config is unavailable/invalid
    }
}

if ($launchInWindowsTerminal) {
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
            # Fall back to in-session launch when wt invocation fails
        }
    }
}

# Default: run in current shell to avoid opening extra PowerShell windows
& $mainMenuPath
