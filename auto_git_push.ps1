# Git Auto Push Script (Real-time FileSystemWatcher + Exit Handler)

Set-Location $PSScriptRoot

function Push-GitChanges([string]$Reason = "Auto-commit") {
    $status = git status --porcelain
    if ($status) {
        $currentTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "`n[$currentTime] [$Reason] Detected changes! Pushing to Git..." -ForegroundColor Cyan
        git add -A
        git commit -m "Auto-commit: $currentTime [$Reason]"
        git push origin main
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[$currentTime] Successfully uploaded to GitHub!`n" -ForegroundColor Green
        } else {
            Write-Host "[$currentTime] Push failed or sync needed.`n" -ForegroundColor Red
        }
    }
}

# Exit Handler (On-Exit Flush)
$exitAction = {
    Write-Host "`n========================================================" -ForegroundColor Yellow
    Write-Host "Process termination detected. Flushing remaining changes..." -ForegroundColor Yellow
    Push-GitChanges -Reason "Final On-Exit Flush"
    Write-Host "========================================================" -ForegroundColor Yellow
}

try {
    [System.AppDomain]::CurrentDomain.add_ProcessExit($exitAction)
    Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action $exitAction -ErrorAction SilentlyContinue | Out-Null
} catch {}

Write-Host "========================================================" -ForegroundColor Green
Write-Host "[AI Golf Coach] Auto Git Push Service Running" -ForegroundColor Green
Write-Host "Real-time file save watcher + Exit flush enabled" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Green

# FileSystemWatcher
$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $PSScriptRoot
$watcher.IncludeSubdirectories = $true
$watcher.EnableRaisingEvents = $true

$filterRegex = "(\.git|\.dart_tool|build|\.idea|android[\\/]\.gradle|android[\\/]app[\\/]build)"

while ($true) {
    $result = $watcher.WaitForChanged([System.IO.WatcherChangeTypes]::All, 2000)
    if (-not $result.TimedOut) {
        if ($result.Name -notmatch $filterRegex) {
            Start-Sleep -Seconds 3
            Push-GitChanges -Reason "Real-time Save"
        }
    }
}
