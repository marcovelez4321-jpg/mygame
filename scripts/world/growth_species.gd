class_name GrowthSpecies
extends Resource

## One kind of growth and how it grows (GrowthScatter reads these): where on
## the land it likes to be, how its groups come -- mostly small groups, now
## and then a big one, rarely a huge horde -- and how it looks and moves.
## Every number here is a tuning knob for the look of the land.

@export var kind: GrowthMeshes.Kind = GrowthMeshes.Kind.GLOW_GRASS
## How many shape variants to mix (each a different random build).
@export_range(1, 8) var variants: int = 4

@export_group("Where")
## Groups per chunk (128 x 128 m) where this kind is at its most common.
@export var groups_per_chunk: float = 6.0
## Its own patchy map over the land: some areas full of it (forests,
## groves), others with none. patch_size = the size of those areas
## (metres), patch_cover = how much of the land they cover (0..1).
@export var patch_size: float = 400.0
@export_range(0.0, 1.0, 0.05) var patch_cover: float = 0.6
## Ground it grows on: slope (degrees) and height (0 = the lowest ground,
## 1 = the highest -- valleys to ridges).
@export var min_slope: float = 0.0
@export var max_slope: float = 35.0
@export_range(0.0, 1.0, 0.05) var min_height: float = 0.0
@export_range(0.0, 1.0, 0.05) var max_height: float = 1.0

@export_group("Groups")
## Members in a group: at least min_group; bigger groups get rarer the
## bigger they are (a "long tail": group_tail near 1 = huge hordes fairly
## often, 3 = almost always small), never more than max_group.
@export var min_group: int = 3
@export var max_group: int = 60
@export var group_tail: float = 1.3
## How far apart members stand (metres, roughly): the group spreads wider
## the more there are.
@export var spacing: float = 1.5
## How tightly they bunch toward the group's middle (1 = evenly, 2 =
## crowded in the middle and thin at the edges).
@export var crowding: float = 1.6
## Lone ones scattered between the groups, per chunk.
@export var loners_per_chunk: float = 4.0

@export_group("Size")
## Size range: members in the middle of a group are toward the big end,
## stragglers at the edge toward the small end, plus a random spread.
@export var min_scale: float = 0.6
@export var max_scale: float = 1.4
## Now and then an "elder", this many times bigger than the rest.
@export_range(0.0, 0.2, 0.005) var elder_chance: float = 0.01
@export var elder_scale: float = 2.2
## How much each leans with the ground (0 = straight up, 1 = square to the
## slope).
@export_range(0.0, 1.0, 0.05) var follow_ground: float = 0.3
## How far it's sunk into the ground (metres, at scale 1).
@export var sink: float = 0.05

@export_group("Look")
## Tints each one a little differently: how much (0..1).
@export_range(0.0, 1.0, 0.05) var tint_variation: float = 0.25
@export var glow_color: Color = Color(0.45, 0.9, 1.0)
@export var sway_amount: float = 0.15
## Gone past this distance (metres). The fog's solid at about 220.
@export var view_distance: float = 180.0
@export var cast_shadows: bool = false


## How many times bigger every default group is than the numbers below.
const GROUP_SCALE := 4


## The default set of growths, tuned to each other: the land's flora.
static func defaults() -> Array[GrowthSpecies]:
	var list: Array[GrowthSpecies] = []
	# Glow grass: carpets the flatter ground in big drifts -- the commonest
	# growth by far: more groups, over more of the land, more strays.
	list.append(_make(GrowthMeshes.Kind.GLOW_GRASS, 16.0, 300.0, 0.85, 0.0, 32.0, 0.0, 1.0,
			6, 220, 1.1, 0.7, 1.4, 20.0, 0.6, 1.4, Color(0.5, 0.95, 1.0), 0.12, 90.0))
	# Brain coral: lumps dotted about, in twos and threes and small beds.
	list.append(_make(GrowthMeshes.Kind.BRAIN_CORAL, 4.0, 350.0, 0.6, 0.0, 30.0, 0.0, 0.8,
			2, 25, 1.6, 2.2, 1.5, 3.0, 0.5, 1.6, Color(0.7, 0.5, 1.0), 0.0, 160.0))
	# Staghorn: coral forests in patches, thick in the middle.
	list.append(_make(GrowthMeshes.Kind.STAGHORN, 3.0, 500.0, 0.45, 0.0, 28.0, 0.0, 0.85,
			4, 80, 1.2, 2.6, 1.8, 1.5, 0.6, 1.7, Color(0.95, 0.5, 0.9), 0.08, 200.0))
	# Kelp: groves in the valleys, tall silhouettes in the fog.
	list.append(_make(GrowthMeshes.Kind.KELP, 2.0, 450.0, 0.5, 0.0, 30.0, 0.0, 0.45,
			3, 45, 1.4, 3.0, 1.5, 0.8, 0.7, 1.5, Color(0.5, 0.95, 1.0), 0.45, 230.0))
	# Sea fans: on the hillsides, a few together.
	list.append(_make(GrowthMeshes.Kind.SEA_FAN, 3.0, 300.0, 0.6, 8.0, 42.0, 0.15, 1.0,
			2, 18, 1.8, 1.8, 1.3, 2.0, 0.6, 1.5, Color(1.0, 0.55, 0.85), 0.2, 150.0))
	# Anemones: fields of them on the flats.
	list.append(_make(GrowthMeshes.Kind.ANEMONE, 3.0, 280.0, 0.5, 0.0, 25.0, 0.0, 0.7,
			5, 90, 1.3, 1.1, 1.6, 2.0, 0.6, 1.5, Color(0.9, 0.6, 0.9), 0.1, 120.0))
	# Tube sponges: up on the ridges, small stacks.
	list.append(_make(GrowthMeshes.Kind.TUBE_SPONGE, 2.5, 300.0, 0.6, 0.0, 35.0, 0.5, 1.0,
			2, 14, 2.0, 1.6, 1.4, 1.5, 0.6, 1.8, Color(1.0, 0.6, 0.8), 0.0, 180.0))
	# Puffballs: little bunches anywhere, not many.
	list.append(_make(GrowthMeshes.Kind.PUFFBALL, 2.0, 250.0, 0.55, 0.0, 30.0, 0.0, 1.0,
			3, 30, 1.6, 1.0, 1.5, 3.0, 0.5, 1.4, Color(0.8, 0.95, 0.85), 0.06, 110.0))
	# Spire coral: twisted spikes on the steeper rough ground.
	list.append(_make(GrowthMeshes.Kind.SPIRE, 1.5, 400.0, 0.5, 20.0, 55.0, 0.2, 1.0,
			2, 20, 1.8, 1.8, 1.4, 1.0, 0.6, 1.6, Color(1.0, 0.35, 0.55), 0.0, 200.0))
	# Bladder pods: rare glowing heaps in the low ground.
	list.append(_make(GrowthMeshes.Kind.BLADDER, 1.0, 400.0, 0.4, 0.0, 25.0, 0.0, 0.4,
			2, 12, 2.0, 1.6, 1.3, 0.8, 0.6, 1.6, Color(0.95, 0.6, 0.85), 0.03, 140.0))
	return list


static func _make(kind: GrowthMeshes.Kind, groups: float, patch: float, cover: float,
		slope_low: float, slope_high: float, height_low: float, height_high: float,
		group_low: int, group_high: int, tail: float, space: float, crowd: float, loners: float,
		scale_low: float, scale_high: float, glow: Color, sway: float, distance: float) -> GrowthSpecies:
	var species := GrowthSpecies.new()
	species.kind = kind
	species.groups_per_chunk = groups
	species.patch_size = patch
	species.patch_cover = cover
	species.min_slope = slope_low
	species.max_slope = slope_high
	species.min_height = height_low
	species.max_height = height_high
	# Groups four times the size they were first tuned at (the members per
	# group; a group spreads twice as wide to hold them at the same density).
	species.min_group = group_low * GROUP_SCALE
	species.max_group = group_high * GROUP_SCALE
	species.group_tail = tail
	species.spacing = space
	species.crowding = crowd
	species.loners_per_chunk = loners
	species.min_scale = scale_low
	species.max_scale = scale_high
	species.glow_color = glow
	species.sway_amount = sway
	species.view_distance = distance
	species.follow_ground = 0.8 if kind == GrowthMeshes.Kind.GLOW_GRASS or kind == GrowthMeshes.Kind.BRAIN_CORAL else 0.25
	species.cast_shadows = kind == GrowthMeshes.Kind.KELP or kind == GrowthMeshes.Kind.STAGHORN or kind == GrowthMeshes.Kind.SPIRE
	return species
