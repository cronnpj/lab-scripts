param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("ADDS","DNS","DHCP","CORE_DC")]
    [string]$Mode
)

$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "..\Lib\Logging.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "..\Lib\Validation.psm1") -Force

Initialize-LabLog
Assert-IsAdmin

function Install-FeatureSafe {
    param([Parameter(Mandatory=$true)][string]$Name)

    $feature = Get-WindowsFeature -Name $Name
    if ($feature -and $feature.Installed) {
        Write-LabLog "Feature already installed: $Name"
        return
    }

    Write-LabLog "Installing feature: $Name"
    $result = Install-WindowsFeature -Name $Name -IncludeManagementTools

    if (-not $result.Success) {
        Write-LabLog "Install-WindowsFeature failed for: $Name" "ERROR"
        throw "Install-WindowsFeature failed for $Name"
    }

    Write-LabLog "Installed feature: $Name"
}

switch ($Mode) {
    "ADDS"    { Install-FeatureSafe -Name "AD-Domain-Services" }
    "DNS"     { Install-FeatureSafe -Name "DNS" }
    "DHCP"    { Install-FeatureSafe -Name "DHCP" }
    "CORE_DC" {
        Install-FeatureSafe -Name "AD-Domain-Services"
        Install-FeatureSafe -Name "DNS"
        Install-FeatureSafe -Name "DHCP"
    }
}

Write-Host ""
Write-Host "Done."
Write-Host "Note: No AD promotion or DHCP scope configuration is performed. Students must complete configuration manually."
Write-Host ("Log: {0}" -f (Get-LabLogPath))
