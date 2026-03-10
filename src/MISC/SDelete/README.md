# SDelete (Sysinternals)

Place the SDelete executable in this folder with this file name:

- `sdelete64.exe`

Runtime menu path:

- `Main > Windows Client Tools > Utilities > [3] Run SDelete free-space overwrite`
- `Main > Windows Client Tools > Utilities > [4] Run VM template prep checklist`

Typical template prep flow for VM images:

1. Run SDelete with `-z` on the target volume (default in this repo task)
2. Run Sysprep (generalize + OOBE + shutdown)
3. (Optional) Sparsify/convert image
4. Convert VM to template

Notes:

- `-z` (zero free space) is best for VM template storage efficiency.
- `-c` (random overwrite) is available but does not improve thin image reclaim/compression.
