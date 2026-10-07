@tool
extends EditorScenePostImport

## Runs when Godot imports PKM.glb / PKM.fbx (set as their import script):
##
## 1. The carry handle was stretched miles out behind the gun. It's a child of
##    the Barrel node, which is scaled ~18x along its length (that's how the
##    barrel was made long) -- and since the handle is also rotated, that
##    stretch hits it at an angle and smears it out ~9 m straight back
##    (non-uniform parent scale + rotated child = shear). Fix: undo the
##    barrel's lengthwise stretch for the handle alone, as if the barrel were
##    scaled evenly -- it lands as a compact handle on top of the receiver.
##    (The real fix in Blender: apply scale on the Barrel, Ctrl+A > Scale,
##    before parenting anything to it.)
## 2. The model has the bipod both folded and deployed; the deployed one is
##    hidden so only the folded bipod shows.

func _post_import(scene: Node) -> Object:
	var handle := scene.find_child("Carry Handle", true, false) as Node3D
	var barrel := handle.get_parent() as Node3D if handle else null
	if handle and barrel:
		var stretch := barrel.basis.get_scale().abs()
		if stretch.y > 0.0:
			var undo := Basis.from_scale(Vector3(1.0, stretch.x / stretch.y, 1.0))
			handle.transform = Transform3D(undo, Vector3.ZERO) * handle.transform
	var deployed := scene.find_child("Bipod Deployed", true, false) as Node3D
	if deployed:
		deployed.visible = false
	return scene
