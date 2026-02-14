# C:\CITA\LabTools\src\Menu\DCToolsMenu.ps1
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

function Show-DCMenu {
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
    Write-Host "Main > Domain Controller Tools" -ForegroundColor Cyan

    Write-Host ""

    Write-Host "  [1] Install AD DS role (no promotion)"
    Write-Host "  [2] Install DNS role"
    Write-Host "  [3] Install DHCP role"
    Write-Host "  [4] Install Core DC roles (AD DS | DNS | DHCP)"
    Write-Host ""
    Write-Host "  [0] Back"
    Write-Host ""

    Write-Host "Status: " -NoNewline
    Write-Host $StatusText -ForegroundColor $StatusColor

    Write-Host "Keys: 1-4 Select  |  0 Back"
    Write-Host ""
}

function Invoke-RoleInstall {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("ADDS","DNS","DHCP","CORE_DC")]
        [string]$Mode
    )

    try {
        $script:LastStatusText  = "Running role install ($Mode)..."
        $script:LastStatusColor = "Gray"

        & $rolesScript -Mode $Mode -ErrorAction Stop

        $script:LastStatusText  = "Role install completed ($Mode)"
        $script:LastStatusColor = "Green"
    }
    catch {
        Write-Host ""
        Write-Host "Error: Role installation failed." -ForegroundColor Red
        Write-Host ("Details: {0}" -f $_.Exception.Message)

        $script:LastStatusText  = "Role install failed ($Mode)"
        $script:LastStatusColor = "Red"
    }
    finally {
        Pause-Menu
    }
}

$rolesScript = Join-Path $PSScriptRoot "..\Tasks\Install-Roles.ps1"

$back = $false

# Status line tracking
$script:LastStatusText  = "Ready"
$script:LastStatusColor = "DarkGray"

do {
    Show-DCMenu -StatusText $script:LastStatusText -StatusColor $script:LastStatusColor
    $choice = Read-Host "Select an option"

    switch ($choice) {
        "1" { Invoke-RoleInstall -Mode ADDS }
        "2" { Invoke-RoleInstall -Mode DNS }
        "3" { Invoke-RoleInstall -Mode DHCP }
        "4" { Invoke-RoleInstall -Mode CORE_DC }
        "0" { $back = $true }
        default {
            $script:LastStatusText  = "Invalid selection"
            $script:LastStatusColor = "Yellow"
            Start-Sleep 1
        }
    }

} while (-not $back)

Clear-Host
return
