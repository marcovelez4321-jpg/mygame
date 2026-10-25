class_name JournalPage
extends Control

## One page of the journal (the user's, 2026-10-25): cheap grey paper, no
## lines, grubby fingerprints; the notes in pencil, in a scrawled hand
## (Reenie Beanie, art/journal/), and a pencil sketch under them. Drawn into
## a SubViewport (JournalView) only when it changes.

const SIZE := Vector2(480, 640)
const FONT_PATH := "res://art/journal/ReenieBeanie.ttf"
const FONT_SIZE := 38
## The scrawl thickened (the user's: bolder, easier to read).
const EMBOLDEN := 0.8
const PAPER := Color(0.72, 0.72, 0.7)
const PENCIL := Color(0.24, 0.24, 0.26)
const MARGIN := 36.0
const TEXT_HEIGHT := 380.0
## The sketch's box, under the notes.
const SKETCH_BOX := Rect2(70, 440, 340, 170)

var _label: RichTextLabel
var _sketch := &""
var _seed := 0

static var _font: Font


func _init() -> void:
	size = SIZE
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.scroll_active = false
	_label.position = Vector2(MARGIN, MARGIN)
	_label.size = Vector2(SIZE.x - MARGIN * 2.0, TEXT_HEIGHT)
	_label.add_theme_font_override("normal_font", font())
	_label.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	_label.add_theme_color_override("default_color", PENCIL)
	add_child(_label)


## The handwriting: the imported font (or read straight from the file before
## the editor's imported it), thickened by EMBOLDEN.
static func font() -> Font:
	if _font == null:
		var base: Font
		if ResourceLoader.exists(FONT_PATH):
			base = load(FONT_PATH) as Font
		else:
			var file := FontFile.new()
			file.load_dynamic_font(FONT_PATH)
			base = file
		var bold := FontVariation.new()
		bold.base_font = base
		bold.variation_embolden = EMBOLDEN
		_font = bold
	return _font


## `entry` (QuestJournal.pages()) on this page, or blank ({}); `number` keeps
## each page's fingerprints its own.
func show_entry(entry: Dictionary, number: int) -> void:
	_label.text = str(entry.get("text", ""))
	_sketch = StringName(str(entry.get("sketch", "")))
	_seed = number * 7919 + 13
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SIZE), PAPER)
	var dice := RandomNumberGenerator.new()
	dice.seed = _seed
	# Grubby: a darker edge, and a few smudged prints.
	for i in 6:
		draw_rect(Rect2(Vector2.ONE * i * 3.0, SIZE - Vector2.ONE * i * 6.0), Color(0.3, 0.3, 0.28, 0.05), false, 3.0)
	for i in dice.randi_range(1, 3):
		_fingerprint(Vector2(dice.randf_range(40, SIZE.x - 40), dice.randf_range(40, SIZE.y - 40)), dice.randf() * TAU, dice)
	match _sketch:
		&"cigarettes":
			_cigarettes(dice)


func _fingerprint(at: Vector2, turn: float, dice: RandomNumberGenerator) -> void:
	draw_set_transform(at, turn, Vector2(1.0, 1.35))
	var ink := Color(0.25, 0.24, 0.22, 0.07)
	for ring in range(3, 26, 3):
		var start := dice.randf_range(0.0, 0.6)
		draw_arc(Vector2.ZERO, float(ring), start, start + TAU * dice.randf_range(0.7, 0.95), 24, ink, 1.6)
	draw_set_transform(Vector2.ZERO)


## A pencil line: two shaky strokes over each other.
func _stroke(a: Vector2, b: Vector2, dice: RandomNumberGenerator, width := 2.0) -> void:
	for pass_ in 2:
		var points := PackedVector2Array()
		var steps := maxi(int(a.distance_to(b) / 12.0), 2)
		var normal := (b - a).orthogonal().normalized()
		for i in steps + 1:
			var t := float(i) / steps
			points.append(a.lerp(b, t) + normal * dice.randf_range(-1.4, 1.4) + Vector2(dice.randf_range(-0.6, 0.6), dice.randf_range(-0.6, 0.6)))
		draw_polyline(points, Color(PENCIL, 0.75 if pass_ == 0 else 0.45), width)


## The last pack: a flip-top box seen from a corner, three left in it, the
## side hatched.
func _cigarettes(dice: RandomNumberGenerator) -> void:
	var box := SKETCH_BOX
	var o := box.position + Vector2(box.size.x * 0.32, box.size.y * 0.3)
	var w := 110.0
	var h := 120.0
	var d := Vector2(55.0, -28.0)
	var front := [o, o + Vector2(w, 0), o + Vector2(w, h), o + Vector2(0, h)]
	for i in 4:
		_stroke(front[i], front[(i + 1) % 4], dice)
	_stroke(front[1], front[1] + d, dice)
	_stroke(front[2], front[2] + d, dice)
	_stroke(front[1] + d, front[2] + d, dice)
	# The lid, flipped back.
	var lid := o + Vector2(0, -6)
	_stroke(lid, lid + d + Vector2(0, -38), dice)
	_stroke(lid + Vector2(w, 0), lid + Vector2(w, 0) + d + Vector2(0, -38), dice)
	_stroke(lid + d + Vector2(0, -38), lid + Vector2(w, 0) + d + Vector2(0, -38), dice)
	# Three cigarettes poking up.
	for i in 3:
		var x := o.x + 18.0 + i * 30.0
		var top := o.y - 22.0 - dice.randf_range(0.0, 10.0)
		_stroke(Vector2(x, o.y + 4), Vector2(x, top), dice, 1.6)
		_stroke(Vector2(x + 14, o.y + 4), Vector2(x + 14, top), dice, 1.6)
		_stroke(Vector2(x, top), Vector2(x + 14, top), dice, 1.6)
	# The side, hatched.
	for i in range(1, 9):
		var t := float(i) / 9.0
		_stroke(front[1].lerp(front[2], t), front[1].lerp(front[2], t) + d * 0.92, dice, 1.2)
