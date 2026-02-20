# Changelog

All notable changes to this repository are documented in this file.

## v2026.02.20 - 2026-02-20

### DevOps Menu Hardening
- Strengthened repo prerequisite flow with pre/post repair checks and safer sync conditions.
- Switched dirty-repo reset controls to explicit boolean behavior with conservative defaults.
- Added explicit git fetch/checkout/pull exit-code validation for clearer failure handling.
- Tightened readiness checks for valid git repo state and reachable kubeconfig where required.
- Improved menu UX with corrected option ordering, reduced redundant pauses, and clearer error/remediation messaging.

### Documentation and Versioning
- Added a README recent-updates section for v2026.02.20.
- Bumped repository version to v2026.02.20.
