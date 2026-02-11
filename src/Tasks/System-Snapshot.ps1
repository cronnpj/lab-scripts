# src\Tasks\System-Snapshot.ps1
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "..\Lib\Logging.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "..\Lib\Validation.psm1") -Force

Initialize-LabLog
Assert-IsAdmin

Write-LabLog "Snapshot: Collecting system snapshot"

function Get-PrimaryAdapter {
    # Prefer an "Up" adapter that has an IPv4 default gateway
    $candidates = Get-NetIPConfiguration |
        Where-Object { $_.NetAdapter.Status -eq "Up" -and $_.IPv4DefaultGateway -ne $null }

    if ($candidates) { return $candidates[0] }

    # Fallback: any Up adapter
    $up = Get-NetIPConfiguration | Where-Object { $_.NetAdapter.Status -eq "Up" }
    if ($up) { return $up[0] }

    return $null
}

function Get-DomainInfo {
    try {
        $cs = Get-CimInstance Win32_ComputerSystem
        return [pscustomobject]@{
            PartOfDomain = [bool]$cs.PartOfDomain
            Domain       = $cs.Domain
        }
    } catch {
        return [pscustomobject]@{
            PartOfDomain = $false
            Domain       = "unknown"
        }
    }
}

function Get-RolesInstalled {
    $features = @("AD-Domain-Services","DNS","DHCP")
    $states = Get-RoleInstallState -FeatureNames $features
    return $states
}

function Get-DhcpState([int]$ifIndex) {
    try {
        $ipif = Get-NetIPInterface -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction Stop
        return $ipif.Dhcp
    } catch {
        return "Unknown"
    }
}

function Get-DnsServers([int]$ifIndex) {
    try {
        $dns = Get-DnsClientServerAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction Stop
        return ($dns.ServerAddresses -join ", ")
    } catch {
        return "Unknown"
    }
}

function Is-LikelyDomainController {
    # Best-effort signals:
    # - NTDS service exists, or
    # - AD DS role installed AND ntdsutil exists, etc.
    try {
        $svc = Get-Service -Name "NTDS" -ErrorAction SilentlyContinue
        if ($svc) { return $true }
    } catch { }

    return $false
}

$domain = Get-DomainInfo
$primary = Get-PrimaryAdapter
$roles = Get-RolesInstalled
$isDc = Is-LikelyDomainController

Clear-Host
Write-Host "CITA Lab Tools - System Snapshot"
Write-Host "--------------------------------"
Write-Host ("Computer Name:   {0}" -f $env:COMPUTERNAME)

if ($domain.PartOfDomain) {
    Write-Host ("Domain Joined:   YES ({0})" -f $domain.Domain)
} else {
    Write-Host ("Domain Joined:   NO (Workgroup: {0})" -f $domain.Domain)
}

Write-Host ("Likely DC:       {0}" -f ($(if ($isDc) { "YES" } else { "NO" })))
Write-Host ""

if ($primary -eq $null) {
    Write-Host "Network: No active adapter configuration found."
} else {
    $adapterName = $primary.NetAdapter.Name
    $ifIndex = $primary.NetAdapter.IfIndex

    $ipv4 = $primary.IPv4Address | ForEach-Object { $_.IPAddress } | Where-Object { $_ } | Select-Object -First 1
    $prefix = $primary.IPv4Address | ForEach-Object { $_.PrefixLength } | Where-Object { $_ } | Select-Object -First 1
    $gw = $primary.IPv4DefaultGateway | ForEach-Object { $_.NextHop } | Where-Object { $_ } | Select-Object -First 1

    $dhcp = Get-DhcpState -ifIndex $ifIndex
    $dnsServers = Get-DnsServers -ifIndex $ifIndex

    Write-Host ("Primary Adapter: {0} (IfIndex {1})" -f $adapterName, $ifIndex)
    Write-Host ("IPv4 Address:    {0}/{1}" -f ($ipv4 ?? "None"), ($prefix ?? ""))
    Write-Host ("Default Gateway: {0}" -f ($gw ?? "None"))
    Write-Host ("DHCP:            {0}" -f $dhcp)
    Write-Host ("DNS Servers:     {0}" -f $dnsServers)
}

Write-Host ""
Write-Host "Roles/Features:"
$roles | Format-Table -AutoSize

Write-Host ""
Write-Host ("Log: {0}" -f (Get-LabLogPath))