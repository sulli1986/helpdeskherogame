extends Node
## Drag-to-scroll for touchscreens, anywhere in the UI. Godot's ScrollContainer only scrolls when
## the drag starts on empty space, so on a phone a finger that lands on an answer, a queue row or
## the evidence box couldn't scroll at all (most of the screen). This sees touches first: a short
## press is left alone (a tap), a drag past SLOP scrolls the deepest ScrollContainer under the
## finger, with a little momentum, and the control under the finger is told the press slid off
## so it doesn't fire.

const SLOP := 12.0          # px a touch may move and still count as a tap
const FRICTION := 4.0       # momentum decay per second
const MIN_SPEED := 30.0     # px/s below which momentum stops

var _down := false
var _start := Vector2.ZERO
var _dragging := false
var _target: ScrollContainer
var _vertical := true
var _vel := 0.0
var _coast: ScrollContainer
var _injecting := false
var _eat_mouse_up := false  # the emulated-mouse release of a drag can arrive after the touch release


func _input(event: InputEvent) -> void:
	if _injecting:
		return
	if event is InputEventScreenTouch and event.index == 0:
		if event.pressed:
			_down = true
			_dragging = false
			_start = event.position
			_coast = null
			for sc in get_tree().root.find_children("*", "ScrollContainer", true, false):
				(sc as ScrollContainer).scroll_deadzone = 100000  # ours replaces the built-in drag (it would double up)
		else:
			_down = false
			if _dragging:
				_dragging = false
				_coast = _target if absf(_vel) > MIN_SPEED else null
				_send_release()
				_eat_mouse_up = true
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == 0 and _down:
		if not _dragging:
			var moved: Vector2 = event.position - _start
			if moved.length() < SLOP:
				return
			_vertical = absf(moved.y) >= absf(moved.x)
			_target = _scroller_at(_start, _vertical)
			if _target == null:
				_down = false  # nothing to scroll that way: leave the gesture to the GUI
				return
			_dragging = true
			_vel = 0.0
			_cancel_press()
		var d: float = -(event.relative.y if _vertical else event.relative.x)
		_scroll_by(_target, d)
		var dt := maxf(get_process_delta_time(), 0.001)
		_vel = lerpf(_vel, d / dt, 0.4)
		get_viewport().set_input_as_handled()
	elif _dragging and (event is InputEventMouseMotion or event is InputEventMouseButton):
		get_viewport().set_input_as_handled()  # the emulated-mouse copies of the drag
	elif _eat_mouse_up and event is InputEventMouseButton and not event.pressed:
		_eat_mouse_up = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		_eat_mouse_up = false


func _process(delta: float) -> void:
	if _coast == null or _dragging:
		return
	if not is_instance_valid(_coast) or not _coast.is_visible_in_tree():
		_coast = null
		return
	_scroll_by(_coast, _vel * delta)
	_vel *= maxf(0.0, 1.0 - FRICTION * delta)
	if absf(_vel) < MIN_SPEED:
		_coast = null


func _scroll_by(sc: ScrollContainer, d: float) -> void:
	if _vertical:
		sc.scroll_vertical = int(round(sc.scroll_vertical + d))
	else:
		sc.scroll_horizontal = int(round(sc.scroll_horizontal + d))


## The innermost visible ScrollContainer under p that has something to scroll in that direction.
func _scroller_at(p: Vector2, vertical: bool) -> ScrollContainer:
	var best: ScrollContainer = null
	var best_depth := -1
	for sc in get_tree().root.find_children("*", "ScrollContainer", true, false):
		var s := sc as ScrollContainer
		if not s.is_visible_in_tree() or not s.get_global_rect().has_point(p):
			continue
		var bar: ScrollBar = s.get_v_scroll_bar() if vertical else s.get_h_scroll_bar()
		var mode := s.vertical_scroll_mode if vertical else s.horizontal_scroll_mode
		if mode == ScrollContainer.SCROLL_MODE_DISABLED or bar.max_value - bar.page <= 1.0:
			continue
		var depth := s.get_path().get_name_count()
		if depth > best_depth:
			best = s
			best_depth = depth
	return best


## Slide the press off-screen so whatever the finger started on (a button, a row) won't fire.
func _cancel_press() -> void:
	var m := InputEventMouseMotion.new()
	m.position = Vector2(-10000, -10000)
	m.global_position = m.position
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	_push(m)


func _send_release() -> void:
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = false
	b.position = Vector2(-10000, -10000)
	b.global_position = b.position
	_push(b)


func _push(e: InputEvent) -> void:
	_injecting = true
	get_viewport().push_input(e, true)
	_injecting = false
