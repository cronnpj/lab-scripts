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

$sysprepExePath = Join-Path $env:WINDIR "System32\Sysprep\Sysprep.exe"
$sdeleteTaskPath = Join-Path $PSScriptRoot "Run-SDelete.ps1"

try {
    Write-Host "VM Template Prep Checklist (Proxmox)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Recommended order:" -ForegroundColor Yellow
    Write-Host "  1) Sysprep (Generalize + OOBE + Shutdown)"
    Write-Host "  2) SDelete with -z on the template drive"
    Write-Host "  3) Shut down VM"
    Write-Host "  4) (Optional) Sparsify/convert image"
    Write-Host "  5) Convert VM to template"
    Write-Host ""

    if (-not (Test-IsAdministrator)) {
        throw "This checklist requires an elevated PowerShell session (Run as Administrator)."
    }

    if (-not (Test-Path $sysprepExePath)) {
        Write-Host "Sysprep executable was not found at expected path:" -ForegroundColor Red
        Write-Host $sysprepExePath -ForegroundColor Red
    }
    else {
        $openSysprep = Read-Host "Open Sysprep now? (Y/N)"
        if ($openSysprep -match '^(y|yes)$') {
            Start-Process -FilePath $sysprepExePath | Out-Null
            Write-Host "Sysprep opened. Use: Enter System Out-of-Box Experience (OOBE) + Generalize + Shutdown." -ForegroundColor Green
        }
    }

    Write-Host ""
    Write-Host "SDelete Step" -ForegroundColor Cyan
    Write-Host "Use -z for VM templates to maximize sparse reclaim/compression." -ForegroundColor DarkGray

    $runSDelete = Read-Host "Run SDelete flow now? (Y/N)"
    if ($runSDelete -match '^(y|yes)$') {
        if (-not (Test-Path $sdeleteTaskPath)) {
            throw "SDelete task script not found at '$sdeleteTaskPath'."
        }

        & $sdeleteTaskPath
    }

    Write-Host ""
    Write-Host "Checklist complete." -ForegroundColor Green
    Write-Host "If preparing a template, shut down the VM before converting to template in Proxmox." -ForegroundColor DarkGray
}
catch {
    Write-Host "Template prep checklist failed." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
finally {
    Wait-MenuContinue
}
