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

    Write-Host "  [1] Launch tool (interactive UI)"
    Write-Host "  [2] Attempt quiet install/run"
    Write-Host ""

    $choice = Read-Host "Select an option (default 1)"
    if ([string]::IsNullOrWhiteSpace($choice)) {
        $choice = "1"
    }

    switch ($choice) {
        "1" {
            Start-Process -FilePath $toolPath
            Write-Host "Tool launched." -ForegroundColor Green
        }
        "2" {
            $defaultArgs = "/S"
            $argsInput = Read-Host "Quiet arguments (default: /S)"
            if ([string]::IsNullOrWhiteSpace($argsInput)) {
                $argsInput = $defaultArgs
            }

            Write-Host "Running quiet mode with args: $argsInput" -ForegroundColor DarkGray
            $proc = Start-Process -FilePath $toolPath -ArgumentList $argsInput -Wait -PassThru

            if ($proc.ExitCode -eq 0) {
                Write-Host "Quiet run completed successfully." -ForegroundColor Green
            }
            else {
                Write-Host "Quiet run finished with exit code $($proc.ExitCode)." -ForegroundColor Yellow
                Write-Host "If the tool does not support these arguments, use option [1] interactive mode or retry with different quiet arguments." -ForegroundColor Yellow
            }
        }
        default {
            Write-Host "Invalid selection. No action taken." -ForegroundColor DarkYellow
        }
    }
}
catch {
    Write-Host "Horizon Optimization Tool launch failed." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
finally {
    Wait-MenuContinue
}
