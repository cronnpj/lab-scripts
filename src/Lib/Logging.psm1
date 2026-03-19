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

    $line = "{0} [{1}] [{2}] {3}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $env:USERNAME, $Message
    Add-Content -Path $script:LabLogPath -Value $line
}

function Get-LabLogPath {
    if (-not $script:LabLogPath) { Initialize-LabLog }
    return $script:LabLogPath
}
