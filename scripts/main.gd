extends Control
## Entry point. Builds the UI in code so each daily change stays a small, readable diff.
## Screens: title (login + leaderboard) -> desk (a shift) -> summary.

const UI := preload("res://scripts/ui.gd")
const Api := preload("res://scripts/api.gd")
const Desk := preload("res://scripts/desk.gd")
const Title := preload("res://scripts/title.gd")

const CASH_SAVE_DELAY := 2.0  # save shortly after earning, batching quick tickets

var api: Node
var title: Control
var desk: Control
var news: PanelContainer
var sfx: Node
var summary: PanelContainer
var _summary_text: Label
var _news_corner: MarginContainer

# Career (persisted). coins = career cash; that's what the leaderboard ranks.
var career := {"coins": 0, "shifts": 0, "solved": 0, "best": 0}
var playtime := 0.0
var _logged_in := false
var _save_seq := 0  # bumps on every save; newest copy (server vs browser) wins on load
var _cash_save_timer := -1.0
var _unload_timer := 0.0
var _board_timer := 0.0
var _demo := false


func _ready() -> void:
	_demo = "--demo" in OS.get_cmdline_user_args()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UI.theme()

	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	api = Api.new()
	api.name = "Api"
	add_child(api)

	var pad := MarginContainer.new()
	pad.name = "Pad"
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 14)
	add_child(pad)

	title = Title.new()
	title.name = "Title"
	pad.add_child(title)
	title.bind(api)
	title.start_requested.connect(start_shift)
	title.guest_requested.connect(func() -> void:
		_logged_in = false
		start_shift())
	title.logout_requested.connect(func() -> void:
		api.logout()
		_logged_in = false
		title.show_logged_out())

	add_child(preload("res://scripts/touch_scroll.gd").new())  # drag-to-scroll anywhere on phones

	sfx = preload("res://scripts/sfx.gd").new()
	sfx.name = "Sfx"
	add_child(sfx)

	desk = Desk.new()
	desk.name = "Desk"
	desk.sfx = sfx
	desk.visible = false
	pad.add_child(desk)
	desk.shift_ended.connect(_on_shift_ended)
	desk.cash_earned.connect(_on_cash_earned)

	_build_summary()

	# What's new button (bottom-left) + panel
	_news_corner = MarginContainer.new()
	_news_corner.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_news_corner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_news_corner.add_theme_constant_override("margin_left", 16)
	_news_corner.add_theme_constant_override("margin_bottom", 12)
	add_child(_news_corner)
	news = preload("res://scripts/whats_new.gd").new()
	news.name = "WhatsNew"
	add_child(news)
	news.setup(_news_corner)

	api.logged_in.connect(_on_logged_in)
	api.leaderboard_received.connect(title.show_leaderboard)

	if not _demo:  # the demo sets its own fixed portrait scale
		get_window().size_changed.connect(_fit_ui_scale)
		_fit_ui_scale()

	if _demo:
		var d := preload("res://scripts/demo.gd").new()
		add_child(d)
		d.start(self)
		return
	api.request_leaderboard()
	api.try_resume()


## Phones get a phone-sized canvas; otherwise the 1280x720 desktop layout is shrunk to a
## third of the screen and too small to read or tap. Portrait: 480 wide. Landscape on a short
## screen (a phone on its side, under ~600 CSS px tall): 480 tall.
func _fit_ui_scale() -> void:
	var w := get_window()
	var portrait := w.size.y > w.size.x
	var css_h: float = w.size.y / maxf(DisplayServer.screen_get_scale(), 1.0)
	if portrait:
		w.content_scale_size = Vector2i(480, 854)
	elif css_h < 600.0:
		w.content_scale_size = Vector2i(roundi(480.0 * w.size.x / w.size.y), 480)
	else:
		w.content_scale_size = Vector2i(1280, 720)


func _process(delta: float) -> void:
	if desk.running:
		playtime += delta
	if title.visible:
		_board_timer += delta
		if _board_timer >= 15.0:
			_board_timer = 0.0
			api.request_leaderboard()
	if not _logged_in:
		return
	if _cash_save_timer >= 0.0:
		_cash_save_timer -= delta
		if _cash_save_timer < 0.0:
			save_game()
	# Keep the latest state ready for the browser to send if the tab closes or reloads.
	_unload_timer += delta
	if _unload_timer >= 1.0:
		_unload_timer = 0.0
		var snap := _save_payload()
		api.cache_local(snap)
		api.set_unload_save(snap)


func start_shift() -> void:
	title.visible = false
	summary.visible = false
	_news_corner.visible = false  # it sat over the ticket on phones; V still opens What's new
	desk.start()
	track("shift_start", {"mode": "member" if _logged_in else "guest"})


func _on_cash_earned(amount: int, resolved: bool) -> void:
	career.coins += amount
	career.solved += int(resolved)  # a multi-step ticket pays per step but counts once
	if _logged_in:
		_cash_save_timer = CASH_SAVE_DELAY


func _on_shift_ended(stats: Dictionary) -> void:
	career.shifts += 1
	# Wrong answers also count as tickets worked (correct ones were counted as they paid out).
	career.solved += int(stats.solved) - int(stats.correct)
	career.best = maxi(int(career.best), int(stats.cash))
	if _logged_in:
		save_game()
	var acc := 0 if int(stats.solved) == 0 else int(round(100.0 * stats.correct / stats.solved))
	var stars := 1 + int(acc >= 60) + int(acc >= 80) + int(stats.breaches <= 2) + int(stats.cash >= 3000)
	_summary_text.text = "%s\n\nEarned: $%s\nTickets: %d worked, %d right (%d%%)\nSLA breaches: %d\nReputation: %d/100\n\n%s\n\nCareer: $%s%s" % [
		stats.reason, UI.money(stats.cash), stats.solved, stats.correct, acc, stats.breaches, stats.rep,
		"★".repeat(stars) + "☆".repeat(5 - stars), UI.money(career.coins),
		"" if _logged_in else "\n(Guest: log in to save your career)"]
	summary.visible = true
	_news_corner.visible = not _demo
	track("shift_end", {"cash": stats.cash, "accuracy": acc})


func _on_logged_in(_username: String, save: Dictionary) -> void:
	_logged_in = true
	# The server may answer from a lagging replica; use the browser's copy if it's newer.
	var local: Dictionary = api.load_local()
	var newer_locally := int(local.get("seq", -1)) > int(save.get("seq", 0))
	if newer_locally:
		save = local
	_save_seq = int(save.get("seq", 0))
	for k in career.keys():
		career[k] = int(save.get(k, 0))
	playtime = float(save.get("playtime", 0))
	title.show_logged_in(api.username, career)
	api.request_leaderboard()
	if newer_locally:
		save_game()  # push the newer copy back up


func save_game() -> void:
	_save_seq += 1
	var data := _save_payload()
	api.cache_local(data)
	api.save(data)


func _save_payload() -> Dictionary:
	var d := career.duplicate()
	d["playtime"] = int(playtime)
	d["seq"] = _save_seq
	return d


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _logged_in:
		save_game()


## Analytics custom event to Umami and GA4 (no-op outside the browser or if a script is blocked).
func track(event: String, data: Dictionary = {}) -> void:
	if OS.has_feature("web"):
		var e := JSON.stringify(event)
		var d := JSON.stringify(data)
		JavaScriptBridge.eval("window.umami && umami.track(%s, %s); window.gtag && gtag('event', %s, %s)" % [e, d, e, d], true)


func _build_summary() -> void:
	summary = PanelContainer.new()
	summary.visible = false
	summary.set_anchors_preset(Control.PRESET_CENTER)
	summary.grow_horizontal = Control.GROW_DIRECTION_BOTH
	summary.grow_vertical = Control.GROW_DIRECTION_BOTH
	summary.custom_minimum_size = Vector2(420, 0)
	summary.add_theme_stylebox_override("panel", UI.box(UI.PANEL.lightened(0.05), 12, 26, UI.ACCENT))
	add_child(summary)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	summary.add_child(v)
	UI.label(v, "Shift report", 26, UI.ACCENT)
	_summary_text = UI.wrap(UI.label(v, "", 17, UI.TEXT))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var again := Button.new()
	again.text = "Next shift"
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	again.pressed.connect(start_shift)
	row.add_child(again)
	var menu := Button.new()
	menu.text = "Menu"
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.pressed.connect(func() -> void:
		summary.visible = false
		desk.visible = false
		title.visible = true
		if _logged_in:
			title.show_logged_in(api.username, career)
		api.request_leaderboard())
	row.add_child(menu)
