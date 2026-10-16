class_name FrameBudget
extends RefCounted

## Time-slicing (the standard way open worlds stream without stutters): work
## that spawns lots of things asks over() before each piece, and once this
## frame's BUDGET_USEC of such work is spent it waits for the next frame
## (`while FrameBudget.over(): await get_tree().process_frame`). Shared by
## everything that uses it, so ten nests loading at once still only take the
## budget each frame between them. (The user's stutters by the Stack: up to
## 85 ms frames, a chunk's barnacle nests all made at once.)

const BUDGET_USEC := 2000

static var _frame := -1
static var _start := 0


## True once this frame's budget is spent (the first ask in a frame starts it).
static func over() -> bool:
	var frame := Engine.get_process_frames()
	if frame != _frame:
		_frame = frame
		_start = Time.get_ticks_usec()
		return false
	return Time.get_ticks_usec() - _start > BUDGET_USEC