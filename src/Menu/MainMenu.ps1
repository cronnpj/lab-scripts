# C:\CITA\LabTools\src\Menu\MainMenu.ps1
$ErrorActionPreference = "SilentlyContinue"

# Import shared UI helpers
Import-Module (Join-Path $PSScriptRoot "..\UI\ConsoleUI.psm1") -Force

function Test-GitInstalled {
    return [bool](Get-Command git -ErrorAction SilentlyContinue)
}

# Use runtime root repo (parent of Menu) for update status checks
function Resolve-RepoPath {
    $runtimeRoot = Split-Path -Parent $PSScriptRoot

    if (-not (Test-GitInstalled)) { return $null }

    # Runtime root as repo
    $isRuntimeRepo = git -C $runtimeRoot rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -eq 0 -and $isRuntimeRepo.Trim() -eq "true") { return $runtimeRoot }

    return $null
}

# Re-evaluate repoPath each time in case updates create/enable it during runtime
function Get-RepoPath {
    return (Resolve-RepoPath)
}

$script:UpdateStatusCache     = $null
$script:UpdateStatusCacheTime = [datetime]::MinValue

function Get-UpdateStatus {
    $cacheTtl = 300  # 5 minutes - git fetch is a network call, no need to run it on every menu render
    if ($null -ne $script:UpdateStatusCache -and
        ([datetime]::Now - $script:UpdateStatusCacheTime).TotalSeconds -lt $cacheTtl) {
        return $script:UpdateStatusCache
    }

    try {
        if (-not (Test-GitInstalled)) { return "NO_GIT" }

        $repoPath = Get-RepoPath
        if (-not $repoPath) { return "NO_REPO" }

        git -C $repoPath fetch --quiet 2>$null | Out-Null

        $branch = (git -C $repoPath rev-parse --abbrev-ref HEAD 2>$null).Trim()
        if (-not $branch) { $result = "UNKNOWN" }
        else {
            $counts = (git -C $repoPath rev-list --left-right --count "HEAD...origin/$branch" 2>$null).Trim()
            if (-not $counts) { $result = "UNKNOWN" }
            else {
                $parts = $counts -split "`t"
                if ($parts.Count -lt 2) { $result = "UNKNOWN" }
                else {
                    $behind = 0
                    if (-not [int]::TryParse($parts[1], [ref]$behind)) { $result = "UNKNOWN" }
                    elseif ($behind -gt 0) { $result = "UPDATE_AVAILABLE" }
                    else { $result = "UP_TO_DATE" }
                }
            }
        }
    }
    catch { $result = "UNKNOWN" }

    $script:UpdateStatusCache     = $result
    $script:UpdateStatusCacheTime = [datetime]::Now
    return $result
}

function Get-StatusLine {
    param([string]$Status = "")
    if ([string]::IsNullOrEmpty($Status)) { $Status = Get-UpdateStatus }
    switch ($Status) {
        "UPDATE_AVAILABLE" { return @{ Text = "[Warning] UPDATE AVAILABLE - Press U to update now"; Color = "Yellow" } }
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
            Clear-JoinDisplayInfoCache  # force header to re-read tenant on next render
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
    $updateStatus = Get-UpdateStatus
    $statusObj = Get-StatusLine -Status $updateStatus
    $updateAvailable = ($updateStatus -eq "UPDATE_AVAILABLE")

    Show-AppHeader -Breadcrumb "Main Menu"

    Write-MenuItem "1" "Server Tools"                 "Cyan"
    Write-MenuItem "2" "Domain Controller Tools"      "Cyan"
    Write-MenuItem "3" "Member Server Tools"           "Green"
    Write-MenuItem "4" "Windows Client Tools"          "Green"
    Write-MenuItem "5" "Troubleshooting & Validation"  "Yellow"
    Write-MenuItem "6" "DevOps & Automation"           "Magenta"
    Write-MenuItem "7" "App Maintenance & Updates"     "White"
    Write-MenuItem "S" "Global Search"                 "White"
    if ($updateAvailable) {
        Write-MenuItem "U" "Update Lab Tools from GitHub" "Yellow"
    }
    if ($graphState.ShowGraphConnect) {
        Write-MenuItem "G" "Connect Microsoft Graph for Tenant info" "Magenta"
    }
    Write-MenuItem "0" "Exit"                          "DarkGray"
    Write-Host ""

    Write-StatusLine -StatusText $statusObj.Text -StatusColor $statusObj.Color

    # Build keys line dynamically based on active shortcuts
    $keyParts = [System.Collections.Generic.List[hashtable]]::new()
    $keyParts.Add(@{ Key = "1-7"; Label = " Select" })
    $keyParts.Add(@{ Key = "S";   Label = " Search" })
    if ($updateAvailable)            { $keyParts.Add(@{ Key = "U"; Label = " Update" }) }
    if ($graphState.ShowGraphConnect) { $keyParts.Add(@{ Key = "G"; Label = " Graph"  }) }
    $keyParts.Add(@{ Key = "0"; Label = " Exit" })

    Write-Host "Keys: " -NoNewline -ForegroundColor DarkGray
    for ($i = 0; $i -lt $keyParts.Count; $i++) {
        Write-Host $keyParts[$i].Key -NoNewline -ForegroundColor Yellow
        if ($i -lt $keyParts.Count - 1) {
            Write-Host "$($keyParts[$i].Label)  |  " -NoNewline -ForegroundColor DarkGray
        } else {
            Write-Host $keyParts[$i].Label -ForegroundColor DarkGray
        }
    }
    Write-Host ""

    return @{
        ShowGraphConnect = $graphState.ShowGraphConnect
        JoinType         = $graphState.JoinType
        UpdateAvailable  = $updateAvailable
    }
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
        [PSCustomObject]@{ Script = "ClientToolsMenu.ps1"; RunScript = "ClientToolsMenu.ps1"; RunOption = "U5"; Area = "Windows Client Tools > Utilities"; Item = "Launch VMware Horizon OS Optimization Tool"; Keywords = "vmware horizon optimization tool osot install quiet" },
        [PSCustomObject]@{ Script = "ClientToolsMenu.ps1"; RunScript = "ClientToolsMenu.ps1"; RunOption = "U6"; Area = "Windows Client Tools > Utilities"; Item = "Open winget command shell"; Keywords = "winget package manager search install uninstall list upgrade shell" },
        [PSCustomObject]@{ Script = "ClientToolsMenu.ps1"; RunScript = "ClientToolsMenu.ps1"; RunOption = "U7"; Area = "Windows Client Tools > Utilities"; Item = "Run winget upgrade --all"; Keywords = "winget upgrade all update packages" },
        [PSCustomObject]@{ Script = "ClientToolsMenu.ps1"; RunScript = "ClientToolsMenu.ps1"; RunOption = "U8"; Area = "Windows Client Tools > Utilities"; Item = "Open new terminal tab"; Keywords = "terminal tab windows terminal wt new tab" },
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
        [PSCustomObject]@{ Script = "MaintenanceMenu.ps1"; Area = "App Maintenance & Updates"; Item = "LabTools maintenance and updates"; Keywords = "maintenance update upgrade shortcuts terminal feedback" }
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

function Read-MainMenuChoice {
    # Polls for a keypress every 500ms. Returns the character pressed immediately
    # (no Enter needed), or $null after the refresh interval to trigger a menu re-render.
    param([int]$RefreshIntervalSeconds = 300)

    Write-Host "Select an option: " -NoNewline

    $refreshAt = [datetime]::Now.AddSeconds($RefreshIntervalSeconds)
    while ($true) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            Write-Host $key.KeyChar  # echo the character
            return $key.KeyChar.ToString()
        }
        if ([datetime]::Now -ge $refreshAt) {
            Write-Host ""  # move to next line before re-render
            return $null
        }
        Start-Sleep -Milliseconds 500
    }
}

$exit = $false
do {
    $menuState = Show-MainMenu

    $choice = $null
    while ($null -eq $choice) {
        $choice = Read-MainMenuChoice -RefreshIntervalSeconds 300
        if ($null -eq $choice) {
            # 5-minute idle timeout: bust update cache and re-render to pick up any new release
            $script:UpdateStatusCache     = $null
            $script:UpdateStatusCacheTime = [datetime]::MinValue
            $menuState = Show-MainMenu
        }
    }

    switch ($choice.ToLowerInvariant()) {
        "1" { & (Join-Path $PSScriptRoot "ServerToolsMenu.ps1") }
        "2" { & (Join-Path $PSScriptRoot "DCToolsMenu.ps1") }
        "3" { & (Join-Path $PSScriptRoot "MemberServerMenu.ps1") }
        "4" { & (Join-Path $PSScriptRoot "ClientToolsMenu.ps1") }
        "5" { & (Join-Path $PSScriptRoot "TroubleshootingMenu.ps1") }
        "6" { & (Join-Path $PSScriptRoot "DevOpsToolsMenu.ps1") }
        "7" { & (Join-Path $PSScriptRoot "MaintenanceMenu.ps1") }
        "s" { Invoke-GlobalSearch }
        "u" {
            if ($menuState.UpdateAvailable) {
                Show-AppHeader -Breadcrumb "Main Menu > Update Lab Tools"
                & (Join-Path $PSScriptRoot "..\Tasks\Update-LabTools.ps1")
                Read-Host "Press Enter to continue" | Out-Null
            }
            else {
                Start-Sleep -Milliseconds 300
            }
        }
        "g" {
            if ($menuState.ShowGraphConnect) {
                Invoke-MainMenuGraphConnect -JoinType $menuState.JoinType
            }
            else {
                Start-Sleep -Milliseconds 300
            }
        }
        "0" { $exit = $true }
        default { Start-Sleep -Milliseconds 300 }
    }

} while (-not $exit)

Clear-Host
