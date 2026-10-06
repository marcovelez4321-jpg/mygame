# Writes maps/sample_doors_and_levers.map -- the example map in the mapping
# kit: one room split by a wall with three doorways.
#   - a lever that raises a gate        (func_lever  -> func_door "gate1")
#   - a button that swings a door open  (func_button -> func_door_rotating "door2")
#   - a door locked until you pick up the gold key (func_door key=Gold + item_key)
# Friends open it in TrenchBroom to see exactly how each one is set up.
# Re-run only if you want to regenerate it:  right-click -> Run with PowerShell

$ErrorActionPreference = 'Stop'
$out = Join-Path (Split-Path $PSScriptRoot -Parent) 'maps\sample_doors_and_levers.map'

# One axis-aligned box brush in TrenchBroom's Valve 220 format (min/max in
# units; plane points and texture axes exactly as TrenchBroom writes a box).
function Box([int]$x0, [int]$y0, [int]$z0, [int]$x1, [int]$y1, [int]$z1, [string]$tex) {
    $s = '0.125 0.125'
    @(
        '{'
        "( $x0 $y0 $z0 ) ( $x0 $($y0 + 1) $z0 ) ( $x0 $y0 $($z0 + 1) ) $tex [ 0 -1 0 0 ] [ 0 0 -1 0 ] 0 $s"
        "( $x0 $y0 $z0 ) ( $x0 $y0 $($z0 + 1) ) ( $($x0 + 1) $y0 $z0 ) $tex [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 $s"
        "( $x0 $y0 $z0 ) ( $($x0 + 1) $y0 $z0 ) ( $x0 $($y0 + 1) $z0 ) $tex [ -1 0 0 0 ] [ 0 -1 0 0 ] 0 $s"
        "( $x1 $y1 $z1 ) ( $x1 $($y1 + 1) $z1 ) ( $($x1 + 1) $y1 $z1 ) $tex [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 $s"
        "( $x1 $y1 $z1 ) ( $($x1 + 1) $y1 $z1 ) ( $x1 $y1 $($z1 + 1) ) $tex [ -1 0 0 0 ] [ 0 0 -1 0 ] 0 $s"
        "( $x1 $y1 $z1 ) ( $x1 $y1 $($z1 + 1) ) ( $x1 $($y1 + 1) $z1 ) $tex [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 $s"
        '}'
    ) -join "`n"
}

function Entity($props, $brushes) {
    $lines = @('{')
    foreach ($key in $props.Keys) { $lines += "`"$key`" `"$($props[$key])`"" }
    $lines += $brushes
    $lines += '}'
    $lines -join "`n"
}

$wall = 'dev_wall_warm'; $floor = 'dev_floor_grey'
$world = @(
    (Box -512 -384 -16  512  384   0 $floor)   # floor
    (Box -512 -384 256  512  384 272 $floor)   # ceiling
    (Box -528 -400   0 -512  400 256 $wall)    # west wall
    (Box  512 -400   0  528  400 256 $wall)    # east wall
    (Box -512 -400   0  512 -384 256 $wall)    # south wall
    (Box -512  384   0  512  400 256 $wall)    # north wall
    # the dividing wall (y -8..8) with three 96-wide, 128-high doorways
    (Box -512   -8   0 -352    8 256 $wall)
    (Box -256   -8   0  -48    8 256 $wall)
    (Box   48   -8   0  256    8 256 $wall)
    (Box  352   -8   0  512    8 256 $wall)
    (Box -352   -8 128 -256    8 256 $wall)    # above doorway 1
    (Box  -48   -8 128   48    8 256 $wall)    # above doorway 2
    (Box  256   -8 128  352    8 256 $wall)    # above doorway 3
)

$entities = @(
    (Entity ([ordered]@{ mapversion = '220'; classname = 'worldspawn' }) $world)
    (Entity ([ordered]@{ classname = 'info_player_start'; origin = '0 -300 24'; angle = '90' }) @())

    # 1. Lever -> gate: the lever's target matches the gate's targetname.
    (Entity ([ordered]@{ classname = 'func_door'; targetname = 'gate1'; angle = '-1' }) @(
        (Box -352 -4 0 -256 4 128 'dev_red')))
    (Entity ([ordered]@{ classname = 'func_lever'; target = 'gate1'; axis = '1'; hinge = '1'; distance = '60' }) @(
        (Box -228 -24 48 -220 -8 104 'dev_blue')))

    # 2. Button -> swinging door, hinged on its west end.
    (Entity ([ordered]@{ classname = 'func_door_rotating'; targetname = 'door2'; hinge = '3'; distance = '90' }) @(
        (Box -48 -4 0 48 4 128 'dev_accent_orange')))
    (Entity ([ordered]@{ classname = 'func_button'; target = 'door2'; angle = '90' }) @(
        (Box 72 -16 56 104 -8 88 'dev_green')))

    # 3. Gold key door: opens by itself once you carry the gold key.
    (Entity ([ordered]@{ classname = 'func_door'; key = '2'; angle = '-1' }) @(
        (Box 256 -4 0 352 4 128 'dev_accent_orange')))
    (Entity ([ordered]@{ classname = 'item_key'; key_type = '1'; origin = '304 -240 32' }) @())
)

$text = "// Game: 2v-2`n// Format: Valve`n" + ($entities -join "`n") + "`n"
[IO.File]::WriteAllText($out, $text, (New-Object Text.UTF8Encoding $false))
"Wrote $out"
