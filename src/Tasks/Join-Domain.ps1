# src\Tasks\Join-Domain.ps1
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "..\Lib\Logging.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "..\Lib\Validation.psm1") -Force

Initialize-LabLog
Assert-IsAdmin

function Get-ComputerSystemInfo {
    try { return Get-CimInstance Win32_ComputerSystem } catch { return $null }
}

function Is-DomainJoined {
    $cs = Get-ComputerSystemInfo
    if ($null -eq $cs) { return $false }
    return [bool]$cs.PartOfDomain
}

function Get-CurrentDomainOrWorkgroup {
    $cs = Get-ComputerSystemInfo
    if ($null -eq $cs) { return "unknown" }
    return $cs.Domain
}

function Is-DomainControllerByRole {
    $cs = Get-ComputerSystemInfo
    if ($null -eq $cs) { return $false }
    return ([int]$cs.DomainRole -ge 4)
}

function Is-ADDSRoleInstalled {
    try {
        $f = Get-WindowsFeature -Name "AD-Domain-Services" -ErrorAction Stop
        return [bool]$f.Installed
    } catch {
        # conservative if feature query fails
        return $true
    }
}

Write-Host ""
Write-Host "Join Existing Domain (Member Server Only)"
Write-Host "----------------------------------------"

# Guardrails
if (Is-DomainControllerByRole) {
    Write-Host "This machine is a Domain Controller."
    Write-Host "Domain join is for MEMBER SERVERS only. Aborting."
    Write-LabLog "JoinDomain: Aborted - machine is a DC" "WARN"
    Pause
    return
}

if (Is-ADDSRoleInstalled) {
    Write-Host "AD DS role is installed on this machine."
    Write-Host "Domain join is for MEMBER SERVERS only. Aborting."
    Write-LabLog "JoinDomain: Aborted - AD DS role installed" "WARN"
    Pause
    return
}

if (Is-DomainJoined) {
    $cur = Get-CurrentDomainOrWorkgroup
    Write-Host "This machine is already domain joined: $cur"
    Write-Host "No action taken."
    Write-LabLog "JoinDomain: No action - already domain joined ($cur)"
    Pause
    return
}

Write-Host "Current Workgroup: $(Get-CurrentDomainOrWorkgroup)"
Write-Host ""
Write-Host "You will need domain credentials that can join computers to the domain."
Write-Host ""

$domain = Read-Host "Enter domain name (example: cronnpj.local)"
if ([string]::IsNullOrWhiteSpace($domain)) {
    Write-Host "Cancelled."
    Write-LabLog "JoinDomain: Cancelled - no domain provided"
    Pause
    return
}
$domain = $domain.Trim()

Write-Host ""
Write-Host "Enter domain credentials (example: $domain\Administrator)"
$cred = Get-Credential

Write-Host ""
$ou = Read-Host "Optional OU distinguishedName (press Enter to skip)"
if (-not [string]::IsNullOrWhiteSpace($ou)) { $ou = $ou.Trim() }

Write-Host ""
Write-Host "Summary:"
Write-Host " Domain: $domain"
Write-Host (" OU:     {0}" -f ($(if ([string]::IsNullOrWhiteSpace($ou)) { "(default Computers container)" } else { $ou })))
Write-Host ""

$confirm = Read-Host "Proceed with domain join? (Y/N)"
if ($confirm.Trim().ToUpper() -ne "Y") {
    Write-Host "Cancelled."
    Write-LabLog "JoinDomain: Cancelled by user"
    Pause
    return
}

Write-LabLog "JoinDomain: Attempting to join domain $domain"

if ([string]::IsNullOrWhiteSpace($ou)) {
    Add-Computer -DomainName $domain -Credential $cred -ErrorAction Stop
} else {
    Add-Computer -DomainName $domain -Credential $cred -OUPath $ou -ErrorAction Stop
}

Write-Host ""
Write-Host "Domain join successful. A reboot is required."
Write-LabLog "JoinDomain: Join successful - reboot required"

$reboot = Read-Host "Reboot now? (Y/N)"
if ($reboot.Trim().ToUpper() -eq "Y") {
    Write-LabLog "JoinDomain: Rebooting now"
    Restart-Computer -Force
} else {
    Write-Host "Please reboot before continuing."
    Write-LabLog "JoinDomain: Reboot deferred by user" "WARN"
    Pause
}