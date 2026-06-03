# c-drive-cleaner

[English](#english) | [中文](#中文)

## English

`c-drive-cleaner` is a Codex Skill for auditing Windows C drive usage and producing safe cleanup plans.

It focuses on the places that often grow quietly:

- `C:\Program Files`
- `C:\Program Files (x86)`
- `%USERPROFILE%\AppData\Local`
- `%USERPROFILE%\AppData\LocalLow`
- `%USERPROFILE%\AppData\Roaming`

The first version is audit-first. It scans first-level directories, classifies likely owner and content type, estimates cleanup risk, and outputs a structured table. It does not integrate with 360 Cleaner Pro or any other closed-source cleaner.

## Install As A Codex Skill

Copy the `c-drive-cleaner` folder into your Codex skills directory:

```powershell
Copy-Item -Recurse -Force .\c-drive-cleaner "$HOME\.codex\skills\c-drive-cleaner"
```

Then ask Codex to use `$c-drive-cleaner`.

## Run The Scanner Directly

```powershell
powershell -ExecutionPolicy Bypass -File .\c-drive-cleaner\scripts\scan_c_drive.ps1
```

Useful modes:

```powershell
# Read-only Markdown audit.
powershell -ExecutionPolicy Bypass -File .\c-drive-cleaner\scripts\scan_c_drive.ps1 -Mode scan

# Read-only JSON audit.
powershell -ExecutionPolicy Bypass -File .\c-drive-cleaner\scripts\scan_c_drive.ps1 -Mode scan -OutputFormat json

# Include Windows system cleanup planning items.
powershell -ExecutionPolicy Bypass -File .\c-drive-cleaner\scripts\scan_c_drive.ps1 -Mode plan

# Preview low-risk cleanup candidates without deleting.
powershell -ExecutionPolicy Bypass -File .\c-drive-cleaner\scripts\scan_c_drive.ps1 -Mode clean-safe
```

`clean-safe` deletes only if both `-Execute` and `-ConfirmClean` are supplied. Review the report first.

## Safety Model

This project avoids raw deletion of Windows-managed or user-sensitive data. It reports and explains risk for:

- Defender quarantine/history
- WinSxS
- pagefile and hibernation file
- restore points and backups
- game saves and user data
- duplicate files
- Program Files application directories

For system-managed cleanup, prefer official Windows commands such as `powercfg` and `DISM` after review.

## License

MIT

## 中文

`c-drive-cleaner` 是一个用于审计 Windows C 盘占用并生成安全清理计划的 Codex Skill。

它重点关注那些经常悄悄变大的位置：

- `C:\Program Files`
- `C:\Program Files (x86)`
- `%USERPROFILE%\AppData\Local`
- `%USERPROFILE%\AppData\LocalLow`
- `%USERPROFILE%\AppData\Roaming`

第一版采用“审计优先”的策略。它只扫描第一级目录，推测目录归属和内容类型，评估清理风险，并输出结构化表格。它不集成 360 清理 Pro，也不依赖任何闭源清理软件。

## 作为 Codex Skill 安装

将 `c-drive-cleaner` 文件夹复制到你的 Codex skills 目录：

```powershell
Copy-Item -Recurse -Force .\c-drive-cleaner "$HOME\.codex\skills\c-drive-cleaner"
```

然后让 Codex 使用 `$c-drive-cleaner`。

## 直接运行扫描脚本

```powershell
powershell -ExecutionPolicy Bypass -File .\c-drive-cleaner\scripts\scan_c_drive.ps1
```

常用模式：

```powershell
# 只读 Markdown 审计。
powershell -ExecutionPolicy Bypass -File .\c-drive-cleaner\scripts\scan_c_drive.ps1 -Mode scan

# 只读 JSON 审计。
powershell -ExecutionPolicy Bypass -File .\c-drive-cleaner\scripts\scan_c_drive.ps1 -Mode scan -OutputFormat json

# 加入 Windows 系统清理规划项。
powershell -ExecutionPolicy Bypass -File .\c-drive-cleaner\scripts\scan_c_drive.ps1 -Mode plan

# 预览低风险清理候选项，不会删除。
powershell -ExecutionPolicy Bypass -File .\c-drive-cleaner\scripts\scan_c_drive.ps1 -Mode clean-safe
```

`clean-safe` 只有在同时提供 `-Execute` 和 `-ConfirmClean` 时才会删除。请先审查报告。

## 安全模型

本项目避免直接删除 Windows 管理的数据或用户敏感数据。它会报告并解释以下内容的风险：

- Defender 隔离区和历史记录
- WinSxS
- 页面文件和休眠文件
- 系统还原点和备份
- 游戏存档和用户数据
- 重复文件
- Program Files 下的应用目录

对于系统管理的清理项，建议在审查后优先使用 Windows 官方命令，例如 `powercfg` 和 `DISM`。

## 许可证

MIT
