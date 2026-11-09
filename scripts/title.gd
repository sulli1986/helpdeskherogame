extends Control
## Title screen: log in / register / guest, career stats, start shift, leaderboard.

signal start_requested
signal guest_requested
signal logout_requested

const UI := preload("res://scripts/ui.gd")

var _api: Node
var _login_box: VBoxContainer
var _career_box: VBoxContainer
var _welcome: Label
var _career: Label
var _user: LineEdit
var _pass: LineEdit
var _status: Label
var _board: Label
var _layout: BoxContainer
var _me := ""


func bind(api: Node) -> void:
	_api = api
	api.auth_failed.connect(func(msg: String) -> void: _status.text = msg)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_layout = BoxContainer.new()
	_layout.add_theme_constant_override("separation", 16)
	center.add_child(_layout)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(400, 0)
	card.add_theme_stylebox_override("panel", UI.box(UI.PANEL, 12, 26))
	_layout.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	var t := UI.label(box, "HELPDESK HERO", 38, UI.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var s := UI.wrap(UI.label(box, "Run the helpdesk at an MSP. Beat the SLA, keep the clients, make the cash. A new change every day.", 14, UI.MUTED))
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.custom_minimum_size = Vector2(340, 0)

	# Logged out
	_login_box = VBoxContainer.new()
	_login_box.add_theme_constant_override("separation", 8)
	box.add_child(_login_box)
	_user = LineEdit.new()
	_user.placeholder_text = "Username"
	_user.max_length = 20
	_login_box.add_child(_user)
	_pass = LineEdit.new()
	_pass.placeholder_text = "Password (8+ chars)"
	_pass.secret = true
	_pass.text_submitted.connect(func(_t: String) -> void: _do_auth(false))
	_login_box.add_child(_pass)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_login_box.add_child(row)
	_button(row, "Log in").pressed.connect(_do_auth.bind(false))
	_button(row, "Register").pressed.connect(_do_auth.bind(true))
	var guest := _button(_login_box, "Play as guest (no saving)")
	guest.flat = true
	guest.pressed.connect(func() -> void: guest_requested.emit())

	# Logged in
	_career_box = VBoxContainer.new()
	_career_box.add_theme_constant_override("separation", 8)
	_career_box.visible = false
	box.add_child(_career_box)
	_welcome = UI.label(_career_box, "", 20, UI.TEXT)
	_career = UI.label(_career_box, "", 14, UI.MUTED)
	var go := _button(_career_box, "Start shift  (Enter)")
	go.custom_minimum_size = Vector2(0, 46)
	go.add_theme_font_size_override("font_size", 20)
	go.pressed.connect(func() -> void: start_requested.emit())
	var out := _button(_career_box, "Log out")
	out.flat = true
	out.pressed.connect(func() -> void: logout_requested.emit())

	_status = UI.wrap(UI.label(box, "", 14, Color(1, 0.7, 0.6)))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var how := UI.wrap(UI.label(box, "How to play: open a ticket, read the evidence, pick the fix (keys 1-4). Right answers pay more the faster you are. Wrong calls and SLA breaches cost reputation.", 13, UI.MUTED))
	how.custom_minimum_size = Vector2(340, 0)

	# Leaderboard
	var lb := PanelContainer.new()
	lb.custom_minimum_size = Vector2(280, 0)
	lb.add_theme_stylebox_override("panel", UI.box(UI.PANEL, 12, 22))
	_layout.add_child(lb)
	var lbv := VBoxContainer.new()
	lb.add_child(lbv)
	UI.label(lbv, "Top techs (career $)", 18, UI.TEXT)
	_board = UI.label(lbv, "Loading...", 15, UI.MUTED)

	var flip := func() -> void:
		var vp := get_viewport_rect().size
		_layout.vertical = vp.y > vp.x
	resized.connect(flip)
	get_viewport().size_changed.connect(flip)
	flip.call()


func show_logged_out() -> void:
	_me = ""
	_login_box.visible = true
	_career_box.visible = false
	_status.text = ""


func show_logged_in(username: String, career: Dictionary) -> void:
	_me = username
	_login_box.visible = false
	_career_box.visible = true
	_status.text = ""
	_welcome.text = "Welcome back, %s" % username
	_career.text = "Career: $%s  ·  %d shifts  ·  %d tickets  ·  best shift $%s" % [
		UI.money(int(career.get("coins", 0))), int(career.get("shifts", 0)),
		int(career.get("solved", 0)), UI.money(int(career.get("best", 0)))]


func show_leaderboard(rows: Array) -> void:
	if rows.is_empty():
		_board.text = "No one yet. Be first!"
		return
	var lines := PackedStringArray()
	for i in rows.size():
		var r: Dictionary = rows[i]
		var name := str(r.get("username", "?"))
		lines.append("%d. %s  $%s%s" % [i + 1, name, UI.money(int(r.get("coins", 0))), "  (you)" if name.to_lower() == _me.to_lower() and _me != "" else ""])
	_board.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if visible and _career_box.visible and event is InputEventKey and event.pressed and not event.echo \
			and (event.physical_keycode == KEY_ENTER or event.physical_keycode == KEY_KP_ENTER):
		start_requested.emit()
		get_viewport().set_input_as_handled()


func _do_auth(register: bool) -> void:
	_status.text = "Creating account..." if register else "Logging in..."
	if register:
		_api.register(_user.text.strip_edges(), _pass.text)
	else:
		_api.login(_user.text.strip_edges(), _pass.text)


func _button(parent: Node, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	parent.add_child(b)
	return b
