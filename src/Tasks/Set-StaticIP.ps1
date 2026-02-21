# src\Tasks\Set-StaticIP.ps1
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "..\Lib\Logging.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "..\Lib\Validation.psm1") -Force

Initialize-LabLog
Assert-IsAdmin

function Wait-MenuContinue {
    Write-Host ""
    Read-Host "Press Enter to continue"
}

function Prompt-NonEmpty([string]$label, [string]$default) {
    $v = Read-Host "$label [$default]"
    if ([string]::IsNullOrWhiteSpace($v)) { return $default }
    return $v.Trim()
}

function Prompt-Int([string]$label, [int]$default) {
    while ($true) {
        $v = Read-Host "$label [$default]"
        if ([string]::IsNullOrWhiteSpace($v)) { return $default }
        $n = 0
        if ([int]::TryParse($v.Trim(), [ref]$n)) { return $n }
        Write-Host "Please enter a valid number."
    }
}

function Select-NetworkAdapter {
    $adapters = @(Get-NetAdapter |
        Where-Object { $_.Status -eq "Up" } |
        Sort-Object -Property Name)

    if ($adapters.Count -lt 1) {
        throw "No active network adapters found."
    }

    Write-Host ""
    Write-Host "Active network adapters:"
    for ($i = 0; $i -lt $adapters.Count; $i++) {
        $a = $adapters[$i]
        Write-Host ("{0}) {1}  (InterfaceIndex: {2}, Status: {3})" -f ($i + 1), $a.Name, $a.IfIndex, $a.Status)
    }

    while ($true) {
        $choice = Read-Host "Select adapter (1-$($adapters.Count))"
        $n = 0
        if ([int]::TryParse($choice, [ref]$n) -and $n -ge 1 -and $n -le $adapters.Count) {
            return $adapters[$n - 1]
        }
        Write-Host "Invalid selection."
    }
}

function Test-IPv4InUse([string]$ip) {
    # Best-effort: if it answers ping, assume it's in use.
    # (Not perfect—some hosts block ICMP—but good enough to prevent common lab collisions.)
    try {
        return (Test-Connection -ComputerName $ip -Count 1 -Quiet -ErrorAction Stop)
    } catch {
        return $false
    }
}

Write-Host ""
Write-Host "Configure Static IPv4 Address"
Write-Host "----------------------------"

$adapter = Select-NetworkAdapter
Write-LabLog "StaticIP: Selected adapter $($adapter.Name) (IfIndex $($adapter.IfIndex))"

# Basic lab defaults
$defaultPrefix  = 24
$defaultGateway = "192.168.1.1"

# Role-based defaults to avoid the 192.168.1.2 duplicate problem
Write-Host ""
Write-Host "Select machine type (for safer defaults):"
Write-Host "1) Domain Controller (DC)  - typically 192.168.1.2"
Write-Host "2) Member Server           - typically 192.168.1.3+"
Write-Host "3) Windows Client          - typically 192.168.1.50+"
$role = Read-Host "Choice [3]"

if ([string]::IsNullOrWhiteSpace($role)) { $role = "3" }

$defaultIp = switch ($role.Trim()) {
    "1" { "192.168.1.2" }
    "2" { "192.168.1.3" }
    default { "192.168.1.50" }
}

$ip      = Prompt-NonEmpty "IP address" $defaultIp
$prefix  = Prompt-Int "Prefix length (CIDR, e.g., 24)" $defaultPrefix
$gw      = Prompt-NonEmpty "Default gateway" $defaultGateway

# DNS default: if DC, use itself; otherwise use DC (.2) unless the user overrides
$defaultDns = if ($role.Trim() -eq "1") { $ip } else { "192.168.1.2" }
$dnsInput = Prompt-NonEmpty "DNS server" $defaultDns

Write-Host ""
Write-Host "Summary:"
Write-Host " Adapter: $($adapter.Name)"
Write-Host " IP:      $ip/$prefix"
Write-Host " Gateway: $gw"
Write-Host " DNS:     $dnsInput"
Write-Host ""

$confirm = Read-Host "Apply these settings? (Y/N)"
if ($confirm.Trim().ToUpper() -ne "Y") {
    Write-LabLog "StaticIP: User cancelled"
    Write-Host "Cancelled."
    Wait-MenuContinue
    return
}

# Duplicate / in-use check
Write-Host ""
Write-Host "Checking if $ip is already in use..."
if (Test-IPv4InUse -ip $ip) {
    Write-Host "WARNING: $ip responded to ping. It may already be in use."
    Write-Host "Pick a different IP to avoid a duplicate-address conflict."
    Write-LabLog "StaticIP: Aborted - IP appears in use ($ip)" "WARN"
    Wait-MenuContinue
    return
}

$ifIndex = $adapter.IfIndex

# Remove existing IPv4 addresses (except APIPA) to avoid duplicates
$existing = Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike "169.254.*" }

foreach ($addr in $existing) {
    Write-LabLog "StaticIP: Removing existing IPv4 address $($addr.IPAddress)"
    Remove-NetIPAddress -InterfaceIndex $ifIndex -IPAddress $addr.IPAddress -Confirm:$false -ErrorAction SilentlyContinue
}

# Remove default route(s) to prevent route conflicts
$routes = Get-NetRoute -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.DestinationPrefix -eq "0.0.0.0/0" }

foreach ($r in $routes) {
    Write-LabLog "StaticIP: Removing default route 0.0.0.0/0"
    Remove-NetRoute -InterfaceIndex $ifIndex -DestinationPrefix "0.0.0.0/0" -Confirm:$false -ErrorAction SilentlyContinue
}

Write-LabLog "StaticIP: Disabling DHCP on adapter $($adapter.Name)"
Set-NetIPInterface -InterfaceIndex $ifIndex -Dhcp Disabled -ErrorAction Stop

Write-LabLog "StaticIP: Setting IP $ip/$prefix GW $gw"
New-NetIPAddress -InterfaceIndex $ifIndex -IPAddress $ip -PrefixLength $prefix -DefaultGateway $gw -ErrorAction Stop | Out-Null

Write-LabLog "StaticIP: Setting DNS server(s): $dnsInput"
Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ServerAddresses @($dnsInput) -ErrorAction Stop

# Bounce adapter to apply cleanly
Write-LabLog "StaticIP: Restarting adapter $($adapter.Name)"
Restart-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Static IP configuration applied."
Write-Host ("Log: {0}" -f (Get-LabLogPath))
Write-Host ""
ipconfig /all
Wait-MenuContinue
