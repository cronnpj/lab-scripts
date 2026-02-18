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

function Write-HostUserLine {
    param(
        [Parameter(Mandatory=$true)][string]$HostName,
        [Parameter(Mandatory=$true)][string]$UserName,
        [int]$Width = 64
    )

    # inside width for text area (excluding "| " and " |")
    $inner = $Width - 4

    $labelHost = "Host: "
    $labelUser = "    User: "

    $textLen = $labelHost.Length + $HostName.Length + $labelUser.Length + $UserName.Length
    if ($textLen -gt $inner) {
        # Truncate user first if needed, then host if still needed
        $maxUser = [Math]::Max(0, $inner - ($labelHost.Length + $HostName.Length + $labelUser.Length))
        if ($UserName.Length -gt $maxUser) { $UserName = $UserName.Substring(0, $maxUser) }

        $textLen = $labelHost.Length + $HostName.Length + $labelUser.Length + $UserName.Length
        if ($textLen -gt $inner) {
            $maxHost = [Math]::Max(0, $inner - ($labelHost.Length + $labelUser.Length + $UserName.Length))
            if ($HostName.Length -gt $maxHost) { $HostName = $HostName.Substring(0, $maxHost) }
        }
    }

    $textLen = $labelHost.Length + $HostName.Length + $labelUser.Length + $UserName.Length
    $pad = " " * ($inner - $textLen)

    Write-Host "| " -NoNewline -ForegroundColor Gray
    Write-Host $labelHost -NoNewline -ForegroundColor Gray
    Write-Host $HostName -NoNewline -ForegroundColor Cyan
    Write-Host $labelUser -NoNewline -ForegroundColor Gray
    Write-Host $UserName -NoNewline -ForegroundColor Cyan
    Write-Host $pad -NoNewline -ForegroundColor Gray
    Write-Host " |" -ForegroundColor Gray
}

function Write-TimezoneDateLine {
    param(
        [int]$Width = 64
    )

    # Get timezone offset and date
    $offset = [System.TimeZoneInfo]::Local.BaseUtcOffset
    $timeZoneStr = "UTC{0:+00;-00}:{0:mm}" -f $offset
    $currentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Inside width for text area (excluding "| " and " |")
    $inner = $Width - 4

    $labelTZ = "TZ: "
    $labelDate = "    Date: "

    $textLen = $labelTZ.Length + $timeZoneStr.Length + $labelDate.Length + $currentDate.Length
    $pad = " " * [Math]::Max(0, $inner - $textLen)

    Write-Host "| " -NoNewline -ForegroundColor Gray
    Write-Host $labelTZ -NoNewline -ForegroundColor Gray
    Write-Host $timeZoneStr -NoNewline -ForegroundColor Cyan
    Write-Host $labelDate -NoNewline -ForegroundColor Gray
    Write-Host $currentDate -NoNewline -ForegroundColor Cyan
    Write-Host $pad -NoNewline -ForegroundColor Gray
    Write-Host " |" -ForegroundColor Gray
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

    # Host/User line with cyan values
    Write-HostUserLine -HostName $hostName -UserName $userName -Width $Width

    # Timezone/Date line with cyan values
    Write-TimezoneDateLine -Width $Width

    Write-Host ("+" + ("-" * ($Width - 2)) + "+") -ForegroundColor DarkGray

    Write-Host ""
    Write-Host "Navigation: " -NoNewline -ForegroundColor DarkGray
    Write-Host $Breadcrumb -ForegroundColor Cyan
    Write-Host ""
}

Export-ModuleMember -Function Get-AppVersion, Write-BoxLine, Write-TimezoneDateLine, Show-AppHeader
