class_name HeartHitbox
extends StaticBody3D

## The heart's body for shots (HeartBoss): its Health, and how a hit on it
## counts (WeaponController asks): while it's stunned every hit is an artery
## shot -- the red hitmarker, the artery spray, weak_spot_multiplier (1.5x,
## the user's) -- otherwise a plain one.

var heart: Node
## A non-normal hit's damage, times the weapon's (WeaponController._damage_for).
var weak_spot_multiplier := 1.5


func artery_now() -> bool:
	return heart != null and bool(heart.get("stunned"))


## The artery spray where it was hit (WeaponController's hit effects).
func artery_spray(at: Vector3, normal: Vector3) -> void:
	if heart:
		heart.call(&"artery_spray", at, normal)