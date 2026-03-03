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

    & ([scriptblock]::Create((Invoke-RestMethod $runUrl)))
    Write-Host "Win11Debloat script finished." -ForegroundColor Green
}
catch {
    Write-Host "Win11Debloat launch failed." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
finally {
    Wait-MenuContinue
}