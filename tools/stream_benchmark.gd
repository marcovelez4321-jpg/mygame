extends Node

## Streaming stress test for the open world: how many chunks can stream
## round a player, at what speed, before frames hitch or the ground under
## them isn't loaded in time. Added as a temporary autoload to a run of the
## test world; it flies the player in a straight line across the land
## (their own movement switched off) for each load radius and speed below,
## and prints a table, then quits:
##   frame ms: average, 1% worst, worst; chunks live; growth jobs queued
##   (most); and "late" = the share of the time the chunk the player's in
##   wasn't loaded yet (streaming falling behind).

const RADII := [2, 3, 4]
## Walking, sprinting, grappling, and well past it.
const SPEEDS := [6.0, 12.0, 26.0, 50.0]
## Seconds per run, and the first part of each not counted (settling in).
const RUN_TIME := 12.0
const WARM_UP := 3.0

var _rows: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var tree := get_tree()
	var world: Node = null
	for i in 600:
		world = tree.current_scene
		if world and world.get_node_or_null(^"WorldChunks"):
			break
		await tree.process_frame
	var chunks := world.get_node_or_null(^"WorldChunks") as WorldChunks
	var growth := world.get_node_or_null(^"GrowthScatter")
	var terrain := world.get_node_or_null(^"Terrain3D")
	var player := world.get_node_or_null(^"Player") as Node3D
	if chunks == null or player == null or terrain == null:
		print("STREAM TEST: no WorldChunks / Player / Terrain3D in ", world)
		tree.quit()
		return
	player.process_mode = Node.PROCESS_MODE_DISABLED # we fly it
	var data: Object = null
	while data == null:
		data = terrain.call("get_data")
		await tree.process_frame
	print("STREAM TEST: chunk size %.0f m" % chunks.chunk_size)
	var heading := Vector3(1.0, 0.0, 0.37).normalized()
	var start := Vector3(-1500.0, 0.0, -600.0)
	for radius: int in RADII:
		chunks.load_radius = radius
		for speed: float in SPEEDS:
			var at := start
			var frames := PackedFloat32Array()
			var time := 0.0
			var late := 0.0
			var counted := 0.0
			var most_live := 0
			var most_jobs := 0
			while time < RUN_TIME:
				var delta := get_process_delta_time()
				await tree.process_frame
				time += delta
				at += heading * speed * delta
				var ground: float = data.call("get_height", at)
				player.global_position = Vector3(at.x, (ground if not is_nan(ground) else 0.0) + 2.0, at.z)
				if time < WARM_UP:
					continue
				frames.append(delta * 1000.0)
				counted += delta
				if not chunks.is_loaded(chunks.chunk_at(player.global_position)):
					late += delta
				var live := 0
				for root in chunks.get_children():
					live += 1
				most_live = maxi(most_live, live)
				if growth:
					most_jobs = maxi(most_jobs, (growth.get("_jobs") as Array).size())
			frames.sort()
			var total := 0.0
			for ms in frames:
				total += ms
			var average := total / maxf(frames.size(), 1)
			var low := frames[int(frames.size() * 0.99)] if not frames.is_empty() else 0.0
			var worst := frames[frames.size() - 1] if not frames.is_empty() else 0.0
			_rows.append("radius %d (%dx%d)  %4.0f m/s   avg %5.1f ms  1%% %5.1f ms  worst %6.1f ms   live %3d   jobs %3d   late %3.0f%%" % [
					radius, radius * 2 + 1, radius * 2 + 1, speed, average, low, worst, most_live, most_jobs,
					late / maxf(counted, 0.001) * 100.0])
			print(_rows[_rows.size() - 1])
			start += Vector3(0.0, 0.0, 250.0) # the next run on fresh ground
	print("STREAM TEST DONE")
	for row in _rows:
		print(row)
	tree.quit()
