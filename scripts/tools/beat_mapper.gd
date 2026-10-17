extends Control

## The beat mapper (the user's, 2026-10-17): tap out a song's drums for the
## heart boss. Open scenes/tools/beat_mapper.tscn and run it (F6).
##   Load a song (mp3, ogg or wav), Space to play, and tap along:
##   1 kick, 2 snare, 3 hi-hat. Each tap lands where you HEARD the song
##   (playback position less the audio's output delay).
##   Snap: with the song's BPM and its first beat (offset) set, taps snap to
##   the nearest 1/16 note.
##   The song's waveform runs under the lanes, to place or check hits by eye.
##   Left/Right seek 1 s (Shift: 5 s), Home to the start; click the timeline
##   to jump there; the wheel scrolls (paused), Ctrl+wheel zooms; right-click
##   a hit to take it out; Ctrl+Z undoes; Ctrl+S saves.
## Saved as a BeatMap (.tres, next to the song by default) the heart reads.

const PEAKS_PER_SECOND := 200
## Song frames decoded for the waveform per frame drawn (keeps it responsive).
const DECODE_PER_FRAME := 60000
const PLAYHEAD := 0.3 # across the timeline
const LANE_COLORS := [Color(1.0, 0.3, 0.25), Color(1.0, 0.85, 0.3), Color(0.35, 0.85, 1.0)]
const LANE_NAMES := ["1  KICK", "2  SNARE", "3  HI-HAT"]
const SONG_DIR := "res://audio/music"

var _map := BeatMap.new()
var _map_path := ""
var _player: AudioStreamPlayer
var _cursor := 0.0
var _window := 6.0 # seconds across the timeline
var _undo: Array = [] # [drum, time, added]
var _dirty := false
var _peaks := PackedFloat32Array()
var _decode: AudioStreamPlayback
var _decode_done := 0
var _decode_total := 0

var _timeline: Control
var _song_label: Label
var _status: Label
var _bpm: SpinBox
var _offset: SpinBox
var _snap: CheckBox
var _song_dialog: FileDialog
var _open_dialog: FileDialog
var _save_dialog: FileDialog
var _hidden := {} # the game's overlays switched off while mapping


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# The game's dither over everything and its pause menu: off in here.
	for name in ["PS1Dither", "PauseMenu"]:
		var node := get_node_or_null("/root/" + name)
		if node:
			_hidden[node] = [node.process_mode, node.get("visible")]
			node.process_mode = Node.PROCESS_MODE_DISABLED
			if node.get("visible") != null:
				node.set("visible", false)
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_player.finished.connect(func() -> void: _cursor = _length())
	_build_ui()
	_refresh()


func _exit_tree() -> void:
	for node: Node in _hidden:
		if is_instance_valid(node):
			node.process_mode = _hidden[node][0]
			if _hidden[node][1] != null:
				node.set("visible", _hidden[node][1])


func _process(_delta: float) -> void:
	_decode_step()
	_timeline.queue_redraw()
	_status.text = _status_text()


# ---- Time ---------------------------------------------------------------------------

## Where in the song you are: while it plays, what you're HEARING now.
func _now() -> float:
	if _player.playing:
		var heard := _player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
		return clampf(heard, 0.0, _length())
	return _cursor


func _length() -> float:
	return _player.stream.get_length() if _player.stream else 0.0


func _toggle_play() -> void:
	if _player.stream == null:
		return
	if _player.playing:
		_cursor = _now()
		_player.stop()
	else:
		if _cursor >= _length() - 0.01:
			_cursor = 0.0
		_player.play(_cursor)


func _seek(time: float) -> void:
	_cursor = clampf(time, 0.0, _length())
	if _player.playing:
		_player.seek(_cursor)


# ---- Taps ---------------------------------------------------------------------------

func _tap(drum: int) -> void:
	if _player.stream == null:
		return
	var time := _now()
	if _snap.button_pressed:
		var grid := _map.beat() / 4.0
		time = _map.offset + roundf((time - _map.offset) / grid) * grid
	if _map.add(drum, time):
		_undo.append([drum, time, true])
		_dirty = true


func _undo_last() -> void:
	if _undo.is_empty():
		return
	var last: Array = _undo.pop_back()
	if last[2]:
		_map.remove(last[0], last[1], 0.0005)
	else:
		_map.add(last[0], last[1], 0.0)
	_dirty = true


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	# Typing a number in a box (paused): the box has it.
	if get_viewport().gui_get_focus_owner() is LineEdit and not _player.playing:
		if key.keycode == KEY_ESCAPE or key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
			get_viewport().gui_release_focus()
		return
	var handled := true
	match key.keycode:
		KEY_1, KEY_KP_1:
			_tap(BeatMap.Drum.KICK)
		KEY_2, KEY_KP_2:
			_tap(BeatMap.Drum.SNARE)
		KEY_3, KEY_KP_3:
			_tap(BeatMap.Drum.HAT)
		KEY_SPACE:
			_toggle_play()
		KEY_LEFT:
			_seek(_now() - (5.0 if key.shift_pressed else 1.0))
		KEY_RIGHT:
			_seek(_now() + (5.0 if key.shift_pressed else 1.0))
		KEY_HOME:
			_seek(0.0)
		KEY_Z:
			if key.ctrl_pressed:
				_undo_last()
			else:
				handled = false
		KEY_S:
			if key.ctrl_pressed:
				_save()
			else:
				handled = false
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()


# ---- The timeline ---------------------------------------------------------------------

func _px_per_second() -> float:
	return _timeline.size.x / _window


func _time_at(x: float) -> float:
	return _now() + (x - _timeline.size.x * PLAYHEAD) / _px_per_second()


func _x_at(time: float) -> float:
	return _timeline.size.x * PLAYHEAD + (time - _now()) * _px_per_second()


## [lane top, lane height] for each drum, and the waveform band under them.
func _lane(drum: int) -> Vector2:
	var height := _timeline.size.y * 0.62 / 3.0
	return Vector2(drum * height, height)


func _timeline_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse == null or not mouse.pressed:
		return
	get_viewport().gui_release_focus()
	match mouse.button_index:
		MOUSE_BUTTON_LEFT:
			_seek(_time_at(mouse.position.x))
		MOUSE_BUTTON_RIGHT:
			# The hit nearest the click in that lane, if it's close.
			for drum in 3:
				var lane := _lane(drum)
				if mouse.position.y >= lane.x and mouse.position.y < lane.x + lane.y:
					var time := _time_at(mouse.position.x)
					var near := 8.0 / _px_per_second()
					var list := _map.hits(drum)
					var at := list.bsearch(time)
					var best := -1
					for i: int in [at - 1, at]:
						if i >= 0 and i < list.size() and absf(list[i] - time) <= near and (best < 0 or absf(list[i] - time) < absf(list[best] - time)):
							best = i
					if best >= 0:
						_undo.append([drum, list[best], false])
						_map.remove(drum, list[best], 0.0005)
						_dirty = true
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			var up := mouse.button_index == MOUSE_BUTTON_WHEEL_UP
			if mouse.ctrl_pressed:
				_window = clampf(_window * (0.8 if up else 1.25), 1.0, 60.0)
			elif not _player.playing:
				_seek(_cursor + _window * 0.08 * (-1.0 if up else 1.0))


func _draw_timeline() -> void:
	var size := _timeline.size
	var now := _now()
	var t0 := _time_at(0.0)
	var t1 := _time_at(size.x)
	_timeline.draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.06, 0.07))
	var lanes_bottom := _lane(2).x + _lane(2).y
	# The waveform band, under the lanes.
	var band := Rect2(0.0, lanes_bottom + 6.0, size.x, size.y - lanes_bottom - 6.0)
	_timeline.draw_rect(band, Color(0.09, 0.09, 0.1))
	if not _peaks.is_empty():
		var middle := band.position.y + band.size.y * 0.5
		var x := 0.0
		while x < size.x:
			var index := int(_time_at(x) * PEAKS_PER_SECOND)
			if index >= 0 and index < _peaks.size():
				var half := _peaks[index] * band.size.y * 0.48
				_timeline.draw_line(Vector2(x, middle - half), Vector2(x, middle + half), Color(0.45, 0.55, 0.65), 2.0)
			x += 2.0
	# The beat grid: bars, beats, and 1/16s when there's room for them.
	var beat := _map.beat()
	var step := beat / 4.0 if step_fits(beat / 4.0) else beat
	var k := ceili((t0 - _map.offset) / step)
	var t := _map.offset + k * step
	while t < t1:
		var x := _x_at(t)
		var sixteenths := roundi((t - _map.offset) / (beat / 4.0))
		var color := Color(1, 1, 1, 0.05)
		if sixteenths % 16 == 0:
			color = Color(1, 1, 1, 0.3)
		elif sixteenths % 4 == 0:
			color = Color(1, 1, 1, 0.13)
		_timeline.draw_line(Vector2(x, 0.0), Vector2(x, size.y), color, 1.0)
		t += step
	# The lanes and their hits.
	var font := get_theme_default_font()
	for drum in 3:
		var lane := _lane(drum)
		var color: Color = LANE_COLORS[drum]
		_timeline.draw_rect(Rect2(0.0, lane.x + 1.0, size.x, lane.y - 2.0), Color(color, 0.06))
		var list := _map.hits(drum)
		for i in range(list.bsearch(t0), list.bsearch(t1)):
			var x := _x_at(list[i])
			_timeline.draw_rect(Rect2(x - 3.0, lane.x + lane.y * 0.15, 6.0, lane.y * 0.7), color)
		_timeline.draw_string(font, Vector2(8.0, lane.x + lane.y * 0.5 + 6.0), LANE_NAMES[drum], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(color, 0.8))
	# Where you are.
	var head := size.x * PLAYHEAD
	_timeline.draw_line(Vector2(head, 0.0), Vector2(head, size.y), Color(1.0, 1.0, 1.0, 0.9), 2.0)
	_timeline.draw_string(font, Vector2(head + 6.0, size.y - 8.0), _clock(now), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.8))


## Whether lines `step` seconds apart are far enough apart to draw.
func step_fits(step: float) -> bool:
	return step * _px_per_second() >= 10.0


static func _clock(time: float) -> String:
	return "%d:%06.3f" % [int(time) / 60, fmod(time, 60.0)]


# ---- The waveform ----------------------------------------------------------------------

## The song decoded a slice a frame into peaks (PEAKS_PER_SECOND), for the band.
func _decode_step() -> void:
	if _decode == null:
		return
	var rate := AudioServer.get_mix_rate()
	var per_peak := int(rate / PEAKS_PER_SECOND)
	var todo := mini(DECODE_PER_FRAME, _decode_total - _decode_done)
	todo -= todo % per_peak
	if todo <= 0:
		_decode.stop()
		_decode = null
		return
	var frames := _decode.mix_audio(1.0, todo)
	var peak := 0.0
	for i in frames.size():
		var f := frames[i]
		peak = maxf(peak, maxf(absf(f.x), absf(f.y)))
		if (i + 1) % per_peak == 0:
			_peaks.append(minf(peak, 1.0))
			peak = 0.0
	_decode_done += todo


func _start_decode() -> void:
	_peaks = PackedFloat32Array()
	_decode = null
	if _player.stream == null:
		return
	_decode = _player.stream.instantiate_playback()
	_decode.start(0.0)
	_decode_done = 0
	_decode_total = int(_length() * AudioServer.get_mix_rate())


# ---- Files ------------------------------------------------------------------------------

func _load_song(path: String) -> void:
	var stream := load(path) as AudioStream
	if stream == null:
		return
	_player.stop()
	_player.stream = stream
	_map.song = stream
	_cursor = 0.0
	_dirty = true
	_start_decode()
	_refresh()


func _open_map(path: String) -> void:
	var map := load(path) as BeatMap
	if map == null:
		return
	_map = map
	_map_path = path
	_undo.clear()
	_player.stop()
	_player.stream = _map.song
	_cursor = 0.0
	_dirty = false
	_start_decode()
	_refresh()


func _save() -> void:
	if _map_path.is_empty():
		var base := _map.song.resource_path.get_basename() if _map.song else SONG_DIR.path_join("song")
		_save_dialog.current_path = base + ".beats.tres"
		_save_dialog.popup_centered_ratio(0.6)
		return
	_save_to(_map_path)


func _save_to(path: String) -> void:
	_map_path = path
	if ResourceSaver.save(_map, path) == OK:
		_dirty = false
	_refresh()


# ---- The screen --------------------------------------------------------------------------

func _build_ui() -> void:
	var back := ColorRect.new()
	back.color = Color(0.04, 0.04, 0.05)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 12.0
	column.offset_top = 12.0
	column.offset_right = -12.0
	column.offset_bottom = -12.0
	add_child(column)
	var bar := HBoxContainer.new()
	column.add_child(bar)
	bar.add_child(_button("Load song", func() -> void: _song_dialog.popup_centered_ratio(0.6)))
	bar.add_child(_button("Open map", func() -> void: _open_dialog.popup_centered_ratio(0.6)))
	bar.add_child(_button("Save", _save))
	bar.add_child(_button("Save as", _save_as))
	_song_label = Label.new()
	_song_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_song_label)
	bar.add_child(_label("BPM"))
	_bpm = _spin(20.0, 400.0, 0.01, _map.bpm, _bpm_changed)
	bar.add_child(_bpm)
	bar.add_child(_label("First beat (s)"))
	_offset = _spin(-10.0, 30.0, 0.001, _map.offset, _offset_changed)
	bar.add_child(_offset)
	_snap = CheckBox.new()
	_snap.text = "Snap to 1/16"
	_snap.focus_mode = Control.FOCUS_NONE
	bar.add_child(_snap)
	_timeline = Control.new()
	_timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_timeline.clip_contents = true
	_timeline.draw.connect(_draw_timeline)
	_timeline.gui_input.connect(_timeline_input)
	column.add_child(_timeline)
	_status = Label.new()
	column.add_child(_status)
	var help := Label.new()
	help.text = "Space play/pause   1 kick   2 snare   3 hi-hat   Left/Right seek 1 s (Shift 5 s)   Home start   click: jump   wheel: scroll   Ctrl+wheel: zoom   right-click a hit: delete   Ctrl+Z undo   Ctrl+S save"
	help.modulate = Color(1, 1, 1, 0.6)
	column.add_child(help)
	_song_dialog = _dialog(FileDialog.FILE_MODE_OPEN_FILE, PackedStringArray(["*.mp3, *.ogg, *.wav ; Songs"]), _load_song)
	_song_dialog.current_dir = SONG_DIR
	_open_dialog = _dialog(FileDialog.FILE_MODE_OPEN_FILE, PackedStringArray(["*.tres ; Beat maps"]), _open_map)
	_open_dialog.current_dir = SONG_DIR
	_save_dialog = _dialog(FileDialog.FILE_MODE_SAVE_FILE, PackedStringArray(["*.tres ; Beat maps"]), _save_to)


func _save_as() -> void:
	_map_path = ""
	_save()


func _bpm_changed(value: float) -> void:
	_map.bpm = value
	_dirty = true


func _offset_changed(value: float) -> void:
	_map.offset = value
	_dirty = true


func _refresh() -> void:
	var song := _map.song.resource_path.get_file() if _map.song else "no song loaded"
	_song_label.text = "  %s   %s" % [song, ("-> " + _map_path.get_file()) if not _map_path.is_empty() else "(not saved yet)"]
	_bpm.set_value_no_signal(_map.bpm)
	_offset.set_value_no_signal(_map.offset)


func _status_text() -> String:
	var decoding := "   waveform %d%%" % int(100.0 * _decode_done / maxf(_decode_total, 1.0)) if _decode else ""
	return "%s / %s   kicks %d   snares %d   hi-hats %d   view %.1f s%s%s" % [_clock(_now()), _clock(_length()),
			_map.kicks.size(), _map.snares.size(), _map.hats.size(), _window, decoding, "   * unsaved" if _dirty else ""]


func _button(text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(pressed)
	return button


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = "   " + text
	return label


func _spin(low: float, high: float, step: float, value: float, changed: Callable) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.value = value
	spin.custom_minimum_size.x = 110.0
	spin.value_changed.connect(changed)
	return spin


func _dialog(mode: FileDialog.FileMode, filters: PackedStringArray, chosen: Callable) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.file_mode = mode
	dialog.access = FileDialog.ACCESS_RESOURCES
	dialog.filters = filters
	dialog.use_native_dialog = false
	dialog.file_selected.connect(chosen)
	add_child(dialog)
	return dialog
