# 实现与限制

## 启动规则

工具只管理 64 位注册表视图中这三个程序名下的两个 DWORD：

```text
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\<image>.exe\PerfOptions
CpuPriorityClass = 1
IoPriority       = 0
```

其中 `<image>.exe` 必须是内置目标清单中的程序名，或带随机 GUID 的独立测试程序名。实际安装前的探测先验证正常 CPU/I/O 值，再验证两次低优先级启动；探测失败会停止安装。

Windows 在进程创建时读取相关性能选项。修改这些值后，需要等待目标程序下一次正常启动。程序后续可更改自身优先级，因此需检查运行实例。

已有 `UseFilter` 路径过滤规则时，本工具停止自动安装，避免误解已有配置。按文件名配置会匹配同名副本，因此目标范围固定为 ACE 程序名。

## 备份、事务和恢复

每台电脑使用独立的本地数据目录。安装状态包含 schema、原始备份文件名、备份 SHA-256、Windows 安装标识摘要和事务阶段。源码目录不携带活动安装状态。

原始值保留是否存在、类型和原始内容。整数以十进制字符串保存，二进制以 Base64 保存，环境变量字符串不展开。首次写入前先持久化 `PendingApply` 恢复记录；中途失败尝试逐目标恢复，未完成的恢复保留 `RecoveryRequired` 记录。

重复安装只有在现有状态完整且配置仍匹配时返回 `AlreadyConfigured`。恢复检查管理的值是否仍是本工具写入值或原始值；出现后续变化时停止，保留恢复记录。恢复只处理两个指定值，并仅删除最初不存在、当前仍为空的键。

同一台电脑的多个源码副本共享操作锁。恢复核验备份所属的 Windows 安装、目标清单、文件名和完整性；不会从其他电脑的备份恢复。

## 运行核验

CPU 使用 `GetPriorityClass`；I/O 使用 `NtQueryInformationProcess` 的 `ProcessIoPriority`（33）和可选的 `ProcessEffectiveIoPriority`（110）。后两者属于内部信息类，可能随 Windows 版本与访问权限变化。查询结果和错误状态需分别处理，读取失败不表示通过。

`Verified` 描述可读取的进程优先级，不涵盖全部线程、驱动、内存优先级或所有磁盘请求。额外有效 I/O 查询不可用时保留 `-1` 和状态，不假造读值。

## 可选相关性

相关性入口读取系统活动处理器掩码，取编号最大的有效位，支持第 63 位的有符号指针表示。多处理器组时停止绑定，避免把组内编号当成全系统编号。CPU / I/O 启动规则使用独立路径。

## 参考资料

- [Windows Internals：进程创建与 PerfOptions](https://download.sysinternals.com/files/WindowsInternals-Ch05.pdf)
- [Microsoft：CPU 优先级与后台模式](https://learn.microsoft.com/windows/win32/api/processthreadsapi/nf-processthreadsapi-setpriorityclass)
- [Microsoft：I/O 优先级提示](https://learn.microsoft.com/windows-hardware/drivers/ddi/wdm/ne-wdm-_io_priority_hint)
- [Microsoft：NtQueryInformationProcess 的兼容性说明](https://learn.microsoft.com/windows/win32/api/winternl/nf-winternl-ntqueryinformationprocess)
- [System Informer：进程信息类声明](https://github.com/winsiderss/systeminformer/blob/master/phnt/include/ntpsapi.h)
