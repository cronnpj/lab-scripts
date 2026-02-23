# src\Tasks\Apply-TerminalBackground.ps1
$ErrorActionPreference = "Stop"

function Set-OrAddProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Value
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    }
    else {
        $Object.$Name = $Value
    }
}

$srcRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $srcRoot "config\terminal-background.json"

if (-not (Test-Path $configPath)) {
    throw "Terminal background config not found: $configPath"
}

$config = Get-Content -Path $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$imagePath = Join-Path $srcRoot $config.imageRelativePath

if (-not (Test-Path $imagePath)) {
    throw "Background image not found: $imagePath"
}

$settingsCandidates = @(
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
)

$settingsPath = $settingsCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $settingsPath) {
    throw "Windows Terminal settings.json not found on this machine."
}

$raw = Get-Content -Path $settingsPath -Raw -Encoding UTF8
$json = $null

if (-not [string]::IsNullOrWhiteSpace($raw)) {
    try {
        $json = $raw | ConvertFrom-Json
    }
    catch {
        $json = $null
    }
}

if ($null -eq $json) {
    $json = [pscustomobject]@{
        '$schema' = 'https://aka.ms/terminal-profiles-schema'
        profiles  = [pscustomobject]@{
            defaults = [pscustomobject]@{}
        }
    }
}

if ($null -eq $json.profiles) {
    Set-OrAddProperty -Object $json -Name "profiles" -Value ([pscustomobject]@{})
}

if ($null -eq $json.profiles.defaults) {
    Set-OrAddProperty -Object $json.profiles -Name "defaults" -Value ([pscustomobject]@{})
}

$opacity = [double]$config.opacity
Set-OrAddProperty -Object $json.profiles.defaults -Name "backgroundImage" -Value $imagePath
Set-OrAddProperty -Object $json.profiles.defaults -Name "backgroundImageOpacity" -Value $opacity
Set-OrAddProperty -Object $json.profiles.defaults -Name "backgroundImageStretchMode" -Value ([string]$config.stretchMode)
Set-OrAddProperty -Object $json.profiles.defaults -Name "backgroundImageAlignment" -Value ([string]$config.alignment)

$backupPath = "$settingsPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
if (Test-Path $settingsPath) {
    Copy-Item -Path $settingsPath -Destination $backupPath -Force
}

$out = $json | ConvertTo-Json -Depth 100
Set-Content -Path $settingsPath -Value $out -Encoding UTF8

Write-Host "Windows Terminal background applied from repo config." -ForegroundColor Green
Write-Host "Config:   $configPath"
Write-Host "Settings: $settingsPath"
Write-Host "Image:    $imagePath"
Write-Host "Backup:   $backupPath"
