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
    param([string]$Name)

    $feature = Get-WindowsFeature -Name $Name
    if ($feature.Installed) {
        Write-LabLog "Feature already installed: $Name"
        return
    }

    Write-LabLog "Installing feature: $Name"
    $result = Install-WindowsFeature -Name $Name -IncludeManagementTools
    if (-not $result.Success) {
        Write-LabLog "Failed installing feature: $Name" "ERROR"
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

Write-Host "Done. (No promotion/config performed—students must complete that manually.)"
Write-Host "Log: $(Get-LabLogPath)"
