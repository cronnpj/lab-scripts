# src\Tasks\Update-LabTools.ps1
# In-place updater model:
# - Pulls latest changes in the currently running repo root
# - Does not create/clone/deploy to C:\CITA cache/runtime folders
# Always shows errors and pauses (no silent window close)

$ErrorActionPreference = "Stop"
$RuntimeRoot = Split-Path -Parent $PSScriptRoot

function Wait-MenuContinue {
    Write-Host ""
    Read-Host "Press Enter to continue"
}

function Assert-IsAdmin {
    $current = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $current.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This updater must be run as Administrator."
    }
}

function Ensure-Git {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "git is not installed. Install Git for Windows first (winget install --id Git.Git -e)."
    }
}

function Is-GitRepo([string]$Path) {
    if (-not (Test-Path $Path)) { return $false }
    $out = git -C $Path rev-parse --is-inside-work-tree 2>$null
    return ($LASTEXITCODE -eq 0 -and $out.Trim() -eq "true")
}

function Repair-KnownLabDrift([string]$Path) {
    $knownTrackedPaths = @(
        "labs/k8s-baremetal-lab/01-talos/student-overrides/README.md"
    )

    foreach ($knownTrackedPath in $knownTrackedPaths) {
        try {
            # Skip if the file doesn't exist in HEAD on this machine (older repo state)
            git -C $Path cat-file -e "HEAD:$knownTrackedPath" 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { continue }

            $prev = $ErrorActionPreference
            $ErrorActionPreference = "SilentlyContinue"
            git -C $Path restore --worktree --staged --source=HEAD -- $knownTrackedPath 2>$null | Out-Null
            $ErrorActionPreference = $prev
        }
        catch {
            # Non-blocking: drift repair is best-effort
        }
    }
}

function Test-IsAllowedStudentDemoChange([string]$PorcelainLine) {
    if ([string]::IsNullOrWhiteSpace($PorcelainLine)) { return $true }

    $line = $PorcelainLine.TrimEnd()
    $allowedPrefix = "labs/k8s-baremetal-lab/05-web-demo/"

    if ($line -match "->\s*(.+)$") {
        $renamedTarget = $Matches[1].Trim()
        return $renamedTarget.Replace('\\','/') -like "$allowedPrefix*"
    }

    if ($line.Length -ge 4) {
        $path = $line.Substring(3).Trim().Replace('\\','/')
        return $path -like "$allowedPrefix*"
    }

    return $false
}

function Pull-InPlace([string]$Path) {
    Repair-KnownLabDrift -Path $Path

    $localChanges = @(git -C $Path status --porcelain 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to inspect git status in '$Path'."
    }

    $pullWithAutostash = $false
    if ($localChanges.Count -gt 0) {
        $allAllowedStudentChanges = $true
        foreach ($line in $localChanges) {
            if (-not (Test-IsAllowedStudentDemoChange -PorcelainLine $line)) {
                $allAllowedStudentChanges = $false
                break
            }
        }

        if (-not $allAllowedStudentChanges) {
            Write-Host "Local changes detected in ${Path}:" -ForegroundColor Yellow
            $localChanges | Out-Host
            throw "Update blocked: local uncommitted changes exist. Commit, stash, or discard changes, then run update again."
        }

        Write-Host "Student demo file changes detected. Proceeding with update using autostash." -ForegroundColor Yellow
        $pullWithAutostash = $true
    }

    Write-Host "Pulling latest changes in $Path ..."
    git -C $Path fetch --all | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Git fetch failed in '$Path'."
    }

    if ($pullWithAutostash) {
        git -C $Path pull --rebase --autostash | Out-Host
    }
    else {
        git -C $Path pull | Out-Host
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Git pull failed in '$Path'."
    }
}

function Invoke-PostUpdateTerminalBackground {
    $destRootCandidates = @($RuntimeRoot)

    $candidates = @(
        (Join-Path $PSScriptRoot "Apply-TerminalBackground.ps1"),
        (Join-Path (Split-Path -Parent $PSScriptRoot) "Tasks\Apply-TerminalBackground.ps1")
    )

    foreach ($root in $destRootCandidates) {
        $candidates += (Join-Path $root "Tasks\Apply-TerminalBackground.ps1")
    }

    $applyScript = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $applyScript) {
        Write-Host "Post-update: terminal background task not found, skipping." -ForegroundColor DarkYellow
        return
    }

    try {
        Write-Host "Post-update: applying Windows Terminal background from repo config..."
        Write-Host "Post-update: using task script: $applyScript" -ForegroundColor DarkGray
        & $applyScript
    }
    catch {
        Write-Host "Post-update: terminal background apply failed (non-blocking)." -ForegroundColor DarkYellow
        Write-Host $_.Exception.Message -ForegroundColor DarkYellow
    }
}

function Invoke-PostUpdateShortcuts {
    $destRootCandidates = @($RuntimeRoot)

    $candidates = @(
        (Join-Path $PSScriptRoot "Create-Shortcuts.ps1"),
        (Join-Path (Split-Path -Parent $PSScriptRoot) "Tasks\Create-Shortcuts.ps1")
    )

    foreach ($root in $destRootCandidates) {
        $candidates += (Join-Path $root "Tasks\Create-Shortcuts.ps1")
    }

    $shortcutScript = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $shortcutScript) {
        Write-Host "Post-update: shortcut task not found, skipping." -ForegroundColor DarkYellow
        return
    }

    try {
        Write-Host "Post-update: creating/repairing Lab Tools shortcuts..."
        Write-Host "Post-update: using task script: $shortcutScript" -ForegroundColor DarkGray
        & $shortcutScript
    }
    catch {
        Write-Host "Post-update: shortcut creation/repair failed (non-blocking)." -ForegroundColor DarkYellow
        Write-Host $_.Exception.Message -ForegroundColor DarkYellow
    }
}

# =========
# RUN
# =========
try {
    $script:updateFailed = $false
    $script:suppressFinalPause = $false

    Assert-IsAdmin
    Ensure-Git
    if (-not (Is-GitRepo $RuntimeRoot)) {
        throw "Update unavailable: runtime root is not a git repository ('$RuntimeRoot'). Run Lab Tools from a cloned repo for in-place updates."
    }

    Write-Host "Updating in-place from runtime repo: $RuntimeRoot"
    Pull-InPlace $RuntimeRoot
    Invoke-PostUpdateShortcuts
    Invoke-PostUpdateTerminalBackground

    $verFile = Join-Path $RuntimeRoot "VERSION.txt"
    $ver = if (Test-Path $verFile) { (Get-Content $verFile | Select-Object -First 1).Trim() } else { "unknown" }

    Write-Host ""
    Write-Host "Update complete. Version: $ver" -ForegroundColor Green

    # What's new: show last 5 commits
    $recentLog = git -C $RuntimeRoot log --oneline -5 2>$null
    if ($recentLog) {
        Write-Host ""
        Write-Host "What's new (recent commits):" -ForegroundColor Cyan
        $recentLog | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    }

    # Offer to relaunch
    Write-Host ""
    $relaunch = Read-Host "Relaunch Lab Tools now? (Y/N)"
    if ($relaunch -match '^(?i)y(es)?$') {
        $launcher = Join-Path $RuntimeRoot "Launch-LabTools.ps1"
        if (Test-Path $launcher) {
            Write-Host "Relaunching..." -ForegroundColor Cyan
            Start-Sleep -Milliseconds 500
            $script:suppressFinalPause = $true
            # Spawn an independent process so the new session gets fresh code.
            # & $launcher would nest inside the current session and leave stale code loaded.
            $shell = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { "pwsh.exe" } else { "powershell.exe" }
            Start-Process -FilePath $shell -ArgumentList @("-NoLogo", "-ExecutionPolicy", "Bypass", "-File", $launcher)
            [Environment]::Exit(0)
        }
        else {
            Write-Host "Launcher not found at: $launcher" -ForegroundColor Yellow
            Write-Host "Re-open the terminal manually to pick up the update." -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host "Re-open the terminal to pick up the update." -ForegroundColor DarkGray
    }
}
catch {
    $script:updateFailed = $true

    Write-Host ""
    Write-Host "UPDATE FAILED:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Details:"
    Write-Host ($_ | Out-String)

    throw
}
finally {
    # Suppress pause if relaunching (process is about to exit) or running from menu
    $isMenu = $script:suppressFinalPause
    if (-not $isMenu) {
        try {
            $parentPid = (Get-CimInstance Win32_Process -Filter "ProcessId = $PID" -ErrorAction Stop).ParentProcessId
            $parentProc = (Get-CimInstance Win32_Process -Filter "ProcessId = $parentPid" -ErrorAction Stop).Name
            if ($parentProc -match 'powershell|pwsh|code|terminal|menu') {
                $isMenu = $true
            }
        }
        catch {
            # If process detection fails, default to no pause (safe for menu-launched context)
            $isMenu = $true
        }
    }
    if (-not $isMenu) {
        Wait-MenuContinue
    }
}
