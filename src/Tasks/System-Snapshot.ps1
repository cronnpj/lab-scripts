# src\Tasks\System-Snapshot.ps1
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "..\Lib\Logging.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "..\Lib\Validation.psm1") -Force

Initialize-LabLog
Assert-IsAdmin

Write-LabLog "Snapshot: Collecting system snapshot"

function Get-ComputerSystemInfo {
    try {
        return Get-CimInstance Win32_ComputerSystem
    } catch {
        return $null
    }
}

function Get-DomainInfo {
    $cs = Get-ComputerSystemInfo
    if ($null -eq $cs) {
        return [pscustomobject]@{ PartOfDomain = $false; Domain = "unknown"; DomainRole = -1 }
    }

    return [pscustomobject]@{
        PartOfDomain = [bool]$cs.PartOfDomain
        Domain       = $cs.Domain
        DomainRole   = [int]$cs.DomainRole
    }
}

function Get-DomainRoleLabel([int]$role) {
    switch ($role) {
        0 { "Standalone Workstation" }
        1 { "Member Workstation" }
        2 { "Standalone Server" }
        3 { "Member Server" }
        4 { "Backup Domain Controller" }
        5 { "Primary Domain Controller" }
        default { "Unknown" }
    }
}

function Is-DomainControllerByRole([int]$domainRole) {
    # 4/5 indicates DC
    return ($domainRole -ge 4)
}

function Get-PrimaryAdapter {
    $candidates = Get-NetIPConfiguration |
        Where-Object { $_.NetAdapter.Status -eq "Up" -and $_.IPv4DefaultGateway -ne $null }
    if ($candidates) { return $candidates[0] }

    $up = Get-NetIPConfiguration | Where-Object { $_.NetAdapter.Status -eq "Up" }
    if ($up) { return $up[0] }

    return $null
}

function Get-RolesInstalled {
    $features = @("AD-Domain-Services","DNS","DHCP")
    return (Get-RoleInstallState -FeatureNames $features)
}

function Is-FeatureInstalled([string]$name) {
    try {
        $f = Get-WindowsFeature -Name $name -ErrorAction Stop
        return [bool]$f.Installed
    } catch {
        return $false
    }
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
        return @($dns.ServerAddresses)
    } catch {
        return @()
    }
}

function Test-PendingReboot {
    # Common indicators
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    )

    foreach ($p in $paths) {
        if (Test-Path $p) { return $true }
    }

    # Pending file rename operations
    try {
        $val = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
        if ($null -ne $val -and $null -ne $val.PendingFileRenameOperations) { return $true }
    } catch { }

    return $false
}

# Collect data
$domain  = Get-DomainInfo
$roleLbl = Get-DomainRoleLabel -role $domain.DomainRole
$isDc    = Is-DomainControllerByRole -domainRole $domain.DomainRole
$pendingReboot = Test-PendingReboot

$primary = Get-PrimaryAdapter
$roles   = Get-RolesInstalled

$addsInstalled = Is-FeatureInstalled "AD-Domain-Services"

Clear-Host
Write-Host "CITA Lab Tools - System Snapshot"
Write-Host "--------------------------------"
Write-Host ("Computer Name:       {0}" -f $env:COMPUTERNAME)

if ($domain.PartOfDomain) {
    Write-Host ("Domain Joined:       YES ({0})" -f $domain.Domain)
} else {
    Write-Host ("Domain Joined:       NO (Workgroup: {0})" -f $domain.Domain)
}

Write-Host ("Domain Role:         {0} ({1})" -f $domain.DomainRole, $roleLbl)
Write-Host ("Is Domain Controller:{0}" -f ($(if ($isDc) { " YES" } else { " NO" })))
Write-Host ("Reboot Required:     {0}" -f ($(if ($pendingReboot) { " YES" } else { " NO" })))
Write-Host ""

if ($null -eq $primary) {
    Write-Host "Network: No active adapter configuration found."
    Write-Host ""
} else {
    $adapterName = $primary.NetAdapter.Name
    $ifIndex     = $primary.NetAdapter.IfIndex

    $ipv4   = $primary.IPv4Address        | ForEach-Object { $_.IPAddress }    | Where-Object { $_ } | Select-Object -First 1
    $prefix = $primary.IPv4Address        | ForEach-Object { $_.PrefixLength } | Where-Object { $_ } | Select-Object -First 1
    $gw     = $primary.IPv4DefaultGateway | ForEach-Object { $_.NextHop }       | Where-Object { $_ } | Select-Object -First 1

    $dhcp = Get-DhcpState -ifIndex $ifIndex
    $dnsServers = Get-DnsServers -ifIndex $ifIndex

    if (-not $ipv4)   { $ipv4 = "None" }
    if (-not $prefix) { $prefix = "" }
    if (-not $gw)     { $gw = "None" }

    Write-Host ("Primary Adapter:     {0} (IfIndex {1})" -f $adapterName, $ifIndex)
    Write-Host ("IPv4 Address:        {0}/{1}" -f $ipv4, $prefix)
    Write-Host ("Default Gateway:     {0}" -f $gw)
    Write-Host ("DHCP:                {0}" -f $dhcp)
    Write-Host ("DNS Servers:         {0}" -f ($(if ($dnsServers.Count -gt 0) { ($dnsServers -join ", ") } else { "None" })))
    Write-Host ""

    # DNS Self-check warning (useful before promotion)
    # If AD DS role installed but DNS does not point to self/local, warn.
    $dnsOk = $false
    if ($dnsServers.Count -gt 0) {
        foreach ($d in $dnsServers) {
            if ($d -eq $ipv4 -or $d -eq "127.0.0.1") { $dnsOk = $true }
        }
    }

    if ($addsInstalled -and (-not $dnsOk)) {
        Write-Host "WARNING: AD DS role is installed, but DNS is not pointing to this server."
        Write-Host "         Before promoting to a DC, set DNS to 127.0.0.1 or this server's IP."
        Write-Host ""
    }
}

Write-Host "Roles/Features:"
$roles | Format-Table -AutoSize

Write-Host ""
Write-Host ("Log: {0}" -f (Get-LabLogPath))
Write-LabLog "Snapshot: Completed"