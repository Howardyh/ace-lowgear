# ACE LowGear

**Shift ACE into low gear and let foreground work go first.**

[简体中文](README.md) · [Privacy](docs/PRIVACY.md) · [Design](docs/DESIGN.md) · [Testing](docs/TESTING.md)

A small Windows PowerShell tool that configures **Idle CPU priority** and **Very Low I/O priority** at process creation for `SGuard64.exe`, `SGuardSvc64.exe`, and `ACE-Service64.exe`. No resident monitor is required. This project is independent of ACE.

## Usage

Requires 64-bit Windows 10 or Windows 11 and the built-in Windows PowerShell 5.1. Extract the complete project, including `src`.

1. Run `Apply.cmd` and accept the administrator prompt. A temporary executable first verifies startup behavior on this Windows installation. Original values are backed up before any ACE values are changed.
2. Start the relevant application normally. Existing processes are not restarted or updated by registry configuration.
3. Run `Check.cmd`. `Configured=True` describes the registry rule. `Running=False` means actual runtime behavior has not been verified.
4. Run `Restore.cmd` to restore the original values, then restart the relevant application normally.

`Check.cmd` does not request elevation by default. If process reads are denied, rerun it with **Run as administrator**. Continued access denial remains a verification failure.

`SelfTest.cmd` runs only the temporary startup probe. `Last-CPU.cmd` optionally applies affinity to currently running target processes. It selects the highest active logical CPU index, supports one processor group with up to 64 logical CPUs, and must be rerun after a process restart. CPU/I/O startup rules remain available on multi-group systems.

If migrating from an earlier tool, restore its settings first and retain its original backup. A fresh installation treats the current settings as its restoration baseline.

## Verification

The desired IFEO values are `CpuPriorityClass=1` and `IoPriority=0`, both DWORD. Runtime values are `CpuClass=64` (Idle) and `IoPriority=0` (Very Low). These CPU values belong to different enums. An effective I/O value of `-1` means that additional query was unavailable; its status is reported separately.

`Check` exits with `0` when all targets are running and readable values match, `1` for a failure or runtime mismatch, and `2` for incomplete configuration or a target that is not running. `Apply` success means startup rules were configured, not that an ACE session has been validated.

Lower priority affects contention rather than imposing a CPU utilization cap. It may delay initialization or scanning on a busy computer. Individual threads, kernel drivers, and I/O requests may use their own priorities. Protected-process reads may fail even as administrator.

Child processes can inherit lower priority. Acceptance testing should also inspect the game process, particularly if a target program creates it.

## Portability and local state

Rules match executable names, independent of installation drive or user profile. Recovery data is stored under the local `%ProgramData%\ACE-LowGear`, with a digest of the Windows installation identity. Integrity and installation identity are checked before restoration. Copy source files between computers; retain each computer's own recovery data.

Repeated Apply preserves the first backup. Later changes to managed values stop automatic overwrite. Restore preserves unrelated registry values and removes only newly created empty keys. A pending recovery record is written before the first ACE write.

IFEO performance options and some native I/O queries are incompletely documented. The first Apply on each computer validates a normal baseline and two low-priority starts with an isolated executable. ARM64 and a multi-computer hardware acceptance matrix remain unverified. No driver, service, or scheduled task is installed.

## Development

Run `tools/Test-Project.ps1` for isolated HKCU registry transactions and an owned temporary-process check. Add `-StartupProbe` in administrator Windows PowerShell 5.1 to validate an isolated HKLM startup rule. Tests do not modify real ACE configuration.

Run `tools/Test-PublicContent.ps1` before publishing. `tools/Package.ps1` packages only the source allowlist in `public-files.json` and verifies archive contents and hashes. Runtime data, credentials, and machine reports are excluded.

Licensed under [MIT](LICENSE).
