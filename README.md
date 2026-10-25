# 🪶 ACE LowGear

**每次 ACE 启动，自动降低 CPU / I/O 优先级，核验后退出。**

[![Verify source](https://github.com/Howardyh/ace-lowgear/actions/workflows/verify.yml/badge.svg)](https://github.com/Howardyh/ace-lowgear/actions/workflows/verify.yml)
[![Release](https://img.shields.io/github/v/release/Howardyh/ace-lowgear)](https://github.com/Howardyh/ace-lowgear/releases/latest)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[English](README.en.md) · [下载最新版](https://github.com/Howardyh/ace-lowgear/releases/latest) · [设计说明](docs/经验与设计.md) · [隐私说明](docs/隐私.md)

ACE LowGear 是一个用于 Windows 的 ACE 进程调度工具，带有中文控制面板。首次启用后，照常启动游戏即可：工具会在 ACE 启动时设置优先级、回读确认，然后结束本次任务。**无需一直打开面板，也没有常驻纠错程序。**

| 管理项 | 设置 |
|---|---|
| CPU 优先级 | 低（Idle） |
| I/O 优先级 | 非常低（Very Low） |
| CPU 相关性 | 默认保持原设置，可选绑定最后一个逻辑 CPU |
| 目标程序 | `SGuard64.exe`、`SGuardSvc64.exe`、`ACE-Service64.exe` |

项目与 ACE 官方无隶属关系。

## 🚀 三步开始

1. 到 [Releases 页面](https://github.com/Howardyh/ace-lowgear/releases/latest)，在 **Assets** 中下载 `ace-lowgear-1.0.0-source.zip`，**完整解压**到一个普通文件夹。不要直接在压缩包里运行，也不要只下载单个启动文件。
2. 双击 **`Start.cmd`**，允许 Windows 管理员提示，打开中文控制中心。
3. 点击 **“启用自动管理”**，等待完成。之后可以关闭面板，正常启动游戏。

首次启用会检查本机启动优先级功能、保留原始设置，再注册自动执行。公开包只含源码，执行程序会在本机编译；**无需安装 Python、Node.js 或 .NET SDK**。

**重启后的使用：**启用状态会保留，下次 ACE 启动时仍会自动执行，无需重新安装。手动暂停后，可在面板点击“恢复自动执行”。

首次使用时，建议启动游戏并等待约 45 秒，再打开面板点击 **“刷新状态”**，确认运行实例的 CPU 为“低”、I/O 为“非常低”，结果为“已核验”。

## 🎛️ 面板能做什么

| 按钮或选项 | 用途 |
|---|---|
| 启用自动管理 | 完成本机自检、备份和自动触发配置；重复启用不会覆盖最早备份 |
| 立即应用一次 | 对当前运行实例设置低 CPU / 非常低 I/O，并立即回读 |
| 刷新状态 | 查看启动规则、当前进程读值和最近一次会话结果 |
| 本次绑定最后 CPU | 为当前实例设置低优先级，并绑定最后一个逻辑处理器 |
| 启动时也绑定最后一个逻辑 CPU | 勾选后点击“启用自动管理”，每次 ACE 启动时一并绑定 |
| 运行自检 | 用随机命名的临时程序验证启动规则，完成后清理测试资料 |
| 暂停自动执行 | 停止当前任务并移除自动触发；启动优先级规则和备份保留 |
| 恢复自动执行 | 恢复自动触发，并执行一次当前实例检查 |
| 完整恢复原设置 | 移除自动触发和任务，恢复第一次修改前的启动设置；备份保留 |

“最后 CPU”指**逻辑处理器**，编号由本机自动检测。默认不改变相关性；需要此功能时再勾选即可。取消启动绑定可取消勾选后再次点击“启用自动管理”，已有实例的相关性会保留到正常重启。

## 🔎 怎样看结果

| 显示 | 含义 |
|---|---|
| 已启用 · 等待启动 | 自动触发已配置，本次任务当前没有运行 |
| 本次执行中 | 正在对这次启动进行有限设置和核验 |
| 已配置 | 启动规则已写入；当前进程是否达标要看运行读值 |
| 已核验 | 当前实例可读取的 CPU / I/O 及启用的相关性策略符合目标 |
| 未运行 · 等待启动 | 该程序当前没有运行，尚不能验证它的实际优先级 |
| 未读取 / 错误原因 | 查询失败，保留真实原因；未知值不会伪装成 `0` 或 `-1` |
| 触发配置异常 / 需要恢复检查 | 请查看错误原因，处理后再启用或恢复 |

三个目标程序不一定都在运行，未运行的行会单独标明。自动会话的完成条件是两个核心程序 `SGuard64.exe`、`SGuardSvc64.exe` 均运行，且所有运行目标连续三次符合策略。最近会话未能完成时会明确显示结果。

## ⏱️ “执行一次”如何工作

Windows 启动规则先提供低优先级默认值。匹配的 ACE 进程启动事件再唤起一次性任务：先等待约 5 秒，再进行有限次设置和回读。核验完成后退出；整个会话最多约 45 秒，任务另设 2 分钟的外层时间上限。紧邻的启动事件由单实例任务合并处理。

**会话完成后，优先级即使又被改高，也不会持续纠正。** 下次 ACE 启动会触发新会话；需要立刻处理时，可点击“立即应用一次”。修改前会通过进程句柄核验程序名，减少 PID 复用带来的误操作。

最低优先级表示资源争用时优先让路，并不限制 CPU 占用率，也不保证帧数提升。线程、内核驱动及独立 I/O 请求可能使用自己的优先级。游戏进程可能继承较低优先级，首次使用请同时确认游戏正常运行。工具不包含驱动、注入或保护绕过，权限不足时会报告失败。

## 💻 系统要求与本机资料

- 64 位 Windows 10 / 11，使用系统内置的 Windows PowerShell 5.1、WMI、计划任务和 .NET Framework。
- 需要管理员权限来安装、管理和完整读取状态；运行本身不需要网络、账户或凭据。
- 相关性绑定支持单处理器组、最多 64 个逻辑处理器。多处理器组下会明确拒绝该绑定选项，CPU / I/O 功能可独立使用。ARM64 尚未验证。
- 本机执行程序、原始备份和会话记录位于 `%ProgramData%\ACE-LowGear\v1`，普通用户可读，管理员与 SYSTEM 可写。
- 源码可移动到其他目录；每台电脑首次使用时独立安装并备份。**不要把本机运行资料复制到其他电脑。**

备份会核验 Windows 安装归属、固定目标清单和 SHA-256，并保留原值的存在性、类型及内容。恢复遇到其他工具后续修改的值时会停止并说明差异。详见[迁移与恢复](docs/迁移与恢复.md)。

## ♻️ 从 0.1.x 升级

保留旧目录和恢复资料，解压新版后运行 `Start.cmd`，点击“启用自动管理”，也可直接运行新版 `Apply.cmd`。

新版会核验并导入**旧版第一次修改前**的原始备份，成功后移除旧常驻任务。失败会尝试恢复迁移前设置及旧任务。迁移完成后请统一使用新版入口，避免新旧工具交替修改设置。新版“完整恢复”不会重新启用旧常驻任务。

## 🧰 快捷入口与命令行

所有快捷入口都调用同一套控制器：

| 文件 | 功能 |
|---|---|
| `Start.cmd` | 打开控制中心 |
| `Apply.cmd` | 安装或启用自动管理 |
| `Check.cmd` | 检查配置与当前进程 |
| `Last-CPU.cmd` | 本次绑定最后逻辑 CPU |
| `SelfTest.cmd` | 运行启动自检 |
| `Stop-Guard.cmd` / `Resume.cmd` | 暂停 / 恢复自动执行 |
| `Restore.cmd` | 完整恢复原设置 |

```powershell
.\LowGear.ps1 -Command Install
.\LowGear.ps1 -Command Status -Json
.\LowGear.ps1 -Command ApplyOnce
.\LowGear.ps1 -Command LastCpu
.\LowGear.ps1 -Command Install -BindLastCpu
.\LowGear.ps1 -Command SetAffinity  # 停止下次启动时绑定最后 CPU
.\LowGear.ps1 -Command Pause
.\LowGear.ps1 -Command Resume
.\LowGear.ps1 -Command SelfTest
.\LowGear.ps1 -Command Restore
```

入口统一处理管理员权限和 64 位宿主。状态与一次性操作退出码：`0` 当前实例均符合目标，`1` 失败或存在运行实例不达标，`2` 至少一个目标未运行。自动任务名为 `ACE-LowGear`，启动事件对象名为 `ACE-LowGear-ProcessStart`。

## 🧪 验证与隐私

已通过隔离的恢复/迁移测试、原生 CPU / I/O 与相关性测试、真实 Windows 启动事件测试，以及会话退出和退出后不持续纠错测试；另已收到单台电脑重启后实际 ACE 核验通过的用户反馈。**这不代表所有电脑和游戏环境均已验证。** 详细范围见[验证说明](docs/验证.md)。

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Run.ps1
# 管理员会话：验证真实 IFEO 临时启动与真实事件触发
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Run.ps1 -StartupProbe
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Event.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Validate-Public.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Package.ps1
```

公开内容由 `public-files.json` 明确列出，只发布源码、文档与测试。生成的 EXE、本机备份、状态、日志和个人资料均不在公开包中。无遥测或自动上传，详见[隐私说明](docs/隐私.md)。

遇到问题可[提交 Issue](https://github.com/Howardyh/ace-lowgear/issues)，提供 Windows 版本、操作步骤和面板错误即可；分享前请隐去用户名、个人目录、机器标识等信息，勿上传原始备份。

MIT 许可证，见 [LICENSE](LICENSE)。
