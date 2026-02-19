# Lab Scripts

PowerShell scripts and helpers for provisioning and managing lab environments.

## Overview

This repository contains a collection of PowerShell modules and scripts used to set up, configure, and maintain lab servers and clients. Typical tasks include installing roles, joining machines to a domain, renaming computers, configuring static IPs, and taking system snapshots.

## Prerequisites

- Windows PowerShell (tested on Windows PowerShell / PowerShell Core)
- Administrative privileges to run the configuration scripts
- Execution policy that permits running local scripts (e.g., `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process`)

## Repository Layout

- File: [src/VERSION.txt](src/VERSION.txt)
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

## Contributing

PRs and issues are welcome. Keep changes focused and include a short description of the testing steps you used.

## License

No license specified. Add a LICENSE file if you want to declare one.

## Contact

For questions or help, open an issue in this repository.