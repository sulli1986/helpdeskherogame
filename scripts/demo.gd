extends Node
## Scripted autopilot for the daily promo clip (~59s, fits a YouTube Short). Launch with:
##   godot --write-movie out.avi --fixed-fps 30 -- --demo
## Renders portrait (720x1280). Daily changes can add a beat to TIMELINE to show off the new
## feature; keep END_AT under 59s and retime an existing beat rather than extending.

const END_AT := 58.8
const READ_TIME := 2.4      # seconds "reading" a ticket before answering
const RESULT_TIME := 1.8    # seconds showing the explanation
const WRONG_AT := 24.0      # make one deliberate wrong call around here (shows the penalty)

var main: Node
var desk: Node
var _t := 0.0
var _i := 0
var _timeline: Array = []
var _auto := false
var _step_t := 0.0
var _wrong_done := false


func start(m: Node) -> void:
	main = m
	desk = m.desk
	# Portrait render: keep the UI at 1:1, and keep it clear of the clip's text overlays
	# (title at the top, footer lower down; see tools/clip_filter.py).
	# `-- --demo --landscape` previews the desktop layout instead (not used for the clip).
	if not "--landscape" in OS.get_cmdline_user_args():
		get_window().content_scale_size = Vector2i(720, 1280)
		var pad: MarginContainer = m.get_node("Pad")
		pad.add_theme_constant_override("margin_top", 230)
		pad.add_theme_constant_override("margin_bottom", 170)
	main._news_corner.visible = false
	main.title.show_leaderboard([
		{"username": "TierOneTom", "coins": 48210}, {"username": "PatchTuesdayQueen", "coins": 39870},
		{"username": "DNSdetective", "coins": 21540},
	])

	_timeline = [
		# 0-4.5s: what's new today
		[0.2, func() -> void: main.news.toggle()],
		[4.5, func() -> void: main.news.toggle()],
		# 4.6s on: a sped-up shift, answered by the autopilot
		[4.6, _start_shift],
		[END_AT, func() -> void: get_tree().quit()],
	]


func _start_shift() -> void:
	main.title.visible = false
	main.summary.visible = false
	desk.spawn_scale = 2.4
	desk.clock_scale = 9.0   # 8am to 5pm in ~47s, leaving time for the shift report
	desk.first_kind = "mfa"  # Day 3: open on the new MFA fatigue ticket
	desk.start(7)
	_auto = true
	_step_t = READ_TIME


func _process(delta: float) -> void:
	_t += delta
	while _i < _timeline.size() and _t >= _timeline[_i][0]:
		(_timeline[_i][1] as Callable).call()
		_i += 1
	if not _auto:
		return
	if not desk.running:
		_auto = false
		return
	_step_t -= delta
	if _step_t > 0.0:
		return
	if desk.current.is_empty() or desk._answered:
		desk.next_ticket()
		_step_t = READ_TIME
	else:
		var pick: int = desk.current.answer
		if not _wrong_done and _t >= WRONG_AT:
			_wrong_done = true
			pick = (pick + 1) % desk.current.options.size()
		desk.answer(pick)
		_step_t = RESULT_TIME
