function Write-LabLog {
    param (
        [string]$Message
    )

    $logPath = "C:\LabLogs\labtools.log"

    if (-not (Test-Path "C:\LabLogs")) {
        New-Item -Path "C:\LabLogs" -ItemType Directory | Out-Null
    }

    Add-Content -Path $logPath -Value "$(Get-Date) - $Message"
}
function Initialize-LabLog {
    param(
        [string]$LogDir = "C:\LabLogs",
        [string]$LogFile = "labtools.log"
    )

    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }

    $script:LabLogPath = Join-Path $LogDir $LogFile
    if (-not (Test-Path $script:LabLogPath)) {
        New-Item -Path $script:LabLogPath -ItemType File -Force | Out-Null
    }
}

function Write-LabLog {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO","WARN","ERROR")][string]$Level = "INFO"
    )

    if (-not $script:LabLogPath) { Initialize-LabLog }

    $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Add-Content -Path $script:LabLogPath -Value $line
}

function Get-LabLogPath {
    if (-not $script:LabLogPath) { Initialize-LabLog }
    return $script:LabLogPath
}
