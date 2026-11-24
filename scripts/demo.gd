extends Node
## Scripted autopilot for the daily promo clip (~27s Short). Launch with:
##   godot --write-movie out.avi --fixed-fps 30 -- --demo
## Renders portrait (720x1280). The clip is about TODAY's feature: the shift starts at once with
## first_kind set to the new/changed ticket, and the autopilot plays it at a watchable pace while
## the voiceover (tools/clip_script.json) explains it. Keep END_AT about 27s.

const END_AT := 27.0
const READ_TIME := 2.4      # seconds "reading" a ticket before answering
const RESULT_TIME := 1.8    # seconds showing the explanation
const WRONG_AT := 17.0      # one deliberate wrong call after the feature (shows the penalty)
const SEED := 11            # Day 17: a verified director locked out (P1): the senior's hints walk it through

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
var _senior := true         # Day 17: ask the senior for every hint on the first ticket before working it


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
		# From the first frame: a shift, opening on today's feature (the hook card sits over it)
		[0.0, _start_shift],
		[END_AT, func() -> void: get_tree().quit()],
	]


func _start_shift() -> void:
	main.title.visible = false
	main.summary.visible = false
	desk.spawn_scale = 4.0
	desk.clock_scale = 8.0   # the clock visibly moves, but the shift doesn't end in the clip
	desk.first_kind = "lockout"  # Day 17: Ask a Senior, shown on a lockout worked in Accounts
	desk.start(SEED)
	_auto = true
	_step_t = 2.8  # the hook line plays over the first ticket


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
		_typing = ["ping 1.1.1.1", "nslookup google.com"]
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
		if _senior:  # Day 17: three hints first, each shown on the ticket
			_senior = false
			var asks: Array = []
			for i in desk.current.get("hints", []).size():
				asks.append([_ask_senior, 2.7])
			_plan = asks + _plan
		_step_t = 0.2
	elif desk.current.has("rc") and not desk.current.get("demo_planned", false):
		desk.current.demo_planned = true
		_plan_remote(desk.current)
		_step_t = 0.2
	elif desk.current.has("mail") and not desk.current.get("demo_planned", false):
		desk.current.demo_planned = true
		_plan_mail(desk.current)
		_step_t = 0.2
	elif desk.current.has("net") and not desk.current.get("demo_planned", false):
		desk.current.demo_planned = true
		if desk.current.net.get("mode", "") == "office":
			_plan_office(desk.current)
		else:
			_plan_net(desk.current)
		_step_t = 0.2
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
		[desk.show_tab.bind("accounts"), 0.1],
		[_scroll_to.bind(acc), 1.4],
		[acc.select.bind(goal.sam), 0.1],
		[_scroll_to.bind(acc._profile), 4.2],  # "check their mobile on file"
	]
	if t.acct.get("security", false):  # Day 15: read the sign-in log, then contain it
		_plan.append([func() -> void: _scroll_to(acc.sec_log if acc.sec_log else acc), 3.2])
	if t.acct.get("bitlocker", false):  # Day 16: match the key ID on their screen, show it, read it out
		_plan.append([func() -> void: _scroll_to(acc.dev_head if acc.dev_head else acc), 3.4])
		if not goal.hold:
			_plan.append([acc.show_key.bind(goal.key), 1.8])
			_plan.append([acc.read_key.bind(goal.key), 2.2])
	if not goal.hold:
		if goal.unlock:
			_plan.append([acc.unlock, 0.9])
		if goal.reset:
			_plan.append([acc.reset_password, 0.9])
		if goal.must_change:
			_plan.append([acc.set_must_change.bind(true), 1.0])
		for g in goal.add:
			_plan.append([_scroll_to.bind(acc._groups), 0.8])
			_plan.append([acc.set_group.bind(g, true), 1.2])
		if goal.get("free", "") != "":  # Day 11: no spare licence: free the leaver's first
			_plan.append([_scroll_to.bind(acc._lic_head), 2.2])
			_plan.append([acc.select.bind(goal.free), 0.1])
			_plan.append([_scroll_to.bind(acc._profile), 2.6])
			_plan.append([acc.remove_licence, 1.2])
			_plan.append([acc.select.bind(goal.sam), 0.1])
			_plan.append([_scroll_to.bind(acc._profile), 1.2])
		if goal.get("revoke", false):
			_plan.append([acc.revoke_sessions, 1.2])
		for id in goal.get("remove", []):
			_plan.append([func() -> void: _scroll_to(acc.sec_log if acc.sec_log else acc), 0.6])
			_plan.append([acc.remove_method.bind(id), 1.2])
		for id in goal.get("drop", []):
			_plan.append([func() -> void: _scroll_to(acc.sec_log if acc.sec_log else acc), 0.6])
			_plan.append([acc.delete_rule.bind(id), 1.4])
		if goal.has("licence"):
			_plan.append([acc.assign_licence.bind(goal.licence), 1.2])
			_plan.append([_scroll_to.bind(acc._lic_head), 1.6])
	_plan.append([desk.answer.bind(1 if goal.hold else 0), RESULT_TIME + 1.0])


## Day 10: Remote Control: connect to the caller's PC, read the hardware ID and the processor,
## install the matching driver from the vendor page, see it working, then close it as Done.
func _plan_remote(t: Dictionary) -> void:
	var rem: Node = desk._remote
	var goal: Dictionary = t.rc.goal
	_plan = [
		[desk.show_tab.bind("remote"), 1.6],               # the PC list: pick the caller's, not the namesake's
		[rem.connect_to.bind(goal.pc), 1.2],
		[rem.show_props, 0.1],
		[_scroll_to_end, 3.0],                            # Code 28, hardware ID PID_...
		[rem.open_app.bind("settings"), 0.1],
		[_scroll_to_end, 2.2],                            # x64 or ARM-based
		[rem.open_app.bind("browser"), 0.1],
		[func() -> void: _scroll_to(rem.pkg_buttons.get("%s|%s" % [goal.model, goal.arch], rem)), 2.4],
	]
	if not goal.hold:
		_plan.append([rem.install.bind("%s|%s" % [goal.model, goal.arch]), 1.4])
		_plan.append([_scroll_to_end, 1.0])
		_plan.append([rem.open_app.bind("devmgr"), 0.1])
		_plan.append([_scroll_to_end, 1.6])
	_plan.append([desk.answer.bind(1 if goal.hold else 0), RESULT_TIME + 1.0])


## Day 12: Mail Console: find the reported email in the message trace, read its headers, then
## delete every copy and block what fits (or release / hold), and close it as Done.
func _plan_mail(t: Dictionary) -> void:
	var mc: Node = desk._mail
	var goal: Dictionary = t.mail.goal
	_plan = [
		[desk.show_tab.bind("mail"), 1.8],                # the message trace: which one did they mean?
		[mc.select.bind(goal.id), 0.1],
		[func() -> void: _scroll_to(mc.headers), 4.4],    # auth passes... but the link is a fake sign-in page
	]
	if goal.kind == "phish":
		_plan.append([mc.act.bind("purge"), 1.6])
	if goal.release:
		_plan.append([mc.act.bind("release"), 1.6])
	for k in ["addr", "domain", "url"]:
		if goal.blocks[k][0] == 1:
			_plan.append([mc.act.bind(k), 1.0])
	_plan.append([_scroll_to_end, 1.4])
	_plan.append([desk.answer.bind(1 if goal.kind == "hold" else 0), RESULT_TIME + 1.0])


## Day 13: Network Map: the print server can't reach the printer, FW01's leases show it got a new
## address, so point the queue's port at it, check it prints, reserve the address and close it as Done.
func _plan_net(t: Dictionary) -> void:
	var nm: Node = desk._net
	var goal: Dictionary = t.net.goal
	_plan = [
		[desk.show_tab.bind("net"), 1.6],                    # the map: PRINT01 has a problem
		[nm.select.bind("PRINT01"), 0.1],
		[func() -> void: _scroll_to(nm.focus), 1.0],
		[nm.ping.bind(goal.mfp), 0.1],
		[_scroll_to_end, 1.8],                               # Offline, ping times out
	]
	match goal.fault:
		"ip":
			_plan.append_array([
				[nm.select.bind("FW01"), 0.1],
				[func() -> void: _scroll_to(nm.focus), 2.6],  # leased today 07:xx: a new address
				[nm.select.bind("PRINT01"), 0.1],
				[func() -> void: _scroll_to(nm.focus), 0.6],
				[func() -> void: nm._port_edit[goal.mfp].text = goal.new_ip, 0.9],
				[nm.act.bind("port", goal.mfp, goal.new_ip), 0.1],
				[func() -> void: _scroll_to(nm.focus), 1.0],
				[nm.ping.bind(goal.mfp), 0.1],
				[_scroll_to_end, 1.4],                       # Ready, replies
				[nm.select.bind("FW01"), 0.1],
				[func() -> void: _scroll_to(nm.focus), 0.8],
				[nm.act.bind("reserve", goal.mfp), 1.4],
			])
		"job", "paused":
			_plan.append([nm.act.bind("cancel" if goal.fault == "job" else "resume", goal.mfp), 1.6])
		_:
			_plan.append([nm.select.bind(goal.mfp), 0.1])
			_plan.append([nm.read_panel.bind(goal.mfp), 1.8])
			var fix: String = {"cable": "cable", "toner_spare": "spare", "toner_order": "order", "fuser": "service"}[goal.fault]
			_plan.append([nm.act.bind(fix, goal.mfp), 0.1])
			_plan.append([_scroll_to_end, 1.6])
	_plan.append([desk.answer.bind(1 if goal.hold else 0), RESULT_TIME + 1.0])


## Day 14: the fix step of "The internet is down!" on the Network Map: check DC01's forwarders, find
## why in FW01's rules and log, make the fix there (or on DC01, the modem or with the ISP), close it.
func _plan_office(t: Dictionary) -> void:
	var nm: Node = desk._net
	var goal: Dictionary = t.net.goal
	var key: String = "%s%d" % [goal.fault, goal.sub]
	var dev: String = {"dns0": "DC01", "dns1": "FW01", "wan0": "ISP", "wan1": "MODEM", "dhcp0": "DC01", "dhcp1": "DC01"}[key]
	_plan = [[desk.show_tab.bind("net"), 1.4]]                # the map: DC01 has a warning
	if key == "dns1":
		_plan.append_array([[nm.select.bind("DC01"), 0.1], [func() -> void: _scroll_to(nm.focus), 1.8]])  # forwarders time out
	_plan.append_array([[nm.select.bind(dev), 0.1], [func() -> void: _scroll_to(nm.focus), 1.2]])
	if key == "dns1":
		_plan.append([_scroll_to_end, 2.2])                    # the log: DENY by yesterday's rule
	var fix: Array = {"dns0": ["set_fwd"], "dns1": ["allow_dns"], "wan0": ["isp_fault"], "wan1": ["modem_check"],
		"dhcp0": ["start_dhcp", "recovery"], "dhcp1": ["authorize"]}[key]
	if key == "wan0" and t.net.backup:
		fix.append("failover")
	for f in fix:
		_plan.append([nm.act.bind(f, dev), 0.1])
		_plan.append([_scroll_to_end if key != "dns1" else func() -> void: _scroll_to(nm.focus), 1.6])
	_plan.append([desk.answer.bind(1 if goal.hold else 0), RESULT_TIME + 1.0])


## Day 17: reveal the next hint and scroll the ticket so the senior's notes are on screen.
func _ask_senior() -> void:
	desk.ask_senior()
	await get_tree().process_frame
	await get_tree().process_frame
	var sc: ScrollContainer = desk._dscroll
	sc.scroll_vertical = int(desk._senior_box.get_global_rect().end.y - sc.get_global_rect().end.y + sc.scroll_vertical + 12.0)


func _scroll_to_end() -> void:
	var sc: ScrollContainer = desk._tool_scroll
	sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)


func _scroll_to(c: Control) -> void:
	var sc: ScrollContainer = desk._tool_scroll
	sc.scroll_vertical = int(c.get_global_rect().position.y - sc.get_global_rect().position.y + sc.scroll_vertical - 12.0)
