# src\Tasks\Set-StaticIP.ps1
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "..\Lib\Logging.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "..\Lib\Validation.psm1") -Force

Initialize-LabLog
Assert-IsAdmin

function Prompt-NonEmpty([string]$label, [string]$default) {
    $v = Read-Host "$label [$default]"
    if ([string]::IsNullOrWhiteSpace($v)) { return $default }
    return $v.Trim()
}

function Prompt-Int([string]$label, [int]$default) {
    while ($true) {
        $v = Read-Host "$label [$default]"
        if ([string]::IsNullOrWhiteSpace($v)) { return $default }
        if ([int]::TryParse($v.Trim(), [ref]$null)) { return [int]$v.Trim() }
        Write-Host "Please enter a valid number."
    }
}

function Select-NetworkAdapter {
    $adapters = Get-NetAdapter |
        Where-Object { $_.Status -eq "Up" -and $_.HardwareInterface -eq $true } |
        Sort-Object -Property Name

    if (-not $adapters) {
        throw "No active network adapters found."
    }

    Write-Host ""
    Write-Host "Active network adapters:"
    for ($i=0; $i -lt $adapters.Count; $i++) {
        $a = $adapters[$i]
        Write-Host ("{0}) {1}  (InterfaceIndex: {2})" -f ($i+1), $a.Name, $a.IfIndex)
    }

    while ($true) {
        $choice = Read-Host "Select adapter (1-$($adapters.Count))"
        if ([int]::TryParse($choice, [ref]$null)) {
            $n = [int]$choice
            if ($n -ge 1 -and $n -le $adapters.Count) {
                return $adapters[$n-1]
            }
        }
        Write-Host "Invalid selection."
    }
}

$adapter = Select-NetworkAdapter
Write-LabLog "StaticIP: Selected adapter $($adapter.Name) (IfIndex $($adapter.IfIndex))"

# Defaults for your lab
$defaultIp      = "192.168.1.2"
$defaultPrefix  = 24
$defaultGateway = "192.168.1.1"

$ip      = Prompt-NonEmpty "IP address" $defaultIp
$prefix  = Prompt-Int "Prefix length (CIDR, e.g., 24)" $defaultPrefix
$gw      = Prompt-NonEmpty "Default gateway" $defaultGateway

# DNS default: use the server's own IP (common for a DC once promoted)
$defaultDns = $ip
$dnsInput = Prompt-NonEmpty "DNS server (use your server IP if this will be a DC)" $defaultDns

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
    Pause
    return
}

# Remove existing IPv4 addresses (except APIPA) to avoid duplicates
$ifIndex = $adapter.IfIndex
$existing = Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike "169.254.*" }

foreach ($addr in $existing) {
    Write-LabLog "StaticIP: Removing existing IPv4 address $($addr.IPAddress)"
    Remove-NetIPAddress -InterfaceIndex $ifIndex -IPAddress $addr.IPAddress -Confirm:$false -ErrorAction SilentlyContinue
}

Write-LabLog "StaticIP: Disabling DHCP on adapter $($adapter.Name)"
Set-NetIPInterface -InterfaceIndex $ifIndex -Dhcp Disabled -ErrorAction Stop

Write-LabLog "StaticIP: Setting IP $ip/$prefix GW $gw"
New-NetIPAddress -InterfaceIndex $ifIndex -IPAddress $ip -PrefixLength $prefix -DefaultGateway $gw -ErrorAction Stop | Out-Null

Write-LabLog "StaticIP: Setting DNS server(s): $dnsInput"
Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ServerAddresses @($dnsInput) -ErrorAction Stop

Write-Host ""
Write-Host "Static IP configuration applied."
Write-Host ("Log: {0}" -f (Get-LabLogPath))
Pause