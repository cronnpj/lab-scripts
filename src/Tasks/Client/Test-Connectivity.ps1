# src\Tasks\Client\Test-Connectivity.ps1
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "..\..\Lib\Logging.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "..\..\Lib\Validation.psm1") -Force

Initialize-LabLog

function Pause-Menu {
    Write-Host ""
    Read-Host "Press Enter to continue"
}

Write-Host ""
Write-Host "Network Connectivity Test"
Write-Host "-------------------------"
Write-Host ""

try {

    $config = Get-NetIPConfiguration | Where-Object { $_.IPv4Address }
    $gw = $config.IPv4DefaultGateway.NextHop
    $dns = (Get-DnsClientServerAddress -AddressFamily IPv4).ServerAddresses |
            Where-Object { $_ }

    # Gateway
    if ($gw) {
        Write-Host "Default Gateway: $gw"
        $gwResult = Test-Connection $gw -Count 2 -Quiet
        Write-Host (" Reachable: {0}" -f $gwResult)
        Write-LabLog ("Connectivity: Gateway {0} Reachable={1}" -f $gw, $gwResult)
    }

    Write-Host ""

    # DNS
    if ($dns) {
        Write-Host "DNS Servers:"
        foreach ($d in $dns) {
            $dnsResult = Test-Connection $d -Count 2 -Quiet
            Write-Host (" {0} - Reachable: {1}" -f $d, $dnsResult)
            Write-LabLog ("Connectivity: DNS {0} Reachable={1}" -f $d, $dnsResult)
        }
    }

    Write-Host ""

    # Internet
    $internet = "1.1.1.1"
    $netResult = Test-Connection $internet -Count 2 -Quiet
    Write-Host ("Internet Test ({0}) Reachable: {1}" -f $internet, $netResult)
    Write-LabLog ("Connectivity: Internet {0} Reachable={1}" -f $internet, $netResult)

}
catch {
    Write-Host ""
    Write-Host "Error during connectivity test:"
    Write-Host $_.Exception.Message
    Write-LabLog ("Connectivity: Failed - {0}" -f $_.Exception.Message) "ERROR"
}

Pause-Menu
