param(
    [ValidateSet("scan", "plan", "clean-safe")]
    [string]$Mode = "scan",

    [ValidateSet("markdown", "json")]
    [string]$OutputFormat = "markdown",

    [ValidateSet("auto", "en", "zh-CN")]
    [string]$Language = "auto",

    [string[]]$RootPaths,

    [string]$OutputPath,

    [int]$MinAgeDays = 7,

    [int]$TopN = 50,

    [switch]$Execute,

    [switch]$ConfirmClean
)

$ErrorActionPreference = "Continue"

function Get-ReportLanguage {
    if ($Language -ne "auto") { return $Language }
    if ([System.Globalization.CultureInfo]::CurrentUICulture.Name -like "zh*") { return "zh-CN" }
    return "en"
}

$script:ReportLanguage = Get-ReportLanguage

function T {
    param([string]$En, [string]$Zh)
    if ($script:ReportLanguage -eq "zh-CN") { return $Zh }
    return $En
}

function Resolve-DefaultRoots {
    $roots = @(
        "C:\Program Files",
        "C:\Program Files (x86)",
        (Join-Path $env:USERPROFILE "AppData\Local"),
        (Join-Path $env:USERPROFILE "AppData\LocalLow"),
        (Join-Path $env:USERPROFILE "AppData\Roaming")
    )
    $roots | Where-Object { Test-Path -LiteralPath $_ }
}

function ConvertTo-HumanSize {
    param([Int64]$Bytes)
    if ($Bytes -ge 1TB) { return ("{0:N2} TB" -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ("{0:N2} GB" -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ("{0:N2} MB" -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ("{0:N2} KB" -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

function Escape-MarkdownCell {
    param([object]$Value)
    if ($null -eq $Value) { return "" }
    return ($Value.ToString() -replace "\|", "\|").Replace("`r", " ").Replace("`n", " ")
}

function ConvertTo-DisplayValue {
    param([string]$Column, [object]$Value)

    if ($script:ReportLanguage -ne "zh-CN" -or $null -eq $Value) { return $Value }

    $text = $Value.ToString()
    $map = @{
        "Low" = "低"
        "Medium" = "中"
        "High" = "高"
        "Unknown" = "未知"
        "Installed application" = "已安装应用"
        "Per-user application data" = "用户级应用数据"
        "Installer/package cache" = "安装器/包缓存"
        "Temporary files" = "临时文件"
        "Cache" = "缓存"
        "Logs" = "日志"
        "Crash dumps" = "崩溃转储"
        "Backup data" = "备份数据"
        "Installer/package data" = "安装器/包数据"
        "Application install" = "应用安装目录"
        "Application state" = "应用状态数据"
        "Hibernation file" = "休眠文件"
        "Pagefile" = "页面文件"
        "System backups" = "系统备份"
        "Security data" = "安全数据"
        "Windows power management" = "Windows 电源管理"
        "Windows crash diagnostics" = "Windows 崩溃诊断"
        "Needs official analysis" = "需要官方工具分析"
    }

    if ($map.ContainsKey($text)) { return $map[$text] }
    return $Value
}

function Get-DirectoryStats {
    param([string]$Path)

    $size = [Int64]0
    $fileCount = 0
    $dirCount = 0
    $latestWrite = $null
    $oldBytes = [Int64]0
    $recentBytes = [Int64]0
    $ageCutoff = (Get-Date).AddDays(-1 * $MinAgeDays)

    try {
        Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.PSIsContainer) {
                $dirCount++
            }
            else {
                $fileCount++
                $size += $_.Length
                if ($_.LastWriteTime -lt $ageCutoff) { $oldBytes += $_.Length } else { $recentBytes += $_.Length }
            }
            if ($null -eq $latestWrite -or $_.LastWriteTime -gt $latestWrite) {
                $latestWrite = $_.LastWriteTime
            }
        }
    }
    catch {
        # Access denied is expected in some Program Files and AppData folders.
    }

    [pscustomobject]@{
        SizeBytes     = $size
        FileCount     = $fileCount
        DirectoryCount = $dirCount
        LastWriteTime = $latestWrite
        OldBytes      = $oldBytes
        RecentBytes   = $recentBytes
    }
}

function Get-KeywordHits {
    param([string]$Name, [string]$Path)

    $text = "$Name $Path".ToLowerInvariant()
    $keywords = @(
        "cache", "temp", "tmp", "log", "logs", "crash", "dump", "dmp",
        "shader", "thumbnail", "thumbcache", "backup", "update", "installer",
        "packages", "node_modules", "pip", "nuget", "gradle", "electron",
        "steam", "epic", "unity", "unreal", "nvidia", "defender", "iis"
    )

    $keywords | Where-Object { $text.Contains($_) }
}

function Get-OwnerGuess {
    param([string]$Name, [string]$Path)

    $known = @{
        "Google" = "Google"
        "Chrome" = "Google Chrome"
        "Microsoft" = "Microsoft"
        "NVIDIA" = "NVIDIA"
        "Steam" = "Steam"
        "EpicGamesLauncher" = "Epic Games"
        "Discord" = "Discord"
        "Tencent" = "Tencent"
        "ByteDance" = "ByteDance/Douyin"
        "Douyin" = "Douyin"
        "Docker" = "Docker"
        "JetBrains" = "JetBrains"
        "Nodejs" = "Node.js"
        "Python" = "Python"
        "Package Cache" = "Installer/package cache"
    }

    foreach ($key in $known.Keys) {
        if ($Name -like "*$key*" -or $Path -like "*$key*") {
            return $known[$key]
        }
    }

    if ($Path -like "*\Program Files*") { return "Installed application" }
    if ($Path -like "*\AppData\*") { return "Per-user application data" }
    return "Unknown"
}

function Get-FolderDescription {
    param([string]$Name, [string]$Path)

    $text = "$Name $Path".ToLowerInvariant()

    if ($text.Contains("tencent") -or $text.Contains("wechat") -or $text.Contains("xwechat") -or $text.Contains("qq")) {
        return (T "Tencent-family application folder; often WeChat, QQ, Tencent Meeting, game components, updates, plugins, logs, or media cache." "Tencent 系应用目录，常见于微信、QQ、腾讯会议、腾讯游戏组件、更新包、插件、日志或媒体缓存。")
    }
    if ($text.Contains("microsoft") -or $text.Contains("edge")) {
        return (T "Microsoft-family application data. Large browser or Windows-managed data should be handled through app settings or official Windows tools." "Microsoft 系应用数据。较大的浏览器数据或 Windows 管理内容应优先通过应用设置或官方 Windows 工具处理。")
    }
    if ($text.Contains("code") -or $text.Contains("vscode") -or $text.Contains("visual studio")) {
        return (T "Developer-tool folder; may contain extension packages, caches, crash reports, settings, or project-related state." "开发工具目录，可能包含扩展安装包、缓存、崩溃报告、设置或项目相关状态。")
    }
    if ($text.Contains("npm-cache") -or $text.Contains("npm") -or $text.Contains("pnpm") -or $text.Contains("yarn")) {
        return (T "JavaScript package-manager cache. Prefer package-manager cleanup commands after confirmation instead of raw deletion." "JavaScript 包管理器缓存。确认后优先使用包管理器清理命令，而不是直接删除目录。")
    }
    if ($text.Contains("temp") -or $text.Contains("tmp")) {
        return (T "Temporary-file area. It may still contain recent installers, diagnostics, or files held by running apps." "临时文件区域，但仍可能包含最近的安装器、诊断输出或正在被运行中应用占用的文件。")
    }
    if ($text.Contains("app_shell_cache")) {
        return (T "Application shell cache with unclear owner. Inspect contained executables/packages and related processes before cleanup." "应用外壳缓存，归属不明确。清理前应检查其中的可执行文件/安装包以及相关进程。")
    }
    if ($text.Contains("nvidia")) {
        return (T "NVIDIA-related folder; may include drivers, shader cache, logs, or control-panel data." "NVIDIA 相关目录，可能包含驱动、着色器缓存、日志或控制面板数据。")
    }
    if ($text.Contains("docker")) {
        return (T "Docker data or application folder. It can contain images, containers, volumes, and VM-backed data; use Docker commands." "Docker 数据或应用目录，可能包含镜像、容器、卷和虚拟机承载的数据，应使用 Docker 命令处理。")
    }
    if ($text.Contains("steam") -or $text.Contains("epic")) {
        return (T "Game platform folder; may mix launchers, games, shader caches, mods, and save-related data." "游戏平台目录，可能混合启动器、游戏本体、着色器缓存、Mod 和存档相关数据。")
    }
    if ($Path -like "*\Program Files*") {
        return (T "Installed application directory. Prefer uninstall, reinstall outside C drive, or app-supported cache migration." "已安装应用目录。优先考虑卸载后安装到 C 盘外，或使用应用内支持的缓存迁移。")
    }
    if ($Path -like "*\AppData\*") {
        return (T "Per-user application data. Cache, settings, account data, and saved state may be mixed." "用户级应用数据，可能混合缓存、设置、账号数据和保存状态。")
    }
    return (T "Unknown folder; inspect before cleanup." "未知目录，清理前需要检查。")
}

function Get-ContentType {
    param([string[]]$Hits, [string]$Path)

    if ($Hits -contains "temp" -or $Hits -contains "tmp") { return "Temporary files" }
    if ($Hits -contains "cache" -or $Hits -contains "shader" -or $Hits -contains "thumbnail" -or $Hits -contains "thumbcache") { return "Cache" }
    if ($Hits -contains "log" -or $Hits -contains "logs") { return "Logs" }
    if ($Hits -contains "crash" -or $Hits -contains "dump" -or $Hits -contains "dmp") { return "Crash dumps" }
    if ($Hits -contains "backup") { return "Backup data" }
    if ($Hits -contains "installer" -or $Hits -contains "packages") { return "Installer/package data" }
    if ($Path -like "*\Program Files*") { return "Application install" }
    if ($Path -like "*\AppData\*") { return "Application state" }
    return "Unknown"
}

function Get-RiskModel {
    param(
        [string]$Name,
        [string]$Path,
        [string]$ContentType,
        [string[]]$Hits,
        [Int64]$SizeBytes,
        [int]$FileCount,
        [int]$DirectoryCount
    )

    $score = 0
    if ($SizeBytes -ge 10GB) { $score += 3 }
    elseif ($SizeBytes -ge 3GB) { $score += 2 }
    elseif ($SizeBytes -ge 1GB) { $score += 1 }

    if ($FileCount -gt 200000 -or $DirectoryCount -gt 10000) { $score += 3 }
    elseif ($FileCount -gt 50000 -or $DirectoryCount -gt 3000) { $score += 2 }
    elseif ($FileCount -gt 10000 -or $DirectoryCount -gt 1000) { $score += 1 }

    $sensitivePattern = "(?i)windows|microsoft|defender|security|installer|winsxs|package cache|driver|database|docker|vmware|virtualbox|steam|epic|save|userdata|onedrive|dropbox|icloud"
    if ($Name -match $sensitivePattern -or $Path -match $sensitivePattern) { $score += 2 }

    if ($ContentType -in @("Cache", "Temporary files", "Logs")) { $score -= 1 }
    if ($ContentType -in @("Backup data", "Installer/package data", "Application install", "Application state")) { $score += 1 }

    $complexity = if ($score -ge 5) { "High" } elseif ($score -ge 2) { "Medium" } else { "Low" }

    $risk = "Medium"
        $hazard = (T "May contain app state mixed with cache; inspect before deleting." "可能混合应用状态和缓存，删除前需要检查。")
        $action = (T "Review contents and prefer in-app cache migration or reinstall outside C drive." "审查内容，优先使用应用内缓存迁移，或卸载后安装到 C 盘外。")
    $reclaimRatio = 0.0

    if ($ContentType -eq "Temporary files" -or $ContentType -eq "Logs" -or $ContentType -eq "Cache") {
        $risk = if ($score -ge 4) { "Medium" } else { "Low" }
        $hazard = (T "Usually rebuildable; apps may launch slower or regenerate files." "通常可重建，但应用可能启动变慢或重新生成文件。")
        $action = (T "Candidate for confirmed cleanup if no related app is running." "若相关应用未运行，可作为确认后清理候选项。")
        $reclaimRatio = 0.7
    }
    elseif ($ContentType -eq "Crash dumps") {
        $risk = "Medium"
        $hazard = (T "Deleting removes debugging evidence for recent crashes." "删除后会丢失近期崩溃的调试证据。")
        $action = (T "Delete only after confirming crash diagnostics are no longer needed." "确认不再需要崩溃诊断后再删除。")
        $reclaimRatio = 0.9
    }

    if ($Name -match $sensitivePattern -or $Path -match $sensitivePattern) {
        if ($risk -eq "Low") { $risk = "Medium" } else { $risk = "High" }
        $hazard = (T "Sensitive application or system-managed data; do not delete by path without exact review." "敏感应用或系统管理数据，未精确审查前不要按路径直接删除。")
        $action = (T "Dispatch focused inspection; use official app or Windows cleanup mechanisms." "派发重点检查；优先使用官方应用或 Windows 清理机制。")
        $reclaimRatio = 0.0
    }

    [pscustomobject]@{
        Complexity = $complexity
        Risk = $risk
        SuggestedAction = $action
        EstimatedReclaimBytes = [Int64]($SizeBytes * $reclaimRatio)
        DeletionHazard = $hazard
    }
}

function Get-FirstLevelAudit {
    param([string[]]$Roots)

    $items = New-Object System.Collections.Generic.List[object]

    foreach ($root in $Roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -Force -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $stats = Get-DirectoryStats -Path $_.FullName
            $hits = @(Get-KeywordHits -Name $_.Name -Path $_.FullName)
            $owner = Get-OwnerGuess -Name $_.Name -Path $_.FullName
            $description = Get-FolderDescription -Name $_.Name -Path $_.FullName
            $contentType = Get-ContentType -Hits $hits -Path $_.FullName
            $risk = Get-RiskModel -Name $_.Name -Path $_.FullName -ContentType $contentType -Hits $hits -SizeBytes $stats.SizeBytes -FileCount $stats.FileCount -DirectoryCount $stats.DirectoryCount

            $items.Add([pscustomobject]@{
                Path = $_.FullName
                SizeBytes = $stats.SizeBytes
                Size = ConvertTo-HumanSize $stats.SizeBytes
                FileCount = $stats.FileCount
                DirectoryCount = $stats.DirectoryCount
                LastWriteTime = $stats.LastWriteTime
                OwnerGuess = $owner
                FolderDescription = $description
                ContentType = $contentType
                KeywordHits = ($hits -join ", ")
                OldBytes = $stats.OldBytes
                RecentBytes = $stats.RecentBytes
                OldSize = ConvertTo-HumanSize $stats.OldBytes
                RecentSize = ConvertTo-HumanSize $stats.RecentBytes
                Complexity = $risk.Complexity
                Risk = $risk.Risk
                SuggestedAction = $risk.SuggestedAction
                EstimatedReclaimBytes = $risk.EstimatedReclaimBytes
                EstimatedReclaim = ConvertTo-HumanSize $risk.EstimatedReclaimBytes
                DeletionHazard = $risk.DeletionHazard
            })
        }
    }

    $items | Sort-Object SizeBytes -Descending
}

function Get-SystemPlanItems {
    $items = New-Object System.Collections.Generic.List[object]

    $hiber = "C:\hiberfil.sys"
    if (Test-Path -LiteralPath $hiber) {
        $file = Get-Item -LiteralPath $hiber -Force -ErrorAction SilentlyContinue
        $items.Add([pscustomobject]@{
            Path = $hiber
            SizeBytes = $file.Length
            Size = ConvertTo-HumanSize $file.Length
            FileCount = 1
            DirectoryCount = 0
            LastWriteTime = $file.LastWriteTime
            OwnerGuess = (T "Windows power management" "Windows 电源管理")
            FolderDescription = (T "System-managed hibernation file. Use official powercfg command only." "系统管理的休眠文件，只能使用官方 powercfg 命令处理。")
            ContentType = (T "Hibernation file" "休眠文件")
            KeywordHits = "hibernate"
            Complexity = "Medium"
            Risk = "Medium"
            SuggestedAction = (T "Plan only: powercfg /hibernate off. This disables hibernation and may affect Fast Startup." "仅计划：powercfg /hibernate off。会关闭休眠，并可能影响快速启动。")
            EstimatedReclaimBytes = $file.Length
            EstimatedReclaim = ConvertTo-HumanSize $file.Length
            DeletionHazard = (T "Do not delete by path; use powercfg." "不要按路径删除，应使用 powercfg。")
        })
    }

    $memoryDump = "C:\Windows\MEMORY.DMP"
    if (Test-Path -LiteralPath $memoryDump) {
        $file = Get-Item -LiteralPath $memoryDump -Force -ErrorAction SilentlyContinue
        $items.Add([pscustomobject]@{
            Path = $memoryDump
            SizeBytes = $file.Length
            Size = ConvertTo-HumanSize $file.Length
            FileCount = 1
            DirectoryCount = 0
            LastWriteTime = $file.LastWriteTime
            OwnerGuess = (T "Windows crash diagnostics" "Windows 崩溃诊断")
            FolderDescription = (T "Kernel crash dump. Useful for diagnosing blue screens and system crashes." "内核崩溃转储，可用于诊断蓝屏和系统崩溃。")
            ContentType = (T "Crash dumps" "崩溃转储")
            KeywordHits = "dump"
            Complexity = "Low"
            Risk = "Medium"
            SuggestedAction = (T "Candidate for confirmed cleanup after crash diagnostics are no longer needed." "确认不再需要崩溃诊断后，可作为清理候选项。")
            EstimatedReclaimBytes = $file.Length
            EstimatedReclaim = ConvertTo-HumanSize $file.Length
            DeletionHazard = (T "Deleting removes evidence for kernel crash analysis." "删除后会丢失内核崩溃分析证据。")
        })
    }

    $advisory = @(
        @("SYSTEM: WinSxS component store", "Windows component store", "Windows 组件存储", "WinSxS", "WinSxS", "DISM.exe /Online /Cleanup-Image /AnalyzeComponentStore; then /StartComponentCleanup", "先运行 DISM.exe /Online /Cleanup-Image /AnalyzeComponentStore，再按需运行 /StartComponentCleanup。", "Never delete C:\Windows\WinSxS by path.", "不要按路径直接删除 C:\Windows\WinSxS。"),
        @("SYSTEM: Windows Temp", "Windows temporary files", "Windows 临时文件", "Temporary files", "临时文件", "Inspect C:\Windows\Temp and delete only old unheld files after closing apps.", "检查 C:\Windows\Temp；关闭应用后只清理较旧且未被占用的文件。", "Recent installers and diagnostics may live here.", "最近的安装器和诊断输出可能位于这里。"),
        @("SYSTEM: User Temp", "Per-user temporary files", "用户临时文件", "Temporary files", "临时文件", "Inspect %TEMP%; use age buckets because recent large files may be active.", "检查 %TEMP%；必须参考年龄分桶，因为近期大文件可能仍在使用。", "Large recent temp files can be installers or diagnostic outputs.", "近期的大型临时文件可能是安装器或诊断输出。"),
        @("SYSTEM: Pagefile relocation", "Windows virtual memory", "Windows 虚拟内存", "Pagefile", "页面文件", "Plan through System Properties or documented WMI/registry change; reboot required.", "通过系统属性或有文档依据的 WMI/注册表方案规划；需要重启。", "Bad pagefile settings can affect stability and crash dumps.", "错误的页面文件设置可能影响系统稳定性和崩溃转储。"),
        @("SYSTEM: Restore points and backups", "Windows recovery", "Windows 恢复", "System backups", "系统备份", "Use Windows UI or official tools to remove old restore points.", "使用 Windows 界面或官方工具删除旧还原点。", "Deleting removes rollback options.", "删除后会失去对应的系统回滚能力。"),
        @("SYSTEM: Defender quarantine/history", "Windows Defender", "Windows Defender", "Security data", "安全数据", "Review in Windows Security or Defender cmdlets; do not raw-delete quarantine.", "在 Windows 安全中心或 Defender cmdlet 中审查；不要直接删除隔离区。", "Raw deletion can hide security context or break Defender state.", "直接删除可能丢失安全上下文或破坏 Defender 状态。")
    )

    foreach ($entry in $advisory) {
        $items.Add([pscustomobject]@{
            Path = $entry[0]
            SizeBytes = 0
            Size = (T "Unknown" "未知")
            FileCount = 0
            DirectoryCount = 0
            LastWriteTime = $null
            OwnerGuess = (T $entry[1] $entry[2])
            FolderDescription = (T "System cleanup advisory item." "系统清理建议项。")
            ContentType = (T $entry[3] $entry[4])
            KeywordHits = "system"
            OldBytes = 0
            RecentBytes = 0
            OldSize = (T "Unknown" "未知")
            RecentSize = (T "Unknown" "未知")
            Complexity = "High"
            Risk = "High"
            SuggestedAction = (T $entry[5] $entry[6])
            EstimatedReclaimBytes = 0
            EstimatedReclaim = (T "Needs official analysis" "需要官方工具分析")
            DeletionHazard = (T $entry[7] $entry[8])
        })
    }

    $items
}

function Write-MarkdownTable {
    param([object[]]$Rows)

    $columns = @(
        "Path", "Size", "OwnerGuess", "FolderDescription", "ContentType", "Complexity", "Risk",
        "SuggestedAction", "EstimatedReclaim", "OldSize", "RecentSize", "DeletionHazard", "CleanupStatus"
    )

    if ($script:ReportLanguage -eq "zh-CN") {
        "| 路径 | 大小 | 归属推测 | 文件夹描述 | 内容类型 | 复杂度 | 风险 | 建议动作 | 预计可释放 | 超过 $MinAgeDays 天 | $MinAgeDays 天内 | 删除危害 | 清理状态 |"
    }
    else {
        "| Path | Size | Owner guess | Folder description | Content type | Complexity | Risk | Suggested action | Estimated reclaim | Older than $MinAgeDays days | Within $MinAgeDays days | Deletion hazard | Cleanup status |"
    }
    "|---|---:|---|---|---|---|---|---|---:|---:|---:|---|---|"
    foreach ($row in $Rows) {
        $values = $columns | ForEach-Object { Escape-MarkdownCell (ConvertTo-DisplayValue -Column $_ -Value $row.$_) }
        "| $($values -join ' | ') |"
    }
}

function Get-CleanupExclusionReason {
    param([object]$Row)

    if ($Row.Risk -ne "Low") { return (T "Excluded: risk is not low." "排除：风险不是低风险。") }
    if ($Row.ContentType -notin @("Cache", "Temporary files", "Logs")) { return (T "Excluded: content type is not a simple cache/temp/log target." "排除：内容类型不是简单缓存/临时文件/日志。") }
    if ($Row.RecentBytes -gt 0 -and $Row.OldBytes -eq 0) { return (T "Excluded: all measured bytes are recent." "排除：测得的文件全部是近期文件。") }
    if ($Row.RecentBytes -gt $Row.OldBytes) { return (T "Excluded: most bytes are recent; inspect age buckets first." "排除：大部分体积来自近期文件，需要先看年龄分布。") }
    return (T "Candidate: old low-risk cache/temp/log data." "候选：较旧的低风险缓存/临时文件/日志。")
}

function Invoke-SafeCleanupPreview {
    param([object[]]$Rows)

    $cutoff = (Get-Date).AddDays(-1 * $MinAgeDays)
    $annotated = $Rows | ForEach-Object {
        $reason = Get-CleanupExclusionReason -Row $_
        $_ | Add-Member -NotePropertyName CleanupStatus -NotePropertyValue $reason -Force
        $_
    }

    $candidates = $annotated | Where-Object {
        $_.CleanupStatus -like (T "Candidate:*" "候选：*") -and
        ($null -eq $_.LastWriteTime -or $_.LastWriteTime -lt $cutoff)
    }

    if (-not $Execute -or -not $ConfirmClean) {
        return $annotated | Sort-Object SizeBytes -Descending | Select-Object -First $TopN
    }

    foreach ($candidate in $candidates) {
        try {
            Remove-Item -LiteralPath $candidate.Path -Recurse -Force -ErrorAction Stop
            $candidate | Add-Member -NotePropertyName CleanupStatus -NotePropertyValue "Deleted" -Force
        }
        catch {
            $candidate | Add-Member -NotePropertyName CleanupStatus -NotePropertyValue "Failed: $($_.Exception.Message)" -Force
        }
        $candidate
    }
}

$roots = if ($RootPaths -and $RootPaths.Count -gt 0) { $RootPaths } else { Resolve-DefaultRoots }
$rows = @(Get-FirstLevelAudit -Roots $roots)

if ($Mode -eq "plan") {
    $rows = @($rows + @(Get-SystemPlanItems)) | Sort-Object SizeBytes -Descending
}
elseif ($Mode -eq "clean-safe") {
    $rows = @(Invoke-SafeCleanupPreview -Rows $rows)
}

if ($OutputFormat -eq "json") {
    $output = $rows | ConvertTo-Json -Depth 6
}
else {
    $output = Write-MarkdownTable -Rows $rows
}

if ($OutputPath) {
    $parent = Split-Path -Parent $OutputPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $output | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Output (T "Wrote report: $OutputPath" "已写入报告：$OutputPath")
}
else {
    $output
}


