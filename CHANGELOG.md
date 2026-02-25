# Changelog

All notable changes to this repository are documented in this file.

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
