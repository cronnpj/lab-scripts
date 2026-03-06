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

function Resolve-TenantNameFromTenantId {
    param(
        [string]$TenantId
    )

    if ([string]::IsNullOrWhiteSpace($TenantId)) {
        return $null
    }

    $normalizedTenantId = $TenantId.Trim()
    $parsedGuid = [Guid]::Empty
    if (-not [Guid]::TryParse($normalizedTenantId, [ref]$parsedGuid)) {
        return $null
    }

    try {
        $uri = "https://login.microsoftonline.com/$normalizedTenantId/v2.0/.well-known/openid-configuration"
        $oidc = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 4 -ErrorAction Stop
        $tokenEndpoint = [string]$oidc.token_endpoint
        if ([string]::IsNullOrWhiteSpace($tokenEndpoint)) {
            return $null
        }

        $segments = $tokenEndpoint -split '/'
        if ($segments.Length -gt 3) {
            $tenantName = $segments[3]
            if (-not [string]::IsNullOrWhiteSpace($tenantName) -and ($tenantName -ne $normalizedTenantId)) {
                return $tenantName
            }
        }

        return $null
    }
    catch {
        return $null
    }
}

function Resolve-TenantNameFromGraphContext {
    param(
        [string]$TenantId
    )

    if ([string]::IsNullOrWhiteSpace($TenantId)) {
        return $null
    }

    $normalizedTenantId = $TenantId.Trim()
    $parsedGuid = [Guid]::Empty
    if (-not [Guid]::TryParse($normalizedTenantId, [ref]$parsedGuid)) {
        return $null
    }

    $getMgContextCmd = Get-Command Get-MgContext -ErrorAction SilentlyContinue
    $getMgOrganizationCmd = Get-Command Get-MgOrganization -ErrorAction SilentlyContinue
    if (-not $getMgContextCmd -or -not $getMgOrganizationCmd) {
        return $null
    }

    try {
        $ctx = Get-MgContext -ErrorAction Stop
        if (-not $ctx -or [string]::IsNullOrWhiteSpace($ctx.Account)) {
            return $null
        }

        $org = $null
        try {
            $org = Get-MgOrganization -OrganizationId $normalizedTenantId -ErrorAction Stop | Select-Object -First 1
        }
        catch {
            $org = Get-MgOrganization -ErrorAction Stop | Select-Object -First 1
        }

        if ($org -and -not [string]::IsNullOrWhiteSpace($org.DisplayName)) {
            return $org.DisplayName
        }

        if ($org -and $org.VerifiedDomains) {
            $defaultDomain = $org.VerifiedDomains | Where-Object { $_.IsDefault } | Select-Object -First 1
            if ($defaultDomain -and -not [string]::IsNullOrWhiteSpace($defaultDomain.Name)) {
                return $defaultDomain.Name
            }

            $anyDomain = $org.VerifiedDomains | Select-Object -First 1
            if ($anyDomain -and -not [string]::IsNullOrWhiteSpace($anyDomain.Name)) {
                return $anyDomain.Name
            }
        }

        return $null
    }
    catch {
        return $null
    }
}

function Get-EntraJoinInfo {
    if ($script:JoinInfoCache -and $script:JoinInfoCache.Timestamp -and (((Get-Date) - $script:JoinInfoCache.Timestamp).TotalSeconds -lt 60)) {
        return $script:JoinInfoCache.Data
    }

    $default = @{
        JoinType           = 'Unknown'
        TenantName         = ''
        TenantId           = ''
        WorkplaceJoined    = $false
    }

    try {
        $dsreg = Get-Command dsregcmd.exe -ErrorAction SilentlyContinue
        if (-not $dsreg) {
            $script:JoinInfoCache = @{ Timestamp = Get-Date; Data = $default }
            return $default
        }

        $lines = @(& dsregcmd.exe /status 2>&1)

        $azureAdJoined = (Get-DsRegValue -Lines $lines -Key 'AzureAdJoined')
        $domainJoined = (Get-DsRegValue -Lines $lines -Key 'DomainJoined')
        $workplaceJoined = (Get-DsRegValue -Lines $lines -Key 'WorkplaceJoined')
        $tenantName = (Get-DsRegValue -Lines $lines -Key 'TenantName')
        if ([string]::IsNullOrWhiteSpace($tenantName)) {
            $tenantName = (Get-DsRegValue -Lines $lines -Key 'WorkplaceTenantName')
        }
        $tenantId = (Get-DsRegValue -Lines $lines -Key 'TenantId')
        if ([string]::IsNullOrWhiteSpace($tenantId)) {
            $tenantId = (Get-DsRegValue -Lines $lines -Key 'WorkplaceTenantId')
        }

        if ([string]::IsNullOrWhiteSpace($tenantName) -and -not [string]::IsNullOrWhiteSpace($tenantId)) {
            $resolvedTenantName = Resolve-TenantNameFromTenantId -TenantId $tenantId
            if (-not [string]::IsNullOrWhiteSpace($resolvedTenantName)) {
                $tenantName = $resolvedTenantName
            }
        }

        if ([string]::IsNullOrWhiteSpace($tenantName) -and -not [string]::IsNullOrWhiteSpace($tenantId)) {
            $resolvedTenantName = Resolve-TenantNameFromGraphContext -TenantId $tenantId
            if (-not [string]::IsNullOrWhiteSpace($resolvedTenantName)) {
                $tenantName = $resolvedTenantName
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

        $script:JoinInfoCache = @{ Timestamp = Get-Date; Data = $result }
        return $result
    }
    catch {
        $script:JoinInfoCache = @{ Timestamp = Get-Date; Data = $default }
        return $default
    }
}

function Get-JoinDisplayInfo {
    $domainInfo = Get-DomainMembershipInfo
    $entraInfo = Get-EntraJoinInfo
    $tenantDisplay = if (-not [string]::IsNullOrWhiteSpace($entraInfo.TenantName)) {
        $entraInfo.TenantName
    } elseif (-not [string]::IsNullOrWhiteSpace($entraInfo.TenantId)) {
        $entraInfo.TenantId
    } else {
        ''
    }

    $joinText = switch ($entraInfo.JoinType) {
        'Hybrid' {
            $domainName = if ($domainInfo.Type -eq 'Domain' -and -not [string]::IsNullOrWhiteSpace($domainInfo.Name)) {
                $domainInfo.Name
            } else {
                ''
            }

            if (-not [string]::IsNullOrWhiteSpace($domainName) -and -not [string]::IsNullOrWhiteSpace($tenantDisplay)) {
                "Hybrid: {0} ({1})" -f $domainName, $tenantDisplay
            } elseif (-not [string]::IsNullOrWhiteSpace($domainName)) {
                "Hybrid: {0}" -f $domainName
            } elseif ([string]::IsNullOrWhiteSpace($tenantDisplay)) {
                'Hybrid'
            } else {
                "Hybrid ({0})" -f $tenantDisplay
            }
        }
        'Cloud' {
            if ([string]::IsNullOrWhiteSpace($tenantDisplay)) {
                'Cloud'
            } else {
                "Cloud ({0})" -f $tenantDisplay
            }
        }
        'Domain' {
            if ($entraInfo.WorkplaceJoined) {
                if ([string]::IsNullOrWhiteSpace($tenantDisplay)) {
                    'Domain + Registered'
                } else {
                    "Domain + Registered ({0})" -f $tenantDisplay
                }
            } elseif ($domainInfo.Type -eq 'Domain') {
                if ([string]::IsNullOrWhiteSpace($tenantDisplay)) {
                    $domainInfo.Name
                } else {
                    "{0} ({1})" -f $domainInfo.Name, $tenantDisplay
                }
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
        Tenant      = $tenantDisplay
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

    $joinTextForHeader = $joinInfo.Text
    $showTenantLine = $false
    $tenantForLine = $joinInfo.Tenant

    $inner = $Width - 4
    $leftLabel = "Internet: "
    $leftValue = [char]0x2714
    $rightLabel = "Join: "
    $rightLabelStart = 24
    $spacerLength = [Math]::Max(1, $rightLabelStart - ($leftLabel.Length + $leftValue.Length))
    $fixedLength = $leftLabel.Length + $leftValue.Length + $spacerLength + $rightLabel.Length
    $maxInlineJoinLength = [Math]::Max(0, $inner - $fixedLength)

    if (-not [string]::IsNullOrWhiteSpace($tenantForLine) -and $joinInfo.Text.Length -gt $maxInlineJoinLength) {
        $joinTextForHeader = $joinInfo.CompactText
        $showTenantLine = $true
    }

    $joinLineInfo = @{
        Text = $joinTextForHeader
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

    # Timezone/Date line with cyan values
    Write-TimezoneDateLine -Width $Width

    # Tenant line for long join strings
    if ($showTenantLine) {
        Write-TenantLine -Tenant $tenantForLine -Width $Width
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

Export-ModuleMember -Function Get-AppVersion, Write-BoxLine, Write-TimezoneDateLine, Show-AppHeader, Write-StatusLine

