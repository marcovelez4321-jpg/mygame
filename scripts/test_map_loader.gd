class_name TestMapLoader
extends Node

## Gets a TrenchBroom .map from the player's own computer into the game, so a
## mapper can test their map in the published web build: the pause menu's
## Load Test Map button opens a file picker, or a .map file can be dragged
## straight onto the game window. The file is copied to TestMapLevel.MAP_PATH
## and map_ready fires; the pause menu then opens TestMapLevel, which builds it.
##
## In a browser, Godot can't open a file picker itself, so a hidden HTML file
## input does it and hands the text back through a JavaScript callback.

signal map_ready

## Kept alive here: JavaScript only holds a weak link to the callback.
var _web_callback: JavaScriptObject
var _file_dialog: FileDialog


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().files_dropped.connect(_on_files_dropped)


func pick() -> void:
	if OS.has_feature("web"):
		_pick_in_browser()
	else:
		_pick_on_desktop()


func _pick_in_browser() -> void:
	if _web_callback == null:
		_web_callback = JavaScriptBridge.create_callback(_on_browser_file_read)
		JavaScriptBridge.get_interface("window").set("godotTestMapRead", _web_callback)
	JavaScriptBridge.eval("""
		(function () {
			var input = document.createElement('input');
			input.type = 'file';
			input.accept = '.map';
			input.onchange = function () {
				var file = input.files[0];
				if (!file) return;
				var reader = new FileReader();
				reader.onload = function () { window.godotTestMapRead(reader.result); };
				reader.readAsText(file);
			};
			input.click();
		})();
	""", true)


func _on_browser_file_read(args: Array) -> void:
	_use_map_text(str(args[0]))


func _pick_on_desktop() -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.filters = PackedStringArray(["*.map ; TrenchBroom map"])
		_file_dialog.use_native_dialog = true
		_file_dialog.file_selected.connect(_load_from_path)
		add_child(_file_dialog)
	_file_dialog.popup_centered_ratio(0.6)


## Dragging a .map onto the game window works in the browser and on desktop.
func _on_files_dropped(files: PackedStringArray) -> void:
	for path in files:
		if path.get_extension().to_lower() == "map":
			_load_from_path(path)
			return


func _load_from_path(path: String) -> void:
	_use_map_text(FileAccess.get_file_as_string(path))


func _use_map_text(text: String) -> void:
	if not text.contains("classname"):
		OS.alert("That doesn't look like a TrenchBroom .map file.", "Load Test Map")
		return
	var file := FileAccess.open(TestMapLevel.MAP_PATH, FileAccess.WRITE)
	if file == null:
		OS.alert("Couldn't save the map (error %d)." % FileAccess.get_open_error(), "Load Test Map")
		return
	file.store_string(text)
	file.close()
	map_ready.emit()
