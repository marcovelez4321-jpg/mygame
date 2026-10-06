# Sets up TrenchBroom for 2v-2 mapping. Double-click SETUP.bat to run this.
# Installs the 2v-2 game config and points TrenchBroom's Game Path at this
# folder (the one with "textures" in it), so every kit texture shows up.
# Moved this folder somewhere else later? Just run SETUP.bat again.

$ErrorActionPreference = 'Stop'
$kit = $PSScriptRoot
$tbDir = Join-Path $env:APPDATA 'TrenchBroom'
$gameDir = Join-Path $tbDir 'games\2v-2'
$prefsPath = Join-Path $tbDir 'Preferences.json'

Write-Host ''
Write-Host '2v-2 TrenchBroom setup' -ForegroundColor Cyan
Write-Host '----------------------'

if (-not (Test-Path -LiteralPath (Join-Path $kit 'textures'))) {
    Write-Host "Can't find the textures folder next to this file." -ForegroundColor Red
    Write-Host 'Unzip the WHOLE kit first (right-click the zip -> Extract All), then run SETUP.bat from the unzipped folder.' -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -LiteralPath (Join-Path $kit 'textures\palette.lmp'))) {
    Write-Host 'textures\palette.lmp is missing from this kit -- TrenchBroom will show no textures without it. Ask for a new kit.' -ForegroundColor Red
    exit 1
}

# TrenchBroom rewrites its settings when it closes, which would undo this.
while (Get-Process -Name 'TrenchBroom' -ErrorAction SilentlyContinue) {
    Write-Host 'TrenchBroom is open -- close it, then press Enter.' -ForegroundColor Yellow
    [void](Read-Host)
}

# 1. The game config (what makes "2v-2" show up under New Map).
New-Item -ItemType Directory -Force -Path $gameDir | Out-Null
foreach ($file in 'GameConfig.cfg', 'game_entities.fgd', 'icon.png') {
    Copy-Item -LiteralPath (Join-Path $kit $file) -Destination $gameDir -Force
}
Write-Host "Game config installed to $gameDir"

# 2. The Game Path (where TrenchBroom looks for the textures folder).
#    Keeps every other TrenchBroom setting as it was.
$prefs = [ordered]@{}
if (Test-Path -LiteralPath $prefsPath) {
    try {
        $json = Get-Content -LiteralPath $prefsPath -Raw
        if ($json -and $json.Trim()) {
            (ConvertFrom-Json $json).PSObject.Properties | ForEach-Object { $prefs[$_.Name] = $_.Value }
        }
    } catch {
        Copy-Item -LiteralPath $prefsPath -Destination "$prefsPath.backup" -Force
        Write-Host 'Old TrenchBroom settings were unreadable -- backed up to Preferences.json.backup.' -ForegroundColor Yellow
    }
}
$prefs['Games/2v-2/Path'] = $kit
# No byte-order mark: TrenchBroom can't read settings files that start with one.
[IO.File]::WriteAllText($prefsPath, ($prefs | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding $false))

$imageTypes = '.png', '.jpg', '.jpeg', '.tga', '.bmp', '.webp'
$count = @(Get-ChildItem -LiteralPath (Join-Path $kit 'textures') -Recurse -File |
    Where-Object { $imageTypes -contains $_.Extension.ToLower() }).Count
Write-Host "Game Path set to $kit ($count textures)" -ForegroundColor Green
Write-Host ''
Write-Host 'Done! Open TrenchBroom -> New map -> 2v-2.' -ForegroundColor Green
Write-Host "If you move this folder later, run SETUP.bat again."
