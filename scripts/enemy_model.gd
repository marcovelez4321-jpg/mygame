@tool
class_name EnemyModel
extends Node3D

## Picks which character model this enemy wears when it spawns, from a list,
## so a room full of one enemy type isn't a room of clones. Any model works if
## it was imported with the shared bone map (art/animations/mixamo_bonemap.tres
## -- FBX Import tab > Skeleton3D > Retarget > Bone Map): that renames its
## skeleton to GeneralSkeleton and its bones to Godot's humanoid names, which
## the shared animations (EnemyAnimator), the ragdoll (RagdollBuilder) and the
## artery-hit Neck lookup all depend on.
##
## The model is added in _enter_tree(), not _ready(), on purpose: EnemyAnimator
## and EnemyRagdoll come later in the scene and look for the AnimationPlayer and
## Skeleton3D in their own _ready(), and every _enter_tree() in a scene runs
## before any _ready().
##
## Rule 1 (co-op): same pattern as EnemyAnimator.variation_seed -- 0 rolls a
## random pick at spawn; the host will send its seed with the spawn message so
## both players see the same model on the same enemy.

## Models to pick from. Keep each enemy TYPE on its own set of models so
## players can tell a rusher from a gunner at a glance (Rule 3: readability).
@export var variants: Array[PackedScene] = []:
	set(value):
		variants = value
		if Engine.is_editor_hint() and is_inside_tree():
			_show_editor_preview()

var model_seed: int = 0

var _model: Node3D


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		_show_editor_preview()
		return
	if _model != null:
		return # already picked; re-entering the tree (reparenting) keeps it
	if variants.is_empty():
		push_warning("EnemyModel: no variants assigned on %s -- enemy has no model." % get_parent().name)
		return
	if model_seed == 0:
		model_seed = randi()
	var rng := RandomNumberGenerator.new()
	rng.seed = model_seed
	_spawn(variants[rng.randi() % variants.size()])


func _spawn(scene: PackedScene) -> void:
	if scene == null:
		push_warning("EnemyModel: an empty slot in variants on %s." % get_parent().name)
		return
	_model = scene.instantiate() as Node3D
	add_child(_model)


## Editor only: shows the first variant so the enemy isn't an invisible capsule
## while you work on its scene or place it in a level. It's never given an
## owner, so it's never saved into the .tscn -- the real pick still happens at
## spawn.
func _show_editor_preview() -> void:
	if is_instance_valid(_model):
		_model.queue_free()
	_model = null
	if not variants.is_empty():
		_spawn(variants[0])
