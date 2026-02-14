# src\UI\ConsoleUI.psm1
# Shared console UI helpers (ASCII-safe)

function Get-AppVersion {
    $versionPath = Join-Path $PSScriptRoot "..\VERSION.txt"
    if (Test-Path $versionPath) {
        return (Get-Content $versionPath -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
    }
    return "Unknown"
}

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

function Show-AppHeader {
    param(
        [Parameter(Mandatory=$true)][string]$Breadcrumb,
        [int]$Width = 64
    )

    Clear-Host

    $version  = Get-AppVersion
    $hostName = $env:COMPUTERNAME
    $userName = $env:USERNAME

    Write-Host ("+" + ("-" * ($Width - 2)) + "+") -ForegroundColor DarkGray
    Write-BoxLine "CITA Lab Tools - Infrastructure Assistant" $Width "Cyan"
    Write-BoxLine ("Version: {0}" -f $version) $Width "Gray"
    Write-BoxLine ("Host: {0}    User: {1}" -f $hostName, $userName) $Width "Gray"
    Write-Host ("+" + ("-" * ($Width - 2)) + "+") -ForegroundColor DarkGray

    Write-Host ""
    Write-Host "Navigation: " -NoNewline -ForegroundColor DarkGray
    Write-Host $Breadcrumb -ForegroundColor Cyan
    Write-Host ""
}

Export-ModuleMember -Function Get-AppVersion, Write-BoxLine, Show-AppHeader
