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
        [string]$Color = "Gray",
        [string]$BorderColor = "Cyan"
    )

    $inner = $Width - 4
    if ($Text.Length -gt $inner) { $Text = $Text.Substring(0, $inner) }
    $pad = " " * ($inner - $Text.Length)
    Write-Host "| " -NoNewline -ForegroundColor $BorderColor
    Write-Host ($Text + $pad) -NoNewline -ForegroundColor $Color
    Write-Host " |" -ForegroundColor $BorderColor
}

function Write-HostUserLine {
    param(
        [Parameter(Mandatory=$true)][string]$HostName,
        [Parameter(Mandatory=$true)][string]$UserName,
        [string]$OSCaption = '',
        [int]$Width = 80
    )

    # inside width for text area (excluding "| " and " |")
    $inner = $Width - 4

    if ([string]::IsNullOrWhiteSpace($OSCaption)) {
        # 2-column layout
        $leftLabel = "Host: "
        $rightLabel = "User: "
        $rightLabelStart = 24

        $maxHostLength = [Math]::Max(0, $rightLabelStart - $leftLabel.Length)
        if ($HostName.Length -gt $maxHostLength) { $HostName = $HostName.Substring(0, $maxHostLength) }

        $spacerLength = [Math]::Max(1, $rightLabelStart - ($leftLabel.Length + $HostName.Length))
        $spacer = " " * $spacerLength

        $fixedLength = $leftLabel.Length + $HostName.Length + $spacerLength + $rightLabel.Length
        $maxUserLength = [Math]::Max(0, $inner - $fixedLength)
        if ($UserName.Length -gt $maxUserLength) { $UserName = $UserName.Substring(0, $maxUserLength) }

        $pad = " " * [Math]::Max(0, $inner - $fixedLength - $UserName.Length)

        Write-Host "| " -NoNewline -ForegroundColor Cyan
        Write-Host $leftLabel -NoNewline -ForegroundColor Gray
        Write-Host $HostName -NoNewline -ForegroundColor Cyan
        Write-Host $spacer -NoNewline -ForegroundColor Gray
        Write-Host $rightLabel -NoNewline -ForegroundColor Gray
        Write-Host $UserName -NoNewline -ForegroundColor Cyan
        Write-Host $pad -NoNewline -ForegroundColor Gray
        Write-Host " |" -ForegroundColor Cyan
    }
    else {
        # 3-column layout with Width=80 (inner=76):
        #   Col1 0-23  (24): "Host: " + up to 18 chars
        #   Col2 24-50 (27): "User: " + up to 21 chars
        #   Col3 51-75 (25): "OS: "   + up to 21 chars
        $col2Start = 24
        $col3Start = 51

        $label1 = "Host: "
        $label2 = "User: "
        $label3 = "OS: "

        # Strip "Windows " prefix to save space ("11 Pro", "Server 2022", etc.)
        $osShort = $OSCaption -replace '^Windows\s+', ''

        $max1 = [Math]::Max(0, $col2Start - $label1.Length)
        if ($HostName.Length -gt $max1) { $HostName = $HostName.Substring(0, $max1) }
        $spacer1 = " " * [Math]::Max(0, $col2Start - $label1.Length - $HostName.Length)

        $max2 = [Math]::Max(0, ($col3Start - $col2Start) - $label2.Length)
        if ($UserName.Length -gt $max2) { $UserName = $UserName.Substring(0, $max2) }
        $spacer2 = " " * [Math]::Max(0, ($col3Start - $col2Start) - $label2.Length - $UserName.Length)

        $max3 = [Math]::Max(0, $inner - $col3Start - $label3.Length)
        if ($osShort.Length -gt $max3) { $osShort = $osShort.Substring(0, $max3) }
        $pad = " " * [Math]::Max(0, $inner - $col3Start - $label3.Length - $osShort.Length)

        Write-Host "| " -NoNewline -ForegroundColor Cyan
        Write-Host $label1 -NoNewline -ForegroundColor Gray
        Write-Host $HostName -NoNewline -ForegroundColor Cyan
        Write-Host $spacer1 -NoNewline -ForegroundColor Gray
        Write-Host $label2 -NoNewline -ForegroundColor Gray
        Write-Host $UserName -NoNewline -ForegroundColor Cyan
        Write-Host $spacer2 -NoNewline -ForegroundColor Gray
        Write-Host $label3 -NoNewline -ForegroundColor Gray
        Write-Host $osShort -NoNewline -ForegroundColor Cyan
        Write-Host $pad -NoNewline -ForegroundColor Gray
        Write-Host " |" -ForegroundColor Cyan
    }
}

function Write-TimezoneDateLine {
    param(
        [int]$Width = 64
    )

    # Get timezone offset and date
    $offset = [System.TimeZoneInfo]::Local.BaseUtcOffset
    $hours = $offset.Hours
    $minutes = $offset.Minutes
    if ($offset.TotalSeconds -ge 0) {
        $timeZoneStr = "UTC+{0:D2}:{1:D2}" -f $hours, $minutes
    } else {
        $timeZoneStr = "UTC-{0:D2}:{1:D2}" -f [Math]::Abs($hours), [Math]::Abs($minutes)
    }
    $currentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Inside width for text area (excluding "| " and " |")
    $inner = $Width - 4

    $labelTZ = "TZ: "
    $labelDate = "           Date: "

    $textLen = $labelTZ.Length + $timeZoneStr.Length + $labelDate.Length + $currentDate.Length
    $pad = " " * [Math]::Max(0, $inner - $textLen)

    Write-Host "| " -NoNewline -ForegroundColor Cyan
    Write-Host $labelTZ -NoNewline -ForegroundColor Gray
    Write-Host $timeZoneStr -NoNewline -ForegroundColor Cyan
    Write-Host $labelDate -NoNewline -ForegroundColor Gray
    Write-Host $currentDate -NoNewline -ForegroundColor Cyan
    Write-Host $pad -NoNewline -ForegroundColor Gray
    Write-Host " |" -ForegroundColor Cyan
}

function Write-UptimeLine {
    param([int]$Width = 80)

    # Aligns with the OS column (col3Start = 51) in Write-HostUserLine
    $inner      = $Width - 4
    $col3Start  = 51
    $label      = "Uptime: "

    try {
        $osInfo = Get-OSInfo
        $lastBoot = $osInfo.LastBootUpTime
        if ($null -eq $lastBoot) { throw "no boot time" }
        $uptime = (Get-Date) - $lastBoot
        $days   = [int]$uptime.TotalDays
        $hours  = $uptime.Hours
        $mins   = $uptime.Minutes

        if ($days -gt 0) {
            $uptimeStr = "${days}d ${hours}h ${mins}m"
        } elseif ($hours -gt 0) {
            $uptimeStr = "${hours}h ${mins}m"
        } else {
            $uptimeStr = "${mins}m"
        }
    }
    catch {
        $uptimeStr = "Unknown"
    }

    $leftPad = " " * $col3Start
    $pad     = " " * [Math]::Max(0, $inner - $col3Start - $label.Length - $uptimeStr.Length)

    Write-Host "| " -NoNewline -ForegroundColor Cyan
    Write-Host $leftPad -NoNewline
    Write-Host $label -NoNewline -ForegroundColor Gray
    Write-Host $uptimeStr -NoNewline -ForegroundColor Cyan
    Write-Host $pad -NoNewline
    Write-Host " |" -ForegroundColor Cyan
}

function Get-PrimaryNetworkInfo {
    try {
        $candidates = @()

        $interfaces = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
            Where-Object {
                $_.OperationalStatus -eq [System.Net.NetworkInformation.OperationalStatus]::Up -and
                $_.NetworkInterfaceType -ne [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback -and
                $_.NetworkInterfaceType -ne [System.Net.NetworkInformation.NetworkInterfaceType]::Tunnel
            }

        foreach ($interface in $interfaces) {
            $ipProps = $interface.GetIPProperties()

            $ipv4 = $ipProps.UnicastAddresses |
                Where-Object {
                    $_.Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and
                    -not $_.Address.IPAddressToString.StartsWith('169.254.')
                } |
                Select-Object -First 1

            if (-not $ipv4) { continue }

            $ipv4Props = $ipProps.GetIPv4Properties()
            $mode = 'Unknown'
            if ($ipv4Props) {
                $mode = if ($ipv4Props.IsDhcpEnabled) { 'DHCP' } else { 'Static' }
            }

            $hasGateway = ($ipProps.GatewayAddresses |
                Where-Object { $_.Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } |
                Measure-Object).Count -gt 0

            $candidates += [PSCustomObject]@{
                IPAddress  = $ipv4.Address.IPAddressToString
                Mode       = $mode
                HasGateway = $hasGateway
            }
        }

        $primary = $candidates |
            Sort-Object -Property @{ Expression = { if ($_.HasGateway) { 0 } else { 1 } } } |
            Select-Object -First 1

        if (-not $primary) {
            return @{ IPAddress = 'N/A'; Mode = 'Unknown' }
        }

        return @{ IPAddress = $primary.IPAddress; Mode = $primary.Mode }
    }
    catch {
        Write-Verbose "Get-PrimaryNetworkInfo: $_"
        return @{ IPAddress = 'N/A'; Mode = 'Unknown' }
    }
}

function Write-NetworkLine {
    param(
        [Parameter(Mandatory=$true)][string]$IPAddress,
        [Parameter(Mandatory=$true)][string]$Mode,
        [int]$Width = 64
    )

    $inner = $Width - 4

    $leftLabel = "IP: "
    $rightLabel = "Mode: "
    $rightLabelStart = 24

    $maxIpLength = [Math]::Max(0, $rightLabelStart - $leftLabel.Length)
    if ($IPAddress.Length -gt $maxIpLength) {
        $IPAddress = $IPAddress.Substring(0, $maxIpLength)
    }

    $spacerLength = [Math]::Max(1, $rightLabelStart - ($leftLabel.Length + $IPAddress.Length))
    $spacer = " " * $spacerLength

    $fixedLength = $leftLabel.Length + $IPAddress.Length + $spacerLength + $rightLabel.Length
    $maxModeLength = [Math]::Max(0, $inner - $fixedLength)
    if ($Mode.Length -gt $maxModeLength) {
        $Mode = $Mode.Substring(0, $maxModeLength)
    }

    $textLen = $fixedLength + $Mode.Length
    $pad = " " * [Math]::Max(0, ($inner - $textLen))

    Write-Host "| " -NoNewline -ForegroundColor Cyan
    Write-Host $leftLabel -NoNewline -ForegroundColor Gray
    Write-Host $IPAddress -NoNewline -ForegroundColor Cyan
    Write-Host $spacer -NoNewline -ForegroundColor Gray
    Write-Host $rightLabel -NoNewline -ForegroundColor Gray
    Write-Host $Mode -NoNewline -ForegroundColor Cyan
    Write-Host $pad -NoNewline -ForegroundColor Gray
    Write-Host " |" -ForegroundColor Cyan
}

$script:InternetStatusCache     = $null
$script:InternetStatusCacheTime = [datetime]::MinValue

function Get-InternetStatus {
    $cacheTtl = 30
    if ($null -ne $script:InternetStatusCache -and
        ([datetime]::Now - $script:InternetStatusCacheTime).TotalSeconds -lt $cacheTtl) {
        return $script:InternetStatusCache
    }

    try {
        $connectTask = [System.Net.Dns]::GetHostAddressesAsync('www.msftconnecttest.com')
        $completed = $connectTask.Wait(1500)

        $result = $completed -and $connectTask.Result -and $connectTask.Result.Count -gt 0
    }
    catch {
        Write-Verbose "Get-InternetStatus: $_"
        $result = $false
    }

    $script:InternetStatusCache     = $result
    $script:InternetStatusCacheTime = [datetime]::Now
    return $result
}

function Write-InternetLine {
    param(
        [Parameter(Mandatory=$true)][bool]$IsConnected,
        [int]$Width = 64
    )

    $inner = $Width - 4
    $label = "Internet: "
    $value = if ($IsConnected) { [char]0x2714 } else { [char]0x2716 }

    $textLen = $label.Length + $value.Length
    $pad = " " * [Math]::Max(0, ($inner - $textLen))
    $valueColor = if ($IsConnected) { "Green" } else { "Red" }

    Write-Host "| " -NoNewline -ForegroundColor Cyan
    Write-Host $label -NoNewline -ForegroundColor Gray
    Write-Host $value -NoNewline -ForegroundColor $valueColor
    Write-Host $pad -NoNewline -ForegroundColor Gray
    Write-Host " |" -ForegroundColor Cyan
}

function Get-DomainMembershipInfo {
    try {
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop

        if ($computerSystem.PartOfDomain -and -not [string]::IsNullOrWhiteSpace($computerSystem.Domain)) {
            return @{
                Type = 'Domain'
                Name = $computerSystem.Domain
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($computerSystem.Workgroup)) {
            return @{
                Type = 'Workgroup'
                Name = $computerSystem.Workgroup
            }
        }

        return @{
            Type = 'None'
            Name = ''
        }
    }
    catch {
        Write-Verbose "Get-DomainMembershipInfo: $_"
        return @{
            Type = 'None'
            Name = ''
        }
    }
}

function Get-DsRegValue {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory=$true)][string]$Key
    )

    $normalizedLines = @($Lines | Where-Object { $_ -ne $null })

    $match = $normalizedLines |
        Where-Object { $_ -match ("^\s*" + [regex]::Escape($Key) + "\s*:\s*") } |
        Select-Object -First 1

    if ($match) {
        return (($match -split ':', 2)[1]).Trim()
    }

    $rawText = ($normalizedLines -join "`n")
    $escapedKey = [regex]::Escape($Key)
    $fallbackMatch = [regex]::Match($rawText, "(?im)^\s*\|?\s*" + $escapedKey + "\s*:\s*(.+?)\s*$")
    if ($fallbackMatch.Success) {
        return $fallbackMatch.Groups[1].Value.Trim()
    }

    return $null
}

function Test-YesValue {
    param(
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    return (($Value.Trim().ToUpperInvariant()) -in @('YES', 'Y', 'TRUE', '1'))
}

function Get-WorkAccountTenantFromDsReg {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
        [string]$PreferredTenantId
    )

    $accounts = @()
    $current = @{ TenantId = ''; TenantName = '' }

    foreach ($line in @($Lines | Where-Object { $_ -ne $null })) {
        if ($line -match '^\s*\|\s*Work Account\s+\d+\s*\|') {
            if (-not [string]::IsNullOrWhiteSpace($current.TenantId) -or -not [string]::IsNullOrWhiteSpace($current.TenantName)) {
                $accounts += @($current)
            }
            $current = @{ TenantId = ''; TenantName = '' }
            continue
        }

        $idMatch = [regex]::Match($line, '^\s*WorkplaceTenantId\s*:\s*(.+?)\s*$')
        if ($idMatch.Success) {
            if (-not [string]::IsNullOrWhiteSpace($current.TenantId) -or -not [string]::IsNullOrWhiteSpace($current.TenantName)) {
                $accounts += @($current)
                $current = @{ TenantId = ''; TenantName = '' }
            }
            $current.TenantId = $idMatch.Groups[1].Value.Trim()
            continue
        }

        $nameMatch = [regex]::Match($line, '^\s*WorkplaceTenantName\s*:\s*(.+?)\s*$')
        if ($nameMatch.Success) {
            $current.TenantName = $nameMatch.Groups[1].Value.Trim()
            continue
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($current.TenantId) -or -not [string]::IsNullOrWhiteSpace($current.TenantName)) {
        $accounts += @($current)
    }

    if ($accounts.Count -eq 0) {
        return @{ TenantId = ''; TenantName = '' }
    }

    if (-not [string]::IsNullOrWhiteSpace($PreferredTenantId)) {
        $exact = $accounts | Where-Object { $_.TenantId -ieq $PreferredTenantId } | Select-Object -First 1
        if ($exact) {
            return $exact
        }
    }

    $named = $accounts | Where-Object { -not [string]::IsNullOrWhiteSpace($_.TenantName) } | Select-Object -First 1
    if ($named) {
        return $named
    }

    return ($accounts | Select-Object -First 1)
}

function Resolve-TenantNameFromCloudDomainJoinRegistry {
    param(
        [string]$TenantId
    )

    if ([string]::IsNullOrWhiteSpace($TenantId)) {
        return $null
    }

    try {
        $basePath = 'HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\TenantInfo'
        if (-not (Test-Path $basePath)) {
            return $null
        }

        $targetPath = Join-Path $basePath $TenantId
        if (-not (Test-Path $targetPath)) {
            return $null
        }

        $props = Get-ItemProperty -Path $targetPath -ErrorAction Stop
        $candidateFields = @('DisplayName', 'TenantName', 'DomainName', 'Name', 'TenantDomain')
        foreach ($field in $candidateFields) {
            if ($props.PSObject.Properties[$field]) {
                $value = [string]$props.$field
                if (-not [string]::IsNullOrWhiteSpace($value) -and ($value -notmatch '^[0-9a-fA-F-]{36}$')) {
                    return $value.Trim()
                }
            }
        }

        return $null
    }
    catch {
        return $null
    }
}

function Ensure-GraphContextForHeader {
    $defaultResult = @{
        Connected = $false
    }

    if (-not (Get-Command Get-MgContext -ErrorAction SilentlyContinue)) {
        return $defaultResult
    }

    if (-not (Get-Command Connect-MgGraph -ErrorAction SilentlyContinue)) {
        return $defaultResult
    }

    if (-not $script:GraphHeaderAuthState) {
        $script:GraphHeaderAuthState = @{
            SilentAttempted = $false
        }
    }

    if (-not $script:GraphHeaderAuthState.SilentAttempted) {
        $script:GraphHeaderAuthState.SilentAttempted = $true

        $enableAutosaveCmd = Get-Command Enable-MgGraphContextAutosave -ErrorAction SilentlyContinue
        if ($enableAutosaveCmd) {
            try {
                Enable-MgGraphContextAutosave -Scope CurrentUser -ErrorAction SilentlyContinue | Out-Null
            }
            catch {
                # Non-blocking: autosave support varies by installed Graph SDK version.
            }
        }
    }

    try {
        $ctx = Get-MgContext -ErrorAction SilentlyContinue
        if ($ctx -and -not [string]::IsNullOrWhiteSpace([string]$ctx.Account)) {
            return @{ Connected = $true }
        }
    }
    catch {
        return $defaultResult
    }

    return $defaultResult
}

function Get-GraphTenantDomainInfo {
    param(
        [string]$TenantId
    )

    $defaultInfo = @{
        DisplayName   = ''
        DefaultDomain = ''
    }

    if (-not (Get-Command Get-MgContext -ErrorAction SilentlyContinue)) {
        return $defaultInfo
    }

    if (-not (Get-Command Get-MgOrganization -ErrorAction SilentlyContinue)) {
        return $defaultInfo
    }

    if (-not $script:GraphTenantDomainCache) {
        $script:GraphTenantDomainCache = @{}
    }

    $cacheKey = if ([string]::IsNullOrWhiteSpace($TenantId)) { '__default__' } else { $TenantId.Trim().ToLowerInvariant() }
    $cacheTtlSeconds = 300

    if ($script:GraphTenantDomainCache.ContainsKey($cacheKey)) {
        $cached = $script:GraphTenantDomainCache[$cacheKey]
        if ($cached -and $cached.Timestamp -and ((New-TimeSpan -Start $cached.Timestamp -End (Get-Date)).TotalSeconds -lt $cacheTtlSeconds)) {
            return $cached.Value
        }
    }

    $ctxState = Ensure-GraphContextForHeader
    if (-not $ctxState.Connected) {
        return $defaultInfo
    }

    try {
        $orgCandidates = @(Get-MgOrganization -ErrorAction Stop)
        if ($orgCandidates.Count -eq 0) {
            return $defaultInfo
        }

        $org = $null
        if (-not [string]::IsNullOrWhiteSpace($TenantId)) {
            $org = $orgCandidates | Where-Object { $_.Id -eq $TenantId } | Select-Object -First 1
        }

        if (-not $org) {
            $org = $orgCandidates | Select-Object -First 1
        }

        if (-not $org) {
            return $defaultInfo
        }

        $defaultDomain = ($org.VerifiedDomains | Where-Object { $_.IsDefault } | Select-Object -First 1).Name
        if ([string]::IsNullOrWhiteSpace($defaultDomain)) {
            $defaultDomain = ($org.VerifiedDomains | Where-Object { $_.IsInitial } | Select-Object -First 1).Name
        }

        $result = @{
            DisplayName   = [string]$org.DisplayName
            DefaultDomain = [string]$defaultDomain
        }

        $script:GraphTenantDomainCache[$cacheKey] = @{
            Timestamp = Get-Date
            Value     = $result
        }

        return $result
    }
    catch {
        return $defaultInfo
    }
}

function Get-EntraJoinInfo {
    $default = @{
        JoinType           = 'Unknown'
        TenantName         = ''
        TenantId           = ''
        WorkplaceJoined    = $false
    }

    try {
        $dsreg = Get-Command dsregcmd.exe -ErrorAction SilentlyContinue
        if (-not $dsreg) {
            return $default
        }

        $lines = @(& dsregcmd.exe /status 2>&1)

        $azureAdJoined = (Get-DsRegValue -Lines $lines -Key 'AzureAdJoined')
        $domainJoined = (Get-DsRegValue -Lines $lines -Key 'DomainJoined')
        $workplaceJoined = (Get-DsRegValue -Lines $lines -Key 'WorkplaceJoined')
        $tenantName = (Get-DsRegValue -Lines $lines -Key 'TenantName')
        $tenantId = (Get-DsRegValue -Lines $lines -Key 'TenantId')
        if ([string]::IsNullOrWhiteSpace($tenantId)) {
            $tenantId = (Get-DsRegValue -Lines $lines -Key 'WorkplaceTenantId')
        }

        $parsedTenantNameGuid = [Guid]::Empty
        if (-not [string]::IsNullOrWhiteSpace($tenantName) -and [Guid]::TryParse($tenantName.Trim(), [ref]$parsedTenantNameGuid)) {
            $tenantName = ''
        }

        if ([string]::IsNullOrWhiteSpace($tenantName) -or [string]::IsNullOrWhiteSpace($tenantId)) {
            $workAccountTenant = Get-WorkAccountTenantFromDsReg -Lines $lines -PreferredTenantId $tenantId
            if ([string]::IsNullOrWhiteSpace($tenantName) -and -not [string]::IsNullOrWhiteSpace($workAccountTenant.TenantName)) {
                $tenantName = $workAccountTenant.TenantName
            }
            if ([string]::IsNullOrWhiteSpace($tenantId) -and -not [string]::IsNullOrWhiteSpace($workAccountTenant.TenantId)) {
                $tenantId = $workAccountTenant.TenantId
            }
        }

        if ([string]::IsNullOrWhiteSpace($tenantName) -and -not [string]::IsNullOrWhiteSpace($tenantId)) {
            $registryTenantName = Resolve-TenantNameFromCloudDomainJoinRegistry -TenantId $tenantId
            if (-not [string]::IsNullOrWhiteSpace($registryTenantName)) {
                $tenantName = $registryTenantName
            }
        }

        $isAzureAdJoined = (Test-YesValue -Value $azureAdJoined)
        $isDomainJoined = (Test-YesValue -Value $domainJoined)
        $isWorkplaceJoined = (Test-YesValue -Value $workplaceJoined)

        $joinType = if ($isAzureAdJoined -and $isDomainJoined) {
            'Hybrid'
        } elseif ($isAzureAdJoined) {
            'Cloud'
        } elseif ($isDomainJoined) {
            'Domain'
        } elseif ($isWorkplaceJoined) {
            'Registered'
        } else {
            'Unknown'
        }

        $result = @{
            JoinType        = $joinType
            TenantName      = $(if ([string]::IsNullOrWhiteSpace($tenantName)) { '' } else { $tenantName })
            TenantId        = $(if ([string]::IsNullOrWhiteSpace($tenantId)) { '' } else { $tenantId })
            WorkplaceJoined = $isWorkplaceJoined
        }

        return $result
    }
    catch {
        Write-Verbose "Get-EntraJoinInfo: $_"
        return $default
    }
}

$script:JoinDisplayInfoCache     = $null
$script:JoinDisplayInfoCacheTime = [datetime]::MinValue

function Get-JoinDisplayInfo {
    $cacheTtl = 60
    if ($null -ne $script:JoinDisplayInfoCache -and
        ([datetime]::Now - $script:JoinDisplayInfoCacheTime).TotalSeconds -lt $cacheTtl) {
        return $script:JoinDisplayInfoCache
    }

    $domainInfo = Get-DomainMembershipInfo
    $entraInfo = Get-EntraJoinInfo

    $tenantText = ''
    if ($entraInfo.JoinType -in @('Hybrid', 'Cloud')) {
        $graphTenant = Get-GraphTenantDomainInfo -TenantId $entraInfo.TenantId
        if (-not [string]::IsNullOrWhiteSpace($graphTenant.DefaultDomain)) {
            $tenantText = $graphTenant.DefaultDomain
        }
        elseif (-not [string]::IsNullOrWhiteSpace($entraInfo.TenantName)) {
            $tenantText = $entraInfo.TenantName
        }
        elseif (-not [string]::IsNullOrWhiteSpace($graphTenant.DisplayName)) {
            $tenantText = $graphTenant.DisplayName
        }
    }

    $joinText = switch ($entraInfo.JoinType) {
        'Hybrid' {
            $domainName = if ($domainInfo.Type -eq 'Domain' -and -not [string]::IsNullOrWhiteSpace($domainInfo.Name)) {
                $domainInfo.Name
            } else {
                ''
            }

            if (-not [string]::IsNullOrWhiteSpace($domainName)) {
                "Hybrid: {0}" -f $domainName
            } else {
                'Hybrid'
            }
        }
        'Cloud' { 'Cloud' }
        'Domain' {
            if ($domainInfo.Type -eq 'Domain' -and -not [string]::IsNullOrWhiteSpace($domainInfo.Name)) {
                $domainInfo.Name
            } else {
                'Domain'
            }
        }
        'Registered' { 'Registered' }
        default {
            switch ($domainInfo.Type) {
                'Domain' { $domainInfo.Name }
                'Workgroup' { 'Workgroup' }
                default { 'None' }
            }
        }
    }

    $compactJoinText = switch ($entraInfo.JoinType) {
        'Hybrid' {
            if ($domainInfo.Type -eq 'Domain' -and -not [string]::IsNullOrWhiteSpace($domainInfo.Name)) {
                "Hybrid: {0}" -f $domainInfo.Name
            } else {
                'Hybrid'
            }
        }
        'Cloud' { 'Cloud' }
        'Domain' {
            if ($entraInfo.WorkplaceJoined) {
                'Domain + Registered'
            } elseif ($domainInfo.Type -eq 'Domain') {
                $domainInfo.Name
            } else {
                'Domain'
            }
        }
        'Registered' { 'Registered' }
        default {
            switch ($domainInfo.Type) {
                'Domain' { $domainInfo.Name }
                'Workgroup' { 'Workgroup' }
                default { 'None' }
            }
        }
    }

    $joinColor = switch ($entraInfo.JoinType) {
        'Hybrid' { 'Green' }
        'Cloud' { 'Green' }
        'Domain' { 'Green' }
        'Registered' { 'Yellow' }
        default {
            switch ($domainInfo.Type) {
                'Domain' { 'Green' }
                'Workgroup' { 'Yellow' }
                default { 'Red' }
            }
        }
    }

    $script:JoinDisplayInfoCache     = @{
        Text        = $joinText
        CompactText = $compactJoinText
        Tenant      = $tenantText
        JoinType    = $entraInfo.JoinType
        Color       = $joinColor
    }
    $script:JoinDisplayInfoCacheTime = [datetime]::Now
    return $script:JoinDisplayInfoCache
}

function Write-DomainLine {
    param(
        [Parameter(Mandatory=$true)][hashtable]$DomainInfo,
        [int]$Width = 64
    )

    $inner = $Width - 4
    $label = "Domain: "

    $value = switch ($DomainInfo.Type) {
        'Domain' { $DomainInfo.Name }
        'Workgroup' { 'Workgroup' }
        default { 'None' }
    }

    $valueColor = switch ($DomainInfo.Type) {
        'Domain' { 'Green' }
        'Workgroup' { 'Yellow' }
        default { 'Red' }
    }

    $maxValueLength = [Math]::Max(0, $inner - $label.Length)
    if ($value.Length -gt $maxValueLength) {
        $value = $value.Substring(0, $maxValueLength)
    }

    $textLen = $label.Length + $value.Length
    $pad = " " * [Math]::Max(0, ($inner - $textLen))

    Write-Host "| " -NoNewline -ForegroundColor Cyan
    Write-Host $label -NoNewline -ForegroundColor Gray
    Write-Host $value -NoNewline -ForegroundColor $valueColor
    Write-Host $pad -NoNewline -ForegroundColor Gray
    Write-Host " |" -ForegroundColor Cyan
}

function Write-InternetDomainLine {
    param(
        [Parameter(Mandatory=$true)][bool]$IsConnected,
        [Parameter(Mandatory=$true)][hashtable]$JoinInfo,
        [int]$Width = 64
    )

    $inner = $Width - 4
    $leftLabel = "Internet: "
    $leftValue = if ($IsConnected) { [char]0x2714 } else { [char]0x2716 }
    $leftColor = if ($IsConnected) { "Green" } else { "Red" }

    $rightLabel = "Join: "
    $rightValue = $JoinInfo.Text
    $rightColor = $JoinInfo.Color

    $rightLabelStart = 24
    $spacerLength = [Math]::Max(1, $rightLabelStart - ($leftLabel.Length + $leftValue.Length))
    $spacer = " " * $spacerLength
    $fixedLength = $leftLabel.Length + $leftValue.Length + $spacerLength + $rightLabel.Length
    $maxRightLength = [Math]::Max(0, $inner - $fixedLength)
    if ($rightValue.Length -gt $maxRightLength) {
        $rightValue = $rightValue.Substring(0, $maxRightLength)
    }

    $textLen = $fixedLength + $rightValue.Length
    $pad = " " * [Math]::Max(0, ($inner - $textLen))

    Write-Host "| " -NoNewline -ForegroundColor Cyan
    Write-Host $leftLabel -NoNewline -ForegroundColor Gray
    Write-Host $leftValue -NoNewline -ForegroundColor $leftColor
    Write-Host $spacer -NoNewline -ForegroundColor Gray
    Write-Host $rightLabel -NoNewline -ForegroundColor Gray
    Write-Host $rightValue -NoNewline -ForegroundColor $rightColor
    Write-Host $pad -NoNewline -ForegroundColor Gray
    Write-Host " |" -ForegroundColor Cyan
}

function Write-TenantLine {
    param(
        [Parameter(Mandatory=$true)][string]$Tenant,
        [int]$Width = 64
    )

    $inner = $Width - 4
    $label = "Tenant: "
    $value = if ([string]::IsNullOrWhiteSpace($Tenant)) { 'N/A' } else { $Tenant }

    $maxValueLength = [Math]::Max(0, $inner - $label.Length)
    if ($value.Length -gt $maxValueLength) {
        $value = $value.Substring(0, $maxValueLength)
    }

    $textLen = $label.Length + $value.Length
    $pad = " " * [Math]::Max(0, ($inner - $textLen))

    Write-Host "| " -NoNewline -ForegroundColor Cyan
    Write-Host $label -NoNewline -ForegroundColor Gray
    Write-Host $value -NoNewline -ForegroundColor Cyan
    Write-Host $pad -NoNewline -ForegroundColor Gray
    Write-Host " |" -ForegroundColor Cyan
}

$script:OSInfoCache              = $null
$script:ServerRolesCache         = $null   # $null = not ready; [string[]] = ready (may be empty)
$script:ServerRolesPowerShell    = $null   # [System.Management.Automation.PowerShell]
$script:ServerRolesRunspace      = $null   # [System.Management.Automation.Runspaces.Runspace]
$script:ServerRolesAsyncResult   = $null   # IAsyncResult from BeginInvoke
$script:ServerRolesDeadline      = [datetime]::MinValue
$script:ServerRolesTimedOut      = $false

function Get-OSInfo {
    if ($null -ne $script:OSInfoCache) { return $script:OSInfoCache }
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $caption = $os.Caption -replace '^Microsoft\s+', ''
        $script:OSInfoCache = @{ Caption = $caption; IsServer = ($caption -match 'Server'); LastBootUpTime = $os.LastBootUpTime }
    }
    catch {
        $script:OSInfoCache = @{ Caption = 'Unknown'; IsServer = $false }
    }
    return $script:OSInfoCache
}

function Get-ServerRoles {
    # Cache hit — already resolved (roles found, empty, or timed out)
    if ($null -ne $script:ServerRolesCache) { return $script:ServerRolesCache }

    # No fetch started yet — open a runspace and begin async invoke.
    # Using a runspace instead of Start-Job so that Get-WindowsFeature's
    # Write-Progress calls are captured in the runspace's own streams
    # rather than leaking to the parent console as a progress bar.
    if ($null -eq $script:ServerRolesPowerShell) {
        $script:ServerRolesRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $script:ServerRolesRunspace.Open()
        $script:ServerRolesPowerShell = [System.Management.Automation.PowerShell]::Create()
        $script:ServerRolesPowerShell.Runspace = $script:ServerRolesRunspace
        $script:ServerRolesPowerShell.AddScript({
            $ProgressPreference = 'SilentlyContinue'
            Get-WindowsFeature -ErrorAction Stop |
                Where-Object { $_.Installed -and $_.FeatureType -eq 'Role' } |
                Select-Object -ExpandProperty DisplayName
        }) | Out-Null
        $script:ServerRolesAsyncResult = $script:ServerRolesPowerShell.BeginInvoke()
        $script:ServerRolesDeadline    = [datetime]::Now.AddSeconds(15)
        return $null
    }

    # Fetch completed — collect results, dispose, and cache
    if ($script:ServerRolesAsyncResult.IsCompleted) {
        try {
            $result = @($script:ServerRolesPowerShell.EndInvoke($script:ServerRolesAsyncResult) |
                        ForEach-Object { [string]$_ })
        } catch { $result = @() }
        $script:ServerRolesPowerShell.Dispose()
        $script:ServerRolesRunspace.Dispose()
        $script:ServerRolesPowerShell  = $null
        $script:ServerRolesRunspace    = $null
        $script:ServerRolesAsyncResult = $null
        $script:ServerRolesCache       = $result
        return $script:ServerRolesCache
    }

    # Deadline exceeded — stop, dispose, and mark timed out
    if ([datetime]::Now -gt $script:ServerRolesDeadline) {
        $script:ServerRolesPowerShell.Stop()
        $script:ServerRolesPowerShell.Dispose()
        $script:ServerRolesRunspace.Dispose()
        $script:ServerRolesPowerShell  = $null
        $script:ServerRolesRunspace    = $null
        $script:ServerRolesAsyncResult = $null
        $script:ServerRolesTimedOut    = $true
        $script:ServerRolesCache       = @()
        return $script:ServerRolesCache
    }

    # Still running — caller shows "Loading..."
    return $null
}

function Write-OSLine {
    param(
        [Parameter(Mandatory=$true)][string]$Caption,
        [int]$Width = 64
    )

    $inner = $Width - 4
    $label = "OS: "
    $value = $Caption

    $maxValueLength = [Math]::Max(0, $inner - $label.Length)
    if ($value.Length -gt $maxValueLength) { $value = $value.Substring(0, $maxValueLength) }

    $pad = " " * [Math]::Max(0, $inner - $label.Length - $value.Length)

    Write-Host "| " -NoNewline -ForegroundColor Cyan
    Write-Host $label -NoNewline -ForegroundColor Gray
    Write-Host $value -NoNewline -ForegroundColor Cyan
    Write-Host $pad -NoNewline -ForegroundColor Gray
    Write-Host " |" -ForegroundColor Cyan
}

function Write-RolesLinePending {
    param([int]$Width = 80)
    $inner = $Width - 4
    $label = "Roles: "
    $text  = "Loading..."
    $pad   = " " * [Math]::Max(0, $inner - $label.Length - $text.Length)
    Write-Host "| " -NoNewline -ForegroundColor Cyan
    Write-Host $label -NoNewline -ForegroundColor Gray
    Write-Host $text -NoNewline -ForegroundColor DarkYellow
    Write-Host $pad -NoNewline -ForegroundColor Gray
    Write-Host " |" -ForegroundColor Cyan
}

function Write-RolesLineTimedOut {
    param([int]$Width = 80)
    $inner = $Width - 4
    $label = "Roles: "
    $text  = "(check timed out)"
    $pad   = " " * [Math]::Max(0, $inner - $label.Length - $text.Length)
    Write-Host "| " -NoNewline -ForegroundColor Cyan
    Write-Host $label -NoNewline -ForegroundColor Gray
    Write-Host $text -NoNewline -ForegroundColor DarkYellow
    Write-Host $pad -NoNewline -ForegroundColor Gray
    Write-Host " |" -ForegroundColor Cyan
}

function Write-RolesLine {
    param(
        [AllowEmptyCollection()][Parameter(Mandatory=$true)][string[]]$Roles,
        [int]$Width = 80
    )

    $inner     = $Width - 4       # usable chars between "| " and " |"
    $label     = "Roles: "        # 7 chars — first line prefix
    $indent    = " " * $label.Length  # continuation lines align under role names
    $maxPerLine = $inner - $label.Length  # chars available for role text per line

    if ($Roles.Count -eq 0) {
        $pad = " " * [Math]::Max(0, $inner - $label.Length - 4)
        Write-Host "| " -NoNewline -ForegroundColor Cyan
        Write-Host $label -NoNewline -ForegroundColor Gray
        Write-Host "None" -NoNewline -ForegroundColor Cyan
        Write-Host $pad -NoNewline -ForegroundColor Gray
        Write-Host " |" -ForegroundColor Cyan
        return
    }

    # Build wrapped lines: greedily pack roles onto each line separated by ", "
    $lines  = [System.Collections.Generic.List[string]]::new()
    $current = ''
    foreach ($role in $Roles) {
        $candidate = if ($current -eq '') { $role } else { "$current, $role" }
        if ($candidate.Length -le $maxPerLine) {
            $current = $candidate
        } else {
            if ($current -ne '') { $lines.Add($current) }
            # If a single role is wider than the line, truncate it
            $current = if ($role.Length -gt $maxPerLine) { $role.Substring(0, $maxPerLine) } else { $role }
        }
    }
    if ($current -ne '') { $lines.Add($current) }

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $prefix = if ($i -eq 0) { $label } else { $indent }
        $text   = $lines[$i]
        $pad    = " " * [Math]::Max(0, $inner - $prefix.Length - $text.Length)
        Write-Host "| " -NoNewline -ForegroundColor Cyan
        Write-Host $prefix -NoNewline -ForegroundColor Gray
        Write-Host $text -NoNewline -ForegroundColor Cyan
        Write-Host $pad -NoNewline -ForegroundColor Gray
        Write-Host " |" -ForegroundColor Cyan
    }
}

$script:GlobalSearchCallback  = $null
$script:AppFooterStatusText  = ""
$script:AppFooterStatusColor = "DarkGray"

function Register-GlobalSearchCallback {
    param([Parameter(Mandatory=$true)][scriptblock]$Callback)
    $script:GlobalSearchCallback = $Callback
}

function Show-AppHeader {
    param(
        [Parameter(Mandatory=$true)][string]$Breadcrumb,
        [int]$Width = 80,
        [string]$StatusText  = "",
        [string]$StatusColor = "DarkGray"
    )

    Clear-Host

    $version  = Get-AppVersion
    $hostName = $env:COMPUTERNAME
    $userName = $env:USERNAME
    $networkInfo = Get-PrimaryNetworkInfo
    $internetConnected = Get-InternetStatus
    $joinInfo = Get-JoinDisplayInfo

    $joinLineInfo = @{
        Text = $joinInfo.Text
        Color = $joinInfo.Color
    }

    Write-Host ("+" + ("-" * ($Width - 2)) + "+") -ForegroundColor Cyan
    Write-BoxLine "CITA Lab Tools - Infrastructure Assistant" $Width "Yellow"
    Write-BoxLine ("Version: {0}" -f $version) $Width "Cyan"

    $osInfo = Get-OSInfo

    # Host/User/OS line
    Write-HostUserLine -HostName $hostName -UserName $userName -OSCaption $osInfo.Caption -Width $Width

    # Uptime line
    Write-UptimeLine -Width $Width

    # Store status for the footer — updated each time Show-AppHeader is called
    $script:AppFooterStatusText  = $StatusText
    $script:AppFooterStatusColor = $StatusColor

    # Primary network line with cyan values
    Write-NetworkLine -IPAddress $networkInfo.IPAddress -Mode $networkInfo.Mode -Width $Width

    # Internet + join status line
    Write-InternetDomainLine -IsConnected $internetConnected -JoinInfo $joinLineInfo -Width $Width

    $normalizedJoinType = ''
    if ($joinInfo.ContainsKey('JoinType') -and $null -ne $joinInfo.JoinType) {
        $normalizedJoinType = ([string]$joinInfo.JoinType).Trim()
    }

    # Timezone/Date line with cyan values
    Write-TimezoneDateLine -Width $Width

    $shouldShowTenantLine = (($normalizedJoinType -in @('Hybrid', 'Cloud')) -or ([string]$joinInfo.Text -match '^(Hybrid|Cloud)')) -and -not [string]::IsNullOrWhiteSpace($joinInfo.Tenant)
    if ($shouldShowTenantLine) {
        Write-TenantLine -Tenant $joinInfo.Tenant -Width $Width
    }

    if ($osInfo.IsServer) {
        $serverRoles = Get-ServerRoles
        if ($null -eq $serverRoles) {
            Write-RolesLinePending -Width $Width
        } elseif ($script:ServerRolesTimedOut) {
            Write-RolesLineTimedOut -Width $Width
        } else {
            Write-RolesLine -Roles $serverRoles -Width $Width
        }
    }

    Write-Host ("+" + ("-" * ($Width - 2)) + "+") -ForegroundColor Cyan

    Write-Host ""
    Write-Host "Navigation: " -NoNewline -ForegroundColor DarkGray
    Write-Host $Breadcrumb -ForegroundColor Cyan
    Write-Host ""
}


function Write-MenuItem {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$true)][string]$Text,
        [string]$Color = "White"
    )
    Write-Host "  [" -NoNewline -ForegroundColor DarkGray
    Write-Host $Key -NoNewline -ForegroundColor Yellow
    Write-Host "] " -NoNewline -ForegroundColor DarkGray
    Write-Host $Text -ForegroundColor $Color
}

function Write-MenuKeysLine {
    param([string]$Range)
    Write-Host "Keys: " -NoNewline -ForegroundColor DarkGray
    Write-Host $Range -NoNewline -ForegroundColor Yellow
    Write-Host " Select  |  " -NoNewline -ForegroundColor DarkGray
    Write-Host "0" -NoNewline -ForegroundColor Yellow
    Write-Host " Back" -ForegroundColor DarkGray
}

function Write-StatusLine {
    param(
        [Parameter(Mandatory=$true)][string]$StatusText,
        [string]$StatusColor = "DarkGray"
    )

    $badgePattern = '^\[(Ready|Running|Warning|Error)\]\s*'
    $hasBadge = [System.Text.RegularExpressions.Regex]::IsMatch($StatusText, $badgePattern)

    if (-not $hasBadge) {
        $badge = switch ($StatusColor) {
            "Cyan" { "[Running]" }
            "Yellow" { "[Warning]" }
            "Red" { "[Error]" }
            default { "[Ready]" }
        }
        $StatusText = "$badge $StatusText"
    }

    Write-Host "Status: " -NoNewline
    Write-Host $StatusText -ForegroundColor $StatusColor
}

function Get-CurrentJoinType {
    try {
        $joinInfo = Get-JoinDisplayInfo
        if ($joinInfo -and $joinInfo.ContainsKey('JoinType') -and -not [string]::IsNullOrWhiteSpace([string]$joinInfo.JoinType)) {
            return ([string]$joinInfo.JoinType).Trim()
        }
    }
    catch {
        Write-Verbose "Get-CurrentJoinType: $_"
        return 'Unknown'
    }

    return 'Unknown'
}

function Write-AppFooter {
    # Draws a pinned 3-row footer at the bottom of the visible window:
    #   Row 1: cyan separator
    #   Row 2: global Ctrl+key shortcuts
    #   Row 3: last status text
    # Cursor is restored to its original position after drawing.
    param([int]$Width = 80)
    try {
        $windowHeight = $host.UI.RawUI.WindowSize.Height
        if ($windowHeight -lt 7) { return }

        $savedTop  = [Console]::CursorTop
        $savedLeft = [Console]::CursorLeft

        $separatorRow = $windowHeight - 4
        $shortcutRow  = $windowHeight - 3
        $statusRow    = $windowHeight - 2

        # Only draw if footer rows are below current cursor (room exists)
        if ($separatorRow -le $savedTop) { return }

        [Console]::SetCursorPosition(0, $separatorRow)
        Write-Host ("-" * $Width) -ForegroundColor Cyan

        [Console]::SetCursorPosition(0, $shortcutRow)
        Write-Host "  " -NoNewline
        Write-Host "^S" -NoNewline -ForegroundColor Yellow
        Write-Host " Search  |  " -NoNewline -ForegroundColor DarkGray
        Write-Host "^R" -NoNewline -ForegroundColor Yellow
        Write-Host " Reboot  " -NoNewline -ForegroundColor DarkGray
        Write-Host "^P" -NoNewline -ForegroundColor Yellow
        Write-Host " Shutdown  " -NoNewline -ForegroundColor DarkGray
        Write-Host "^L" -NoNewline -ForegroundColor Yellow
        Write-Host " Lock  " -NoNewline -ForegroundColor DarkGray
        Write-Host "^T" -NoNewline -ForegroundColor Yellow
        Write-Host " Task Mgr  " -NoNewline -ForegroundColor DarkGray
        Write-Host "^N" -NoNewline -ForegroundColor Yellow
        Write-Host " New Tab" -ForegroundColor DarkGray

        [Console]::SetCursorPosition(0, $statusRow)
        $statusText  = $script:AppFooterStatusText
        $statusColor = $script:AppFooterStatusColor
        if ([string]::IsNullOrWhiteSpace($statusText)) {
            Write-Host (' ' * $Width) -NoNewline
        } else {
            Write-Host "  " -NoNewline
            Write-Host "Status: " -NoNewline -ForegroundColor DarkGray
            $maxLen  = $Width - 12
            if ($statusText.Length -gt $maxLen) { $statusText = $statusText.Substring(0, $maxLen) }
            $pad = ' ' * ($Width - 10 - $statusText.Length)
            Write-Host $statusText -NoNewline -ForegroundColor $statusColor
            Write-Host $pad -NoNewline
        }

        [Console]::SetCursorPosition($savedLeft, $savedTop)
    } catch {}
}

function Read-PowerConfirmation {
    param([string]$Action)
    $savedTop = [Console]::CursorTop
    Write-Host ""
    Write-Host "  $Action this machine? Press " -NoNewline -ForegroundColor Yellow
    Write-Host "Y" -NoNewline -ForegroundColor Red
    Write-Host " to confirm or any other key to cancel: " -NoNewline -ForegroundColor Yellow

    $confirmed = $false
    while ($true) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            $confirmed = ($key.KeyChar.ToString().ToLower() -eq 'y')
            break
        }
        Start-Sleep -Milliseconds 100
    }

    # Clear the confirmation line
    $clearedTop = [Console]::CursorTop
    for ($row = $savedTop; $row -le $clearedTop; $row++) {
        [Console]::SetCursorPosition(0, $row)
        Write-Host (' ' * 80) -NoNewline
    }
    [Console]::SetCursorPosition(0, $savedTop)

    return $confirmed
}

function Invoke-PowerShortcut {
    # Called from Read-MenuChoice and Read-MainMenuChoice with the raw ConsoleKeyInfo.
    # Returns $true if the key was a handled Ctrl+shortcut, $false otherwise.
    param([Parameter(Mandatory=$true)][System.ConsoleKeyInfo]$Key)

    $isCtrl = ($Key.Modifiers -band [System.ConsoleModifiers]::Control) -ne 0
    if (-not $isCtrl) { return $false }

    switch ($Key.Key.ToString()) {
        'R' {
            if (Read-PowerConfirmation -Action 'Reboot') {
                try { Restart-Computer -Force } catch { Write-Host "  Reboot failed: $($_.Exception.Message)" -ForegroundColor Red; Start-Sleep 2 }
            }
            return $true
        }
        'P' {
            if (Read-PowerConfirmation -Action 'Shut down') {
                try { Stop-Computer -Force } catch { Write-Host "  Shutdown failed: $($_.Exception.Message)" -ForegroundColor Red; Start-Sleep 2 }
            }
            return $true
        }
        'L' {
            try { rundll32.exe user32.dll,LockWorkStation } catch {}
            return $true
        }
        'T' {
            try { Start-Process taskmgr.exe } catch {}
            return $true
        }
        'S' {
            if ($null -ne $script:GlobalSearchCallback) {
                & $script:GlobalSearchCallback
            }
            return $true
        }
        'N' {
            try {
                $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
                if ($wt) {
                    Start-Process -FilePath $wt.Source -ArgumentList @("-w", "0", "new-tab")
                } else {
                    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
                    if ($pwsh) {
                        Start-Process -FilePath $pwsh.Source -ArgumentList @("-NoLogo")
                    } else {
                        Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @("-NoLogo")
                    }
                }
            } catch {}
            return $true
        }
    }
    return $false
}

function Read-MenuChoice {
    # Single-keypress input. Ctrl+R/P/L/T are intercepted globally as power shortcuts.
    Write-AppFooter
    Write-Host "Select an option: " -NoNewline
    while ($true) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if (Invoke-PowerShortcut -Key $key) {
                Write-AppFooter
                Write-Host "Select an option: " -NoNewline
                continue
            }
            Write-Host $key.KeyChar
            return $key.KeyChar.ToString()
        }
        Start-Sleep -Milliseconds 100
    }
}

function Clear-JoinDisplayInfoCache {
    $script:JoinDisplayInfoCache     = $null
    $script:JoinDisplayInfoCacheTime = [datetime]::MinValue
}

Export-ModuleMember -Function Get-AppVersion, Write-BoxLine, Write-TimezoneDateLine, Write-UptimeLine, Show-AppHeader, Write-StatusLine, Get-CurrentJoinType, Write-MenuItem, Write-MenuKeysLine, Clear-JoinDisplayInfoCache, Read-MenuChoice, Get-InternetStatus, Write-AppFooter, Invoke-PowerShortcut, Register-GlobalSearchCallback

