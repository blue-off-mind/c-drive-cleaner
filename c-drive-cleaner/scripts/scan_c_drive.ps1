param(
    [ValidateSet("scan", "plan", "clean-safe")]
    [string]$Mode = "scan",

    [ValidateSet("markdown", "json")]
    [string]$OutputFormat = "markdown",

    [string[]]$RootPaths,

    [int]$MinAgeDays = 7,

    [switch]$Execute,

    [switch]$ConfirmClean
)

$ErrorActionPreference = "Continue"

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

function Get-DirectoryStats {
    param([string]$Path)

    $size = [Int64]0
    $fileCount = 0
    $dirCount = 0
    $latestWrite = $null

    try {
        Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.PSIsContainer) {
                $dirCount++
            }
            else {
                $fileCount++
                $size += $_.Length
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
    $hazard = "May contain app state mixed with cache; inspect before deleting."
    $action = "Review contents and prefer in-app cache migration or reinstall outside C drive."
    $reclaimRatio = 0.0

    if ($ContentType -eq "Temporary files" -or $ContentType -eq "Logs" -or $ContentType -eq "Cache") {
        $risk = if ($score -ge 4) { "Medium" } else { "Low" }
        $hazard = "Usually rebuildable; apps may launch slower or regenerate files."
        $action = "Candidate for confirmed cleanup if no related app is running."
        $reclaimRatio = 0.7
    }
    elseif ($ContentType -eq "Crash dumps") {
        $risk = "Medium"
        $hazard = "Deleting removes debugging evidence for recent crashes."
        $action = "Delete only after confirming crash diagnostics are no longer needed."
        $reclaimRatio = 0.9
    }

    if ($Name -match $sensitivePattern -or $Path -match $sensitivePattern) {
        if ($risk -eq "Low") { $risk = "Medium" } else { $risk = "High" }
        $hazard = "Sensitive application or system-managed data; do not delete by path without exact review."
        $action = "Dispatch focused inspection; use official app or Windows cleanup mechanisms."
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
                ContentType = $contentType
                KeywordHits = ($hits -join ", ")
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
            OwnerGuess = "Windows power management"
            ContentType = "Hibernation file"
            KeywordHits = "hibernate"
            Complexity = "Medium"
            Risk = "Medium"
            SuggestedAction = "Plan only: powercfg /hibernate off. This disables hibernation and may affect Fast Startup."
            EstimatedReclaimBytes = $file.Length
            EstimatedReclaim = ConvertTo-HumanSize $file.Length
            DeletionHazard = "Do not delete by path; use powercfg."
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
            OwnerGuess = "Windows crash diagnostics"
            ContentType = "Crash dumps"
            KeywordHits = "dump"
            Complexity = "Low"
            Risk = "Medium"
            SuggestedAction = "Candidate for confirmed cleanup after crash diagnostics are no longer needed."
            EstimatedReclaimBytes = $file.Length
            EstimatedReclaim = ConvertTo-HumanSize $file.Length
            DeletionHazard = "Deleting removes evidence for kernel crash analysis."
        })
    }

    $items
}

function Write-MarkdownTable {
    param([object[]]$Rows)

    $columns = @(
        "Path", "Size", "OwnerGuess", "ContentType", "Complexity", "Risk",
        "SuggestedAction", "EstimatedReclaim", "DeletionHazard"
    )

    "| Path | Size | Owner guess | Content type | Complexity | Risk | Suggested action | Estimated reclaim | Deletion hazard |"
    "|---|---:|---|---|---|---|---|---:|---|"
    foreach ($row in $Rows) {
        $values = $columns | ForEach-Object { Escape-MarkdownCell $row.$_ }
        "| $($values -join ' | ') |"
    }
}

function Invoke-SafeCleanupPreview {
    param([object[]]$Rows)

    $cutoff = (Get-Date).AddDays(-1 * $MinAgeDays)
    $candidates = $Rows | Where-Object {
        $_.Risk -eq "Low" -and
        $_.ContentType -in @("Cache", "Temporary files", "Logs") -and
        ($null -eq $_.LastWriteTime -or $_.LastWriteTime -lt $cutoff)
    }

    if (-not $Execute -or -not $ConfirmClean) {
        return $candidates | ForEach-Object {
            $_ | Add-Member -NotePropertyName CleanupStatus -NotePropertyValue "Preview only; rerun with -Execute -ConfirmClean after review." -Force
            $_
        }
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
    $rows | ConvertTo-Json -Depth 6
}
else {
    Write-MarkdownTable -Rows $rows
}
