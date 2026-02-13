# src\Tasks\Client\Get-JoinStatus.ps1
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "..\..\Lib\Logging.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "..\..\Lib\Validation.psm1") -Force

Initialize-LabLog

function Pause-Menu {
    Write-Host ""
    Read-Host "Press Enter to continue"
}

function Safe-Run([string]$label, [scriptblock]$sb) {
    try {
        & $sb
    }
    catch {
        Write-Host ""
        Write-Host ("Error ({0}): {1}" -f $label, $_.Exception.Message)
        Write-LabLog ("GetJoinStatus: {0} failed - {1}" -f $label, $_.Exception.Message) "ERROR"
    }
}

Write-Host ""
Write-Host "Join Status (Domain + Entra ID / Hybrid)"
Write-Host "----------------------------------------"
Write-Host ""

Safe-Run "Local domain join" {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    Write-Host "Local Domain Join:"
    Write-Host (" Computer:    {0}" -f $env:COMPUTERNAME)
    Write-Host (" User:        {0}\{1}" -f $env:USERDOMAIN, $env:USERNAME)
    Write-Host (" PartOfDomain:{0}" -f $cs.PartOfDomain)
    Write-Host (" Domain/WG:   {0}" -f $cs.Domain)
    Write-Host ""
    Write-LabLog ("GetJoinStatus: PartOfDomain={0} Domain={1}" -f $cs.PartOfDomain, $cs.Domain)
}

Safe-Run "dsregcmd /status" {
    $dsreg = Get-Command dsregcmd.exe -ErrorAction SilentlyContinue
    if (-not $dsreg) {
        Write-Host "Entra ID / Hybrid Status:"
        Write-Host " dsregcmd.exe not found on this system."
        Write-LabLog "GetJoinStatus: dsregcmd.exe not found" "WARN"
        return
    }

    Write-Host "Entra ID / Hybrid Status (dsregcmd key fields):"
    Write-Host "---------------------------------------------"

    $lines = @(& dsregcmd.exe /status 2>&1)

    $keys = @(
        "AzureAdJoined",
        "EnterpriseJoined",
        "DomainJoined",
        "DeviceName",
        "TenantName",
        "TenantId",
        "WorkplaceJoined",
        "WamDefaultSet",
        "NgcSet",
        "MDMUrl"
    )

    foreach ($k in $keys) {
        $match = $lines | Where-Object { $_ -match "^\s*$([regex]::Escape($k))\s*:\s*" } | Select-Object -First 1
        if ($match) { Write-Host (" " + $match.Trim()) }
    }

    Write-Host ""
    Write-Host "Notes:"
    Write-Host " - DomainJoined=YES and AzureAdJoined=NO usually means domain-only."
    Write-Host " - DomainJoined=YES and AzureAdJoined=YES is typically hybrid-joined."

    Write-LabLog "GetJoinStatus: dsregcmd key fields displayed"
}

Write-Host ""
Write-Host ("Log: {0}" -f (Get-LabLogPath))
Pause-Menu
