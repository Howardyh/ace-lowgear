# 🪶 ACE LowGear

> **1.3.0 预发布**：新增云母开关、窗口记忆与安全位置恢复，保留 Fluent 三页控制中心及“启动时设置，核验后退出”。[试用 1.3](https://github.com/Howardyh/ace-lowgear/releases/tag/v1.3.0) · [稳定版 1.2](https://github.com/Howardyh/ace-lowgear/releases/latest)

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

1. 选择 [1.3 外观预发布](https://github.com/Howardyh/ace-lowgear/releases/tag/v1.3.0) 或 [1.2 稳定版](https://github.com/Howardyh/ace-lowgear/releases/latest)，在 **Assets** 下载对应的 `ace-lowgear-<版本>-source.zip`，**完整解压**到普通文件夹。不要直接在压缩包里运行，也不要只复制单个启动文件。
2. 双击 **`Start.cmd`**，允许 Windows 管理员提示，打开中文控制中心。
3. 点击 **“启用自动管理”**，等待完成。之后可以关闭面板，正常启动游戏。

首次启用会检查本机启动优先级功能、保留原始设置，再注册自动执行。公开包只含源码，执行程序会在本机编译；**无需安装 Python、Node.js 或 .NET SDK**。

**重启后的使用：**启用状态会保留，下次 ACE 启动时仍会自动执行，无需重新安装。手动暂停后，可在面板点击“恢复自动执行”。

首次使用时，建议启动游戏并等待约 45 秒，再打开面板点击 **“刷新状态”**，确认运行实例的 CPU 为“低”、I/O 为“非常低”，结果为“已核验”。

## 🪟 1.3 外观与窗口控制（预发布）

在“设置 → 外观”中调整，立即生效，无需改动自动执行配置：

- **背景材质**：选择“自动使用云母”或“关闭，使用实色”。面板显示当前实际效果及回退原因；高对比度、系统透明效果与节电设置仍优先遵循 Windows。
- **记住窗口大小和位置**：默认开启。正常关闭后保存普通窗口尺寸、所在工作区内的位置和最大化状态；最小化关闭也不会让下次启动隐藏。关闭此选项只清除记忆，当前窗口不移动。
- **安全恢复位置**：按当前显示器工作区和 WPF 缩放换算；支持副屏负坐标，显示器移除时返回主屏。工作区过小时缩小窗口并放宽最小尺寸，保留页面滚动；打开期间只在标题栏无法操作时修正位置。
- **恢复外观默认**：恢复跟随系统、自动云母和窗口记忆，并将普通窗口按默认 1060×800 居中到当前显示器；空间不足时适配工作区。不会恢复调度策略或原始备份。

主题仍只保存在原来的 `ui.json`；材质和窗口记忆单独保存在同目录的 `appearance.json`。旧版主题文件保持兼容，外观文件损坏不会影响调度、诊断或最早原始备份。位置记忆和显示器几何不会进入诊断摘要与源码包。关闭后不保留显示器监听。

1.3 以预发布源码包提供，248 项本地检查通过；1.2 继续保留为稳定版。打开新版面板不会自动升级本机执行组件；已有安装可在确认后点击“升级本机组件”，保留启用/暂停状态、策略和最早备份。实际多显示器拔插尚未验收，原生窗口测试与显示器几何模拟分别记录，见[验证说明](docs/验证.md)。

## 🆕 1.2 Fluent 界面

1.2 的 196 项本地检查通过，包含原生窗口云母与回退测试；本机已从 1.1 无损升级，并收到用户验收通过的确认。本轮未采集新的 1.2 实际 ACE 自动启动读值，也未自动化验证鼠标拖拽，详见[验证说明](docs/验证.md)。

- **概览**：自动执行配置与当前进程核验分开显示；主按钮按状态提供启用、升级、恢复或立即应用。三个目标程序按组显示，展开可查看每个实例的 PID、有效 I/O、原始读值及错误。
- **设置**：主题可选择跟随系统、浅色或深色并立即生效。相关性修改先保留为草稿，点击“保存策略”才生效；首次启用时一并保存选择。暂停/恢复、组件升级与完整恢复也在这里。
- **诊断**：独立显示各项健康检查，保留自检、手动修复、本次绑定最后 CPU 和预览后复制的诊断摘要。
- **材质与兼容**：支持的 Windows 11 尝试原生云母，关闭透明效果、高对比度、节电或不支持时使用实色。Windows 10 保留全部调度功能。主题偏好仅保存在本机 `%LocalAppData%\ACE-LowGear\ui.json`，损坏时回退跟随系统。
- **操作反馈**：显示中文阶段和不确定进度；查询失败保留上次数据并标记可能过期。窗口较窄时侧栏收为图标，修改进行中暂缓关闭，完整恢复前说明影响并确认。

## 🆕 1.1 使用变化

- **已有 1.0 / 1.1 / 1.2**：从新版 `Start.cmd` 打开面板，点击“升级本机组件”。最早原始备份、相关性策略和暂停状态会保留。升级失败会尝试回退；中断后可点击“修复自动执行”撤回未完成的部署。
- **首次安装**：点击“启用自动管理”。安装成功后可以关闭窗口，正常启动游戏。
- **版本与结果**：面板和本机组件版本分别显示（1.2 位于侧栏底部）；最近会话增加时间、耗时。自动配置、实际读值和故障分项显示，某项查询失败不会把其他结果一起隐藏。
- **高级选项**：1.1 的相关性与自检位于“高级选项”；1.2 分别移入设置与诊断页。1.2 中已安装时在设置页点击“保存策略”；首次安装时随启用操作保存。
- **手动修复**：修复归属明确的任务或启动事件配置。遇到外部修改、归属不明、备份损坏或策略无效时停止覆盖。暂停状态会保留，修复不会自行启用。
- **诊断摘要**：点击“诊断摘要…”先预览，再点击复制。只包含版本、Windows 版本、处理器数量、配置状态及错误码；不包含用户名、路径、PID、机器标识、原始错误文本或备份，不会自动上传。
- **界面响应**：进程读值约每 5 秒异步读取，完整配置约每 30 秒检查。手动刷新执行完整检查。修改配置时会暂缓关闭窗口，避免操作未结束就误以为完成。

```powershell
.\LowGear.ps1 -Command Upgrade        # 保留启用/暂停状态及相关性策略
.\LowGear.ps1 -Command Repair         # 手动修复，或撤回未完成的升级
.\LowGear.ps1 -Command Diagnose       # 仅输出可分享的脱敏摘要
.\LowGear.ps1 -Command Install -ClearLastCpu  # 启用并取消下次启动的 CPU 绑定
```

`Install` 保持“安装并启用”的语义；不指定相关性参数时保留已有选择。旧的 `SetAffinity` 无参数用法仍表示停止下次启动绑定，旧快捷入口与退出码保留。1.1 没有新增常驻纠错、自动更新、遥测或便携 EXE。

## 🎛️ 面板能做什么

| 页面 | 按钮或选项 | 用途 |
|---|---|---|
| 概览 | 按状态显示的主按钮 | 启用、升级、恢复自动执行或立即应用一次；配置异常时进入诊断 |
| 概览 | 立即应用一次 | 对当前运行实例设置低 CPU / 非常低 I/O，并立即回读 |
| 各页右上角 | 刷新 | 强制完整检查配置及当前进程 |
| 设置 | 明暗主题 | 跟随系统、浅色或深色；立即生效并记住本机选择 |
| 设置 | 背景材质 | 自动使用云母或关闭为实色；显示实际效果与原因 |
| 设置 | 记住窗口大小和位置 | 正常关闭时保存；关闭记忆不移动当前窗口 |
| 设置 | 恢复外观默认 | 恢复默认外观，普通窗口居中到当前显示器；调度配置保留 |
| 设置 | 启动时绑定最后一个逻辑 CPU | 已安装时点击“保存策略”；首次安装时随启用一并保存 |
| 设置 | 暂停 / 恢复自动执行 | 管理自动触发，保留启动规则和原始备份 |
| 设置 | 升级本机组件 | 保留启用/暂停状态、原始备份和相关性策略 |
| 设置 | 完整恢复原设置 | 确认后移除自动触发和任务，恢复最早原值，备份保留 |
| 诊断 | 预览诊断摘要… | 先预览再复制；不自动上传 |
| 诊断 | 修复自动执行 | 只重建归属明确的配置，保留暂停状态 |
| 诊断 | 运行自检 | 使用随机命名临时程序验证启动行为，完成后清理 |
| 诊断 | 本次绑定最后 CPU | 对当前实例应用低优先级并绑定最后逻辑 CPU |

“最后 CPU”指**逻辑处理器**，编号由本机自动检测。默认不改变相关性；修改后需明确保存，已有实例保持原相关性到正常重启，或使用一次性绑定操作。

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

1.1 已通过 **126 项本地检查**，覆盖原功能、升级回滚、诊断脱敏、异步界面及真实 Windows 启动事件。2026-10-28 的单机真实 ACE 启动验收中，两个核心程序的 CPU / I/O 与现有相关性策略均符合目标，新会话约 11.1 秒完成，执行程序退出后连续三次回读达标。`ACE-Service64.exe` 当时未运行，未计入实际核验。**1.1 尚未做整机重启验收；1.0.0 曾收到重启后通过的用户反馈。** 其他电脑和游戏环境仍需首次核验，详细范围见[验证说明](docs/验证.md)。

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Run.ps1
# 管理员会话：验证真实 IFEO 临时启动与真实事件触发
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Run.ps1 -StartupProbe
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Event.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Upgrade.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Panel.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Window.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Appearance.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Validate-Public.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Package.ps1
```

公开内容由 `public-files.json` 明确列出，只发布源码、文档与测试。生成的 EXE、本机备份、状态、日志和个人资料均不在公开包中。无遥测或自动上传，详见[隐私说明](docs/隐私.md)。

遇到问题可[提交 Issue](https://github.com/Howardyh/ace-lowgear/issues)，提供操作步骤及面板中预览后的“诊断摘要”。它只包含允许分享的版本、处理器数量、配置状态与错误码；自行补充资料时请隐去用户名、个人目录和机器标识，勿上传原始备份。

MIT 许可证，见 [LICENSE](LICENSE)。
