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

    $leftLabel = "Host: "
    $rightLabel = "User: "
    $rightLabelStart = 24

    $maxHostLength = [Math]::Max(0, $rightLabelStart - $leftLabel.Length)
    if ($HostName.Length -gt $maxHostLength) {
        $HostName = $HostName.Substring(0, $maxHostLength)
    }

    $spacerLength = [Math]::Max(1, $rightLabelStart - ($leftLabel.Length + $HostName.Length))
    $spacer = " " * $spacerLength

    $fixedLength = $leftLabel.Length + $HostName.Length + $spacerLength + $rightLabel.Length
    $maxUserLength = [Math]::Max(0, $inner - $fixedLength)
    if ($UserName.Length -gt $maxUserLength) {
        $UserName = $UserName.Substring(0, $maxUserLength)
    }

    $textLen = $fixedLength + $UserName.Length
    $pad = " " * [Math]::Max(0, ($inner - $textLen))

    Write-Host "| " -NoNewline -ForegroundColor Gray
    Write-Host $leftLabel -NoNewline -ForegroundColor Gray
    Write-Host $HostName -NoNewline -ForegroundColor Cyan
    Write-Host $spacer -NoNewline -ForegroundColor Gray
    Write-Host $rightLabel -NoNewline -ForegroundColor Gray
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

    Write-Host "| " -NoNewline -ForegroundColor Gray
    Write-Host $labelTZ -NoNewline -ForegroundColor Gray
    Write-Host $timeZoneStr -NoNewline -ForegroundColor Cyan
    Write-Host $labelDate -NoNewline -ForegroundColor Gray
    Write-Host $currentDate -NoNewline -ForegroundColor Cyan
    Write-Host $pad -NoNewline -ForegroundColor Gray
    Write-Host " |" -ForegroundColor Gray
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

    Write-Host "| " -NoNewline -ForegroundColor Gray
    Write-Host $leftLabel -NoNewline -ForegroundColor Gray
    Write-Host $IPAddress -NoNewline -ForegroundColor Cyan
    Write-Host $spacer -NoNewline -ForegroundColor Gray
    Write-Host $rightLabel -NoNewline -ForegroundColor Gray
    Write-Host $Mode -NoNewline -ForegroundColor Cyan
    Write-Host $pad -NoNewline -ForegroundColor Gray
    Write-Host " |" -ForegroundColor Gray
}

function Get-InternetStatus {
    try {
        $connectTask = [System.Net.Dns]::GetHostAddressesAsync('www.msftconnecttest.com')
        $completed = $connectTask.Wait(1500)

        if (-not $completed) {
            return $false
        }

        $addresses = $connectTask.Result
        return ($addresses -and $addresses.Count -gt 0)
    }
    catch {
        return $false
    }
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

    Write-Host "| " -NoNewline -ForegroundColor Gray
    Write-Host $label -NoNewline -ForegroundColor Gray
    Write-Host $value -NoNewline -ForegroundColor $valueColor
    Write-Host $pad -NoNewline -ForegroundColor Gray
    Write-Host " |" -ForegroundColor Gray
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
        return $default
    }
}

function Get-JoinDisplayInfo {
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

    return @{
        Text        = $joinText
        CompactText = $compactJoinText
        Tenant      = $tenantText
        JoinType    = $entraInfo.JoinType
        Color       = $joinColor
    }
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

    Write-Host "| " -NoNewline -ForegroundColor Gray
    Write-Host $label -NoNewline -ForegroundColor Gray
    Write-Host $value -NoNewline -ForegroundColor $valueColor
    Write-Host $pad -NoNewline -ForegroundColor Gray
    Write-Host " |" -ForegroundColor Gray
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

    Write-Host "| " -NoNewline -ForegroundColor Gray
    Write-Host $leftLabel -NoNewline -ForegroundColor Gray
    Write-Host $leftValue -NoNewline -ForegroundColor $leftColor
    Write-Host $spacer -NoNewline -ForegroundColor Gray
    Write-Host $rightLabel -NoNewline -ForegroundColor Gray
    Write-Host $rightValue -NoNewline -ForegroundColor $rightColor
    Write-Host $pad -NoNewline -ForegroundColor Gray
    Write-Host " |" -ForegroundColor Gray
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

    Write-Host "| " -NoNewline -ForegroundColor Gray
    Write-Host $label -NoNewline -ForegroundColor Gray
    Write-Host $value -NoNewline -ForegroundColor Cyan
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
    $networkInfo = Get-PrimaryNetworkInfo
    $internetConnected = Get-InternetStatus
    $joinInfo = Get-JoinDisplayInfo

    $joinLineInfo = @{
        Text = $joinInfo.Text
        Color = $joinInfo.Color
    }

    Write-Host ("+" + ("-" * ($Width - 2)) + "+") -ForegroundColor DarkGray
    Write-BoxLine "CITA Lab Tools - Infrastructure Assistant" $Width "Cyan"
    Write-BoxLine ("Version: {0}" -f $version) $Width "Gray"

    # Host/User line with cyan values
    Write-HostUserLine -HostName $hostName -UserName $userName -Width $Width

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

    $shouldShowTenantLine = ($normalizedJoinType -in @('Hybrid', 'Cloud')) -or ([string]$joinInfo.Text -match '^(Hybrid|Cloud)')
    if ($shouldShowTenantLine) {
        Write-TenantLine -Tenant $joinInfo.Tenant -Width $Width
    }

    Write-Host ("+" + ("-" * ($Width - 2)) + "+") -ForegroundColor DarkGray

    Write-Host ""
    Write-Host "Navigation: " -NoNewline -ForegroundColor DarkGray
    Write-Host $Breadcrumb -ForegroundColor Cyan
    Write-Host ""
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
        return 'Unknown'
    }

    return 'Unknown'
}

Export-ModuleMember -Function Get-AppVersion, Write-BoxLine, Write-TimezoneDateLine, Show-AppHeader, Write-StatusLine, Get-CurrentJoinType

