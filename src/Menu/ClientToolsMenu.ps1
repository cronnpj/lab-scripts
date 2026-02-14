# C:\CITA\LabTools\src\Menu\ClientToolsMenu.ps1
# Updated: app-feel header + colored breadcrumb + status line
$ErrorActionPreference = "SilentlyContinue"

$versionPath = Join-Path $PSScriptRoot '..\VERSION.txt'
$version = if (Test-Path $versionPath) {
    (Get-Content $versionPath -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
} else { "Unknown" }

function Write-BoxLine {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [int]$Width = 64,
        [string]$Color = "Gray"
    )

    $inner = $Width - 4
    if ($Text.Length -gt $inner) { $Text = $Text.Substring(0, $inner) }
    $pad = " " * ($inner - $Text.Length)
    Write-Host ("| " + $Text + $pad + " |") -ForegroundColor $Color
}

function Pause-Menu {
    Write-Host ""
    Read-Host "Press Enter to continue" | Out-Null
}

function Run-Safely {
    param([Parameter(Mandatory=$true)][scriptblock]$Action)

    try {
        & $Action
        $script:LastStatusText  = "Completed"
        $script:LastStatusColor = "Green"
    }
    catch {
        Write-Host ""
        Write-Host "Error:" -ForegroundColor Red
        Write-Host $_.Exception.Message
        $script:LastStatusText  = "Error - see message above"
        $script:LastStatusColor = "Red"
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

function Show-ClientMenu {
    param(
        [string]$StatusText = "Ready",
        [string]$StatusColor = "DarkGray"
    )

    Clear-Host

    $width = 64
    $hostName = $env:COMPUTERNAME
    $userName = $env:USERNAME

    # Header
    Write-Host ("+" + ("-" * ($width - 2)) + "+") -ForegroundColor DarkGray
    Write-BoxLine "CITA Lab Tools - Infrastructure Assistant" $width "Cyan"
    Write-BoxLine ("Version: {0}" -f $version) $width "Gray"
    Write-BoxLine ("Host: {0}    User: {1}" -f $hostName, $userName) $width "Gray"
    Write-Host ("+" + ("-" * ($width - 2)) + "+") -ForegroundColor DarkGray

    Write-Host ""

    # Colored Breadcrumb
    Write-Host "Navigation: " -NoNewline -ForegroundColor DarkGray
    Write-Host "Main > Windows Client Tools" -ForegroundColor Cyan

    Write-Host ""

    Write-Host "Identity / Enrollment"
    Write-Host "  [1]  Join existing domain"
    Write-Host "  [2]  Show Join Status (Domain + Entra ID / Hybrid)"
    Write-Host "  [3]  Open Work/School Accounts (Enrollment)"
    Write-Host "  [4]  Force Intune Sync (best-effort)"
    Write-Host ""

    Write-Host "Policy / Management"
    Write-Host "  [5]  Force Group Policy Update (gpupdate /force)"
    Write-Host "  [6]  Show GPO Results (gpresult /r)"
    Write-Host "  [7]  Export GPO Report to Desktop (HTML)"
    Write-Host ""

    Write-Host "Networking"
    Write-Host "  [8]  Show IP Configuration (ipconfig /all)"
    Write-Host "  [9]  Flush DNS Cache"
    Write-Host "  [10] Renew DHCP Lease (release/renew)"
    Write-Host "  [11] Quick Connectivity Tests (GW/DNS/Internet)"
    Write-Host ""

    Write-Host "Client Actions"
    Write-Host "  [12] Rename computer"
    Write-Host ""

    Write-Host "Client Maintenance"
    Write-Host "  [14] Restart Windows Update Services"
    Write-Host "  [15] System File Check (SFC)"
    Write-Host ""

    Write-Host "  [0] Back"
    Write-Host ""

    Write-Host "Status: " -NoNewline
    Write-Host $StatusText -ForegroundColor $StatusColor

    Write-Host "Keys: 1-15 Select  |  0 Back"
    Write-Host ""
}

# Task paths (unchanged)
$joinDomainScript   = Join-Path $PSScriptRoot "..\Tasks\Join-Domain.ps1"
$renameScript       = Join-Path $PSScriptRoot "..\Tasks\Rename-Computer.ps1"

$joinStatusScript   = Join-Path $PSScriptRoot "..\Tasks\Client\Get-JoinStatus.ps1"
$gpoReportScript    = Join-Path $PSScriptRoot "..\Tasks\Client\GPO-Report.ps1"
$testConnScript     = Join-Path $PSScriptRoot "..\Tasks\Client\Test-Connectivity.ps1"

$back = $false

# Status line tracking
$script:LastStatusText  = "Ready"
$script:LastStatusColor = "DarkGray"

do {
    Show-ClientMenu -StatusText $script:LastStatusText -StatusColor $script:LastStatusColor
    $choice = Read-Host "Select an option"

    switch ($choice) {

        # Identity / Enrollment
        "1"  { $script:LastStatusText="Joining domain..."; $script:LastStatusColor="Gray"; Run-Safely { Invoke-Task $joinDomainScript } }
        "2"  { $script:LastStatusText="Checking join status..."; $script:LastStatusColor="Gray"; Run-Safely { Invoke-Task $joinStatusScript } }
        "3"  { $script:LastStatusText="Opening Work/School Accounts..."; $script:LastStatusColor="Gray"; Run-Safely { Start-Process "ms-settings:workplace" } }
        "4"  {
            $script:LastStatusText="Opening enrollment settings..."; $script:LastStatusColor="Gray"
            Run-Safely {
                Clear-Host
                Write-Host "Opening Work/School settings. Use Sync if available."
                Start-Process "ms-settings:workplace"
            }
        }

        # Policy / Management
        "5"  { $script:LastStatusText="Running gpupdate /force..."; $script:LastStatusColor="Gray"; Run-Safely { Clear-Host; gpupdate /force } }
        "6"  { $script:LastStatusText="Running gpresult /r..."; $script:LastStatusColor="Gray"; Run-Safely { Clear-Host; gpresult /r } }
        "7"  { $script:LastStatusText="Exporting GPO report..."; $script:LastStatusColor="Gray"; Run-Safely { Invoke-Task $gpoReportScript } }

        # Networking
        "8"  { $script:LastStatusText="Showing IP config..."; $script:LastStatusColor="Gray"; Run-Safely { Clear-Host; ipconfig /all } }
        "9"  { $script:LastStatusText="Flushing DNS cache..."; $script:LastStatusColor="Gray"; Run-Safely { Clear-Host; ipconfig /flushdns; Write-Host "DNS cache flushed." } }
        "10" {
            $script:LastStatusText="Renewing DHCP lease..."; $script:LastStatusColor="Gray"
            Run-Safely {
                Clear-Host
                Write-Host "Renewing DHCP lease (may not apply to static IP systems)..."
                ipconfig /release
                ipconfig /renew
                ipconfig /all
            }
        }
        "11" { $script:LastStatusText="Running connectivity tests..."; $script:LastStatusColor="Gray"; Run-Safely { Invoke-Task $testConnScript } }

        # Client Actions
        "12" { $script:LastStatusText="Renaming computer..."; $script:LastStatusColor="Gray"; Run-Safely { Invoke-Task $renameScript } }

        # Client Maintenance
        "14" {
            $script:LastStatusText="Restarting Windows Update services..."; $script:LastStatusColor="Gray"
            Run-Safely {
                Clear-Host
                Write-Host "Restarting Windows Update services..."
                Restart-Service wuauserv -Force
                Restart-Service bits -Force
                Get-Service wuauserv, bits | Format-Table Status, Name, DisplayName -AutoSize | Out-Host
            }
        }
        "15" { $script:LastStatusText="Running SFC..."; $script:LastStatusColor="Gray"; Run-Safely { Clear-Host; sfc /scannow } }

        "0"  { $back = $true }
        default {
            $script:LastStatusText  = "Invalid selection"
            $script:LastStatusColor = "Yellow"
            Start-Sleep 1
        }
    }

} while (-not $back)

Clear-Host
return
