# C:\CITA\LabTools\src\Menu\ServerToolsMenu.ps1
$ErrorActionPreference = "SilentlyContinue"

# Grab version the same way as MainMenu (Menu folder is one level below the runtime root)
$versionPath = Join-Path $PSScriptRoot '..\VERSION.txt'
$version = if (Test-Path $versionPath) {
    (Get-Content $versionPath -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
} else { "Unknown" }

function Write-BoxLine {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [int]$Width = 64
    )

    $inner = $Width - 4
    if ($Text.Length -gt $inner) { $Text = $Text.Substring(0, $inner) }
    $pad = " " * ($inner - $Text.Length)
    Write-Host ("| " + $Text + $pad + " |")
}

function Pause-Menu {
    Write-Host ""
    Read-Host "Press Enter to continue" | Out-Null
}

function Show-ServerToolsMenu {
    param(
        [string]$StatusText = "Ready",
        [string]$StatusColor = "DarkGray"
    )

    Clear-Host

    $width = 64
    $hostName = $env:COMPUTERNAME
    $userName = $env:USERNAME

    Write-Host ("+" + ("-" * ($width - 2)) + "+")
    Write-BoxLine "CITA Lab Tools - Infrastructure Assistant" $width
    Write-BoxLine ("Version: {0}" -f $version) $width
    Write-BoxLine ("Host: {0}    User: {1}" -f $hostName, $userName) $width
    Write-Host ("+" + ("-" * ($width - 2)) + "+")

    Write-Host ""
    Write-Host "Navigation: Main > Server Tools"
    Write-Host ""

    Write-Host "  [1] Rename computer"
    Write-Host "  [2] Configure static IP"
    Write-Host ""
    Write-Host "  [0] Back"
    Write-Host ""

    Write-Host "Status: " -NoNewline
    Write-Host $StatusText -ForegroundColor $StatusColor
    Write-Host "Keys: 1-2 Select  |  0 Back"
    Write-Host ""
}

$back = $false

# Optional: track last action result for the status line
$lastStatusText = "Ready"
$lastStatusColor = "DarkGray"

do {
    Show-ServerToolsMenu -StatusText $lastStatusText -StatusColor $lastStatusColor
    $choice = Read-Host "Select an option"

    switch ($choice) {
        "1" {
            # Run task
            & (Join-Path $PSScriptRoot "..\Tasks\Rename-Computer.ps1")

            $lastStatusText = "Rename computer completed"
            $lastStatusColor = "Green"
            Pause-Menu
        }
        "2" {
            & (Join-Path $PSScriptRoot "..\Tasks\Set-StaticIP.ps1")

            $lastStatusText = "Static IP task completed"
            $lastStatusColor = "Green"
            Pause-Menu
        }
        "0" {
            $back = $true
        }
        default {
            $lastStatusText = "Invalid selection"
            $lastStatusColor = "Yellow"
            Start-Sleep -Milliseconds 400
        }
    }

} while (-not $back)

Clear-Host
return
