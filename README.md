# Lab Scripts

PowerShell scripts and helpers for provisioning and managing lab environments.

## Overview

This repository contains a collection of PowerShell modules and scripts used to set up, configure, and maintain lab servers and clients. Typical tasks include installing roles, joining machines to a domain, renaming computers, configuring static IPs, and taking system snapshots.

## Prerequisites

- Windows PowerShell (tested on Windows PowerShell / PowerShell Core)
- Administrative privileges to run the configuration scripts
- Execution policy that permits running local scripts (e.g., `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process`)

## Repository Layout

- File: [src/VERSION.txt](src/VERSION.txt#L1)
- File: [src/config/labtools.json](src/config/labtools.json#L1)
- File: [src/Lib/Logging.psm1](src/Lib/Logging.psm1#L1)
- File: [src/Lib/Validation.psm1](src/Lib/Validation.psm1#L1)
- File: [src/Menu/ServerRoleMenu.ps1](src/Menu/ServerRoleMenu.ps1#L1)
- Files: [src/Tasks/Install-Roles.ps1](src/Tasks/Install-Roles.ps1#L1), [src/Tasks/Join-Domain.ps1](src/Tasks/Join-Domain.ps1#L1), [src/Tasks/Rename-Computer.ps1](src/Tasks/Rename-Computer.ps1#L1), [src/Tasks/Set-StaticIP.ps1](src/Tasks/Set-StaticIP.ps1#L1), [src/Tasks/System-Snapshot.ps1](src/Tasks/System-Snapshot.ps1#L1), [src/Tasks/Update-LabToolsFromGitHub.ps1](src/Tasks/Update-LabToolsFromGitHub.ps1#L1)

## Usage

1. Open PowerShell as Administrator.
2. (Optional) Allow script execution for the session:

``powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
``

3. Run a script, for example the server role menu:

``powershell
.\src\Menu\ServerRoleMenu.ps1
``

Or run a task directly, for example to install roles:

``powershell
.\src\Tasks\Install-Roles.ps1
``

## Contributing

PRs and issues are welcome. Keep changes focused and include a short description of the testing steps you used.

## License

No license specified. Add a LICENSE file if you want to declare one.

## Contact

For questions or help, open an issue in this repository.

