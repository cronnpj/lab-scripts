function Show-ClientMenu {
    Clear-Host
    Write-Host "Windows Client Tools"
    Write-Host "---------------------"
    Write-Host ""

    Write-Host "Identity / Enrollment"
    Write-Host "  1) Join existing domain"
    Write-Host "  2) Show Join Status (Domain + Entra ID / Hybrid)"
    Write-Host "  3) Open Work/School Accounts (Enrollment)"
    Write-Host "  4) Force Intune Sync (best-effort)"
    Write-Host ""

    Write-Host "Policy / Management"
    Write-Host "  5) Force Group Policy Update (gpupdate /force)"
    Write-Host "  6) Show GPO Results (gpresult /r)"
    Write-Host "  7) Export GPO Report to Desktop (HTML)"
    Write-Host ""

    Write-Host "Networking"
    Write-Host "  8) Show IP Configuration (ipconfig /all)"
    Write-Host "  9) Flush DNS Cache"
    Write-Host " 10) Renew DHCP Lease (release/renew)"
    Write-Host " 11) Quick Connectivity Tests (GW/DNS/Internet)"
    Write-Host ""

    Write-Host "Client Actions"
    Write-Host " 12) Rename computer"
    Write-Host ""

    Write-Host "Client Maintenance"
    Write-Host " 14) Restart Windows Update Services"
    Write-Host " 15) System File Check (SFC)"
    Write-Host ""

    Write-Host "0) Back"
    Write-Host ""
}

function Pause-Menu {
    Write-Host ""
    Read-Host "Press Enter to continue"
}

function Run-Safely {
    param([Parameter(Mandatory=$true)][scriptblock]$Action)

    try {
        & $Action
    }
    catch {
        Write-Host ""
        Write-Host "Error:"
        Write-Host $_.Exception.Message
    }
    finally {
        Pause-Menu
    }
}

function Invoke-Task {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path $Path)) {
        throw "Task script not found: $Path"
    }
    & $Path
}

$joinDomainScript   = Join-Path $PSScriptRoot "..\Tasks\Join-Domain.ps1"
$renameScript       = Join-Path $PSScriptRoot "..\Tasks\Rename-Computer.ps1"

$joinStatusScript   = Join-Path $PSScriptRoot "..\Tasks\Client\Get-JoinStatus.ps1"
$gpoReportScript    = Join-Path $PSScriptRoot "..\Tasks\Client\GPO-Report.ps1"
$testConnScript     = Join-Path $PSScriptRoot "..\Tasks\Client\Test-Connectivity.ps1"

$back = $false
do {
    Show-ClientMenu
    $choice = Read-Host "Select an option"

    switch ($choice) {

        # Identity / Enrollment
        "1"  { Run-Safely { Invoke-Task $joinDomainScript } }
        "2"  { Run-Safely { Invoke-Task $joinStatusScript } }
        "3"  { Run-Safely { Start-Process "ms-settings:workplace" } }
        "4"  { Run-Safely {
                Clear-Host
                Write-Host "Opening Work/School settings. Use Sync if available."
                Start-Process "ms-settings:workplace"
            }
        }

        # Policy / Management
        "5"  { Run-Safely { Clear-Host; gpupdate /force } }
        "6"  { Run-Safely { Clear-Host; gpresult /r } }
        "7"  { Run-Safely { Invoke-Task $gpoReportScript } }

        # Networking
        "8"  { Run-Safely { Clear-Host; ipconfig /all } }
        "9"  { Run-Safely { Clear-Host; ipconfig /flushdns; Write-Host "DNS cache flushed." } }
        "10" { Run-Safely {
                Clear-Host
                Write-Host "Renewing DHCP lease (may not apply to static IP systems)..."
                ipconfig /release
                ipconfig /renew
                ipconfig /all
            }
        }
        "11" { Run-Safely { Invoke-Task $testConnScript } }

        # Client Actions
        "12" { Run-Safely { Invoke-Task $renameScript } }

        # Client Maintenance
        "14" { Run-Safely {
                Clear-Host
                Write-Host "Restarting Windows Update services..."
                Restart-Service wuauserv -Force
                Restart-Service bits -Force
                Get-Service wuauserv, bits | Format-Table Status, Name, DisplayName -AutoSize | Out-Host
            }
        }
        "15" { Run-Safely { Clear-Host; sfc /scannow } }

        "0"  { $back = $true }
        default { Write-Host ""; Write-Host "Invalid selection."; Start-Sleep 1 }
    }

} while (-not $back)

Clear-Host
return
