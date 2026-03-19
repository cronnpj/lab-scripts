$ErrorActionPreference = "Stop"

function Wait-MenuContinue {
    Write-Host ""
    Read-Host "Press Enter to continue"
}

$projectUrl = "https://github.com/Raphire/Win11Debloat"
$runUrl = "https://debloat.raphi.re/"

try {
    Write-Host "Win11Debloat (official upstream)" -ForegroundColor Cyan
    Write-Host "Project: $projectUrl"
    Write-Host ""
    Write-Host "This will run the upstream script from: $runUrl" -ForegroundColor Yellow
    Write-Host "Review the project docs before continuing." -ForegroundColor Yellow
    Write-Host ""

    $openProject = Read-Host "Open the Win11Debloat GitHub page now? (Y/N)"
    if ($openProject -match '^(y|yes)$') {
        Start-Process $projectUrl | Out-Null
    }

    $confirm = Read-Host "Run Win11Debloat now in this PowerShell session? (Y/N)"
    if ($confirm -notmatch '^(y|yes)$') {
        Write-Host "Cancelled. No changes were made." -ForegroundColor DarkYellow
        return
    }

    # Download to a temp file rather than executing directly from the network.
    # This avoids running an in-memory scriptblock whose content cannot be
    # inspected or logged, and lets the OS/AV scan the file before execution.
    $tempScript = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "Win11Debloat_$(Get-Date -Format 'yyyyMMddHHmmss').ps1")
    try {
        Write-Host "Downloading script to: $tempScript" -ForegroundColor Cyan
        Invoke-WebRequest -Uri $runUrl -OutFile $tempScript -UseBasicParsing -ErrorAction Stop
        Write-Host "Download complete. Executing..." -ForegroundColor Cyan
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tempScript
    }
    finally {
        if (Test-Path $tempScript) {
            Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host "Win11Debloat script finished." -ForegroundColor Green
}
catch {
    Write-Host "Win11Debloat launch failed." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
finally {
    Wait-MenuContinue
}