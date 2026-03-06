# src\Tasks\Client\Get-JoinStatus.ps1
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "..\..\Lib\Logging.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "..\..\Lib\Validation.psm1") -Force

Initialize-LabLog

function Wait-MenuContinue {
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

function Show-GraphTenantInfo {
    $connectCmd = Get-Command Connect-MgGraph -ErrorAction SilentlyContinue
    $getOrgCmd = Get-Command Get-MgOrganization -ErrorAction SilentlyContinue
    $getCtxCmd = Get-Command Get-MgContext -ErrorAction SilentlyContinue
    $autosaveCmd = Get-Command Enable-MgGraphContextAutosave -ErrorAction SilentlyContinue

    Write-Host "Microsoft Graph Tenant Check:"

    if (-not $connectCmd -or -not $getOrgCmd -or -not $getCtxCmd) {
        Write-Host " Graph module is not available in this session." -ForegroundColor Yellow
        Write-Host " Install (CurrentUser):"
        Write-Host "  Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force"
        Write-Host "  Install-Module Microsoft.Graph.Identity.DirectoryManagement -Scope CurrentUser -Force"
        Write-LabLog "GetJoinStatus: Graph commands missing; skipped tenant lookup" "WARN"
        return
    }

    if ($autosaveCmd) {
        try {
            Enable-MgGraphContextAutosave -Scope CurrentUser -ErrorAction SilentlyContinue | Out-Null
        }
        catch {
            # Non-blocking: autosave support varies by Graph SDK version.
        }
    }

    $ctx = $null
    try {
        $ctx = Get-MgContext -ErrorAction SilentlyContinue
    }
    catch {
        $ctx = $null
    }

    if (-not $ctx -or [string]::IsNullOrWhiteSpace([string]$ctx.Account)) {
        $connectNow = Read-Host " Connect to Microsoft Graph now? (Y/N)"
        if ($connectNow -notmatch '^(?i)y(es)?$') {
            Write-Host " Skipped Graph tenant lookup."
            Write-LabLog "GetJoinStatus: Graph tenant lookup skipped by user"
            return
        }

        Connect-MgGraph -Scopes "Organization.Read.All" -NoWelcome -ContextScope CurrentUser -ErrorAction Stop | Out-Null
        $ctx = Get-MgContext -ErrorAction SilentlyContinue
    }

    $org = Get-MgOrganization -ErrorAction Stop | Select-Object -First 1
    if (-not $org) {
        Write-Host " No organization information returned by Graph." -ForegroundColor Yellow
        Write-LabLog "GetJoinStatus: Graph returned no organization object" "WARN"
        return
    }

    $defaultDomain = ($org.VerifiedDomains | Where-Object { $_.IsDefault } | Select-Object -First 1).Name

    Write-Host (" TenantId:      {0}" -f $org.Id)
    Write-Host (" DisplayName:   {0}" -f $org.DisplayName)
    Write-Host (" DefaultDomain: {0}" -f $(if ([string]::IsNullOrWhiteSpace($defaultDomain)) { "N/A" } else { $defaultDomain }))
    Write-LabLog ("GetJoinStatus: Graph tenant resolved DisplayName={0} TenantId={1} DefaultDomain={2}" -f $org.DisplayName, $org.Id, $defaultDomain)
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
Safe-Run "Microsoft Graph tenant lookup" {
    Show-GraphTenantInfo
}

Write-Host ""
Write-Host ("Log: {0}" -f (Get-LabLogPath))
Wait-MenuContinue
