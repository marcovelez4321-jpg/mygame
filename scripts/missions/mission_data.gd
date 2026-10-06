class_name MissionData
extends Resource

## One mission Grandma can send you on. To add a mission, make a new .tres
## in res://missions/ (right-click the folder > New Resource > MissionData),
## fill these in -- it shows up in her list automatically, in `order`.
## Rule 1 (co-op): a mission is picked by its file path, which is the same
## on both players' games, so "start mission X" is one short string to send.

const FOLDER := "res://missions"
## Where "Back to Grandma's" (pause menu) takes you. The test map for now;
## becomes the real hub house once it's built.
const HUB_SCENE := "res://scenes/test_map/test_map.tscn"

@export var title: String = "Mission"
## One line under the title in Grandma's list.
@export_multiline var description: String = ""
## The level it takes you to.
@export_file("*.tscn") var scene: String = ""
## Lower comes first in the list.
@export var order: int = 0


## Every mission in FOLDER, sorted by order then title.
static func all() -> Array[MissionData]:
	var missions: Array[MissionData] = []
	for file in ResourceLoader.list_directory(FOLDER):
		if file.get_extension() != "tres":
			continue
		var mission := load(FOLDER.path_join(file)) as MissionData
		if mission and not mission.scene.is_empty():
			missions.append(mission)
	missions.sort_custom(func(a: MissionData, b: MissionData) -> bool:
		return a.order < b.order if a.order != b.order else a.title < b.title)
	return missions
