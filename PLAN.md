# CleanOS implementation plan

## Phase 0 — Safe MVP (implemented in 0.1.0)

- Single PowerShell entry point compatible with Windows PowerShell 5.1.
- No third-party modules or background service.
- Menu-driven workflows: Performance, Debloat, Privacy, Windows Update, Service manager and Rollback.
- Per-change JSON transaction journal and JSONL audit log stored under `%LOCALAPPDATA%\CleanOS`.
- Current-user registry changes are journaled before the UI reports completion.
- Rollback compares current values with the values written by CleanOS; it skips settings changed after the original action to avoid overwriting newer preferences.
- Appx removals are marked non-reversible and require an explicit `REMOVE` confirmation.
- Protected service list and executable path/signature filter for service-startup modifications.
- CI parse/smoke test and tagged ZIP release workflow.

## Phase 1 — Hardening before public release

1. Run `tests/Parse-SmokeTest.ps1` on Windows PowerShell 5.1 and PowerShell 7.
2. Test in clean Windows 10 22H2 + eligible ESU configuration, Windows 11 23H2/24H2/25H2/26H2 images as available, standard-user session and elevated session.
3. Validate RegistryKey value type round-trips, machine/user Run entries, and rollback after partial failure.
4. Validate service filtering against common GPU, audio, VPN, anti-cheat and OEM services; keep ambiguous services blocked.
5. Add Pester unit tests for snapshot comparison and transaction serialization.
6. Review release workflow and pin third-party GitHub Actions to commit SHAs before a security-sensitive public release.
7. Optionally Authenticode-sign the distributed `.ps1` with a trusted code-signing certificate.

## Phase 2 — UX and observability

- Add a preview/dry-run report before applying batch changes.
- Add export/import of a diagnostic report with explicit redaction.
- Add clear Windows build compatibility checks and localized messages.
- Add per-setting links to Microsoft documentation.
- Add a first-run system restore point option only where System Restore is enabled; do not imply that a restore point guarantees undo for every application change.

## Non-goals

- No silent removal of provisioned Appx packages.
- No blanket service disabling, telemetry-service disabling, Defender/firewall changes, Windows Update disabling, network-stack modifications, or anti-cheat bypasses.
- No remote telemetry, scheduled background task, driver installer, or automatic self-update.
