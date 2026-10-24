# ACE LowGear

**让 ACE 降挡运行，为前台任务让路。**

[English](README.en.md) · [隐私说明](docs/PRIVACY.md) · [实现与限制](docs/DESIGN.md) · [测试说明](docs/TESTING.md)

ACE LowGear 是一个轻量的 Windows PowerShell 工具，为指定 ACE 用户态程序配置启动优先级：CPU **低（Idle）**，I/O **非常低（Very Low）**。配置一次，之后正常启动目标程序时由 Windows 应用规则，无需常驻监控。

目标程序为 `SGuard64.exe`、`SGuardSvc64.exe` 和 `ACE-Service64.exe`。项目与 ACE 官方无隶属关系。

## 快速使用

适用于 64 位 Windows 10 / Windows 11，使用系统内置 Windows PowerShell 5.1。无需安装 Python、Node.js 或其他运行库。请解压完整项目，保留 `src` 目录。

| 文件 | 用途 |
|---|---|
| `Apply.cmd` | 管理员运行；先验证本机启动规则，再备份并配置三个程序 |
| `Check.cmd` | 查看启动配置，以及当前运行实例的实际 CPU / I/O 优先级 |
| `Restore.cmd` | 管理员运行；依据本机原始备份恢复本工具管理的两个值 |
| `SelfTest.cmd` | 管理员运行；仅用临时测试程序验证启动规则，完成后清理测试键 |
| `Last-CPU.cmd` | 可选；将当前运行的目标程序绑定到最后一个逻辑处理器 |

1. 双击 `Apply.cmd`，允许 Windows 管理员权限提示。
2. 看到 `ConfiguredForNextStart` 后，正常启动相关游戏或程序。已运行的进程需要在下一次正常启动时才会使用新规则。
3. 双击 `Check.cmd`，核对配置和运行实例。程序尚未运行时会显示 `Running=False`，表示实际运行状态尚未验证。
4. 需要撤销时，双击 `Restore.cmd`，之后正常重启相关程序。

`Check.cmd` 默认不请求管理员权限。读取进程时若提示拒绝访问，可右键选择“以管理员身份运行”后复查；仍被拒绝时保留失败状态。

如果使用过旧版工具，请先用旧版的恢复入口撤销旧设置，保留原始备份，再使用本项目。新安装会把安装当时的配置作为恢复基线。

## 如何判断生效

| 检查字段 | 目标值 | 含义 |
|---|---|---|
| `Configuration.CpuPriorityClass` | `1` | IFEO 中的低 CPU 优先级配置 |
| `Configuration.IoPriority` | `0` | IFEO 中的非常低 I/O 优先级配置 |
| `Configuration.Configured` | `True` | 两个注册表值的类型、数值及过滤状态符合目标 |
| `Processes.CpuClass` | `64` | 运行进程为 Windows Idle 优先级类 |
| `Processes.IoPriority` | `0` | 运行进程的 I/O 优先级为 Very Low |
| `Processes.EffectiveIoPriority` | `0` 或 `-1` | `0` 为读取到的有效值；`-1` 表示此查询不可用，详见状态字段 |
| `Processes.Verified` | `True` | 可读取的进程优先级符合目标；不代表所有线程、驱动和磁盘请求均符合目标 |

CPU 注册表值 `1` 和运行时值 `64` 属于不同的枚举，不能互换。低优先级是在资源争用时让路，不是 CPU 占用率上限。I/O 优先级也是调度提示，效果取决于实际请求与驱动支持。

`Check` 的退出码：`0` 全部目标已运行且读值符合目标；`1` 检查或运行实例核验失败；`2` 配置未完整匹配或至少一个目标未运行。`Apply` 成功只代表规则已配置，下次启动的实际行为仍需检查。

## 在其他电脑上使用

- 按程序文件名配置，不依赖某个用户目录、游戏安装盘或个人账户。
- 运行数据放在本机 `%ProgramData%\ACE-LowGear`，不写入源码目录。
- 备份包含本地 Windows 安装标识的摘要，恢复时检查归属和文件完整性。只复制源码到另一台电脑，保留各自的本地备份。
- 重复安装保留第一次的原始备份；存在后续修改时停止自动覆盖，便于先检查差异。
- 恢复保留其他注册表值，仅清理本工具新建且仍为空的键。失败回滚保留恢复记录。

`Last-CPU.cmd` 会读取当前电脑可用的逻辑处理器掩码，自动选择编号最大的一个；不会写死 CPU 编号。逻辑处理器不一定对应整个物理核心。此入口执行一次，进程重启后需重跑。单处理器组、最多 64 个逻辑处理器的系统支持此绑定；多处理器组仍可使用 CPU / I/O 启动规则，相关性入口会停止并说明原因。

## 兼容性与边界

`IFEO\PerfOptions` 与部分 I/O 查询依赖 Windows 内部行为，公开文档并不完整。工具在每台电脑第一次安装前执行独立探测，验证正常值及两次低优先级启动；失败时不写入 ACE 规则。CPU / I/O 规则若被程序自行更改，`Check` 会反映读值。

管理员权限仍可能无法读取受保护进程。此时会报告读取错误，不能把注册表配置成功当成运行验证成功。更低优先级可能延长繁忙时的初始化或扫描；出现异常可使用恢复入口。

Windows 子进程可能继承较低优先级。实际接受测试应同时检查游戏主进程，尤其是由目标程序创建游戏进程的启动流程。

当前实现不安装驱动、服务或计划任务。ACE 内核驱动及独立 I/O 请求的调度不由本工具统一控制。ARM64 和不同硬件电脑的实际接受测试尚未完成。

## 开发与验证

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Project.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-PublicContent.ps1
```

第一项在独立、随机命名的 HKCU 测试区验证恢复、幂等性、跨机器状态拒绝、备份完整性和失败回滚，并检查临时进程的 CPU / I/O 读取及相关性。它不会修改真实 ACE 配置。管理员 Windows PowerShell 中可加 `-StartupProbe` 验证临时程序的 HKLM 启动规则。

打包使用 `tools/Package.ps1`，只收录 `public-files.json` 列出的源码与文档，并逐文件校验 ZIP 内容。测试结果和其他运行数据不会随源码打包。

MIT 许可证。参见 [LICENSE](LICENSE)。
