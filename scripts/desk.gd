extends Control
## One helpdesk shift. Tickets queue on the left (top in portrait), the open ticket on the right.
## Answer with the option buttons or keys 1-4, Enter for the next ticket, Tab / arrows to switch.

signal shift_ended(stats: Dictionary)
signal cash_earned(amount: int, resolved: bool)  # resolved: the ticket is closed (not just one step)

const Tickets := preload("res://scripts/tickets.gd")
const UI := preload("res://scripts/ui.gd")
const Terminal := preload("res://scripts/terminal.gd")

const SHIFT_SECONDS := 420.0           # 8:00am to 5:00pm in seven real minutes
const START_HOUR := 8.0
const END_HOUR := 17.0
const SLA := {1: 120.0, 2: 180.0, 3: 240.0, 4: 300.0}  # real seconds
const PAY := {1: 300, 2: 200, 3: 120, 4: 80}
const REP_WRONG := 8.0
const REP_BREACH := 12.0
const REP_RIGHT := 2.0
const STEP_PAY := 0.75                 # multi-step tickets: each step pays this share of the ticket's pay
const MAX_QUEUE := 8
## Commands offered as tap-to-run buttons under the prompt on touchscreens.
const TERM_CHIPS := ["ipconfig", "ping 192.168.1.1", "ping 1.1.1.1", "nslookup google.com", "tracert 1.1.1.1",
	"ipconfig /renew", "ping google.com", "nslookup google.com 8.8.8.8"]

var gen: RefCounted
var sfx: Node              # scripts/sfx.gd, set by main before _ready
var running := false
var elapsed := 0.0
var cash := 0
var rep := 100.0
var solved := 0
var correct := 0
var breaches := 0
var spawn_scale := 1.0     # demo speeds up arrivals
var clock_scale := 1.0     # demo runs the shift clock faster
var first_kind := ""       # demo forces the first ticket's type
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
var _info_scroll: ScrollContainer  # grows to fit, except terminal tickets: fixed height, follows output
var _term_row: HBoxContainer   # command prompt under the evidence box (network tickets)
var _term_prompt: Label
var _term_input: LineEdit
var _term_chips: HBoxContainer   # tap-to-run commands (one swipeable row), so phones don't need the keyboard
var _chip_scroll: ScrollContainer
var _press_at := Vector2.ZERO  # where a press on the feedback panel started (tap vs scroll)
var _touch := false            # touchscreen: show the chips and "tap" wording
var _term_hist: Array = []
var _term_hist_i := 0
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
var _sound_btn: Button
var _brand: Label
var _top_row: HBoxContainer


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
		_next_spawn = lerpf(18.0, 10.0, progress) / spawn_scale
		if queue.size() < MAX_QUEUE:
			_spawn()

	for t in queue.duplicate():
		t.age += delta
		var left: float = SLA[t.priority] - t.age
		var bar: ProgressBar = t.row.get_meta("bar")
		bar.value = clampf(left / SLA[t.priority] * 100.0, 0.0, 100.0)
		bar.modulate = Color(1, 0.3, 0.3) if left < 10.0 else Color.WHITE
		if left < 10.0 and left > 0.0 and not t.get("warned", false):
			t.warned = true
			_sfx("warn")
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
	var ok: bool = i == current.answer
	var more: bool = ok and not current.get("steps", []).is_empty()  # right, but there's another step
	if not more:
		solved += 1
	var pay := 0
	if ok:
		var left_frac: float = clampf(1.0 - current.age / SLA[current.priority], 0.0, 1.0)
		var share: float = STEP_PAY if current.has("steps") else 1.0
		pay = int(round(PAY[current.priority] * share * (1.0 + 0.5 * left_frac) / 10.0)) * 10
		cash += pay
		if not more:
			correct += 1
			rep = minf(100.0, rep + REP_RIGHT)
		cash_earned.emit(pay, not more)
		_show_toast("+$%d" % pay, UI.GOOD)
		_sfx("right")
	else:
		rep -= REP_WRONG
		_sfx("wrong")
		_show_toast("Escalated: -%d rep" % REP_WRONG, UI.BAD)
	_mark_options(i)
	_term_input.release_focus()  # so Enter goes to the next ticket
	_term_input.editable = false
	_term_input.focus_mode = Control.FOCUS_NONE
	for chip in _term_chips.get_children():
		chip.disabled = true
	_show_feedback(ok, pay, more)
	if more:
		_advance_step(current)
	else:
		_remove(current)


## Load a multi-step ticket's next step into it. It stays in the queue (SLA still running) and
## opens at the new step on Enter / tap, or whenever the player comes back to it.
func _advance_step(t: Dictionary) -> void:
	var st: Dictionary = t.steps.pop_front()
	t.step_no = t.get("step_no", 1) + 1
	t.step_name = st.name
	t.info += st.info_add
	for k in ["question", "options", "answer", "explain"]:
		t[k] = st[k]
	(t.row.get_meta("subject") as Label).text = "%s  (step %d: %s)" % [t.subject, t.step_no, st.name]


func next_ticket() -> void:
	if not running:
		return
	_show_ticket(current if current in queue and _answered else _most_urgent())


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
	var t: Dictionary = gen.make(first_kind)
	first_kind = ""
	t.id = _next_id
	_next_id += 1
	t.age = 0.0
	t.row = _make_row(t)
	queue.append(t)
	_queue_list.add_child(t.row)
	_queue_head.text = "Queue (%d)" % queue.size()
	_sfx("new")
	if current.is_empty() and not _answered:
		_show_ticket(t)


func _breach(t: Dictionary) -> void:
	breaches += 1
	rep -= REP_BREACH
	_show_toast("SLA breached: %s" % t.client, UI.BAD)
	_sfx("wrong")
	if t.id == current.get("id", -1) and not _answered:
		_answered = true
		_mark_options(-1)
		_term_input.release_focus()
		_term_input.editable = false
		_term_input.focus_mode = Control.FOCUS_NONE
		for chip in _term_chips.get_children():
			chip.disabled = true
		_feedback_label.text = "SLA breached. The client escalated to their account manager.\n\n%s\n\n%s" % [t.explain, _next_hint()]
		_feedback.add_theme_stylebox_override("panel", UI.box(UI.BAD.darkened(0.6), 8, 14))
		_feedback.visible = true
		_scroll_to_feedback()
	elif t.id == current.get("id", -1):  # breached between steps: the next step is gone
		_feedback_label.text = "SLA breached before the fix. The client escalated to their account manager.\n\n%s" % _next_hint()
		_feedback.add_theme_stylebox_override("panel", UI.box(UI.BAD.darkened(0.6), 8, 14))
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
	if t.has("step_name"):
		var total: int = t.get("step_no", 1) + t.steps.size()
		_meta.text += "  ·  Step %d of %d: %s" % [t.get("step_no", 1), total, t.step_name]
	_meta.add_theme_color_override("font_color", UI.PRIORITY[t.priority])
	_body.text = t.body
	_info_title.text = t.info_title
	_info.text = t.info
	_size_console()
	var live_term: bool = t.has("term") and t.get("step_no", 1) == 1  # later steps: the console is evidence only
	_term_row.visible = live_term
	_chip_scroll.visible = live_term and _touch
	_chip_scroll.scroll_horizontal = 0
	for chip in _term_chips.get_children():
		chip.disabled = false
	_term_input.text = ""
	_term_input.editable = true
	_term_input.focus_mode = Control.FOCUS_ALL
	if t.has("term"):
		_term_prompt.text = t.prompt
	else:
		_term_input.release_focus()
	_question.text = t.question
	if t.has("term") and t.get("step_no", 1) > 1:
		_console_to_end()  # the new step's evidence was added at the bottom
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


## Run a command in the open ticket's simulated command prompt and append the output.
func run_command(line: String) -> void:
	if current.is_empty() or not current.has("term") or not running or _answered or current.get("step_no", 1) > 1:
		return
	line = line.strip_edges()
	_term_input.text = ""
	if line != "":
		_term_hist.append(line)
	_term_hist_i = _term_hist.size()
	if line.to_lower() == "cls":
		current.info = ""
	else:
		var out := Terminal.run(line, current.term)
		current.info += "\n%s %s\n%s\n" % [current.prompt, line, out] if out != "" else "\n%s\n" % current.prompt
		var lines: PackedStringArray = current.info.split("\n")
		if lines.size() > 80:  # keep the box from growing forever
			current.info = "\n".join(lines.slice(lines.size() - 80))
	_info.text = current.info
	_sfx("type")
	_console_to_end()


func _console_to_end() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_info_scroll.scroll_vertical = int(_info_scroll.get_v_scroll_bar().max_value)


## Terminal tickets get a fixed-height console that follows the output; shorter in portrait so
## the answers stay on screen under it.
func _size_console() -> void:
	var term: bool = not current.is_empty() and current.has("term")
	var vp := get_viewport_rect().size
	_info_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if term else ScrollContainer.SCROLL_MODE_DISABLED
	_info_scroll.custom_minimum_size.y = clampf(vp.y * (0.2 if vp.y > vp.x else 0.3), 150.0, 320.0) if term else 0.0


func _on_term_key(e: InputEvent) -> void:
	# Up/Down recall earlier commands (and must not switch tickets while typing).
	if not (e is InputEventKey) or not e.pressed:
		return
	var k: int = e.physical_keycode
	if k == KEY_TAB:  # leave the prompt and switch ticket, as Tab does everywhere else
		_term_input.release_focus()
		_term_input.accept_event()
		select_offset(1)
	elif k == KEY_UP or k == KEY_DOWN:
		if not _term_hist.is_empty():
			_term_hist_i = clampi(_term_hist_i + (-1 if k == KEY_UP else 1), 0, _term_hist.size())
			_term_input.text = _term_hist[_term_hist_i] if _term_hist_i < _term_hist.size() else ""
			_term_input.caret_column = _term_input.text.length()
		_term_input.accept_event()
	elif k == KEY_ESCAPE:
		_term_input.release_focus()
		_term_input.accept_event()


func _mark_options(chosen: int) -> void:
	var btns := _opts.get_children()
	for i in btns.size():
		var b: Button = btns[i]
		b.disabled = true
		if i == current.answer:
			b.add_theme_stylebox_override("disabled", UI.box(UI.GOOD.darkened(0.55), 6, 8))
		elif i == chosen:
			b.add_theme_stylebox_override("disabled", UI.box(UI.BAD.darkened(0.55), 6, 8))


func _show_feedback(ok: bool, pay: int, more := false) -> void:
	var head := ("Resolved. +$%d" % pay) if ok else "Wrong call. Escalated to Tier 2."
	if more:
		head = "%s: right. +$%d" % [current.step_name, pay]
	var hint := _next_hint()
	if more:
		hint = "Tap here or press Enter for the next step" if _touch else "Enter: next step"
	_feedback_label.text = "%s\n\n%s\n\n%s" % [head, current.explain, hint]
	_feedback.add_theme_stylebox_override("panel", UI.box((UI.GOOD if ok else UI.BAD).darkened(0.6), 8, 14))
	_feedback.visible = true
	_scroll_to_feedback()


func _next_hint() -> String:
	return "Tap here or press Enter for the next ticket" if _touch else "Enter: next ticket"


func _scroll_to_feedback() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_dscroll.scroll_vertical = int(_dscroll.get_v_scroll_bar().max_value)


func _sfx(id: String) -> void:
	if sfx:
		sfx.play(id)


func _update_sound_btn(muted: bool) -> void:
	_sound_btn.text = "Sound: off" if muted else "Sound: on"
	_sound_btn.tooltip_text = "Toggle sound (M)"


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
	var subj := UI.label(v, t.subject, 14, UI.MUTED)
	subj.clip_text = true
	row.set_meta("subject", subj)
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
	_top_row = hb
	hb.add_theme_constant_override("separation", 18)
	bar.add_child(hb)
	_brand = UI.label(hb, "HELPDESK HERO", 18, UI.ACCENT)
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
	_sound_btn = Button.new()
	_sound_btn.focus_mode = Control.FOCUS_NONE
	_sound_btn.add_theme_font_size_override("font_size", 13)
	hb.add_child(_sound_btn)
	if sfx:
		_sound_btn.pressed.connect(sfx.toggle_mute)
		sfx.mute_changed.connect(_update_sound_btn)
		_update_sound_btn(sfx.muted)
	else:
		_sound_btn.visible = false

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
	_info_scroll = ScrollContainer.new()
	_info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	info_box.add_child(_info_scroll)
	_info = UI.wrap(UI.label(_info_scroll, "", 13, Color("b8f5c8")))
	_info.add_theme_font_override("font", UI.mono())
	_term_row = HBoxContainer.new()
	_term_row.add_theme_constant_override("separation", 6)
	_detail.add_child(_term_row)
	_term_prompt = UI.label(_term_row, "C:\\>", 13, Color("b8f5c8"))
	_term_prompt.add_theme_font_override("font", UI.mono())
	_term_input = LineEdit.new()
	_term_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_term_input.placeholder_text = "type a command, Enter to run (Esc to leave)"
	_term_input.add_theme_font_override("font", UI.mono())
	_term_input.add_theme_font_size_override("font_size", 13)
	_term_input.add_theme_color_override("font_color", Color("b8f5c8"))
	_term_input.context_menu_enabled = false
	_term_input.text_submitted.connect(run_command)
	_term_input.gui_input.connect(_on_term_key)
	_term_row.add_child(_term_input)
	_touch = DisplayServer.is_touchscreen_available()
	_chip_scroll = ScrollContainer.new()
	_chip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_chip_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER  # swipe; no bar
	_detail.add_child(_chip_scroll)
	_term_chips = HBoxContainer.new()
	_term_chips.add_theme_constant_override("separation", 8)
	_chip_scroll.add_child(_term_chips)
	for cmd in TERM_CHIPS:
		var chip := Button.new()
		chip.text = cmd
		chip.focus_mode = Control.FOCUS_NONE
		chip.add_theme_font_override("font", UI.mono())
		chip.add_theme_font_size_override("font_size", 13)
		chip.custom_minimum_size = Vector2(0, 46)
		chip.pressed.connect(run_command.bind(cmd))
		_term_chips.add_child(chip)
	if _touch:
		_term_input.placeholder_text = "tap a command below (swipe for more)"
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
		# Advance on a tap/click, not on a press that turns into a scroll (or a mouse wheel).
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_press_at = e.global_position
			elif e.global_position.distance_to(_press_at) < 12.0:
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
	_brand.visible = vp.x >= 640  # phones: make room in the top bar for clock, cash, rep and sound
	_top_row.add_theme_constant_override("separation", 18 if vp.x >= 640 else 10)
	_size_console()
	_toast.position.y = 58.0 if portrait else 6.0  # below the top bar in portrait, in its middle otherwise
	if portrait:
		_queue_panel.custom_minimum_size = Vector2(0, vp.y * 0.17)
		_queue_panel.size_flags_vertical = Control.SIZE_FILL
	else:
		_queue_panel.custom_minimum_size = Vector2(minf(380.0, size.x * 0.34), 0)
		_queue_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
