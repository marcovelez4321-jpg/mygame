extends StaticBody3D

## A dummy target for testing shots before real enemies exist. It uses the
## same Health component real monsters and the player will use.

@onready var health: Health = $Health


func _ready() -> void:
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)


func _on_damaged(amount: float, _attacker_id: int) -> void:
	print("Target hit for %.0f (%.0f left)" % [amount, health.current_health])


func _on_died(_attacker_id: int, _is_critical: bool) -> void:
	queue_free()
