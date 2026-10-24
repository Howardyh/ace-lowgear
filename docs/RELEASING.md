# 发布流程

1. 检查中英文 README、许可证、功能边界、版本号与 `public-files.json`。
2. 运行隔离测试和可执行的本机启动探测，分别记录已验证与未验证项。
3. 使用 `git add` 明确暂存允许公开的文件，不使用仓库外的原始材料或运行数据。
4. 运行 `tools/Test-PublicContent.ps1 -CheckIndex`，人工审阅暂存差异，检查提交作者使用 GitHub noreply 邮箱。
5. 使用 `tools/Package.ps1` 生成源码包，审阅文件清单并核验 SHA-256。
6. 获取项目所有者对名称、文件内容、许可证与公开仓库的最终批准。
7. 批准后才创建公开 GitHub 仓库并推送。发布仅包含已审核源码与文档，不包含本地审阅报告、运行数据或备份。
8. 发布后检查匿名访问、远端文件清单和 CI 的实际结果。尚未运行的 CI 不能报告为通过。

工具文档：[GitHub CLI 仓库创建](https://cli.github.com/manual/gh_repo_create)。
