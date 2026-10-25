# 🪶 ACE LowGear

**Lower ACE CPU / I/O priorities after each startup, verify, then exit.**

[![Verify source](https://github.com/Howardyh/ace-lowgear/actions/workflows/verify.yml/badge.svg)](https://github.com/Howardyh/ace-lowgear/actions/workflows/verify.yml)
[![Release](https://img.shields.io/github/v/release/Howardyh/ace-lowgear)](https://github.com/Howardyh/ace-lowgear/releases/latest)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[简体中文](README.md) · [Download](https://github.com/Howardyh/ace-lowgear/releases/latest)

ACE LowGear is a Windows process scheduling tool with a Chinese control panel. Enable it once, then launch your game as usual. It applies low priorities when ACE starts, reads them back, and exits. **The panel can stay closed; no resident correction process is required.** Independent of ACE and not affiliated with its publisher.

| Setting | Target |
|---|---|
| CPU priority | Idle |
| I/O priority | Very Low |
| CPU affinity | Unchanged by default; optional last logical CPU |
| Images | `SGuard64.exe`, `SGuardSvc64.exe`, `ACE-Service64.exe` |

## 🚀 Quick start

1. Open [Releases](https://github.com/Howardyh/ace-lowgear/releases/latest) and download `ace-lowgear-1.0.0-source.zip` from **Assets**. Extract the entire archive into a folder. Keep all included files together.
2. Double-click **`Start.cmd`**, accept the Windows administrator prompt, and open the control panel.
3. Click **启用自动管理** (Enable automatic management). After it finishes, close the panel and launch your game normally.

The installer checks startup priority behavior, saves the original settings and registers automatic execution. The executable is compiled locally from the included source. No Python, Node.js or .NET SDK installation is required.

**After reboot:** no repeat installation or manual launch is needed. Each ACE startup triggers a new session. If you previously paused automation, use **恢复自动执行** to resume.

On first use, launch your game, wait about 45 seconds, then open the panel and click **刷新状态** (Refresh). Running targets should show CPU **低**, I/O **非常低**, and **已核验** (Verified).

## 🎛️ Controls

| Chinese label | Action |
|---|---|
| 启用自动管理 | Install or enable; keep the earliest original backup |
| 立即应用一次 | Apply and read back CPU / I/O settings for current instances |
| 刷新状态 | Read startup configuration, live values and the last session result |
| 本次绑定最后 CPU | Apply low priorities and last-logical-CPU affinity once |
| 启动时也绑定最后一个逻辑 CPU | Check, then enable management to apply affinity in each startup session |
| 运行自检 | Test startup behavior with a temporary, uniquely named process |
| 暂停自动执行 | Remove automatic triggering and stop the task; keep startup rules and backups |
| 恢复自动执行 | Restore automatic triggering and run one session now |
| 完整恢复原设置 | Remove automation and restore the original startup settings; keep backups |

Affinity is optional and detected from the current computer's active CPU mask. It supports one processor group with up to 64 logical CPUs. Multi-group systems can use priority management independently. To disable startup affinity, uncheck it and enable management again; existing process affinity lasts until a normal restart.

## 🔎 Reading results

- **已启用 · 等待启动**: automatic execution is configured and currently idle.
- **本次执行中**: a bounded startup session is running.
- **已配置**: startup rules match; check live values separately.
- **已核验**: readable CPU / I/O values and any enabled affinity policy match.
- **未运行 · 等待启动**: this image is not running and cannot be verified yet.
- **未读取** or an error: the query failed; unknown values stay null.

Not all three images must always be running. A completed automatic session requires both core images, `SGuard64.exe` and `SGuardSvc64.exe`, plus matching readings for every running target, three times in a row. An incomplete session is reported explicitly.

## ⏱️ Once per startup

Windows startup rules establish defaults. A filtered process-start event starts a SYSTEM task, which waits about 5 seconds, applies settings and reads them back. It exits after successful verification or a roughly 45-second session limit. The task also has a 2-minute outer limit. Closely spaced events share one task instance.

**After completion, later priority increases are left alone.** A new ACE startup creates another session; use the one-time action for an immediate manual application. Image identity is checked through the process handle before changes to reduce PID-reuse errors.

Low priority yields resources under contention. It does not cap CPU utilization or guarantee more FPS. Threads, drivers and individual I/O requests can behave differently. Game processes may inherit lower priorities, so check normal gameplay on first use. The tool includes no driver, injection or protection bypass; access failures are reported.

## 💻 Requirements and recovery

Use 64-bit Windows 10/11 with built-in Windows PowerShell 5.1, WMI, Task Scheduler and .NET Framework. Administrator permission is required. No network, account or credentials are required at runtime. ARM64 and broader hardware acceptance remain unverified.

Runtime files, original backups and session records stay under `%ProgramData%\ACE-LowGear\v1`, writable only by administrators and SYSTEM. Source files can move. Install independently on each computer; do not transfer machine recovery data between computers.

Recovery validates the Windows installation, target list and backup hash, preserves registry value types and refuses later conflicting edits. Full Restore affects startup settings; restart existing target processes normally to use their original settings.

## ♻️ Upgrade from 0.1.x

Keep the old source and recovery data. Extract this version, open `Start.cmd` and enable management, or run the new `Apply.cmd`.

The installer validates and imports the **original pre-0.1-change baseline**, then removes the old resident task. Failed installation attempts try to roll back settings and the old task. After migration, use only the new entry points. Full Restore returns to the earliest baseline without re-enabling the old guard.

## 🧰 Shortcuts and CLI

`Start.cmd` opens the panel. `Apply.cmd` installs/enables, `Check.cmd` checks status, `Last-CPU.cmd` applies last-CPU affinity once, and `SelfTest.cmd` runs a startup test. `Stop-Guard.cmd` / `Resume.cmd` pause/resume automatic execution; `Restore.cmd` fully restores original settings.

```powershell
.\LowGear.ps1 -Command Install
.\LowGear.ps1 -Command Status -Json
.\LowGear.ps1 -Command ApplyOnce
.\LowGear.ps1 -Command LastCpu
.\LowGear.ps1 -Command Install -BindLastCpu
.\LowGear.ps1 -Command SetAffinity  # Disable affinity for future startups
.\LowGear.ps1 -Command Pause
.\LowGear.ps1 -Command Resume
.\LowGear.ps1 -Command SelfTest
.\LowGear.ps1 -Command Restore
```

Status and one-time actions return `0` when current readings match, `1` for failures or live mismatches, and `2` when at least one target is absent. The task is named `ACE-LowGear`, and event objects are named `ACE-LowGear-ProcessStart`.

## 🧪 Verification and privacy

Isolated tests cover original-state recovery, migration, rollback, native priorities, affinity, real Windows startup events, session exit and no continuing correction afterward. A user has also reported successful real ACE verification after reboot on one computer. This does not establish compatibility with every computer or game environment.

Run `tests/Run.ps1`; add `-StartupProbe` in an administrator Windows PowerShell session for real temporary IFEO tests. Run `tests/Event.ps1` as administrator for real event/task tests. Use `tools/Validate-Public.ps1` before `tools/Package.ps1` to validate and package the explicit source allowlist.

The project has no telemetry or automatic uploads. `public-files.json` allows only source, documentation and tests. Generated executables, machine backups, state and logs are excluded. When [reporting an issue](https://github.com/Howardyh/ace-lowgear/issues), redact personal paths, usernames and machine identifiers; do not upload original backups.

Licensed under [MIT](LICENSE).
