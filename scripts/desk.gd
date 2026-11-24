extends Control
## One helpdesk shift. Tickets queue on the left (top in portrait), the open ticket on the right.
## Answer with the option buttons or keys 1-4, Enter for the next ticket, Tab / arrows to switch.
## Toolbox: each tool is its own tab beside the Ticket tab (like a separate admin app). T switches
## between the ticket and the tool it needs (Accounts, Remote Control, Mail Console or Network Map). Tickets fixed in a tool are
## closed on the Ticket tab with "Done" / "Hold".
## Ask a Senior (H, or the button under the answers): each press reveals the next of the step's three
## hints (t.hints), and each one revealed takes HINT_COST off what that step pays.

signal shift_ended(stats: Dictionary)
signal cash_earned(amount: int, resolved: bool)  # resolved: the ticket is closed (not just one step)

const Tickets := preload("res://scripts/tickets.gd")
const UI := preload("res://scripts/ui.gd")
const Terminal := preload("res://scripts/terminal.gd")
const Accounts := preload("res://scripts/accounts.gd")
const Remote := preload("res://scripts/remote.gd")
const Mail := preload("res://scripts/mail.gd")
const NetMap := preload("res://scripts/netmap.gd")

const SHIFT_SECONDS := 600.0           # 8:00am to 5:00pm in ten real minutes
const START_HOUR := 8.0
const END_HOUR := 17.0
const SLA := {1: 180.0, 2: 270.0, 3: 360.0, 4: 480.0}  # real seconds, for a one-step ticket
const SLA_PER_STEP := 75.0             # extra time for each later step (diagnose, fix, verify all take work)
const SPAWN_GAP := [50.0, 36.0]        # seconds between arrivals, start to end of the shift
const MAX_UNREAD := 3                  # arrivals hold off while this many tickets wait unopened
const PAY := {1: 300, 2: 200, 3: 120, 4: 80}
const REP_WRONG := 8.0
const REP_BREACH := 12.0
const REP_RIGHT := 2.0
const STEP_PAY := 0.5                  # multi-step tickets: each step pays this share of the ticket's pay
const MAX_QUEUE := 8
const HINT_COST := 0.25                # Ask a Senior: each hint revealed takes this share off the step's pay
const TOOL_ABOUT := {
	"accounts": "Accounts: the client's users, groups, licences and sign-in settings. Nothing on this ticket needs a change here.",
	"remote": "Remote Control: connect to one of the client's PCs and work on it. Nothing on this ticket needs it.",
	"mail": "Mail Console: the client's message trace, quarantine and block list. Nothing on this ticket needs it.",
	"net": "Network Map: the client's ISP link, firewall, servers, switch and printers. Nothing on this ticket needs it.",
}
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
var hints_asked := 0       # Ask a Senior: hints revealed this shift
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
var _compact := false          # phone portrait: queue and ticket are separate screens
var _view_queue := false       # compact only: showing the queue screen rather than the ticket
var _back: Button              # compact only: "< Queue (n)" above the ticket
var _next_btn: Button          # under the result: next ticket / next step
var _tabs: HFlowContainer      # Toolbox tabs: Ticket, Accounts, Remote Control, Mail Console (wrap on phones)
var _tab_btns := {}            # tab name -> Button
var _tab := "ticket"           # the tab on show; each ticket remembers its own in t.tab
var _tool_scroll: ScrollContainer  # holds the tool tabs' content
var _accounts: Node            # scripts/accounts.gd, the Accounts tab
var _remote: Node              # scripts/remote.gd, the Remote Control tab
var _mail: Node                # scripts/mail.gd, the Mail Console tab
var _net: Node                 # scripts/netmap.gd, the Network Map tab
var _tool_empty: Label         # a tool tab on a ticket that doesn't need it
var _senior_btn: Button        # Ask a Senior, under the answers
var _senior_box: PanelContainer
var _senior_label: Label       # the hints revealed so far on this step
var _tool_hint: Label          # the latest hint, repeated at the top of the tool tabs


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
	hints_asked = 0
	_end_reason = ""
	_next_spawn = 20.0 / spawn_scale
	running = true
	visible = true
	_show_ticket({})
	_spawn()  # opens the first ticket straight away
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
		_next_spawn = lerpf(SPAWN_GAP[0], SPAWN_GAP[1], progress) * gen.rng.randf_range(0.7, 1.3) / spawn_scale
		var unread := queue.filter(func(q: Dictionary) -> bool: return not q.get("seen", false)).size()
		if queue.size() < MAX_QUEUE and unread < MAX_UNREAD:
			_spawn()
		else:  # held back: try again soon rather than after a whole gap
			_next_spawn = 5.0 / spawn_scale

	for t in queue.duplicate():
		t.age += delta
		var left: float = t.sla - t.age
		var bar: ProgressBar = t.row.get_meta("bar")
		bar.value = clampf(left / t.sla * 100.0, 0.0, 100.0)
		bar.modulate = Color(1, 0.3, 0.3) if left < 10.0 else Color.WHITE
		if left < 10.0 and left > 0.0 and not t.get("warned", false):
			t.warned = true
			_sfx("warn")
		var secs := maxi(0, ceili(left))
		@warning_ignore("integer_division")
		(t.row.get_meta("time") as Label).text = "%d:%02d" % [secs / 60, secs % 60]
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
	if _uses_tool(current):  # Toolbox tickets: "Done" or "Hold", judged on what was done in the tool
		show_tab("ticket")  # the result shows on the ticket
		var held: bool = i == opts.size() - 1
		var problems: Array
		if current.has("acct"):
			problems = Accounts.check(current.acct, held)
		elif current.has("rc"):
			problems = Remote.check(current.rc, held)
		elif current.has("net"):
			problems = NetMap.check(current.net, held)
		else:
			problems = Mail.check(current.mail, held)
		if not problems.is_empty():
			current.explain = "%s.\n%s" % [".\n".join(problems), current.explain]
		current.acct_ok = problems.is_empty()
		_resolve(problems.is_empty(), i)
		return
	_resolve(i == current.answer, i)


## T: flip between the Ticket tab and the tool this ticket needs (Accounts if none).
func toggle_toolbox() -> void:
	show_tab((_tool_for(current) if _tab == "ticket" else "ticket"))


## Ask a Senior: reveal the next hint for this step. Each one costs HINT_COST of the step's pay.
func ask_senior() -> void:
	if current.is_empty() or _answered or not running:
		return
	var hints: Array = current.get("hints", [])
	var used: int = current.get("hints_used", 0)
	if used >= hints.size():
		return
	current.hints_used = used + 1
	hints_asked += 1
	_show_toast("Senior's hint: -%d%% pay" % int(HINT_COST * 100), UI.ACCENT)
	_sfx("type")
	_update_senior()
	if _tab != "ticket":
		show_tab(_tab)  # refresh the hint line at the top of the tool


## The Ask a Senior button and the hints revealed so far on this step.
func _update_senior() -> void:
	var hints: Array = current.get("hints", [])
	var used: int = current.get("hints_used", 0)
	_senior_btn.visible = not current.is_empty() and not hints.is_empty()
	_senior_btn.disabled = _answered or used >= hints.size()
	if used >= hints.size():
		_senior_btn.text = "The senior has told you all they know"
	else:
		_senior_btn.text = "%s  (-%d%% of this step's pay)%s" % ["Ask a Senior" if used == 0 else "Ask the senior again",
			int(HINT_COST * 100), "" if _touch else "   H"]
	_senior_box.visible = used > 0
	var lines: Array = []
	for i in mini(used, hints.size()):
		lines.append("%d. %s" % [i + 1, hints[i]])
	_senior_label.text = "Senior tech:\n" + "\n".join(lines)


func _tool_for(t: Dictionary) -> String:
	if t.has("net"):
		return "net"
	return "remote" if t.has("rc") else ("mail" if t.has("mail") else "accounts")


## Is this ticket worked in a Toolbox tool and closed with Done / Hold?
func _uses_tool(t: Dictionary) -> bool:
	return t.has("acct") or t.has("rc") or t.has("mail") or t.has("net")


## Switch the work area to a tab: the ticket itself, or one of the Toolbox tools.
func show_tab(name: String) -> void:
	if current.is_empty() or not running:
		name = "ticket"
	_tab = name
	if not current.is_empty():
		current.tab = name
	_tabs.visible = not current.is_empty()
	_dscroll.visible = name == "ticket"
	_tool_scroll.visible = name != "ticket"
	for k in _tab_btns:
		var b: Button = _tab_btns[k]
		var on: bool = k == name
		b.add_theme_stylebox_override("normal", UI.box(UI.ROW_SEL if on else UI.ROW, 6, 8, UI.ACCENT if on else Color(0, 0, 0, 0)))
		b.add_theme_color_override("font_color", UI.TEXT if on else UI.MUTED)
	var tool: String = "" if current.is_empty() or not _uses_tool(current) else _tool_for(current)
	_tab_btns.ticket.text = "Ticket #%d" % current.id if not current.is_empty() else "Ticket"
	for k in [["accounts", "Accounts"], ["remote", "Remote Control"], ["mail", "Mail Console"], ["net", "Network Map"]]:
		_tab_btns[k[0]].text = ("%s  ●" % k[1] if tool == k[0] and name != k[0] else k[1]) + ("  (T)" if tool == k[0] and not _touch else "")
	_accounts.visible = name == "accounts" and tool == "accounts"
	_remote.visible = name == "remote" and tool == "remote"
	_mail.visible = name == "mail" and tool == "mail"
	_net.visible = name == "net" and tool == "net"
	_tool_empty.visible = name != "ticket" and tool != name
	_tool_empty.text = TOOL_ABOUT.get(name, "")
	_tool_hint.visible = name != "ticket" and tool == name and not _answered and current.get("hints_used", 0) > 0
	if _tool_hint.visible:
		_tool_hint.text = "Senior: %s" % current.hints[current.hints_used - 1]
	if _accounts.visible:
		_accounts.touch = _touch
		_accounts.open(current.acct, current.client, not _answered)
	elif _remote.visible:
		_remote.touch = _touch
		_remote.open(current.rc, current.client, not _answered)
	elif _mail.visible:
		_mail.touch = _touch
		_mail.open(current.mail, current.client, not _answered)
	elif _net.visible:
		_net.touch = _touch
		_net.open(current.net, current.client, not _answered)


func _resolve(ok: bool, i: int) -> void:
	_answered = true
	var more: bool = ok and not current.get("steps", []).is_empty()  # right, but there's another step
	if not more:
		solved += 1
	var pay := 0
	if ok:
		var left_frac: float = clampf(1.0 - current.age / current.sla, 0.0, 1.0)
		var share: float = STEP_PAY if current.has("steps") else 1.0
		share *= 1.0 - HINT_COST * current.get("hints_used", 0)
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
	_update_senior()
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
	t.term_live = st.get("live", false)  # this step reopens the command prompt
	if st.has("term_fault"):
		t.term.fault = st.term_fault
	for k in ["question", "explain"]:
		t[k] = st[k]
	if st.has("net"):  # this step is worked on the Network Map, then closed Fixed / Hold
		t.net = st.net
	else:
		t.erase("net")
		t.tab = "ticket"
	t.options = st.options
	t.answer = st.answer
	t.hints = st.get("hints", [])
	t.hints_used = 0  # a new step: the senior starts over, and so does the cost
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
	if k >= KEY_1 and k <= KEY_9:
		answer(k - KEY_1)
	elif k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE:
		if _answered or current.is_empty():
			next_ticket()
	elif k == KEY_T:
		toggle_toolbox()
	elif k == KEY_H:
		ask_senior()
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
	t.sla = SLA[t.priority] + SLA_PER_STEP * t.get("steps", []).size()
	t.row = _make_row(t)
	queue.append(t)
	_queue_list.add_child(t.row)
	_update_queue_count()
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
		show_tab("ticket")
		_mark_options(-1)
		_term_input.release_focus()
		_term_input.editable = false
		_term_input.focus_mode = Control.FOCUS_NONE
		for chip in _term_chips.get_children():
			chip.disabled = true
		_update_senior()
		_feedback_label.text = "SLA breached. The client escalated to their account manager.\n\n%s" % t.explain
		_next_btn.text = _next_hint()
		_feedback.add_theme_stylebox_override("panel", UI.box(UI.BAD.darkened(0.6), 8, 14))
		_feedback.visible = true
		_scroll_to_feedback()
	elif t.id == current.get("id", -1):  # breached between steps: the next step is gone
		_feedback_label.text = "SLA breached before you finished. The client escalated to their account manager."
		_next_btn.text = _next_hint()
		_feedback.add_theme_stylebox_override("panel", UI.box(UI.BAD.darkened(0.6), 8, 14))
	_remove(t)


func _remove(t: Dictionary) -> void:
	queue.erase(t)
	if is_instance_valid(t.row):
		t.row.queue_free()
	_update_queue_count()


func _most_urgent() -> Dictionary:
	var best: Dictionary = {}
	var best_left := INF
	for t in queue:
		var left: float = t.sla - t.age
		if left < best_left:
			best_left = left
			best = t
	return best


func _end(reason: String) -> void:
	running = false
	_end_reason = reason
	shift_ended.emit({
		"cash": cash, "solved": solved, "correct": correct, "breaches": breaches,
		"rep": int(maxf(rep, 0.0)), "reason": reason, "hints": hints_asked,
	})


# ------------------------------------------------------------------ view
func _update_queue_count() -> void:
	_queue_head.text = "Queue (%d)%s" % [queue.size(), "  ·  tap a ticket to open it" if _compact else ""]
	_back.text = "‹  Queue (%d)" % queue.size()


## Phones: show the queue or the ticket full-screen. Wider screens show both side by side.
func _apply_view() -> void:
	_queue_panel.visible = not _compact or _view_queue
	_detail_panel.visible = not _compact or not _view_queue
	_back.visible = _compact
	_update_queue_count()


func show_queue() -> void:
	_view_queue = true
	_apply_view()


func _show_ticket(t: Dictionary) -> void:
	current = t
	if not t.is_empty():
		t.seen = true  # opened at least once (unread tickets hold off new arrivals)
	_answered = false
	_feedback.visible = false
	if not t.is_empty() or queue.is_empty():
		_view_queue = false
		_apply_view()
	for row in _queue_list.get_children():
		row.add_theme_stylebox_override("panel", UI.box(UI.ROW, 6, 10))
	if t.is_empty():
		_detail.visible = false
		show_tab("ticket")
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
	var live_term: bool = t.has("term") and t.get("term_live", true)  # the fix step: the console is evidence only
	_term_row.visible = live_term
	_chip_scroll.visible = live_term and _touch
	_chip_scroll.scroll_horizontal = 0
	for chip in _term_chips.get_children():
		chip.disabled = false
	_term_input.text = ""
	# Touchscreens use the command buttons: the on-screen keyboard covered the ticket.
	_term_input.editable = not _touch
	_term_input.focus_mode = Control.FOCUS_NONE if _touch else Control.FOCUS_ALL
	if t.has("term"):
		_term_prompt.text = t.prompt
	else:
		_term_input.release_focus()
	_question.text = t.question
	_update_senior()
	if t.has("acct") and not is_same(_accounts.acct, t.acct):
		_accounts.selected = ""  # a different ticket: start from the user list
	_tool_scroll.scroll_vertical = 0
	show_tab(t.get("tab", "ticket"))
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
		b.custom_minimum_size = Vector2(0, 52 if _touch else 40)
		b.pressed.connect(answer.bind(i))
		_opts.add_child(b)


## Run a command in the open ticket's simulated command prompt and append the output.
func run_command(line: String) -> void:
	if current.is_empty() or not current.has("term") or not running or _answered or not current.get("term_live", true):
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
	if _uses_tool(current):  # Done / Hold: only right if the tool was left right too
		_accounts.set_enabled(false)
		_remote.set_enabled(false)
		_mail.set_enabled(false)
		_net.set_enabled(false)
		if chosen >= 0:
			for b in btns:
				b.disabled = true
			btns[chosen].add_theme_stylebox_override("disabled", UI.box((UI.GOOD if current.get("acct_ok", false) else UI.BAD).darkened(0.55), 6, 8))
			return
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
	var used: int = current.get("hints_used", 0)
	if ok and used > 0:
		head += "  (the senior's %d hint%s cost %d%% of it)" % [used, "" if used == 1 else "s", int(HINT_COST * 100) * used]
	_feedback_label.text = "%s\n\n%s" % [head, current.explain]
	_next_btn.text = _next_hint(more)
	_feedback.add_theme_stylebox_override("panel", UI.box((UI.GOOD if ok else UI.BAD).darkened(0.6), 8, 14))
	_feedback.visible = true
	_scroll_to_feedback()


func _next_hint(step := false) -> String:
	var what := "Next step" if step else "Next ticket"
	return "%s  ›" % what if _touch else "%s  ›   (Enter)" % what


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
		# Open on a tap/click (press and release in the same place), so a drag can scroll the list.
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				row.set_meta("press_at", e.global_position)
			elif running and e.global_position.distance_to(row.get_meta("press_at", Vector2.INF)) < 12.0:
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
	var dcol := VBoxContainer.new()
	dcol.add_theme_constant_override("separation", 8)
	_detail_panel.add_child(dcol)
	_back = Button.new()
	_back.focus_mode = Control.FOCUS_NONE
	_back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_back.custom_minimum_size = Vector2(0, 44)
	_back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_back.pressed.connect(show_queue)
	_back.visible = false
	dcol.add_child(_back)
	# Toolbox tabs: the ticket, and each tool in its own tab, like separate admin apps
	_tabs = HFlowContainer.new()
	_tabs.add_theme_constant_override("h_separation", 6)
	_tabs.add_theme_constant_override("v_separation", 6)
	dcol.add_child(_tabs)
	for k in ["ticket", "accounts", "remote", "mail", "net"]:
		var tb := Button.new()
		tb.focus_mode = Control.FOCUS_NONE
		tb.custom_minimum_size = Vector2(0, 44 if DisplayServer.is_touchscreen_available() else 34)
		tb.pressed.connect(show_tab.bind(k))
		_tabs.add_child(tb)
		_tab_btns[k] = tb
	_tool_scroll = ScrollContainer.new()
	_tool_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tool_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tool_scroll.visible = false
	var tcol := VBoxContainer.new()
	tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tool_scroll.add_child(tcol)
	_tool_hint = UI.wrap(UI.label(tcol, "", 14, UI.ACCENT))
	_tool_hint.visible = false
	_accounts = Accounts.new()
	_accounts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_accounts.changed.connect(func() -> void: _sfx("type"))
	tcol.add_child(_accounts)
	_remote = Remote.new()
	_remote.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_remote.changed.connect(func() -> void: _sfx("type"))
	tcol.add_child(_remote)
	_mail = Mail.new()
	_mail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mail.changed.connect(func() -> void: _sfx("type"))
	tcol.add_child(_mail)
	_net = NetMap.new()
	_net.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_net.changed.connect(func() -> void: _sfx("type"))
	tcol.add_child(_net)
	_tool_empty = UI.wrap(UI.label(tcol, "", 15, UI.MUTED))
	var dscroll := ScrollContainer.new()
	dscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dcol.add_child(dscroll)
	dcol.add_child(_tool_scroll)
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
	_subject = UI.wrap(UI.label(_detail, "", 22, UI.TEXT))  # long subjects ran off phone screens
	_meta = UI.wrap(UI.label(_detail, "", 14, UI.MUTED))
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
		_term_input.editable = false
		_term_input.focus_mode = Control.FOCUS_NONE
	_question = UI.label(_detail, "", 16, UI.ACCENT)
	_opts = VBoxContainer.new()
	_opts.add_theme_constant_override("separation", 6)
	_detail.add_child(_opts)
	_senior_btn = Button.new()
	_senior_btn.focus_mode = Control.FOCUS_NONE
	_senior_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_senior_btn.custom_minimum_size = Vector2(0, 44 if DisplayServer.is_touchscreen_available() else 34)
	_senior_btn.add_theme_font_size_override("font_size", 14)
	_senior_btn.pressed.connect(ask_senior)
	_detail.add_child(_senior_btn)
	_senior_box = PanelContainer.new()
	_senior_box.add_theme_stylebox_override("panel", UI.box(UI.ROW, 6, 10, UI.ACCENT))
	_senior_box.visible = false
	_detail.add_child(_senior_box)
	_senior_label = UI.wrap(UI.label(_senior_box, "", 14, UI.TEXT))
	_feedback = PanelContainer.new()
	_feedback.visible = false
	_detail.add_child(_feedback)
	var fcol := VBoxContainer.new()
	fcol.add_theme_constant_override("separation", 10)
	fcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feedback.add_child(fcol)
	_feedback_label = UI.wrap(UI.label(fcol, "", 15, UI.TEXT))
	_next_btn = Button.new()
	_next_btn.focus_mode = Control.FOCUS_NONE
	_next_btn.custom_minimum_size = Vector2(0, 50)
	_next_btn.pressed.connect(next_ticket)
	fcol.add_child(_next_btn)
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
	_rep_bar.custom_minimum_size.x = 110.0 if vp.x >= 640 else 64.0  # keep the Sound button on screen
	_size_console()
	_toast.position.y = 58.0 if portrait else 6.0  # below the top bar in portrait, in its middle otherwise
	_compact = portrait
	_apply_view()
	if portrait:  # full-screen queue (see _apply_view)
		_queue_panel.custom_minimum_size = Vector2.ZERO
		_queue_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		_queue_panel.custom_minimum_size = Vector2(minf(380.0, size.x * 0.34), 0)
		_queue_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
