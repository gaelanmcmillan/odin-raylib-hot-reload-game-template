# Watches gameplay sources and rebuilds the hot-reload DLL when they change.
# game_hot_reload.exe notices game.dll on its own. Ctrl+C stops this watcher
# and leaves the game running.
#
# Default watch set: *.odin directly in source\ (package game). Pass extra
# file or directory paths to watch those too. A directory adds its top-level
# *.odin files. source\main_* is not included.

Set-StrictMode -Version Latest

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

$ExtraPaths = @($args)
$PollMs = 250

function Get-WatchedFiles {
    $files = @()

    $sourceDir = Join-Path $Root "source"
    if (Test-Path -LiteralPath $sourceDir) {
        $files += @(Get-ChildItem -LiteralPath $sourceDir -Filter *.odin -File -ErrorAction SilentlyContinue)
    }

    foreach ($extra in $ExtraPaths) {
        if (Test-Path -LiteralPath $extra -PathType Container) {
            $files += @(Get-ChildItem -LiteralPath $extra -Filter *.odin -File -ErrorAction SilentlyContinue)
        } elseif (Test-Path -LiteralPath $extra -PathType Leaf) {
            $files += @(Get-Item -LiteralPath $extra)
        } else {
            $files += @(Get-Item -Path $extra -ErrorAction SilentlyContinue)
        }
    }

    return @($files | Sort-Object -Property FullName -Unique)
}

function Get-WatchSignature {
    $parts = @(foreach ($file in (Get-WatchedFiles)) {
        "{0}|{1}" -f $file.FullName, $file.LastWriteTimeUtc.Ticks
    })
    return ($parts -join "`n")
}

function Format-WatchPath([string]$FullName) {
    $prefix = $Root.TrimEnd('\') + '\'
    if ($FullName.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $FullName.Substring($prefix.Length)
    }
    return $FullName
}

function Invoke-HotReloadBuild {
    & cmd.exe /c "build_hot_reload.bat run"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Build failed (exit $LASTEXITCODE). Still watching."
    }
}

Write-Host "Watching gameplay sources. Ctrl+C stops the watcher; the game keeps running."

foreach ($extra in $ExtraPaths) {
    $found = (Test-Path -LiteralPath $extra) -or (@(Get-Item -Path $extra -ErrorAction SilentlyContinue).Count -gt 0)
    if (-not $found) {
        Write-Host "Warning: not found: $extra"
    }
}

$listed = @(Get-WatchedFiles)
if ($listed.Count -eq 0) {
    Write-Host "No files to watch yet."
} else {
    foreach ($file in $listed) {
        Write-Host ("  " + (Format-WatchPath $file.FullName))
    }
}

# Snapshot before building. The build does not rewrite these files, and an
# edit that lands while odin is running still differs from this snapshot, so
# the next poll rebuilds again.
$signature = Get-WatchSignature
Invoke-HotReloadBuild

while ($true) {
    Start-Sleep -Milliseconds $PollMs
    $now = Get-WatchSignature
    if ($now -eq $signature) {
        continue
    }

    do {
        $signature = $now
        Start-Sleep -Milliseconds $PollMs
        $now = Get-WatchSignature
    } while ($now -ne $signature)

    Write-Host "Change detected, rebuilding..."
    Invoke-HotReloadBuild
}
