# C:\CITA\LabTools\src\Menu\MaintenanceMenu.ps1
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

function Show-MaintenanceMenu {
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
    Write-Host "Main > Maintenance & Updates" -ForegroundColor Cyan

    Write-Host ""

    Write-Host "  [1] Update Lab Tools from GitHub"
    Write-Host ""
    Write-Host "  [0] Back"
    Write-Host ""

    Write-Host "Status: " -NoNewline
    Write-Host $StatusText -ForegroundColor $StatusColor

    Write-Host "Keys: 1 Select  |  0 Back"
    Write-Host ""
}

$back = $false
$updateScript = Join-Path $PSScriptRoot "..\Tasks\Update-LabTools.ps1"

# Status line tracking
$script:LastStatusText  = "Ready"
$script:LastStatusColor = "DarkGray"

do {
    Show-MaintenanceMenu -StatusText $script:LastStatusText -StatusColor $script:LastStatusColor
    $choice = Read-Host "Select an option"

    switch ($choice) {
        "1" {
            if (-not (Test-Path $updateScript)) {
                $script:LastStatusText  = "Update script not found"
                $script:LastStatusColor = "Red"
                Write-Host ""
                Write-Host "Error: Task script not found:" -ForegroundColor Red
                Write-Host $updateScript
                Pause-Menu
                break
            }

            $script:LastStatusText  = "Updating Lab Tools..."
            $script:LastStatusColor = "Gray"

            try {
                & $updateScript
                $script:LastStatusText  = "Update completed"
                $script:LastStatusColor = "Green"
            }
            catch {
                $script:LastStatusText  = "Update failed"
                $script:LastStatusColor = "Red"
                Write-Host ""
                Write-Host "Error: Update failed." -ForegroundColor Red
                Write-Host $_.Exception.Message
            }

            Pause-Menu
        }
        "0" {
            $back = $true
        }
        default {
            $script:LastStatusText  = "Invalid selection"
            $script:LastStatusColor = "Yellow"
            Start-Sleep 1
        }
    }

} while (-not $back)

Clear-Host
return
