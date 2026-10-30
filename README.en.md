# 🪶 ACE LowGear

Lower ACE CPU / I/O priorities after each startup, verify, then exit. [简体中文](README.md)

## 🚀 Install: start here

**Use 64-bit Windows 10/11 and allow the administrator prompt. No commands, programming, Python, Node.js or .NET SDK installation are needed.**

### 1. Download the recommended ZIP

**[⬇️ Download ACE LowGear 1.4.0 source package](https://github.com/Howardyh/ace-lowgear/releases/download/v1.4.0/ace-lowgear-1.4.0-source.zip)**

The source package includes a ready-to-use launcher and compiles the worker automatically. You do not compile it yourself. On the [latest release page](https://github.com/Howardyh/ace-lowgear/releases/latest), expand **Assets** and select `ace-lowgear-<version>-source.zip`. The `.sha256` is a checksum, not a program. GitHub's automatic Source code archives are repository snapshots; use the recommended package for these steps.

### 2. Extract every file

Right-click the downloaded ZIP, choose **Extract All**, and open the extracted folder, then its **ace-lowgear** subfolder. You should see **开始使用.cmd**, **Start.cmd**, **LowGear.ps1**, **src** and **ui** together. Run from that extracted folder, keep all files together, and avoid running inside the ZIP viewer or copying only a launcher.

### 3. Open the launcher

Double-click **开始使用.cmd** or **Start.cmd** and choose **Yes** at the Windows administrator prompt. File extensions may be hidden; select the command script, while **开始使用.txt** is the short manual. If you cancelled authorization, open the launcher again when ready.

### 4. Follow the first-install wizard

1. Keep the default affinity choice on first use, then click **下一步：检查** (Next: Check).
2. Wait for preflight. If there are no blocking issues, click **确认并启用** (Confirm and enable). Otherwise follow the explanation or open Diagnostics.
3. Wait for completion before closing or clicking again.
4. **配置已完成** means automatic execution is configured. **等待游戏启动** means no game target is running yet; continue below.

Choosing **先查看面板** (View panel first) remembers deferral. To install later, open **概览 → 启用自动管理**. Existing installations enter the panel directly; follow the upgrade steps below when offered.

### 5. Launch the game and check the result

Launch your game normally, wait about **45 seconds**, reopen the panel and click **刷新** (Refresh) in Overview. If the game was already running before installation, exit and restart it normally. Automation should show **已启用**; running targets should show CPU **低**, I/O **非常低**, and **已核验**. A target marked **未运行 · 等待启动** is absent and has not been verified; all three targets need not run together. For unknown readings or configuration errors, open Diagnostics.

**After enabling, close the panel and launch games as usual. Rebooting requires no repeat installation or manual tool launch.** Resume automation first if you paused it yourself.

## ♻️ Upgrade an existing installation

Extract the new package into a **new folder**, retaining the old source and recovery data. Open the new launcher, choose **升级本机组件**, review the versions and select **确认升级**. Wait for the result, then use the new entry point. Original backups, affinity and enabled/paused state are retained; paused installations stay paused. No repeat upgrade is needed for the same installed version. For 0.1.x, read the migration section below first.

## ❓ Common installation questions

| Situation | Next step |
|---|---|
| Missing files | Extract the complete ZIP and find the folder containing src and ui |
| No panel appears | Open Start.cmd to read the startup message and complete authorization |
| Notepad opens | Check that you selected the .cmd launcher rather than 开始使用.txt |
| No first-install wizard | Use Enable in Overview if uninstalled, or Upgrade for an older installed component |
| Configured, but no targets | Launch the game, wait and refresh; configuration is separate from live verification |
| Temporarily stop automation | Choose 暂停自动执行 in Settings, then resume when needed |
| Undo the tool's changes | Confirm 完整恢复原设置 in Settings; deleting the downloaded folder does not restore system settings |

For help, preview the diagnostic summary and [open an issue](https://github.com/Howardyh/ace-lowgear/issues). Do not share original backups or personal paths.

## 🪶 Features and details

[![Verify source](https://github.com/Howardyh/ace-lowgear/actions/workflows/verify.yml/badge.svg)](https://github.com/Howardyh/ace-lowgear/actions/workflows/verify.yml)
[![Release](https://img.shields.io/github/v/release/Howardyh/ace-lowgear)](https://github.com/Howardyh/ace-lowgear/releases/latest)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

ACE LowGear is a Windows scheduling tool with a Chinese panel. It applies priorities, reads them back and exits after each startup. The panel can stay closed; no resident correction process is required. It is independent of ACE and not affiliated with its publisher.

| Setting | Target |
|---|---|
| CPU priority | Idle |
| I/O priority | Very Low |
| CPU affinity | Unchanged by default; optional last logical CPU |
| Images | `SGuard64.exe`, `SGuardSvc64.exe`, `ACE-Service64.exe` |

## 📦 Installation and delivery in 1.4

The independent first-install wizard introduces the policy, performs read-only checks, asks for explicit confirmation, then shows execution and results. Choosing **先查看面板** remembers deferral; use Overview to install later. Existing and paused installations enter the panel directly, with uncertain or damaged state routed to Diagnostics.

The primary launcher uses Windows PowerShell directly, reports missing runtime files, authorization cancellation and interface failures, and exits after readiness. A timeout does not kill or restart the original process. Installation, upgrade and restore have independent result pages; absent targets remain waiting, and paused upgrades stay paused.

Use `.\LowGear.ps1 -Command Preflight -Json` for read-only checks (0 passes, 1 blocks). Existing commands retain their exit codes. Source archives use stage-neutral documentation; candidate/stable status and later machine acceptance are recorded on the release page without replacing frozen package hashes. See [installation and delivery](docs/安装与交付.md).

## 🪟 Appearance and placement in 1.3

Open **设置 → 外观** (Settings → Appearance):

- **背景材质** selects automatic native Mica or an explicit solid background. The panel explains the actual effect; high contrast, system transparency and battery saver remain authoritative.
- **记住窗口大小和位置** is enabled by default. Normal close saves logical normal bounds, relative placement and maximized state. A minimized close never causes a hidden startup. Disabling memory clears the saved placement without moving the current window.
- Placement adapts to current work areas and WPF scale, supports negative secondary-monitor coordinates and returns to the primary display when the saved display is absent. Small work areas relax minimum dimensions. Live recovery only moves a window with an inaccessible caption.
- **恢复外观默认** restores system theme, automatic Mica and window memory, then centres a normal 1060×800 window on the current display, fitting smaller work areas. Scheduling policies and original backups are retained.

The existing theme-only `ui.json` is unchanged. Its sibling `appearance.json` stores material and placement only; malformed geometry resets independently. No display identifiers are collected, and geometry is excluded from diagnostics and source packages. Closing releases display-change hooks.

The 1.3 appearance features remain available; historical acceptance is recorded in [verification](docs/验证.md). Opening the new panel does not automatically upgrade the worker. Existing installations use **升级本机组件**, retaining enabled/paused state, policy and the earliest backup. Physical display unplugging and simulated layouts are reported separately.

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
