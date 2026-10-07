class_name DeepmawBend
extends SkeletonModifier3D

## Bends a Deepmaw's spine along the path it's swimming, AFTER its animation
## has posed the skeleton -- so the jaws still bite and snap from the
## animation while the body follows the tunnel. Added under the model's
## Skeleton3D by Deepmaw.

var worm: Deepmaw


func _process_modification_with_delta(_delta: float) -> void:
	if is_instance_valid(worm):
		worm.bend_spine(get_skeleton())
