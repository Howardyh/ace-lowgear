# 验证方法

测试使用 Windows PowerShell 5.1，不依赖 Pester 或联网安装。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Project.ps1
```

默认测试在随机命名的 HKCU 独立测试区中进行，验证：

- 不存在的键与值、原有多种注册表类型、未展开的环境变量字符串的准确恢复。
- 未管理值的保留、无关程序名拒绝、重复安装不覆盖原始备份。
- 异机状态与被篡改备份拒绝、后续修改冲突检测。
- 故意注入部分写入失败后，全体目标的回滚与恢复记录处理。
- 自行创建的临时进程的 CPU / I/O 读取与最后一个逻辑 CPU 相关性，以及第 63 位掩码。

这些测试区中的程序名只是键名，根路径不是实际 IFEO。默认测试不会修改真实 ACE 设置。

管理员 Windows PowerShell 5.1 中增加 `-StartupProbe`，会额外针对唯一命名的临时程序验证实际 HKLM 启动行为：正常基线、第一次低优先级启动、第二次低优先级启动，并核验清理结果。真实 ACE 目标不会被测试写入。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Project.ps1 -StartupProbe
```

每次首次 `Apply` 本身也执行该本机探测。通过探测不等于 ACE 实际接受测试通过；ACE 启动、运行一段时间与再次启动后应分别执行 `Check.cmd`，并确认游戏正常使用。

验证范围应分开记录：代码与隔离事务测试、本机临时程序启动测试、真实 ACE 实例检查、不同电脑接受测试。不能用其中一项替代其他项。

公开 CI 仅运行临时测试，不上传本机报告或恢复数据。提交前还应运行 `tools/Test-PublicContent.ps1 -CheckIndex`，打包使用 `tools/Package.ps1`。
