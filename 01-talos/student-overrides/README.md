# Student Talos Configuration Folder

This folder is intentionally empty.

When you run:

    .\bootstrap.ps1

Talos configuration files will be generated here automatically:

- controlplane.yaml
- worker.yaml
- talosconfig
- kubeconfig (in repo root)

---

## Why Are These Not in GitHub?

Talos configuration files contain:

- Cluster certificates
- Private keys
- Join tokens
- Sensitive cluster secrets

For security reasons, these files are generated locally and must **never** be committed to GitHub.

This repository is public and contains only:

- Templates
- Installation manifests
- Bootstrap scripts

---

## What Should Be In This Folder?

After running bootstrap.ps1, you will see:

01-talos/
  student-overrides/
    controlplane.yaml
    worker.yaml
    talosconfig

If you do not see these files, run bootstrap again.

---

## Important

If something breaks, you can safely:

1. Delete the contents of this folder
2. Re-run bootstrap.ps1

This folder is safe to regenerate at any time.
