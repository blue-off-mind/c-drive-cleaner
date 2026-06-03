# Cleanup Targets Reference

Use this reference when explaining C drive cleanup categories. Prefer reporting and confirmation over execution.

| Category | Examples | Default risk | Safe handling |
|---|---|---|---|
| System temporary files | `%TEMP%`, `C:\Windows\Temp` | Low to medium | Delete only old files after closing apps; access denied is normal. |
| Windows Defender scan history | Defender operational history and logs | Medium | Report size; prefer Windows Security UI or Defender cmdlets. |
| Windows system logs | `.log`, `.etl`, CBS/DISM logs | Medium | Keep recent logs; delete only stale logs after explaining diagnostic loss. |
| WinSxS component store | `C:\Windows\WinSxS` | High | Never delete by path; use DISM analyze and cleanup commands. |
| Defender quarantine | Quarantined threats | High | Do not raw-delete; use Windows Security review flow. |
| Defender update cache | Signature update remnants | Medium | Report first; cleanup only with Windows-supported mechanisms. |
| Douyin/TikTok desktop cache | AppData cache directories | Medium | Confirm account/session impact; prefer in-app cache clear if available. |
| IIS logs | `C:\inetpub\logs\LogFiles` | Low to medium | Archive or delete logs older than a user-approved age. |
| Memory dump files | `MEMORY.DMP`, minidumps | Medium | Delete only after crash debugging is no longer needed. |
| Thumbnail cache | Explorer thumbnail databases | Low | Rebuildable; Explorer may regenerate cache. |
| Duplicate files | Same-size and same-hash groups | High | Report groups only; never auto-delete. |
| Pagefile relocation | `pagefile.sys` settings | High | Use System Properties or planned WMI/registry change; requires reboot. |
| System restore/backup | Restore points, Windows backups | High | Use Windows UI or official tools; deleting can remove rollback options. |
| Hibernation file | `hiberfil.sys` | Medium | Use `powercfg /hibernate off`; warn about hibernation and Fast Startup. |

## Recommendation Language

For useful software data, recommend this order:

1. Move cache inside the application's own settings.
2. Uninstall and reinstall the app outside C drive.
3. Use `mklink` only when the app has no supported relocation path, with rollback steps.

For disposable data, list:

- Exact path.
- Estimated reclaim.
- Why it appears disposable.
- What may break or be lost.
- Whether the app should be closed first.
- Whether regeneration or re-login is expected.
