$ErrorActionPreference = "Stop"

function Wait-MenuContinue {
    Write-Host ""
    Read-Host "Press Enter to continue" | Out-Null
}

$toolPath = Join-Path $PSScriptRoot "..\MISC\VMwareHorizonOSOptimizationTool\VMwareHorizonOSOptimizationTool-x86_64.exe"

try {
    Write-Host "VMware Horizon OS Optimization Tool" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-Path $toolPath)) {
        throw "Tool not found. Place VMwareHorizonOSOptimizationTool-x86_64.exe in src\MISC\VMwareHorizonOSOptimizationTool\ and try again."
    }

    Start-Process -FilePath $toolPath
    Write-Host "Tool launched." -ForegroundColor Green
}
catch {
    Write-Host "Horizon Optimization Tool launch failed." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
finally {
    Wait-MenuContinue
}
