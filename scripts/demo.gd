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
var _typing: Array = []     # commands still to type into a network ticket's terminal
var _typed := ""
var _plan: Array = []       # Day 9: Toolbox > Accounts moves still to make, each [callable, pause]


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
	desk.spawn_scale = 5.0
	desk.clock_scale = 12.8  # 8am to 5pm in ~47s, leaving time for the shift report
	desk.first_kind = "lockout"  # Day 9: open on a lockout: check the caller and fix it in Toolbox > Accounts
	desk.start(11)  # Day 9: a lockout that checks out, fixed in Accounts
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
		_typing.clear()
		_plan.clear()
		_step_t = READ_TIME
	elif desk.current.has("term") and desk.current.get("term_live", true) and desk.current.get("demo_typed", 0) != desk.current.get("step_no", 1):
		desk.current.demo_typed = desk.current.get("step_no", 1)  # Day 4: investigate in the command prompt
		_typing = ["ipconfig", "ping 1.1.1.1", "nslookup google.com"]
		if desk.current.get("step_no", 1) > 1:  # Day 6: the verify step: prove the fix from the PC
			_typing = ["ipconfig /renew", "ping 1.1.1.1"] if desk.current.term.fault == "renew" else ["nslookup google.com", "ping 1.1.1.1"]
		_typed = ""
		_step_t = 0.3
	elif not _typing.is_empty():
		# Type the next command a character at a time, then run it and pause to read the output.
		var cmd: String = _typing[0]
		if _typed.length() < cmd.length():
			_typed = cmd.left(_typed.length() + 1)
			desk._term_input.text = _typed
			_step_t = 0.07
		else:
			desk.run_command(cmd)
			_typing.pop_front()
			_typed = ""
			_step_t = 1.6
	elif not _plan.is_empty():
		var move: Array = _plan.pop_front()
		(move[0] as Callable).call()
		_step_t = move[1]
	elif desk.current.has("acct") and not desk.current.get("demo_planned", false):
		desk.current.demo_planned = true
		_plan_accounts(desk.current)
		_step_t = 0.2
	elif desk.current.has("actions"):
		# Day 8: tick the actions the account needs one by one, then Apply.
		for i in desk.current.actions.size():
			if desk.current.actions[i].need == 1 and not desk._action_boxes[i].button_pressed:
				desk.answer(i)
				_step_t = 0.7
				return
		desk.apply_console()
		_step_t = RESULT_TIME + 1.0
	else:
		var pick: int = desk.current.answer
		if not _wrong_done and _t >= WRONG_AT:
			_wrong_done = true
			pick = (pick + 1) % desk.current.options.size()
		desk.answer(pick)
		_step_t = RESULT_TIME


## Day 9: open the Toolbox, find the caller in Accounts, then fix it there or refuse / hold.
func _plan_accounts(t: Dictionary) -> void:
	var acc: Node = desk._accounts
	var goal: Dictionary = t.acct.goal
	_plan = [
		[desk.toggle_toolbox, 0.1],
		[_scroll_to.bind(acc), 1.4],
		[acc.select.bind(goal.sam), 0.1],
		[_scroll_to.bind(acc._profile), 2.0],
	]
	if not goal.hold:
		if goal.unlock:
			_plan.append([acc.unlock, 0.8])
		if goal.reset:
			_plan.append([acc.reset_password, 0.8])
		if goal.must_change:
			_plan.append([acc.set_must_change.bind(true), 1.0])
		for g in goal.add:
			_plan.append([_scroll_to.bind(acc._groups), 0.8])
			_plan.append([acc.set_group.bind(g, true), 1.2])
	_plan.append([desk.answer.bind(1 if goal.hold else 0), RESULT_TIME + 1.0])


func _scroll_to(c: Control) -> void:
	var sc: ScrollContainer = desk._dscroll
	sc.scroll_vertical = int(c.get_global_rect().position.y - sc.get_global_rect().position.y + sc.scroll_vertical - 12.0)
