# C:\CITA\LabTools\src\Menu\MainMenu.ps1
$ErrorActionPreference = "SilentlyContinue"

# Import shared UI helpers
Import-Module (Join-Path $PSScriptRoot "..\UI\ConsoleUI.psm1") -Force

function Test-GitInstalled {
    return [bool](Get-Command git -ErrorAction SilentlyContinue)
}

# Prefer separate repo if it exists, otherwise use runtime root (parent of Menu)
function Resolve-RepoPath {
    $preferred   = "C:\CITA\_LabToolsRepo"
    $runtimeRoot = Split-Path -Parent $PSScriptRoot

    if (-not (Test-GitInstalled)) { return $null }

    # 1) Preferred repo
    $isPreferredRepo = git -C $preferred rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -eq 0 -and $isPreferredRepo.Trim() -eq "true") { return $preferred }

    # 2) Runtime root as repo
    $isRuntimeRepo = git -C $runtimeRoot rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -eq 0 -and $isRuntimeRepo.Trim() -eq "true") { return $runtimeRoot }

    return $null
}

# Re-evaluate repoPath each time in case updates create/enable it during runtime
function Get-RepoPath {
    return (Resolve-RepoPath)
}

function Get-UpdateStatus {
    try {
        if (-not (Test-GitInstalled)) { return "NO_GIT" }

        $repoPath = Get-RepoPath
        if (-not $repoPath) { return "NO_REPO" }

        git -C $repoPath fetch --quiet 2>$null | Out-Null

        $branch = (git -C $repoPath rev-parse --abbrev-ref HEAD 2>$null).Trim()
        if (-not $branch) { return "UNKNOWN" }

        $counts = (git -C $repoPath rev-list --left-right --count "HEAD...origin/$branch" 2>$null).Trim()
        if (-not $counts) { return "UNKNOWN" }

        $parts = $counts -split "`t"
        if ($parts.Count -lt 2) { return "UNKNOWN" }

        $behind = 0
        if (-not [int]::TryParse($parts[1], [ref]$behind)) { return "UNKNOWN" }

        if ($behind -gt 0) { return "UPDATE_AVAILABLE" }
        return "UP_TO_DATE"
    }
    catch { return "UNKNOWN" }
}

function Get-StatusLine {
    $status = Get-UpdateStatus
    switch ($status) {
        "UPDATE_AVAILABLE" { return @{ Text = "[Warning] UPDATE AVAILABLE - Run Maintenance and Updates"; Color = "Yellow" } }
        "UP_TO_DATE"       { return @{ Text = "[Ready] Up to date"; Color = "Green" } }
        "NO_GIT"           { return @{ Text = "[Ready] Git not installed"; Color = "DarkGray" } }
        "NO_REPO"          { return @{ Text = "[Ready] Update check unavailable (repo not detected)"; Color = "DarkGray" } }
        default             { return @{ Text = "[Ready] Update check unavailable"; Color = "DarkGray" } }
    }
}

function Get-JoinTypeForMainMenu {
    try {
        $joinType = Get-CurrentJoinType
        if (-not [string]::IsNullOrWhiteSpace($joinType)) {
            return $joinType
        }
    }
    catch {
        return 'Unknown'
    }

    return 'Unknown'
}

function Get-GraphConnectMenuState {
    $joinType = Get-JoinTypeForMainMenu
    return @{
        ShowGraphConnect = ($joinType -in @('Hybrid', 'Cloud'))
        JoinType = $joinType
    }
}

function Invoke-MainMenuGraphConnect {
    param(
        [string]$JoinType = 'Unknown'
    )

    Show-AppHeader -Breadcrumb "Main Menu > Graph Tenant Connection"

    Write-Host "This app detected a $JoinType environment." -ForegroundColor Cyan
    Write-Host "Connect to Microsoft Graph now to populate Tenant info (verified domain) in the header?" -ForegroundColor Gray
    Write-Host ""

    $connectNow = Read-Host "Connect now? (Y/N)"
    if ($connectNow -notmatch '^(?i)y(es)?$') {
        Write-Host "Skipped Graph connection." -ForegroundColor DarkYellow
        Start-Sleep -Milliseconds 600
        return
    }

    $connectCmd = Get-Command Connect-MgGraph -ErrorAction SilentlyContinue
    $contextCmd = Get-Command Get-MgContext -ErrorAction SilentlyContinue

    if (-not $connectCmd -or -not $contextCmd) {
        Write-Host "Microsoft Graph module commands are not available in this session." -ForegroundColor Yellow
        Write-Host "Run Maintenance option [5] first to verify/install required modules." -ForegroundColor Yellow
        Read-Host "Press Enter to continue" | Out-Null
        return
    }

    $autosaveCmd = Get-Command Enable-MgGraphContextAutosave -ErrorAction SilentlyContinue
    if ($autosaveCmd) {
        try {
            Enable-MgGraphContextAutosave -Scope CurrentUser -ErrorAction SilentlyContinue | Out-Null
        }
        catch {
            # Non-blocking: autosave support varies by Graph SDK version.
        }
    }

    try {
        Connect-MgGraph -Scopes "Organization.Read.All" -NoWelcome -ContextScope CurrentUser -ErrorAction Stop | Out-Null
        $ctx = Get-MgContext -ErrorAction SilentlyContinue

        if ($ctx -and -not [string]::IsNullOrWhiteSpace([string]$ctx.Account)) {
            Write-Host "Connected to Microsoft Graph as: $($ctx.Account)" -ForegroundColor Green
        }
        else {
            Write-Host "Graph sign-in completed, but no active context was returned yet." -ForegroundColor DarkYellow
        }
    }
    catch {
        Write-Host "Graph connection failed: $($_.Exception.Message)" -ForegroundColor Red
    }

    Read-Host "Press Enter to continue" | Out-Null
}

function Show-MainMenu {
    $graphState = Get-GraphConnectMenuState
    $statusObj = Get-StatusLine

    Show-AppHeader -Breadcrumb "Main Menu"

    Write-Host "  [1] Server Tools"
    Write-Host "  [2] Domain Controller Tools"
    Write-Host "  [3] Member Server Tools"
    Write-Host "  [4] Windows Client Tools"
    Write-Host "  [5] Troubleshooting & Validation"
    Write-Host "  [6] DevOps & Automation"
    Write-Host "  [7] Maintenance & Updates"
    Write-Host "  [S] Global Search"
    if ($graphState.ShowGraphConnect) {
        Write-Host "  [G] Connect Microsoft Graph for Tenant info"
    }
    Write-Host "  [0] Exit"
    Write-Host ""

    Write-StatusLine -StatusText $statusObj.Text -StatusColor $statusObj.Color

    if ($graphState.ShowGraphConnect) {
        Write-Host "Keys: 1-7 Select  |  S Search  |  G Graph  |  0 Exit"
    }
    else {
        Write-Host "Keys: 1-7 Select  |  S Search  |  0 Exit"
    }
    Write-Host ""

    return $graphState
}

function Get-GlobalSearchCatalog {
    return @(
        [PSCustomObject]@{ Script = "ServerToolsMenu.ps1"; Area = "Server Tools"; Item = "Server management and administrative utilities"; Keywords = "server admin tools" },
        [PSCustomObject]@{ Script = "DCToolsMenu.ps1"; Area = "Domain Controller Tools"; Item = "Active Directory and domain controller operations"; Keywords = "dc active directory ad domain" },
        [PSCustomObject]@{ Script = "MemberServerMenu.ps1"; Area = "Member Server Tools"; Item = "Member server configuration and checks"; Keywords = "member server config" },
        [PSCustomObject]@{ Script = "ClientToolsMenu.ps1"; RunScript = "ClientToolsMenu.ps1"; RunOption = "I1"; Area = "Windows Client Tools > Identity & Enrollment"; Item = "Join existing domain"; Keywords = "join domain enrollment identity entra" },
        [PSCustomObject]@{ Script = "ClientToolsMenu.ps1"; RunScript = "ClientToolsMenu.ps1"; RunOption = "I2"; Area = "Windows Client Tools > Identity & Enrollment"; Item = "Show Join Status"; Keywords = "join status domain entra hybrid" },
        [PSCustomObject]@{ Script = "ClientToolsMenu.ps1"; RunScript = "ClientToolsMenu.ps1"; RunOption = "I3"; Area = "Windows Client Tools > Identity & Enrollment"; Item = "Open Work/School Accounts"; Keywords = "work school accounts enrollment" },
        [PSCustomObject]@{ Script = "ClientToolsMenu.ps1"; RunScript = "ClientToolsMenu.ps1"; RunOption = "I4"; Area = "Windows Client Tools > Identity & Enrollment"; Item = "Force Intune Sync"; Keywords = "intune sync" },
        [PSCustomObject]@{ Script = "ClientToolsMenu.ps1"; RunScript = "ClientToolsMenu.ps1"; RunOption = "P1"; Area = "Windows Client Tools > Policy & Management"; Item = "Force Group Policy Update"; Keywords = "gpo gpupdate policy update" },
        [PSCustomObject]@{ Script = "ClientToolsMenu.ps1"; RunScript = "ClientToolsMenu.ps1"; RunOption = "P2"; Area = "Windows Client Tools > Policy & Management"; Item = "Show GPO Results"; Keywords = "gpresult gpo results policy" },
        [PSCustomObject]@{ Script = "ClientToolsMenu.ps1"; RunScript = "ClientToolsMenu.ps1"; RunOption = "P3"; Area = "Windows Client Tools > Policy & Management"; Item = "Export GPO Report"; Keywords = "gpo report html export policy" },
        [PSCustomObject]@{ Script = "ClientToolsMenu.ps1"; RunScript = "ClientToolsMenu.ps1"; RunOption = "N1"; Area = "Windows Client Tools > Network Tools"; Item = "Show IP Configuration"; Keywords = "ipconfig ip configuration network" },
        [PSCustomObject]@{ Script = "ClientToolsMenu.ps1"; RunScript = "ClientToolsMenu.ps1"; RunOption = "N2"; Area = "Windows Client Tools > Network Tools"; Item = "Flush DNS Cache"; Keywords = "dns flush flushdns" },
        [PSCustomObject]@{ Script = "ClientToolsMenu.ps1"; RunScript = "ClientToolsMenu.ps1"; RunOption = "N3"; Area = "Windows Client Tools > Network Tools"; Item = "Renew DHCP Lease"; Keywords = "dhcp renew release" },
        [PSCustomObject]@{ Script = "ClientToolsMenu.ps1"; RunScript = "ClientToolsMenu.ps1"; RunOption = "N4"; Area = "Windows Client Tools > Network Tools"; Item = "Quick Connectivity Tests"; Keywords = "connectivity gateway dns internet ping" },
        [PSCustomObject]@{ Script = "ClientToolsMenu.ps1"; RunScript = "ClientToolsMenu.ps1"; RunOption = "S1"; Area = "Windows Client Tools > System Actions"; Item = "Rename computer"; Keywords = "rename hostname computer" },
        [PSCustomObject]@{ Script = "ClientToolsMenu.ps1"; RunScript = "ClientToolsMenu.ps1"; RunOption = "S2"; Area = "Windows Client Tools > System Actions"; Item = "Set timezone to Eastern + resync clock"; Keywords = "timezone eastern clock sync time" },
        [PSCustomObject]@{ Script = "ClientToolsMenu.ps1"; RunScript = "ClientToolsMenu.ps1"; RunOption = "S3"; Area = "Windows Client Tools > System Actions"; Item = "Restart Windows Update Services"; Keywords = "windows update services restart wuauserv bits" },
        [PSCustomObject]@{ Script = "ClientToolsMenu.ps1"; RunScript = "ClientToolsMenu.ps1"; RunOption = "S4"; Area = "Windows Client Tools > System Actions"; Item = "System File Check (SFC)"; Keywords = "sfc scannow system file check" },
        [PSCustomObject]@{ Script = "ClientToolsMenu.ps1"; RunScript = "ClientToolsMenu.ps1"; RunOption = "U1"; Area = "Windows Client Tools > Utilities"; Item = "Launch vmPing"; Keywords = "vmping utility" },
        [PSCustomObject]@{ Script = "ClientToolsMenu.ps1"; RunScript = "ClientToolsMenu.ps1"; RunOption = "U2"; Area = "Windows Client Tools > Utilities"; Item = "Run Win11Debloat"; Keywords = "win11 debloat utility cleanup" },
        [PSCustomObject]@{ Script = "ClientToolsMenu.ps1"; RunScript = "ClientToolsMenu.ps1"; RunOption = "U3"; Area = "Windows Client Tools > Utilities"; Item = "Run SDelete free-space overwrite"; Keywords = "sdelete sysinternals template proxmox zero free space" },
        [PSCustomObject]@{ Script = "ClientToolsMenu.ps1"; RunScript = "ClientToolsMenu.ps1"; RunOption = "U4"; Area = "Windows Client Tools > Utilities"; Item = "Run VM template prep checklist"; Keywords = "template prep sysprep sdelete proxmox golden image" },
        [PSCustomObject]@{ Script = "TroubleshootingMenu.ps1"; RunScript = "TroubleshootingMenu.ps1"; RunOption = "T1"; Area = "Troubleshooting & Validation"; Item = "Show server role install status"; Keywords = "troubleshoot validation install status role status" },
        [PSCustomObject]@{ Script = "TroubleshootingMenu.ps1"; RunScript = "TroubleshootingMenu.ps1"; RunOption = "T2"; Area = "Troubleshooting & Validation"; Item = "System snapshot"; Keywords = "snapshot system inventory diagnostics" },
        [PSCustomObject]@{ Script = "DevOpsToolsMenu.ps1"; Area = "DevOps & Automation"; Item = "DevOps tooling, labs, and automation"; Keywords = "devops automation lab tools" },
        [PSCustomObject]@{ Script = "DevOpsInstallUpdateMenu.ps1"; RunScript = "DevOpsInstallUpdateMenu.ps1"; RunOption = "1"; Area = "DevOps > Install / Update Tools"; Item = "Upgrade all Winget packages"; Keywords = "winget update upgrade packages" },
        [PSCustomObject]@{ Script = "DevOpsInstallUpdateMenu.ps1"; RunScript = "DevOpsInstallUpdateMenu.ps1"; RunOption = "2"; Area = "DevOps > Install / Update Tools"; Item = "Install talosctl"; Keywords = "talos talosctl install" },
        [PSCustomObject]@{ Script = "DevOpsInstallUpdateMenu.ps1"; RunScript = "DevOpsInstallUpdateMenu.ps1"; RunOption = "3"; Area = "DevOps > Install / Update Tools"; Item = "Install kubectl"; Keywords = "kubernetes kubectl install" },
        [PSCustomObject]@{ Script = "DevOpsInstallUpdateMenu.ps1"; RunScript = "DevOpsInstallUpdateMenu.ps1"; RunOption = "4"; Area = "DevOps > Install / Update Tools"; Item = "Install helm"; Keywords = "helm install charts" },
        [PSCustomObject]@{ Script = "DevOpsInstallUpdateMenu.ps1"; RunScript = "DevOpsInstallUpdateMenu.ps1"; RunOption = "5"; Area = "DevOps > Install / Update Tools"; Item = "Install DevOps bundle"; Keywords = "bundle talosctl kubectl helm" },
        [PSCustomObject]@{ Script = "DevOpsQuickChecksMenu.ps1"; RunScript = "DevOpsQuickChecksMenu.ps1"; RunOption = "1"; Area = "DevOps > Quick Checks / Utilities"; Item = "Show installed versions"; Keywords = "versions git kubectl talosctl helm" },
        [PSCustomObject]@{ Script = "DevOpsQuickChecksMenu.ps1"; RunScript = "DevOpsQuickChecksMenu.ps1"; RunOption = "2"; Area = "DevOps > Quick Checks / Utilities"; Item = "kubectl get nodes/pods"; Keywords = "kubectl nodes pods services ingress cluster check" },
        [PSCustomObject]@{ Script = "DevOpsQuickChecksMenu.ps1"; RunScript = "DevOpsQuickChecksMenu.ps1"; RunOption = "3"; Area = "DevOps > Quick Checks / Utilities"; Item = "Open repo folder in File Explorer"; Keywords = "repo explorer open folder files" },
        [PSCustomObject]@{ Script = "DevOpsLabInstallOpsMenu.ps1"; RunScript = "DevOpsToolsMenu.ps1"; RunOption = "91"; Area = "DevOps > Lab Install Operations"; Item = "Install core platform"; Keywords = "bootstrap cluster metallb ingress install" },
        [PSCustomObject]@{ Script = "DevOpsLabInstallOpsMenu.ps1"; RunScript = "DevOpsToolsMenu.ps1"; RunOption = "92"; Area = "DevOps > Lab Install Operations"; Item = "Repair / Reinstall MetalLB"; Keywords = "metallb vip pool range loadbalancer" },
        [PSCustomObject]@{ Script = "DevOpsLabInstallOpsMenu.ps1"; RunScript = "DevOpsToolsMenu.ps1"; RunOption = "93"; Area = "DevOps > Lab Install Operations"; Item = "Install / Reinstall Portainer Admin UI"; Keywords = "portainer ingress nodeport loadbalancer" },
        [PSCustomObject]@{ Script = "DevOpsLabInstallOpsMenu.ps1"; RunScript = "DevOpsToolsMenu.ps1"; RunOption = "94"; Area = "DevOps > Lab Install Operations"; Item = "Deploy / Update CITA Web Demo"; Keywords = "cita web demo deploy update" },
        [PSCustomObject]@{ Script = "DevOpsLabInstallOpsMenu.ps1"; RunScript = "DevOpsToolsMenu.ps1"; RunOption = "95"; Area = "DevOps > Lab Install Operations"; Item = "Scale CITA Web Demo"; Keywords = "scale replicas deployment cita web" },
        [PSCustomObject]@{ Script = "DevOpsLabInstallOpsMenu.ps1"; RunScript = "DevOpsToolsMenu.ps1"; RunOption = "96"; Area = "DevOps > Lab Install Operations"; Item = "Scale any deployed app"; Keywords = "scale app deployment interactive" },
        [PSCustomObject]@{ Script = "DevOpsLabInstallOpsMenu.ps1"; RunScript = "DevOpsToolsMenu.ps1"; RunOption = "97"; Area = "DevOps > Lab Install Operations"; Item = "Install / Update app via Helm"; Keywords = "helm install update chart" },
        [PSCustomObject]@{ Script = "DevOpsLabAdvancedOpsMenu.ps1"; RunScript = "DevOpsToolsMenu.ps1"; RunOption = "161"; Area = "DevOps > Lab Advanced Operations"; Item = "Wipe + Rebuild cluster"; Keywords = "wipe rebuild reset cluster" },
        [PSCustomObject]@{ Script = "DevOpsLabAdvancedOpsMenu.ps1"; RunScript = "DevOpsToolsMenu.ps1"; RunOption = "162"; Area = "DevOps > Lab Advanced Operations"; Item = "Nuke local generated files"; Keywords = "nuke clean kubeconfig student overrides" },
        [PSCustomObject]@{ Script = "DevOpsLabAdvancedOpsMenu.ps1"; RunScript = "DevOpsToolsMenu.ps1"; RunOption = "163"; Area = "DevOps > Lab Advanced Operations"; Item = "Repo lab-safe reset"; Keywords = "repo reset discard local changes" },
        [PSCustomObject]@{ Script = "DevOpsLabAdvancedOpsMenu.ps1"; RunScript = "DevOpsToolsMenu.ps1"; RunOption = "164"; Area = "DevOps > Lab Advanced Operations"; Item = "Add new worker node"; Keywords = "worker node talos join cluster" },
        [PSCustomObject]@{ Script = "DevOpsLabAdvancedOpsMenu.ps1"; RunScript = "DevOpsToolsMenu.ps1"; RunOption = "165"; Area = "DevOps > Lab Advanced Operations"; Item = "Reset CITA Web Demo only"; Keywords = "reset cita web delete namespace" },
        [PSCustomObject]@{ Script = "DevOpsLabAdvancedOpsMenu.ps1"; RunScript = "DevOpsToolsMenu.ps1"; RunOption = "166"; Area = "DevOps > Lab Advanced Operations"; Item = "Open kubectl prompt"; Keywords = "kubectl prompt shell kubeconfig" },
        [PSCustomObject]@{ Script = "MaintenanceMenu.ps1"; Area = "Maintenance & Updates"; Item = "LabTools maintenance and updates"; Keywords = "maintenance update upgrade shortcuts terminal feedback" }
    )
}

function Invoke-GlobalSearch {
    Show-AppHeader -Breadcrumb "Main Menu > Global Search"
    Write-Host "Search by keyword (example: dns, gpo, join, update, devops)." -ForegroundColor DarkGray
    Write-Host ""

    $query = Read-Host "Enter keyword (blank to cancel)"
    if ([string]::IsNullOrWhiteSpace($query)) {
        return
    }

    $catalog = Get-GlobalSearchCatalog
    $searchMatches = @($catalog | Where-Object {
        $_.Area -like "*$query*" -or
        $_.Item -like "*$query*" -or
        $_.Keywords -like "*$query*"
    })

    Show-AppHeader -Breadcrumb "Main Menu > Global Search Results"

    if (-not $searchMatches -or $searchMatches.Count -eq 0) {
        Write-Host ("No matches found for '{0}'." -f $query) -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to return" | Out-Null
        return
    }

    Write-Host ("Matches for '{0}':" -f $query) -ForegroundColor Cyan
    Write-Host ""

    for ($index = 0; $index -lt $searchMatches.Count; $index++) {
        $displayIndex = $index + 1
        Write-Host ("  [{0}] {1} > {2}" -f $displayIndex, $searchMatches[$index].Area, $searchMatches[$index].Item)
    }

    Write-Host ""
    Write-Host "Tip: pick a result number to open its menu, or press Enter to cancel." -ForegroundColor DarkGray
    $selection = Read-Host "Open result"

    if ([string]::IsNullOrWhiteSpace($selection)) {
        return
    }

    $selectedIndex = 0
    if (-not [int]::TryParse($selection, [ref]$selectedIndex)) {
        return
    }

    if ($selectedIndex -lt 1 -or $selectedIndex -gt $searchMatches.Count) {
        return
    }

    $selectedResult = $searchMatches[$selectedIndex - 1]
    Write-Host ""
    Write-Host ("Running: {0} > {1}" -f $selectedResult.Area, $selectedResult.Item) -ForegroundColor Cyan
    Start-Sleep -Milliseconds 500

    $runScriptName = $null
    $runOption = $null

    if ($selectedResult.PSObject.Properties.Match("RunScript").Count -gt 0) {
        $runScriptName = $selectedResult.RunScript
    }
    if ($selectedResult.PSObject.Properties.Match("RunOption").Count -gt 0) {
        $runOption = $selectedResult.RunOption
    }

    if (-not [string]::IsNullOrWhiteSpace($runScriptName) -and -not [string]::IsNullOrWhiteSpace($runOption)) {
        $runScriptPath = Join-Path $PSScriptRoot $runScriptName
        if (Test-Path $runScriptPath) {
            & $runScriptPath -RunOption $runOption
            return
        }
    }

    $scriptPath = Join-Path $PSScriptRoot $selectedResult.Script
    if (Test-Path $scriptPath) {
        & $scriptPath
    }
}

$exit = $false
do {
    $graphState = Show-MainMenu
    $choice = Read-Host "Select an option"

    switch ($choice.ToLowerInvariant()) {
        "1" { & (Join-Path $PSScriptRoot "ServerToolsMenu.ps1") }
        "2" { & (Join-Path $PSScriptRoot "DCToolsMenu.ps1") }
        "3" { & (Join-Path $PSScriptRoot "MemberServerMenu.ps1") }
        "4" { & (Join-Path $PSScriptRoot "ClientToolsMenu.ps1") }
        "5" { & (Join-Path $PSScriptRoot "TroubleshootingMenu.ps1") }
        "6" { & (Join-Path $PSScriptRoot "DevOpsToolsMenu.ps1") }
        "7" { & (Join-Path $PSScriptRoot "MaintenanceMenu.ps1") }
        "s" { Invoke-GlobalSearch }
        "g" {
            if ($graphState.ShowGraphConnect) {
                Invoke-MainMenuGraphConnect -JoinType $graphState.JoinType
            }
            else {
                Start-Sleep -Milliseconds 300
            }
        }
        "0" { $exit = $true }
        default { Start-Sleep -Milliseconds 300 }
    }

    if (-not $exit) { Clear-Host }  # show fresh main menu after returning

} while (-not $exit)

Clear-Host
