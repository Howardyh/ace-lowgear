# 🪶 ACE LowGear

> **1.3.0 stable:** Mica control, window memory and safe placement recovery, retaining the Fluent panel and apply-on-startup, verify and exit. [Download latest](https://github.com/Howardyh/ace-lowgear/releases/latest) · [Previous 1.2](https://github.com/Howardyh/ace-lowgear/releases/tag/v1.2.0)

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

1. Download `ace-lowgear-1.3.0-source.zip` from the **Assets** of [stable 1.3](https://github.com/Howardyh/ace-lowgear/releases/tag/v1.3.0), then extract it in full. Keep all included files together. [Previous 1.2](https://github.com/Howardyh/ace-lowgear/releases/tag/v1.2.0) remains available.
2. Double-click **`Start.cmd`**, accept the Windows administrator prompt, and open the control panel.
3. Click **启用自动管理** (Enable automatic management). After it finishes, close the panel and launch your game normally.

The installer checks startup priority behavior, saves the original settings and registers automatic execution. The executable is compiled locally from the included source. No Python, Node.js or .NET SDK installation is required.

**After reboot:** no repeat installation or manual launch is needed. Each ACE startup triggers a new session. If you previously paused automation, use **恢复自动执行** to resume.

On first use, launch your game, wait about 45 seconds, then open the panel and click **刷新状态** (Refresh). Running targets should show CPU **低**, I/O **非常低**, and **已核验** (Verified).

## 🪟 Appearance and placement in 1.3

Open **设置 → 外观** (Settings → Appearance):

- **背景材质** selects automatic native Mica or an explicit solid background. The panel explains the actual effect; high contrast, system transparency and battery saver remain authoritative.
- **记住窗口大小和位置** is enabled by default. Normal close saves logical normal bounds, relative placement and maximized state. A minimized close never causes a hidden startup. Disabling memory clears the saved placement without moving the current window.
- Placement adapts to current work areas and WPF scale, supports negative secondary-monitor coordinates and returns to the primary display when the saved display is absent. Small work areas relax minimum dimensions. Live recovery only moves a window with an inaccessible caption.
- **恢复外观默认** restores system theme, automatic Mica and window memory, then centres a normal 1060×800 window on the current display, fitting smaller work areas. Scheduling policies and original backups are retained.

The existing theme-only `ui.json` is unchanged. Its sibling `appearance.json` stores material and placement only; malformed geometry resets independently. No display identifiers are collected, and geometry is excluded from diagnostics and source packages. Closing releases display-change hooks.

Version 1.3 is stable after user interface acceptance, 248 local checks and a verified local 1.2 → 1.3 upgrade. Opening the new panel does not automatically upgrade the installed worker. Existing installations can use **升级本机组件**, retaining enabled/paused state, policy and the earliest backup. Physical display unplugging is not yet accepted; native window checks and simulated display layouts are reported separately in [verification](docs/验证.md). The tested tag and source archive are unchanged; their prerelease-era notes remain historical. This page and the release page describe the current release status.

## 🆕 Fluent panel in 1.2

Version 1.2 passed 196 local checks, including native window material tests. A local upgrade from 1.1 preserved state and backups, and the user confirmed acceptance. This run did not capture fresh real ACE startup readings for 1.2 or automate physical mouse dragging; see the [verification scope](docs/验证.md).

- **Overview / 概览:** automation configuration and live verification are separate. The primary action follows installation, upgrade and paused states. Expand each target group for every instance's PID, effective I/O, raw readings and local errors.
- **Settings / 设置:** switch immediately between system, light and dark themes. Affinity changes remain drafts until **保存策略** (Save policy); first installation includes the selected choice. Pause, resume, component upgrade and full restore are grouped here.
- **Diagnostics / 诊断:** independent health sections, self-test, manual repair, one-time last-CPU binding and diagnostic preview/copy remain available.
- **Materials:** supported Windows 11 systems attempt native Mica, with a solid fallback for unsupported systems, transparency disabled, high contrast, battery saver or API failure. Windows 10 retains scheduling functionality. Only the theme choice is stored in `%LocalAppData%\ACE-LowGear\ui.json`; invalid preferences fall back to system theme.
- **Feedback:** Chinese operation stages, indeterminate progress, visible stale-data timestamps, compact navigation and close protection. Full restore explains its effects before confirmation.

## 🆕 Changes in 1.1

- From 1.0.0, open the new `Start.cmd` and choose **升级本机组件**. The earliest original backup, affinity policy and paused/enabled state are retained. Failed upgrades try to roll back; use **修复自动执行** to undo an interrupted deployment.
- The header distinguishes panel and installed versions. Session results show their time and duration. Configuration health and live verification are displayed separately, including partial-query failures.
- Version 1.1 grouped affinity and self-test under advanced options; 1.2 moves them into Settings and Diagnostics. First-time guidance explains enabling management, starting the game and checking live results.
- Repair only rebuilds owned task/event configuration. Conflicting edits, unknown ownership, damaged backups and invalid policies are not overwritten. Paused installations stay paused.
- Preview **诊断摘要…** before copying it. The allowlisted summary contains versions, processor counts, configuration states and error codes, with no usernames, paths, PIDs, machine identifiers, raw messages or backups. Nothing is uploaded automatically.
- Reads run away from the UI thread: about 5 seconds for processes, 30 seconds for full checks. Manual refresh forces a full check; queries never overlap. Closing waits while a configuration-changing operation is active.

```powershell
.\LowGear.ps1 -Command Upgrade
.\LowGear.ps1 -Command Repair
.\LowGear.ps1 -Command Diagnose
.\LowGear.ps1 -Command Install -ClearLastCpu
```

`Upgrade` retains paused/enabled state. `Install` keeps its install-and-enable meaning and preserves the affinity choice when omitted. Existing shortcuts and exit codes remain supported. No resident correction, automatic updates, telemetry or portable EXE is added.

## 🎛️ Controls

| Page | Chinese label | Action |
|---|---|---|
| Overview | Primary action | Enable, upgrade, resume or apply once according to current state |
| Overview | 立即应用一次 | Apply and read back low CPU / Very Low I/O for current instances |
| All pages | 刷新 | Force a full configuration and live process check |
| Settings | 明暗主题 | System, light or dark; applied immediately and stored locally |
| Settings | 背景材质 | Automatic Mica or solid; show the actual effect and reason |
| Settings | 记住窗口大小和位置 | Save on normal close; disabling memory keeps current placement |
| Settings | 恢复外观默认 | Reset appearance and centre the normal window on its current display |
| Settings | 启动时绑定最后一个逻辑 CPU | Save explicitly, or include the selection during first enable |
| Settings | 暂停 / 恢复自动执行 | Manage automatic triggering while retaining startup rules and backups |
| Settings | 升级本机组件 | Preserve enabled/paused state, original backup and affinity policy |
| Settings | 完整恢复原设置 | Confirm and restore the earliest startup baseline; retain backups |
| Diagnostics | 预览诊断摘要… | Preview the sanitized summary before copying; no automatic upload |
| Diagnostics | 修复自动执行 | Rebuild owned task/event configuration while retaining pause |
| Diagnostics | 运行自检 | Test startup behaviour with an isolated temporary process |
| Diagnostics | 本次绑定最后 CPU | Apply low priorities and last-logical-CPU affinity once |

Affinity is optional and detected from the current computer. Last-CPU binding supports one processor group with up to 64 logical CPUs; priority management remains available independently on multi-group systems. Saving changes affects future startups; existing instances retain their affinity until a normal restart or an explicit one-time binding.

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

Version 1.1 passed **126 local checks** covering existing features, upgrade rollback, diagnostic privacy, the asynchronous panel and real Windows startup events. In real ACE acceptance on one computer on 2026-10-28, both core images matched CPU / I/O and the existing affinity policy. A fresh session completed in about 11.1 seconds, the worker exited, and three subsequent read-only checks matched. `ACE-Service64.exe` was absent and was not verified. **A full reboot has not been tested with 1.1; the earlier reboot acceptance report applies to 1.0.0.** Other computers and game environments still need their own initial verification.

Run `tests/Run.ps1`; add `-StartupProbe` in an administrator Windows PowerShell session for real temporary IFEO tests. Run `tests/Event.ps1` as administrator for real event/task tests, `tests/Upgrade.ps1` for upgrade and privacy tests, and `tests/Panel.ps1` in an STA session for panel checks. Use `tools/Validate-Public.ps1` before `tools/Package.ps1` to validate and package the explicit source allowlist.

Run `tests/Window.ps1` for a real HWND lifecycle and material fallback, and `tests/Appearance.ps1` in an STA session for isolated appearance persistence, close/reopen behavior and simulated display layouts. These tests use temporary preferences rather than the user's appearance files.

The project has no telemetry or automatic uploads. `public-files.json` allows only source, documentation and tests. Generated executables, machine backups, state and logs are excluded. When [reporting an issue](https://github.com/Howardyh/ace-lowgear/issues), describe the steps and share the panel's diagnostic summary after previewing it. Redact personal paths, usernames and machine identifiers from any additional material; do not upload original backups.

Licensed under [MIT](LICENSE).
