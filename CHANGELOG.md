# Changelog

All notable changes to this repository are documented in this file.

## v2026.03.20.1 - 2026-03-20

### UI / Navigation — Persistent Header

- Changed all sub-menu `Import-Module` calls for [src/UI/ConsoleUI.psm1](src/UI/ConsoleUI.psm1) from unconditional `-Force` to a conditional check (`if (-not (Get-Module ConsoleUI))`). This preserves the `$script:AppHeaderDrawn` module state across menu transitions so the in-place header overwrite works when navigating between menus. Affects: [ServerToolsMenu.ps1](src/Menu/ServerToolsMenu.ps1), [DCToolsMenu.ps1](src/Menu/DCToolsMenu.ps1), [MemberServerMenu.ps1](src/Menu/MemberServerMenu.ps1), [ClientToolsMenu.ps1](src/Menu/ClientToolsMenu.ps1), [TroubleshootingMenu.ps1](src/Menu/TroubleshootingMenu.ps1), [MaintenanceMenu.ps1](src/Menu/MaintenanceMenu.ps1), [DevOpsToolsMenu.ps1](src/Menu/DevOpsToolsMenu.ps1), [DevOpsInstallUpdateMenu.ps1](src/Menu/DevOpsInstallUpdateMenu.ps1), [DevOpsQuickChecksMenu.ps1](src/Menu/DevOpsQuickChecksMenu.ps1), [DevOpsLabInstallOpsMenu.ps1](src/Menu/DevOpsLabInstallOpsMenu.ps1), [DevOpsLabAdvancedOpsMenu.ps1](src/Menu/DevOpsLabAdvancedOpsMenu.ps1).
- Removed `Clear-Host` before `return` in all sub-menus. The exit clear was causing a blank-screen flicker when pressing `0` to go back to the main menu. [src/UI/ConsoleUI.psm1](src/UI/ConsoleUI.psm1) already clears below the header via `ESC[J` on each redraw, making the exit clear redundant.

### Version
- Bumped [src/VERSION.txt](src/VERSION.txt) to `v2026.03.20.1`.

## v2026.03.19.2 - 2026-03-19

### UI Color Enhancements

- Added `Write-MenuItem` and `Write-MenuKeysLine` shared helpers to [src/UI/ConsoleUI.psm1](src/UI/ConsoleUI.psm1) and exported them so all menus share a consistent colored rendering path.
- Updated [src/UI/ConsoleUI.psm1](src/UI/ConsoleUI.psm1) header box borders (`+---+` and `| |`) from DarkGray/Gray to Cyan, title line from Cyan to Yellow, and version value from Gray to Cyan.
- Updated `Write-BoxLine` in [src/UI/ConsoleUI.psm1](src/UI/ConsoleUI.psm1) to render border pipes (`| |`) in a separate `BorderColor` (default Cyan) from the text color.
- Applied `Write-MenuItem` (yellow keys, DarkGray brackets, colored label) and `Write-MenuKeysLine` (yellow keys, DarkGray text) across all menu files: [MainMenu.ps1](src/Menu/MainMenu.ps1), [DCToolsMenu.ps1](src/Menu/DCToolsMenu.ps1), [ServerToolsMenu.ps1](src/Menu/ServerToolsMenu.ps1), [MemberServerMenu.ps1](src/Menu/MemberServerMenu.ps1), [TroubleshootingMenu.ps1](src/Menu/TroubleshootingMenu.ps1), [MaintenanceMenu.ps1](src/Menu/MaintenanceMenu.ps1), [ClientToolsMenu.ps1](src/Menu/ClientToolsMenu.ps1), [DevOpsToolsMenu.ps1](src/Menu/DevOpsToolsMenu.ps1), [DevOpsInstallUpdateMenu.ps1](src/Menu/DevOpsInstallUpdateMenu.ps1), [DevOpsQuickChecksMenu.ps1](src/Menu/DevOpsQuickChecksMenu.ps1), [DevOpsLabInstallOpsMenu.ps1](src/Menu/DevOpsLabInstallOpsMenu.ps1), [DevOpsLabAdvancedOpsMenu.ps1](src/Menu/DevOpsLabAdvancedOpsMenu.ps1).
- Highlighted Maintenance option [1] (`Update Lab Tools from GitHub`) in Green in [src/Menu/MaintenanceMenu.ps1](src/Menu/MaintenanceMenu.ps1) to distinguish it as the primary update action.
- Simplified Maintenance option [1] label in [src/Menu/MaintenanceMenu.ps1](src/Menu/MaintenanceMenu.ps1) — shortcut repair and terminal background apply happen silently behind the scenes.

### Bug Fix

- Fixed null-reference error in [src/Menu/DevOpsToolsMenu.ps1](src/Menu/DevOpsToolsMenu.ps1) `Show-CurrentContext` where `Test-Path` was called with a `$null` kubeconfig path when no kubeconfig file exists; both call sites now guard with `$kubeconfigPath -and` before invoking `Test-Path`.

### Version
- Bumped [src/VERSION.txt](src/VERSION.txt) to `v2026.03.19.2`.

## v2026.03.19.1 - 2026-03-19

### Security and Code Quality Fixes

#### High Severity
- Updated [src/Tasks/Run-Win11Debloat.ps1](src/Tasks/Run-Win11Debloat.ps1) to download the upstream script to a temp file before execution rather than running it directly in-memory via `Invoke-RestMethod`, allowing OS/AV scanning and leaving an auditable path in output.
- Added a comment block to [src/Tasks/Create-Shortcuts.ps1](src/Tasks/Create-Shortcuts.ps1) documenting exactly what the `-EncodedCommand` elevation wrapper does, so future reviewers can verify it without decoding the base64.
- Added `Assert-ValidBranchName` in [src/Menu/DevOpsToolsMenu.ps1](src/Menu/DevOpsToolsMenu.ps1) to validate branch names before use in `git checkout` and `git reset --hard`, preventing potential argument injection if the variable origin changes.

#### Medium Severity
- Added `Assert-ValidIPv4` helper to [src/Tasks/Set-StaticIP.ps1](src/Tasks/Set-StaticIP.ps1) and applied it to IP address, gateway, and DNS inputs before any network cmdlets are called.
- Added reserved Windows device name check (`CON`, `NUL`, `COM1`–`COM9`, `LPT1`–`LPT9`) to [src/Tasks/Rename-Computer.ps1](src/Tasks/Rename-Computer.ps1).
- Updated [src/Tasks/Set-EasternTimeAndResync.ps1](src/Tasks/Set-EasternTimeAndResync.ps1) to throw if the W32Time service is missing, use `-ErrorAction Stop` when starting it, and wait/verify the service reaches `Running` state before attempting resync.
- Fixed null reference in [src/Tasks/Client/Test-Connectivity.ps1](src/Tasks/Client/Test-Connectivity.ps1) where a nested `Get-CimInstance` call could throw if the parent process had already exited; split into two calls with null guards.
- Changed `Resolve-KubeconfigPath` fallback return value in [src/Menu/DevOpsToolsMenu.ps1](src/Menu/DevOpsToolsMenu.ps1) from `$candidates[0]` to `$null` so callers receive an unambiguous signal when no kubeconfig is found.

#### Low Severity
- Removed duplicate `Write-LabLog` definition (lines 1–13) from [src/Lib/Logging.psm1](src/Lib/Logging.psm1); the first definition was dead code with a hardcoded `C:\LabLogs\labtools.log` path.
- Added `$env:USERNAME` to the log line format in [src/Lib/Logging.psm1](src/Lib/Logging.psm1) for a complete audit trail.
- Added `Write-Verbose` to silent catch blocks in [src/UI/ConsoleUI.psm1](src/UI/ConsoleUI.psm1) (`Get-PrimaryNetworkInfo`, `Get-InternetStatus`, `Get-DomainMembershipInfo`, `Get-EntraJoinInfo`, `Get-CurrentJoinType`) so errors are surfaced when running with `-Verbose`.
- Switched kubectl interactive prompt in [src/Menu/DevOpsToolsMenu.ps1](src/Menu/DevOpsToolsMenu.ps1) from `-Command` with a dynamic string to `-EncodedCommand`; also fixed a pre-existing bug where `$env:KUBECONFIG` was expanded by the parent process instead of being assigned in the child.
- Added adapter re-verification step to [src/Tasks/Set-StaticIP.ps1](src/Tasks/Set-StaticIP.ps1) after the confirm prompt to catch the case where the selected adapter goes down before settings are applied.
- Added elevation comment to [src/Tasks/Client/Get-JoinStatus.ps1](src/Tasks/Client/Get-JoinStatus.ps1) documenting that admin rights are not required.

### Version
- Bumped [src/VERSION.txt](src/VERSION.txt) to `v2026.03.19.1`.

## v2026.03.12.1 - 2026-03-12

### Repository Consolidation
- Imported external repo history from `cronnpj/375` into [labs/375](labs/375) using a history-preserving subtree workflow.
- Imported external repo history from `cronnpj/320-assignment-5` into [labs/320/320-assignment-5](labs/320/320-assignment-5) using a history-preserving subtree workflow.
- Added [labs/320/README.md](labs/320/README.md) as a course-level index path for future 320 lab additions.
- Added [labs/375/README.md](labs/375/README.md) to describe imported 375 assets and configuration files.
- Updated [README.md](README.md) repository layout links to include consolidated lab paths.

## v2026.03.10.2 - 2026-03-10

### Maintenance and Shortcut Host Selection Updates
- Updated maintenance naming to `App Maintenance & Updates` in [src/Menu/MainMenu.ps1](src/Menu/MainMenu.ps1) and [src/Menu/MaintenanceMenu.ps1](src/Menu/MaintenanceMenu.ps1).
- Hardened shortcut host detection in [src/Tasks/Create-Shortcuts.ps1](src/Tasks/Create-Shortcuts.ps1) so `CITA Lab Tools.lnk` prefers PowerShell 7 when installed, using PATH checks, common install directories, and App Paths registry lookups before falling back to Windows PowerShell.
- Added selected-host logging in [src/Tasks/Create-Shortcuts.ps1](src/Tasks/Create-Shortcuts.ps1) to make shortcut host resolution visible during option [1]/[2] maintenance runs.

### Windows Client Utilities: Winget and Terminal Actions
- Expanded Windows Client Utilities in [src/Menu/ClientToolsMenu.ps1](src/Menu/ClientToolsMenu.ps1) with options [6]-[8]: `Open winget command shell`, `Run winget upgrade --all`, and `Open new terminal tab`.
- Added Winget availability validation in [src/Menu/ClientToolsMenu.ps1](src/Menu/ClientToolsMenu.ps1) with clear guidance when `winget.exe` is missing.
- Implemented `Open winget command shell` to launch a persistent shell tab/window and display a quick command cheat sheet for common Winget actions.
- Added global-search mappings (`RunOption = "U6"`, `"U7"`, `"U8"`) in [src/Menu/MainMenu.ps1](src/Menu/MainMenu.ps1) for the new Utilities actions.

## v2026.03.10.1 - 2026-03-10

### VM Template Prep Order Fix
- Updated [src/Tasks/Run-TemplatePrepChecklist.ps1](src/Tasks/Run-TemplatePrepChecklist.ps1) to present and execute the recommended template workflow in the correct order: run SDelete (`-z`) before Sysprep shutdown.
- Updated [src/MISC/SDelete/README.md](src/MISC/SDelete/README.md) to match the corrected VM template prep flow.

## v2026.03.09.1 - 2026-03-09

### Windows Client Utilities: SDelete Integration
- Added [src/Tasks/Run-HorizonOptimizationTool.ps1](src/Tasks/Run-HorizonOptimizationTool.ps1) to launch `VMwareHorizonOSOptimizationTool-x86_64.exe` in interactive mode.
- Updated [src/Menu/ClientToolsMenu.ps1](src/Menu/ClientToolsMenu.ps1) Utilities to include option [5] `Launch VMware Horizon OS Optimization Tool`.
- Added direct global-search execution mapping in [src/Menu/MainMenu.ps1](src/Menu/MainMenu.ps1) (`RunOption = "U5"`) for the Horizon Optimization Tool.
- Added MISC placement docs in [src/MISC/README.md](src/MISC/README.md) and [src/MISC/VMwareHorizonOSOptimizationTool/README.md](src/MISC/VMwareHorizonOSOptimizationTool/README.md).
- Simplified [src/Tasks/Update-LabTools.ps1](src/Tasks/Update-LabTools.ps1) to in-place runtime-repo updates only; removed repo-cache/deploy behavior that created `C:\CITA\_LabToolsRepo`, `C:\CITA\LabTools`, and backup folders.
- Updated repo detection in [src/Menu/MainMenu.ps1](src/Menu/MainMenu.ps1) to use runtime root git repo only for update status checks.
- Updated vmPing launch flow in [src/Menu/ClientToolsMenu.ps1](src/Menu/ClientToolsMenu.ps1) so Utilities option [1] now ensures `vmPing.lnk` exists on both current-user Desktop and Public Desktop before launching.
- Added skip-if-exists behavior for vmPing shortcut creation and non-blocking handling when Public Desktop shortcut creation is not permitted.
- Added Maintenance option [6] in [src/Menu/MaintenanceMenu.ps1](src/Menu/MaintenanceMenu.ps1) for `Install / Repair PS7 only`.
- Added [src/Tasks/Install-PowerShell7Only.ps1](src/Tasks/Install-PowerShell7Only.ps1) for dedicated PowerShell 7 install/repair without Graph module/sign-in steps.
- Added [src/Tasks/Run-TemplatePrepChecklist.ps1](src/Tasks/Run-TemplatePrepChecklist.ps1) for guided Proxmox VM template prep (Sysprep prompt + optional SDelete handoff + post-step reminders).
- Updated [src/Menu/ClientToolsMenu.ps1](src/Menu/ClientToolsMenu.ps1) Utilities to include option [4] `Run VM template prep checklist`.
- Added direct global-search execution mapping in [src/Menu/MainMenu.ps1](src/Menu/MainMenu.ps1) (`RunOption = "U4"`) for the template prep checklist.
- Added [src/Tasks/Run-SDelete.ps1](src/Tasks/Run-SDelete.ps1) to run Sysinternals SDelete interactively with:
	- default `-z` mode (zero free space, VM-template friendly)
	- optional `-c` mode
	- drive selection prompt (defaults to `C:`)
	- admin/elevation and executable presence checks
- Updated [src/Menu/ClientToolsMenu.ps1](src/Menu/ClientToolsMenu.ps1) Utilities from 2 to 3 options and added `Run SDelete free-space overwrite` as option [3].
- Added direct global-search execution mapping in [src/Menu/MainMenu.ps1](src/Menu/MainMenu.ps1) (`RunOption = "U3"`) for SDelete.
- Added deployable MISC docs for SDelete placement in:
	- [src/MISC/README.md](src/MISC/README.md)
	- [src/MISC/SDelete/README.md](src/MISC/SDelete/README.md)

## v2026.03.05.1 - 2026-03-05

### Header Layout and Status Enhancements
- Added domain membership detection in [src/UI/ConsoleUI.psm1](src/UI/ConsoleUI.psm1) with `Domain`, `Workgroup`, and `None` states shown in the app header.
- Combined `Internet` and `Domain` status into one row in [src/UI/ConsoleUI.psm1](src/UI/ConsoleUI.psm1) to reduce header height.
- Updated header row alignment logic in [src/UI/ConsoleUI.psm1](src/UI/ConsoleUI.psm1) so right-side labels (`User`, `Mode`, `Domain`, `Date`) align to a consistent column.
- Tuned spacing offsets in [src/UI/ConsoleUI.psm1](src/UI/ConsoleUI.psm1) for `Mode`, `Domain`, and `Date` to match the current dashboard layout.

### Shortcut Behavior Updates
- Updated [src/config/labtools.json](src/config/labtools.json) default `shortcuts.createPublicDesktopShortcuts` to `true` so public desktop shortcut creation is enabled by default.
- Updated [src/Tasks/Create-Shortcuts.ps1](src/Tasks/Create-Shortcuts.ps1) to self-elevate when needed for all-users shortcut locations.
- Updated [src/Tasks/Create-Shortcuts.ps1](src/Tasks/Create-Shortcuts.ps1) shortcut launch arguments to run Lab Tools elevated (`Start-Process -Verb RunAs`).

## v2026.03.04.2 - 2026-03-04

### Client Utilities Menu Reorganization
- Moved `Run Win11Debloat (official upstream script)` from [src/Menu/MaintenanceMenu.ps1](src/Menu/MaintenanceMenu.ps1) to Windows Client Tools > Utilities in [src/Menu/ClientToolsMenu.ps1](src/Menu/ClientToolsMenu.ps1).
- Expanded Utilities in [src/Menu/ClientToolsMenu.ps1](src/Menu/ClientToolsMenu.ps1) from 1 option to 2 options so `vmPing` and `Win11Debloat` are grouped together.
- Updated Maintenance option/key hints in [src/Menu/MaintenanceMenu.ps1](src/Menu/MaintenanceMenu.ps1) to reflect options [1]-[4] only.

### Global Search Catalog Update
- Added a direct search action for `Run Win11Debloat` (`RunOption = "U2"`) under Windows Client Tools > Utilities in [src/Menu/MainMenu.ps1](src/Menu/MainMenu.ps1).
- Kept Maintenance search coverage in [src/Menu/MainMenu.ps1](src/Menu/MainMenu.ps1) focused on update/shortcut/background/feedback tasks.

## v2026.03.04.1 - 2026-03-04

### Header Status and Client Menu Guidance
- Added an `Internet` status indicator in [src/UI/ConsoleUI.psm1](src/UI/ConsoleUI.psm1) to the app header with green/red checkmark state.
- Updated [src/Menu/ClientToolsMenu.ps1](src/Menu/ClientToolsMenu.ps1) top-level Windows Client categories with short context descriptions and option counts to improve discoverability.
- Styled Windows Client category description lines with `DarkGray` in [src/Menu/ClientToolsMenu.ps1](src/Menu/ClientToolsMenu.ps1) for better visual hierarchy.

### Global Search and Direct Action Execution
- Added a single global search entry on the main menu in [src/Menu/MainMenu.ps1](src/Menu/MainMenu.ps1) (`[S] Global Search`) with keyword matching across major tool areas.
- Expanded global search catalog coverage to include granular Windows Client, Troubleshooting, and DevOps actions in [src/Menu/MainMenu.ps1](src/Menu/MainMenu.ps1).
- Fixed single-result rendering in global search by normalizing match results as an array in [src/Menu/MainMenu.ps1](src/Menu/MainMenu.ps1).
- Added direct action execution from search results (instead of only opening menus) by introducing `RunOption` pathways in:
	- [src/Menu/ClientToolsMenu.ps1](src/Menu/ClientToolsMenu.ps1)
	- [src/Menu/TroubleshootingMenu.ps1](src/Menu/TroubleshootingMenu.ps1)
	- [src/Menu/DevOpsInstallUpdateMenu.ps1](src/Menu/DevOpsInstallUpdateMenu.ps1)
	- [src/Menu/DevOpsQuickChecksMenu.ps1](src/Menu/DevOpsQuickChecksMenu.ps1)
- Added a pre-execution confirmation line (`Running: <Area> > <Item>`) in [src/Menu/MainMenu.ps1](src/Menu/MainMenu.ps1) before launching a search-selected action.

## v2026.03.03.2 - 2026-03-03

### Maintenance Menu Addition
- Added a Win11Debloat pathway in [src/Menu/MaintenanceMenu.ps1](src/Menu/MaintenanceMenu.ps1) as option [5] (`Run Win11Debloat (official upstream script)`).
- Added [src/Tasks/Run-Win11Debloat.ps1](src/Tasks/Run-Win11Debloat.ps1), which opens the upstream project page on request and runs the official command from `https://debloat.raphi.re/` only after explicit user confirmation.

## v2026.03.03.1 - 2026-03-03

### Feedback and Menu UX Updates
- Added a feedback/reporting pathway using Microsoft Forms (`https://forms.office.com/r/5pJZNxzxgq`) in [src/Menu/MaintenanceMenu.ps1](src/Menu/MaintenanceMenu.ps1) as option [4] (`Report a Problem / Submit Feedback`).
- Removed the feedback option from [src/Menu/MainMenu.ps1](src/Menu/MainMenu.ps1) to keep the main menu uncluttered.
- Updated Maintenance menu key hints in [src/Menu/MaintenanceMenu.ps1](src/Menu/MaintenanceMenu.ps1) to reflect options [1]-[4].

### Maintenance Task Flow and Pause Behavior
- Updated option [1] in [src/Menu/MaintenanceMenu.ps1](src/Menu/MaintenanceMenu.ps1) to run update + shortcut repair + terminal background in sequence with a single menu pause at the end.
- Added optional pause control (`ShowPause`) in maintenance/client menu task helpers to reduce duplicate continue prompts during chained actions.
- Adjusted connectivity-task prompt handling in [src/Tasks/Client/Test-Connectivity.ps1](src/Tasks/Client/Test-Connectivity.ps1) to better avoid duplicate `Press Enter to continue` prompts when launched from menu flows.

## v2026.02.25.2 - 2026-02-25

### Maintenance Update Flow Fix
- Updated [src/Tasks/Update-LabTools.ps1](src/Tasks/Update-LabTools.ps1) post-update task discovery to support both deployed-root (`...\Tasks`) and repo-root (`...\src\Tasks`) layouts.
- This resolves option [1] cases where repo pull succeeded but shortcut/background steps were incorrectly skipped as "task not found".

## v2026.02.25.1 - 2026-02-25

### Maintenance Update Flow Fix
- Updated [src/Tasks/Update-LabTools.ps1](src/Tasks/Update-LabTools.ps1) to resolve post-update task scripts from the updater's local task folder first, with fallback to deployed `C:\CITA\LabTools\Tasks` paths.
- Added explicit post-update script-path logging so option [1] output shows exactly which shortcut/background task script is executed.

## v2026.02.25 - 2026-02-25

### Maintenance Update Flow
- Updated [src/Tasks/Update-LabTools.ps1](src/Tasks/Update-LabTools.ps1) so Maintenance option [1] now includes post-update shortcut repair by running `Create-Shortcuts.ps1` (non-blocking on failure).
- Kept post-update Windows Terminal background apply behavior in [src/Tasks/Update-LabTools.ps1](src/Tasks/Update-LabTools.ps1), so option [1] now covers both prior options [2] and [3] checks/actions.
- Updated Maintenance menu text in [src/Menu/MaintenanceMenu.ps1](src/Menu/MaintenanceMenu.ps1) to reflect that option [1] includes shortcut repair and terminal background apply.

## v2026.02.23.1 - 2026-02-23

### Shortcut and UX Refinements
- Updated [src/Tasks/Create-Shortcuts.ps1](src/Tasks/Create-Shortcuts.ps1) to create only `CITA Lab Tools.lnk`.
- Added legacy cleanup behavior to remove `CITA Server Setup.lnk` from managed shortcut locations when present.
- Added shortcut icon configuration in [src/config/labtools.json](src/config/labtools.json) via `shortcuts.iconRelativePath`, with fallback to the default PowerShell icon.
- Added [src/MISC/Icons/README.md](src/MISC/Icons/README.md) and a default icon folder for custom shortcut icon placement.
- Reduced noisy expected warnings by skipping all-users Desktop/Start Menu writes and public desktop cleanup when not running elevated.
- Kept public desktop shortcut behavior configurable via `shortcuts.createPublicDesktopShortcuts` (default `false`).

## v2026.02.22 - 2026-02-22

### Menu and Launch Experience
- Added [src/Launch-LabTools.ps1](src/Launch-LabTools.ps1) to start Lab Tools in Windows Terminal (`wt.exe`) when available, with PowerShell fallback.
- Added Windows Client Tools option [16] in [src/Menu/ClientToolsMenu.ps1](src/Menu/ClientToolsMenu.ps1) to launch vmPing from the local MISC path.
- Added [src/Tasks/Create-Shortcuts.ps1](src/Tasks/Create-Shortcuts.ps1) and Maintenance option [2] to create/repair current-user Desktop and Start Menu shortcuts.
- Expanded [src/Tasks/Create-Shortcuts.ps1](src/Tasks/Create-Shortcuts.ps1) to also repair legacy shortcut name (`CITA Server Setup.lnk`) and attempt all-users Desktop/Start Menu locations.
- Added [src/Tasks/Apply-TerminalBackground.ps1](src/Tasks/Apply-TerminalBackground.ps1) and Maintenance option [3] to apply Windows Terminal background settings from [src/config/terminal-background.json](src/config/terminal-background.json).
- Updated [src/Tasks/Update-LabTools.ps1](src/Tasks/Update-LabTools.ps1) to auto-run the Terminal background apply step after successful updates (non-blocking if it fails).

### MISC Asset Structure
- Added [src/MISC/README.md](src/MISC/README.md) as a deployable location for executables, images, and other growth assets.
- Added [src/MISC/vmPing/README.md](src/MISC/vmPing/README.md) with vmPing placement guidance (`vmPing.exe`).

## v2026.02.20 - 2026-02-20

### DevOps Menu Hardening
- Strengthened repo prerequisite flow with pre/post repair checks and safer sync conditions.
- Switched dirty-repo reset controls to explicit boolean behavior with conservative defaults.
- Added explicit git fetch/checkout/pull exit-code validation for clearer failure handling.
- Tightened readiness checks for valid git repo state and reachable kubeconfig where required.
- Improved menu UX with corrected option ordering, reduced redundant pauses, and clearer error/remediation messaging.
- Updated option [9] to prompt for control-plane and worker IPs while keeping adaptive full-build/add-ons workflow.
- Removed option [16] and renumbered Advanced Operations menu entries to maintain contiguous numbering.
- Expanded option [11] Portainer publishing to support Ingress host mode, NodePort IP mode, and LoadBalancer VIP mode.

### Documentation and Versioning
- Added a README recent-updates section for v2026.02.20.
- Bumped repository version to v2026.02.20.
