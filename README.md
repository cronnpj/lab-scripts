# Lab Scripts

![PowerShell](https://img.shields.io/badge/PowerShell-Automation-5391FE?style=for-the-badge&logo=powershell&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-Lab%20Ops-0078D4?style=for-the-badge&logo=windows&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-Bare%20Metal-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)
![Talos Linux](https://img.shields.io/badge/Talos-Linux-111111?style=for-the-badge)
![Helm](https://img.shields.io/badge/Helm-Charts-0F1689?style=for-the-badge&logo=helm&logoColor=white)
![MetalLB](https://img.shields.io/badge/MetalLB-LoadBalancer-5B2C87?style=for-the-badge)
![NGINX Ingress](https://img.shields.io/badge/NGINX-Ingress-009639?style=for-the-badge&logo=nginx&logoColor=white)
![Portainer](https://img.shields.io/badge/Portainer-Management-13BEF9?style=for-the-badge)
![Lab](https://img.shields.io/badge/Lab-Infrastructure%20Automation-34C759?style=for-the-badge)

PowerShell scripts and helpers for provisioning and managing lab environments.

## Overview

This repository contains a collection of PowerShell modules and scripts used to set up, configure, and maintain lab servers and clients. Typical tasks include installing roles, joining machines to a domain, renaming computers, configuring static IPs, and taking system snapshots.

## Recent Updates (v2026.02.20)

- Hardened DevOps repo prep flow in [src/Menu/DevOpsToolsMenu.ps1](src/Menu/DevOpsToolsMenu.ps1) with pre/post repair checks and safer sync behavior.
- Switched repo reset controls to explicit boolean parameters (`AutoResetIfDirty`) with conservative defaults.
- Improved Git sync reliability with explicit fetch/checkout/pull exit-code validation and clearer remediation messages.
- Tightened readiness checks to require a valid `.git` repository and reachable kubeconfig where needed.
- Polished menu UX by fixing option ordering, reducing redundant pauses, and aligning web demo apply behavior.
- Updated DevOps option [9] to prompt for control-plane and worker IPs while preserving smart full-build vs add-ons-only behavior.
- Removed DevOps option [16] and renumbered Advanced Operations options to keep numbering contiguous.
- Added DevOps option [11] mode selection for Portainer publish paths: Ingress host, NodePort IP, or LoadBalancer VIP.

## Prerequisites

- Windows PowerShell (tested on Windows PowerShell / PowerShell Core)
- Administrative privileges to run the configuration scripts
- Execution policy that permits running local scripts (e.g., `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process`)

## Repository Layout

- File: [src/VERSION.txt](src/VERSION.txt)
- File: [CHANGELOG.md](CHANGELOG.md)
- File: [src/config/labtools.json](src/config/labtools.json)
- Files: [src/Lib/Logging.psm1](src/Lib/Logging.psm1), [src/Lib/Validation.psm1](src/Lib/Validation.psm1)
- Menus: [src/Menu/MainMenu.ps1](src/Menu/MainMenu.ps1), [src/Menu/DevOpsToolsMenu.ps1](src/Menu/DevOpsToolsMenu.ps1), [src/Menu/MaintenanceMenu.ps1](src/Menu/MaintenanceMenu.ps1), [src/Menu/ServerToolsMenu.ps1](src/Menu/ServerToolsMenu.ps1), [src/Menu/TroubleshootingMenu.ps1](src/Menu/TroubleshootingMenu.ps1)
- Core tasks: [src/Tasks/Install-Roles.ps1](src/Tasks/Install-Roles.ps1), [src/Tasks/Join-Domain.ps1](src/Tasks/Join-Domain.ps1), [src/Tasks/Rename-Computer.ps1](src/Tasks/Rename-Computer.ps1), [src/Tasks/Set-StaticIP.ps1](src/Tasks/Set-StaticIP.ps1), [src/Tasks/System-Snapshot.ps1](src/Tasks/System-Snapshot.ps1), [src/Tasks/Update-LabTools.ps1](src/Tasks/Update-LabTools.ps1)
- Kubernetes lab: [labs/k8s-baremetal-lab/README.md](labs/k8s-baremetal-lab/README.md), [labs/k8s-baremetal-lab/bootstrap.ps1](labs/k8s-baremetal-lab/bootstrap.ps1)

## Usage

1. Open PowerShell as Administrator.
2. (Optional) Allow script execution for the session:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
```

3. Launch the main menu:

```powershell
.\src\Menu\MainMenu.ps1
```

Or run a task directly, for example to install roles:

```powershell
.\src\Tasks\Install-Roles.ps1
```

## DevOps Menu Map (Options 9-20)

- [9] Install core platform (interactive CP/worker IP prompts + adaptive full-build/add-ons path)
- [10] Repair / Reinstall MetalLB (IP pool/range)
- [11] Install / Reinstall Portainer Admin UI (Ingress host, NodePort IP, or LoadBalancer VIP)
- [12] Deploy / Update CITA Web Demo
- [13] Scale CITA Web Demo
- [14] Scale any deployed app (interactive selector)
- [15] Install / Update app via Helm (interactive)
- [16] Wipe + Rebuild cluster (student reset mode)
- [17] Nuke local generated files (kubeconfig + student-overrides)
- [18] Repo lab-safe reset (discard local changes)
- [19] Add new worker node to existing cluster
- [20] Reset CITA Web Demo only (delete namespace cita-web)

### Option 11 Quick Tests (Portainer)

- Ingress host mode (`I`)
	- Use when DNS or hosts mapping is available.
	- Expected URL: `http://portainer.<your-domain>`
	- Verify objects: `kubectl --kubeconfig C:\CITA\LabTools\labs\k8s-baremetal-lab\kubeconfig -n portainer get pods,svc,ingress`

- NodePort IP mode (`P`)
	- Use when you want no DNS/hosts dependency.
	- Find NodePort: `kubectl --kubeconfig C:\CITA\LabTools\labs\k8s-baremetal-lab\kubeconfig -n portainer get svc portainer`
	- Expected URL format: `https://<control-plane-or-worker-ip>:<nodeport>`

- LoadBalancer VIP mode (`L`)
	- Uses MetalLB to assign a VIP to Portainer service.
	- Get assigned VIP: `kubectl --kubeconfig C:\CITA\LabTools\labs\k8s-baremetal-lab\kubeconfig -n portainer get svc portainer -o wide`
	- Expected URL format: `https://<portainer-vip>:9443`

## Contributing

PRs and issues are welcome. Keep changes focused and include a short description of the testing steps you used.

## License

No license specified. Add a LICENSE file if you want to declare one.

## Contact

For questions or help, open an issue in this repository.