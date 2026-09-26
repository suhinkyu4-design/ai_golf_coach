$ErrorActionPreference = 'Stop'

$root = git rev-parse --show-toplevel
if (-not $root) {
    throw 'Run this script inside the ai_golf_coach Git repository.'
}

git -C $root config core.hooksPath .githooks
git -C $root config push.default current
Write-Host 'Automatic push is enabled: each commit on main will push to origin/main.'
