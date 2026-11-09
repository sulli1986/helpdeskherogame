extends Control
## One helpdesk shift. Tickets queue on the left (top in portrait), the open ticket on the right.
## Answer with the option buttons or keys 1-4, Enter for the next ticket, Tab / arrows to switch.

signal shift_ended(stats: Dictionary)
signal cash_earned(amount: int)

const Tickets := preload("res://scripts/tickets.gd")
const UI := preload("res://scripts/ui.gd")

const SHIFT_SECONDS := 300.0           # 8:00am to 5:00pm in five real minutes
const START_HOUR := 8.0
const END_HOUR := 17.0
const SLA := {1: 40.0, 2: 60.0, 3: 90.0, 4: 120.0}
const PAY := {1: 300, 2: 200, 3: 120, 4: 80}
const REP_WRONG := 8.0
const REP_BREACH := 12.0
const REP_RIGHT := 2.0
const MAX_QUEUE := 8

var gen: RefCounted
var running := false
var elapsed := 0.0
var cash := 0
var rep := 100.0
var solved := 0
var correct := 0
var breaches := 0
var spawn_scale := 1.0     # demo speeds up arrivals
var clock_scale := 1.0     # demo runs the shift clock faster
var queue: Array = []      # open tickets (Dictionaries), each with "age" and "row"
var current: Dictionary = {}
var _answered := false
var _next_spawn := 0.0
var _next_id := 1001
var _end_reason := ""

# UI
var _layout: BoxContainer
var _queue_panel: PanelContainer
var _queue_list: VBoxContainer
var _queue_head: Label
var _detail_panel: PanelContainer
var _empty: Label
var _detail: VBoxContainer
var _subject: Label
var _meta: Label
var _body: Label
var _info_title: Label
var _info: Label
var _question: Label
var _opts: VBoxContainer
var _feedback: PanelContainer
var _feedback_label: Label
var _dscroll: ScrollContainer
var _clock: Label
var _cash_label: Label
var _rep_bar: ProgressBar
var _toast: Label
var _toast_t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	resized.connect(_relayout)
	get_viewport().size_changed.connect(_relayout)
	_relayout()


func start(seed_value := -1) -> void:
	var r := RandomNumberGenerator.new()
	if seed_value >= 0:
		r.seed = seed_value
	else:
		r.randomize()
	gen = Tickets.new(r)
	for t in queue:
		t.row.queue_free()
	queue.clear()
	current = {}
	elapsed = 0.0
	cash = 0
	rep = 100.0
	solved = 0
	correct = 0
	breaches = 0
	_end_reason = ""
	_next_spawn = 3.0
	running = true
	visible = true
	_spawn()
	_show_ticket({})
	_update_bar()


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t / 0.4, 0.0, 1.0)
	if not running:
		return
	elapsed += delta * clock_scale
	_next_spawn -= delta
	if _next_spawn <= 0.0:
		var progress := elapsed / SHIFT_SECONDS
		_next_spawn = lerpf(13.0, 6.0, progress) / spawn_scale
		if queue.size() < MAX_QUEUE:
			_spawn()

	for t in queue.duplicate():
		t.age += delta
		var left: float = SLA[t.priority] - t.age
		var bar: ProgressBar = t.row.get_meta("bar")
		bar.value = clampf(left / SLA[t.priority] * 100.0, 0.0, 100.0)
		bar.modulate = Color(1, 0.3, 0.3) if left < 10.0 else Color.WHITE
		(t.row.get_meta("time") as Label).text = "%ds" % maxi(0, ceili(left))
		if left <= 0.0:
			_breach(t)

	if elapsed >= SHIFT_SECONDS:
		_end("5:00pm. Shift over.")
	elif rep <= 0.0:
		_end("The client cancelled their contract.")
	_update_bar()


# ------------------------------------------------------------------ actions
func answer(i: int) -> void:
	if current.is_empty() or _answered or not running:
		return
	var opts: Array = current.options
	if i < 0 or i >= opts.size():
		return
	_answered = true
	solved += 1
	var ok: bool = i == current.answer
	var pay := 0
	if ok:
		correct += 1
		var left_frac: float = clampf(1.0 - current.age / SLA[current.priority], 0.0, 1.0)
		pay = int(round(PAY[current.priority] * (1.0 + 0.5 * left_frac) / 10.0)) * 10
		cash += pay
		rep = minf(100.0, rep + REP_RIGHT)
		cash_earned.emit(pay)
		_show_toast("+$%d" % pay, UI.GOOD)
	else:
		rep -= REP_WRONG
		_show_toast("Escalated: -%d rep" % REP_WRONG, UI.BAD)
	_mark_options(i)
	_show_feedback(ok, pay)
	_remove(current)


func next_ticket() -> void:
	if not running:
		return
	_show_ticket(_most_urgent())


func select_offset(step: int) -> void:
	if queue.is_empty():
		return
	var i := queue.find(current)
	i = 0 if i < 0 else wrapi(i + step, 0, queue.size())
	_show_ticket(queue[i])


func open_ticket(t: Dictionary) -> void:
	_show_ticket(t)


func _unhandled_input(event: InputEvent) -> void:
	if not running or not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = event.physical_keycode
	if k >= KEY_1 and k <= KEY_4:
		answer(k - KEY_1)
	elif k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE:
		if _answered or current.is_empty():
			next_ticket()
	elif k == KEY_TAB or k == KEY_DOWN:
		select_offset(1)
	elif k == KEY_UP:
		select_offset(-1)
	else:
		return
	get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ queue
func _spawn() -> void:
	var t: Dictionary = gen.make()
	t.id = _next_id
	_next_id += 1
	t.age = 0.0
	t.row = _make_row(t)
	queue.append(t)
	_queue_list.add_child(t.row)
	_queue_head.text = "Queue (%d)" % queue.size()
	if current.is_empty() and not _answered:
		_show_ticket(t)


func _breach(t: Dictionary) -> void:
	breaches += 1
	rep -= REP_BREACH
	_show_toast("SLA breached: %s" % t.client, UI.BAD)
	if t.id == current.get("id", -1) and not _answered:
		_answered = true
		_mark_options(-1)
		_feedback_label.text = "SLA breached. The client escalated to their account manager.\n\n%s\n\nEnter: next ticket" % t.explain
		_feedback.add_theme_stylebox_override("panel", UI.box(UI.BAD.darkened(0.6), 8, 14))
		_feedback.visible = true
		_scroll_to_feedback()
	_remove(t)


func _remove(t: Dictionary) -> void:
	queue.erase(t)
	if is_instance_valid(t.row):
		t.row.queue_free()
	_queue_head.text = "Queue (%d)" % queue.size()


func _most_urgent() -> Dictionary:
	var best: Dictionary = {}
	var best_left := INF
	for t in queue:
		var left: float = SLA[t.priority] - t.age
		if left < best_left:
			best_left = left
			best = t
	return best


func _end(reason: String) -> void:
	running = false
	_end_reason = reason
	shift_ended.emit({
		"cash": cash, "solved": solved, "correct": correct, "breaches": breaches,
		"rep": int(maxf(rep, 0.0)), "reason": reason,
	})


# ------------------------------------------------------------------ view
func _show_ticket(t: Dictionary) -> void:
	current = t
	_answered = false
	_feedback.visible = false
	for row in _queue_list.get_children():
		row.add_theme_stylebox_override("panel", UI.box(UI.ROW, 6, 10))
	if t.is_empty():
		_detail.visible = false
		_empty.visible = true
		_empty.text = "Queue clear. Grab a coffee." if running else ""
		return
	_detail.visible = true
	_empty.visible = false
	_dscroll.scroll_vertical = 0
	t.row.add_theme_stylebox_override("panel", UI.box(UI.ROW_SEL, 6, 10, UI.ACCENT))
	_subject.text = "#%d  %s" % [t.id, t.subject]
	_meta.text = "P%d  ·  %s  ·  %s" % [t.priority, t.client, t.user]
	_meta.add_theme_color_override("font_color", UI.PRIORITY[t.priority])
	_body.text = t.body
	_info_title.text = t.info_title
	_info.text = t.info
	_question.text = t.question
	for c in _opts.get_children():
		c.queue_free()
	for i in t.options.size():
		var b := Button.new()
		b.text = "%d   %s" % [i + 1, t.options[i]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 40)
		b.pressed.connect(answer.bind(i))
		_opts.add_child(b)


func _mark_options(chosen: int) -> void:
	var btns := _opts.get_children()
	for i in btns.size():
		var b: Button = btns[i]
		b.disabled = true
		if i == current.answer:
			b.add_theme_stylebox_override("disabled", UI.box(UI.GOOD.darkened(0.55), 6, 8))
		elif i == chosen:
			b.add_theme_stylebox_override("disabled", UI.box(UI.BAD.darkened(0.55), 6, 8))


func _show_feedback(ok: bool, pay: int) -> void:
	var head := ("Resolved. +$%d" % pay) if ok else "Wrong call. Escalated to Tier 2."
	_feedback_label.text = "%s\n\n%s\n\nEnter: next ticket" % [head, current.explain]
	_feedback.add_theme_stylebox_override("panel", UI.box((UI.GOOD if ok else UI.BAD).darkened(0.6), 8, 14))
	_feedback.visible = true
	_scroll_to_feedback()


func _scroll_to_feedback() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_dscroll.scroll_vertical = int(_dscroll.get_v_scroll_bar().max_value)


func _show_toast(text: String, colour: Color) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", colour)
	_toast_t = 1.6


func _update_bar() -> void:
	var hours := START_HOUR + (END_HOUR - START_HOUR) * clampf(elapsed / SHIFT_SECONDS, 0.0, 1.0)
	var h := int(hours)
	var m := int((hours - h) * 60.0)
	_clock.text = "%d:%02d%s" % [(h - 1) % 12 + 1, m, "am" if h < 12 else "pm"]
	_cash_label.text = "$%s" % UI.money(cash)
	_rep_bar.value = rep
	_rep_bar.modulate = UI.GOOD if rep > 60 else (Color(1, 0.75, 0.3) if rep > 30 else UI.BAD)


func _make_row(t: Dictionary) -> PanelContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UI.box(UI.ROW, 6, 10))
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and running:
			open_ticket(t))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	var p := UI.label(top, "P%d" % t.priority, 15, UI.PRIORITY[t.priority])
	p.custom_minimum_size = Vector2(30, 0)
	var client := UI.label(top, t.client, 15, UI.TEXT)
	client.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	client.clip_text = true
	var time := UI.label(top, "", 15, UI.MUTED)
	UI.label(v, t.subject, 14, UI.MUTED).clip_text = true
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 5)
	bar.value = 100
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", UI.box(Color(1, 1, 1, 0.08), 2, 0))
	bar.add_theme_stylebox_override("fill", UI.box(UI.PRIORITY[t.priority], 2, 0))
	v.add_child(bar)
	row.set_meta("bar", bar)
	row.set_meta("time", time)
	return row


func _build() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	# Top bar: clock, shift cash, reputation
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UI.box(UI.PANEL, 8, 12))
	root.add_child(bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	bar.add_child(hb)
	UI.label(hb, "HELPDESK HERO", 18, UI.ACCENT)
	_clock = UI.label(hb, "8:00am", 18, UI.TEXT)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer)
	UI.label(hb, "Shift", 14, UI.MUTED)
	_cash_label = UI.label(hb, "$0", 18, UI.GOOD)
	UI.label(hb, "Rep", 14, UI.MUTED)
	_rep_bar = ProgressBar.new()
	_rep_bar.show_percentage = false
	_rep_bar.custom_minimum_size = Vector2(110, 12)
	_rep_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rep_bar.add_theme_stylebox_override("background", UI.box(Color(1, 1, 1, 0.08), 4, 0))
	_rep_bar.add_theme_stylebox_override("fill", UI.box(Color.WHITE, 4, 0))
	hb.add_child(_rep_bar)

	_layout = BoxContainer.new()
	_layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_layout.add_theme_constant_override("separation", 10)
	root.add_child(_layout)

	# Queue
	_queue_panel = PanelContainer.new()
	_queue_panel.add_theme_stylebox_override("panel", UI.box(UI.PANEL, 8, 10))
	_layout.add_child(_queue_panel)
	var qv := VBoxContainer.new()
	qv.add_theme_constant_override("separation", 8)
	_queue_panel.add_child(qv)
	_queue_head = UI.label(qv, "Queue", 16, UI.MUTED)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	qv.add_child(scroll)
	_queue_list = VBoxContainer.new()
	_queue_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_queue_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_queue_list)

	# Ticket detail
	_detail_panel = PanelContainer.new()
	_detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_panel.add_theme_stylebox_override("panel", UI.box(UI.PANEL, 8, 16))
	_layout.add_child(_detail_panel)
	var dscroll := ScrollContainer.new()
	dscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_panel.add_child(dscroll)
	_dscroll = dscroll
	var dwrap := VBoxContainer.new()
	dwrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dwrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dscroll.add_child(dwrap)
	_empty = UI.label(dwrap, "", 20, UI.MUTED)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 8)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dwrap.add_child(_detail)
	_subject = UI.label(_detail, "", 22, UI.TEXT)
	_meta = UI.label(_detail, "", 14, UI.MUTED)
	_body = UI.wrap(UI.label(_detail, "", 16, UI.TEXT))
	_info_title = UI.label(_detail, "", 13, UI.MUTED)
	var info_box := PanelContainer.new()
	info_box.add_theme_stylebox_override("panel", UI.box(UI.CONSOLE, 6, 10))
	_detail.add_child(info_box)
	_info = UI.wrap(UI.label(info_box, "", 13, Color("b8f5c8")))
	_info.add_theme_font_override("font", UI.mono())
	_question = UI.label(_detail, "", 16, UI.ACCENT)
	_opts = VBoxContainer.new()
	_opts.add_theme_constant_override("separation", 6)
	_detail.add_child(_opts)
	_feedback = PanelContainer.new()
	_feedback.visible = false
	_detail.add_child(_feedback)
	_feedback_label = UI.wrap(UI.label(_feedback, "", 15, UI.TEXT))
	_feedback.mouse_filter = Control.MOUSE_FILTER_STOP
	_feedback.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			next_ticket())

	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 26)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.position = Vector2(-200, 6)  # sits in the top bar's empty middle
	_toast.size = Vector2(400, 40)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	add_child(_toast)


func _relayout() -> void:
	if not _layout:
		return
	var vp := get_viewport_rect().size
	var portrait := vp.y > vp.x  # window shape, not this control's (padding can skew it)
	_layout.vertical = portrait
	_toast.position.y = 58.0 if portrait else 6.0  # below the top bar in portrait, in its middle otherwise
	if portrait:
		_queue_panel.custom_minimum_size = Vector2(0, vp.y * 0.17)
		_queue_panel.size_flags_vertical = Control.SIZE_FILL
	else:
		_queue_panel.custom_minimum_size = Vector2(minf(380.0, size.x * 0.34), 0)
		_queue_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
