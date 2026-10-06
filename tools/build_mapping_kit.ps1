# Builds the TrenchBroom mapping kit for friends: Desktop\2v2_mapping_kit.zip.
# Run again whenever you add textures or change entities (after "Export
# GameConfig" in Godot -- see MAPPING_GUIDE.md section 1).
#
#   Right-click this file -> Run with PowerShell
#
# The zip has no folder inside it, so Windows' "Extract All" gives exactly one
# folder (no 2v2_mapping_kit\2v2_mapping_kit nesting), and paths use forward
# slashes so every unzip tool, Mac included, recreates the textures folder.

param(
    [string]$Output = (Join-Path ([Environment]::GetFolderPath('Desktop')) '2v2_mapping_kit.zip')
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$config = Join-Path $env:APPDATA 'TrenchBroom\games\2v-2'
$textures = Join-Path $repo 'trenchbroom\textures'

$files = [ordered]@{
    'GameConfig.cfg'    = Join-Path $config 'GameConfig.cfg'
    'game_entities.fgd' = Join-Path $config 'game_entities.fgd'
    'icon.png'          = Join-Path $config 'icon.png'
    'MAPPING_GUIDE.md'  = Join-Path $repo 'MAPPING_GUIDE.md'
    'SETUP.bat'         = Join-Path $PSScriptRoot 'mapping_kit\SETUP.bat'
    'setup.ps1'         = Join-Path $PSScriptRoot 'mapping_kit\setup.ps1'
}
foreach ($name in $files.Keys) {
    if (-not (Test-Path -LiteralPath $files[$name])) {
        throw "Missing $($files[$name]) -- in Godot, click Export GameConfig first (MAPPING_GUIDE.md section 1)."
    }
}

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
if (Test-Path -LiteralPath $Output) { Remove-Item -LiteralPath $Output }
$zip = [IO.Compression.ZipFile]::Open($Output, 'Create')
$imageTypes = '.png', '.jpg', '.jpeg', '.tga', '.bmp', '.webp'
# palette.lmp too: GameConfig.cfg names textures/palette.lmp, and TrenchBroom
# refuses to load ANY textures if it's missing.
$kitTypes = $imageTypes + '.lmp'
$count = 0
try {
    foreach ($name in $files.Keys) {
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $files[$name], $name)
    }
    # Images and the palette -- not Godot's .import files or generated materials.
    Get-ChildItem -LiteralPath $textures -Recurse -File |
        Where-Object { $kitTypes -contains $_.Extension.ToLower() } |
        ForEach-Object {
            $entry = 'textures/' + $_.FullName.Substring($textures.Length + 1).Replace('\', '/')
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $entry)
            if ($imageTypes -contains $_.Extension.ToLower()) { $count++ }
        }
    if (-not (Test-Path -LiteralPath (Join-Path $textures 'palette.lmp'))) {
        throw "Missing $textures\palette.lmp -- copy it from addons\func_godot\palette.lmp."
    }
} finally {
    $zip.Dispose()
}
"Built $Output ($count textures, {0:N0} MB)" -f ((Get-Item -LiteralPath $Output).Length / 1MB)
