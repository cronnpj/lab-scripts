# SDelete (Sysinternals)

Place the SDelete executable in this folder with this file name:

- `sdelete64.exe`

Runtime menu path:

- `Main > Windows Client Tools > Utilities > [3] Run SDelete free-space overwrite`
- `Main > Windows Client Tools > Utilities > [4] Run VM template prep checklist`

Typical template prep flow for VM images:

1. Run Sysprep (generalize)
2. Run SDelete with `-z` on the target volume (default in this repo task)
3. Shut down VM
4. (Optional) Sparsify/convert image
5. Convert VM to template

Notes:

- `-z` (zero free space) is best for VM template storage efficiency.
- `-c` (random overwrite) is available but does not improve thin image reclaim/compression.
