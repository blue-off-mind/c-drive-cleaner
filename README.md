# c-drive-cleaner

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
