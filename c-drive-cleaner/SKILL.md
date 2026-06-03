---
name: c-drive-cleaner
description: Audit Windows C drive space usage and build safe cleanup plans. Use when the user wants to analyze or clean C drive pressure, inspect Program Files and AppData growth, identify application caches, compare safe cleanup options, plan cache migration or mklink moves, review duplicate-file risk, or reason about Windows cleanup items such as temp files, logs, WinSxS component cleanup, hibernation, pagefile placement, Defender caches, IIS logs, crash dumps, and thumbnail cache.
---

# C Drive Cleaner

## Core Rule

Default to audit-first behavior. Do not delete, move, relink, disable, or reconfigure anything unless the user explicitly asks for execution after reviewing a plan.

Treat this skill as a transparent alternative to opaque cleaner apps: inspect, classify, estimate risk, and ask for review before any cleanup.

## Workflow

1. Run `scripts/scan_c_drive.ps1` in `scan` mode first.
2. Review only first-level directories under:
   - `C:\Program Files`
   - `C:\Program Files (x86)`
   - `%USERPROFILE%\AppData\Local`
   - `%USERPROFILE%\AppData\LocalLow`
   - `%USERPROFILE%\AppData\Roaming`
3. Produce a structured table with these columns:
   - Path
   - Size
   - Owner guess
   - Folder description
   - Content type
   - Complexity
   - Risk
   - Suggested action
   - Estimated reclaim
   - Age buckets
   - Deletion hazard
   - Cleanup status when previewing safe cleanup
4. Use size, folder name, file counts, recent modification, cache keywords, and system sensitivity to decide what to inspect next.
5. For complex folders, dispatch a subagent or separate focused inspection. For simple folders, inspect directly.
6. End with two improvement paths:
   - Useful software data: prefer in-app cache migration or uninstall/reinstall outside C drive. Offer `mklink` only as an advanced option with rollback notes.
   - Disposable cache or stale data: list exact targets, expected benefit, hazards, and require user approval.

## Script Usage

Run from the skill directory:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\scan_c_drive.ps1
```

Common commands:

```powershell
# Markdown audit of default C drive targets.
powershell -ExecutionPolicy Bypass -File .\scripts\scan_c_drive.ps1 -Mode scan -OutputFormat markdown

# Chinese Markdown audit.
powershell -ExecutionPolicy Bypass -File .\scripts\scan_c_drive.ps1 -Mode scan -Language zh-CN -OutputPath .\c-drive-scan.md

# JSON audit for further processing.
powershell -ExecutionPolicy Bypass -File .\scripts\scan_c_drive.ps1 -Mode scan -OutputFormat json

# Include Windows cleanup plan items, still read-only.
powershell -ExecutionPolicy Bypass -File .\scripts\scan_c_drive.ps1 -Mode plan

# Preview low-risk cleanup candidates. This does not delete without both switches.
powershell -ExecutionPolicy Bypass -File .\scripts\scan_c_drive.ps1 -Mode clean-safe
```

When writing reports or Markdown files, match the user's language. Use `-Language zh-CN` for Chinese users, `-Language en` for English users, or `-Language auto` when the system UI culture is reliable. Prefer `-OutputPath` for long reports so terminal truncation does not hide rows.

Only run cleanup with both explicit switches after user review:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\scan_c_drive.ps1 -Mode clean-safe -Execute -ConfirmClean
```

## Classification Rules

Use these default meanings unless local evidence contradicts them:

- `Low complexity`: obvious cache, temp, log, or thumbnail data with low nesting and low system sensitivity.
- `Medium complexity`: application-owned AppData or Program Files data where cache and user state may be mixed.
- `High complexity`: large software suites, game launchers, development tools, package managers, cloud sync tools, Microsoft/Windows directories, security software, databases, virtual machines, or folders with many files.
- `Low risk`: rebuildable cache or old logs.
- `Medium risk`: app cache mixed with settings, crash dumps, or data that may slow first launch after cleanup.
- `High risk`: user documents, saved games, project dependencies, sync folders, security quarantine, pagefile, hibernation, restore points, WinSxS, installers, databases, or unknown large directories.

Always include a short folder description for suspicious or recognizable folders, for example:

- Tencent: Tencent-family app data such as WeChat, QQ, Tencent Meeting, updates, plugins, logs, or media cache.
- Microsoft: Microsoft-family data; browser and Windows-managed state should use app settings or official Windows tools.
- Code/VS Code: developer-tool caches, extensions, crash reports, and settings may be mixed.
- npm/pnpm/yarn: package-manager caches; prefer package-manager cleanup commands after confirmation.
- Temp: may contain active installers or diagnostics, so use age buckets instead of assuming all bytes are disposable.
- Docker/game launchers/cloud sync: high-impact data; prefer official commands or in-app migration.

## 360 Cleaner Pro Parity

Do not integrate, download, invoke, or require 360 Cleaner Pro. Recreate comparable categories transparently:

- Junk files: audit temp files, logs, thumbnails, crash dumps, Defender caches, app caches, IIS logs, and common stale data.
- Duplicate files: scan and hash only when explicitly requested; never auto-delete duplicates.
- System settings: generate official-command plans for hibernation, WinSxS cleanup, pagefile relocation, and restore-point cleanup; do not execute them by default.

Read `references/cleanup_targets.md` before advising on system cleanup categories or deletion hazards.

## Hard Safety Limits

Never directly delete:

- Windows Defender quarantine or threat history.
- `C:\Windows\WinSxS` contents by path.
- `pagefile.sys`, `hiberfil.sys`, restore points, or system backups by raw file deletion.
- Game saves, project folders, databases, VM images, cloud sync roots, or user documents.
- Anything in Program Files unless it is an obvious application cache and the user has approved exact paths.

Prefer official commands for Windows-managed state:

- Hibernation: `powercfg /hibernate off`
- WinSxS: `DISM.exe /Online /Cleanup-Image /AnalyzeComponentStore` then `/StartComponentCleanup`
- Defender threats: Windows Security UI or Defender cmdlets, not raw quarantine deletion
- Pagefile: System Properties or documented WMI/registry plan with reboot warning
