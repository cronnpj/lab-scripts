# Changelog

All notable changes to this repository are documented in this file.

## v2026.02.22 - 2026-02-22

### Menu and Launch Experience
- Added [src/Launch-LabTools.ps1](src/Launch-LabTools.ps1) to start Lab Tools in Windows Terminal (`wt.exe`) when available, with PowerShell fallback.
- Added Windows Client Tools option [16] in [src/Menu/ClientToolsMenu.ps1](src/Menu/ClientToolsMenu.ps1) to launch vmPing from the local MISC path.
- Added [src/Tasks/Create-Shortcuts.ps1](src/Tasks/Create-Shortcuts.ps1) and Maintenance option [2] to create/repair current-user Desktop and Start Menu shortcuts.

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
