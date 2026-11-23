extends SceneTree
## Ticket sanity test. Run: godot --headless -s tools/test_tickets.gd   (exit code 1 on failure)
## Generates thousands of tickets of every kind and checks the structure is sound, so a broken
## ticket type can never ship. It can't judge technical accuracy; that's the daily fact-check.

const PER_KIND := 500
const REQUIRED := ["kind", "priority", "client", "user", "subject", "body", "info_title", "info", "question", "options", "answer", "explain"]
# Country/city-specific terms that shouldn't appear (the game is global and generic).
const BANNED := ["perth", "nbn", "g'day", ".com.au", "fremantle", "freo", "telstra", "optus"]

# Commands run against every simulated terminal (tickets with "term"); each must print something.
const COMMANDS := ["ipconfig", "ipconfig /all", "ipconfig/all", "ipconfig /renew", "ipconfig /release",
	"ipconfig /bogus", "ping 192.168.1.1", "ping 1.1.1.1", "ping -n 2 1.1.1.1", "ping google.com",
	"ping dc01", "ping 192.168.1.77", "nslookup google.com", "nslookup google.com 8.8.8.8",
	"nslookup 192.168.1.10", "nslookup 1.1.1.1", "nslookup dc01", "tracert 1.1.1.1", "tracert dc01",
	"tracert google.com", "foo", "help"]

var fails := 0


func _init() -> void:
	var T = load("res://scripts/tickets.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var g = T.new(rng)
	for kind in T.KINDS:
		var answers := {}
		for i in PER_KIND:
			var t: Dictionary = g.make(kind)
			_check(kind, t)
			if t.has("options") and t.has("answer") and t.answer >= 0 and t.answer < t.options.size():
				answers[t.options[t.answer]] = true
			if t.has("acct"):  # Toolbox work: what has to be done in the tool must vary too
				var gl: Dictionary = t.acct.goal.duplicate()
				gl.erase("sam")
				gl.erase("hold_why")
				answers["acct:" + str(gl)] = true
			for si in t.get("steps", []).size():  # later steps must vary too
				var st: Dictionary = t.steps[si]
				if st.get("options", []) is Array and st.get("answer", -1) is int and st.answer >= 0 and st.answer < st.options.size():
					answers["step%d:%s" % [si, st.options[st.answer]]] = true
		# A ticket type whose right answer never varies is a memory test, not a puzzle.
		if answers.size() < 2:
			_fail(kind, "right answer never changes across %d tickets" % PER_KIND)
	print("tickets: %d kinds x %d, %d failure(s)" % [T.KINDS.size(), PER_KIND, fails])
	quit(1 if fails > 0 else 0)


func _check(kind: String, t: Dictionary) -> void:
	for k in REQUIRED:
		if not t.has(k):
			_fail(kind, "missing field '%s'" % k)
			return
	if t.kind != kind:
		_fail(kind, "kind is '%s'" % t.kind)
	if not (t.priority is int) or t.priority < 1 or t.priority > 4:
		_fail(kind, "priority %s not 1-4" % str(t.priority))
	var opts: Array = t.options
	_check_options(kind, opts, t.answer)
	for k in ["subject", "body", "info", "question", "explain", "client", "user"]:
		if str(t[k]).strip_edges() == "":
			_fail(kind, "empty '%s'" % k)
	var text := " ".join([t.subject, t.body, t.info, t.question, t.explain, t.client, " ".join(opts)]).to_lower()
	if t.has("steps"):
		if not t.has("step_name"):
			_fail(kind, "multi-step ticket has no step_name for step 1")
		if not (t.steps is Array) or t.steps.is_empty():
			_fail(kind, "steps is empty")
		else:
			for st in t.steps:
				var keys := ["name", "info_add", "question", "explain"]
				keys.append_array(["options", "answer"])
				for k in keys:
					if not st.has(k):
						_fail(kind, "step missing field '%s'" % k)
						return
				_check_options(kind, st.options, st.answer)
				text += " " + " ".join(st.options).to_lower()
				if st.has("net"):
					_check_office(kind, st)
					text += " " + " ".join(st.net.changes + st.net.log + st.net.events).to_lower()
				for k in ["name", "info_add", "question", "explain"]:
					if str(st[k]).strip_edges() == "":
						_fail(kind, "empty step '%s'" % k)
				text += " " + " ".join([st.info_add, st.question, st.explain]).to_lower()
	if t.has("acct"):
		_check_acct(kind, t)
		for u in t.acct.users:
			text += " " + " ".join([u.name, u.title, u.upn, u.device, u.licence, " ".join(u.groups)]).to_lower()
			for d in u.get("devices", []):
				text += " " + " ".join([d.name, d.about] + d.keys.map(func(k): return k.drive + " " + k.when)).to_lower()
			if t.acct.get("security", false):
				text += " " + " ".join(u.signins + u.sessions + u.auth.map(func(m): return m.text) + u.rules.map(func(r): return r.text)).to_lower()
	if t.has("rc"):
		_check_rc(kind, t)
		for pc in t.rc.pcs:
			text += " " + " ".join([pc.name, pc.user, pc.cpu]).to_lower()
	if t.has("mail"):
		_check_mail(kind, t)
		for x in t.mail.msgs:
			text += " " + " ".join([x.from_name, x.from_addr, x.reply_to, x.subject, x.auth, x.links, x.attach, x.note]).to_lower()
	if t.has("net"):
		_check_net(kind, t)
		text += " " + " ".join(t.net.changes).to_lower()
	if t.has("term"):
		var Terminal = load("res://scripts/terminal.gd")
		if not t.has("prompt"):
			_fail(kind, "terminal ticket has no prompt")
		for cmd in COMMANDS:
			var out: String = Terminal.run(cmd, t.term)
			if out.strip_edges() == "":
				_fail(kind, "terminal printed nothing for '%s'" % cmd)
			if "%s" in out or "%d" in out:
				_fail(kind, "unfilled placeholder in terminal output for '%s'" % cmd)
			text += " " + out.to_lower()
		for st in t.get("steps", []):  # a verify step heals the network: the proving tests must pass
			if st.has("term_fault"):
				var net: Dictionary = t.term.duplicate()
				net.fault = st.term_fault
				for cmd in COMMANDS:
					if Terminal.run(cmd, net.duplicate()).strip_edges() == "":
						_fail(kind, "healed terminal printed nothing for '%s'" % cmd)
				Terminal.run("ipconfig /renew", net)
				var proof: String = Terminal.run("nslookup google.com", net) + Terminal.run("ping 1.1.1.1", net) + Terminal.run("tracert 1.1.1.1", net)
				if net.fault != "ok" or "169.254" in Terminal.run("ipconfig", net) or "failed" in proof or "timed out" in proof.to_lower():
					_fail(kind, "network still broken after the fix (%s)" % st.term_fault)
	for b in BANNED:
		if b in text:
			_fail(kind, "region-specific term '%s'" % b)
	if "%" in text.replace("%%", "") and ("%s" in text or "%d" in text):
		_fail(kind, "unfilled format placeholder")


## Toolbox > Network Map tickets: Done / Hold; doing what the fault needs must pass (and the other
## close must not), the untouched network must fail both ways, and every harmful action must be caught.
func _check_net(kind: String, t: Dictionary) -> void:
	var N = load("res://scripts/netmap.gd")
	var n: Dictionary = t.net
	var goal: Dictionary = n.goal
	if t.options.size() != 2 or t.answer != (1 if goal.hold else 0):
		_fail(kind, "net options must be Done / Hold, answer matching goal.hold")
	var tm: Dictionary = N.mfp_in(n, goal.mfp)
	var other: Dictionary = N.mfp_in(n, goal.other)
	if tm.is_empty() or other.is_empty() or not N.printing(other) or N.printing(tm):
		_fail(kind, "net: the target must be broken and the other printer working")
		return
	if not goal.mfp in t.body:
		_fail(kind, "net: body doesn't name the broken printer")
	if N.check(n, false).is_empty() or N.check(n, true).is_empty():
		_fail(kind, "net: untouched network judged right")
	var fix: Array = {"job": [["cancel"]], "paused": [["resume"]], "ip": [["port", goal.new_ip], ["reserve"]],
		"cable": [["cable"]], "toner_spare": [["spare"]], "toner_order": [["order"]], "fuser": [["service"]]}[goal.fault]
	if goal.fault == "toner_spare" and not n.spare or goal.fault == "toner_order" and n.spare:
		_fail(kind, "net: spare toner doesn't match the case")
	var ok: Dictionary = n.duplicate(true)
	for f in fix:
		N.apply(ok, f[0], goal.mfp, f[1] if f.size() > 1 else null)
	if not N.check(ok, goal.hold).is_empty() or N.check(ok, not goal.hold).is_empty():
		_fail(kind, "net: the right fix doesn't pass (%s): %s" % [goal.fault, str(N.check(ok, goal.hold))])
		return
	if not goal.hold and not N.printing(N.mfp_in(ok, goal.mfp)):
		_fail(kind, "net: not printing after the fix")
	if goal.fault == "ip":  # the port alone isn't enough
		var half: Dictionary = n.duplicate(true)
		N.apply(half, "port", goal.mfp, goal.new_ip)
		if N.check(half, false).is_empty():
			_fail(kind, "net: missing DHCP reservation wasn't caught")
	var bad: Array = [["spooler", "PRINT01"], ["port", goal.mfp, "192.168.10.%d" % (60 if goal.fault != "ip" else 51)],
		["port", goal.other, "192.168.10.99"], ["order", goal.other], ["service", goal.other]]
	if not goal.fault.begins_with("toner"):
		bad.append(["order", goal.mfp])
	if goal.fault != "fuser":
		bad.append(["service", goal.mfp])
	for b in bad:  # each harmful action on top of the right fix must fail
		var w: Dictionary = n.duplicate(true)
		for f in fix:
			N.apply(w, f[0], goal.mfp, f[1] if f.size() > 1 else null)
		N.apply(w, b[0], b[1], b[2] if b.size() > 2 else null)
		if N.check(w, goal.hold).is_empty():
			_fail(kind, "net: harmful %s wasn't caught (%s)" % [str(b), goal.fault])
	for a in ["bounce", "cable", "spare"]:  # harmless checks on the other printer change nothing
		var h: Dictionary = n.duplicate(true)
		for f in fix:
			N.apply(h, f[0], goal.mfp, f[1] if f.size() > 1 else null)
		N.apply(h, a, goal.other)
		if not N.check(h, goal.hold).is_empty():
			_fail(kind, "net: harmless %s was judged wrong" % a)


## Network Map, office mode (the fix step of an "internet is down" ticket): Fixed / Hold; the right fix
## must pass (and the other close must not), the untouched network and half-fixes must fail, every
## harmful action on top of the fix must be caught and harmless checks must not count against you.
func _check_office(kind: String, st: Dictionary) -> void:
	var O = load("res://scripts/netmap_office.gd")
	var n: Dictionary = st.net
	var goal: Dictionary = n.goal
	var key: String = "%s%d" % [goal.fault, goal.sub]
	if st.options.size() != 2 or st.answer != (1 if goal.hold else 0):
		_fail(kind, "office: options must be Fixed / Hold, answer matching goal.hold")
	if O.why_not(n) == "" and not goal.hold:
		_fail(kind, "office: the network starts out working (%s)" % key)
	if O.check(n, false).is_empty() or O.check(n, true).is_empty():
		_fail(kind, "office: untouched network judged right (%s)" % key)
	var fix: Array = {"dns0": ["set_fwd"], "dns1": ["allow_dns"], "wan0": ["isp_fault"], "wan1": ["modem_check"],
		"dhcp0": ["start_dhcp", "recovery"], "dhcp1": ["authorize"]}[key]
	if key == "wan0" and n.backup:
		fix.append("failover")
	var ok: Dictionary = n.duplicate(true)
	for f in fix:
		O.apply(ok, f, "")
	if not O.check(ok, goal.hold).is_empty() or O.check(ok, not goal.hold).is_empty():
		_fail(kind, "office: the right fix doesn't pass (%s): %s" % [key, str(O.check(ok, goal.hold))])
		return
	if not goal.hold and O.why_not(ok) != "":
		_fail(kind, "office: still broken after the fix (%s)" % key)
	if fix.size() > 1:  # every part of a multi-part fix is needed
		for skip in fix:
			var half: Dictionary = n.duplicate(true)
			for f in fix:
				if f != skip:
					O.apply(half, f, "")
			if O.check(half, goal.hold).is_empty():
				_fail(kind, "office: skipping %s wasn't caught (%s)" % [skip, key])
	var bad: Array = [["factory", ""], ["scope_dns", ""]]
	for r in n.rules:
		bad.append(["rule_off", r.name])
	if key != "wan0":
		bad.append(["isp_fault", ""])
	if goal.fault != "wan":
		bad.append(["failover", ""])
	for b in bad:
		var w: Dictionary = n.duplicate(true)
		for f in fix:
			O.apply(w, f, "")
		O.apply(w, b[0], b[1])
		if O.check(w, goal.hold).is_empty():
			_fail(kind, "office: harmful %s wasn't caught (%s)" % [str(b), key])
	var harmless: Array = ["restart_fw", "clear_cache", "modem_check", "authorize"]
	if not goal.hold and goal.fault != "dns":
		harmless.append("set_fwd")
	for a in harmless:
		var h: Dictionary = n.duplicate(true)
		for f in fix:
			O.apply(h, f, "")
		O.apply(h, a, "")
		if not O.check(h, goal.hold).is_empty():
			_fail(kind, "office: harmless %s was judged wrong (%s): %s" % [a, key, str(O.check(h, goal.hold))])
	if key == "wan1" and n.backup:  # running on the backup with the modem still dark isn't fixed
		var bk: Dictionary = n.duplicate(true)
		O.apply(bk, "failover", "")
		if O.check(bk, false).is_empty():
			_fail(kind, "office: failover alone accepted for a powerless modem")
	var cheat: Dictionary = n.duplicate(true)  # disabling the culprit rule works, but isn't the fix
	if key == "dns1":
		O.apply(cheat, "rule_off", "Servers: HTTPS out only")
		if O.check(cheat, false).is_empty():
			_fail(kind, "office: disabling the lockdown rule was accepted")


## Toolbox > Accounts tickets: options are Done / Hold; the goal must be reachable in the tool and
## the solved directory must pass Accounts.check (and the untouched one must not, unless it's a hold).
func _check_acct(kind: String, t: Dictionary) -> void:
	var A = load("res://scripts/accounts.gd")
	var a: Dictionary = t.acct
	for k in ["users", "orig", "groups", "goal"]:
		if not a.has(k):
			_fail(kind, "acct missing '%s'" % k)
			return
	if t.options.size() != 2 or t.answer != (1 if a.goal.hold else 0):
		_fail(kind, "acct options must be Done / Hold, answer matching goal.hold")
	var sams := {}
	for u in a.users:
		if sams.has(u.sam):
			_fail(kind, "duplicate username %s" % u.sam)
		sams[u.sam] = true
		for g in u.groups:
			if not g in a.groups:
				_fail(kind, "user in unknown group %s" % g)
	if not sams.has(a.goal.sam):
		_fail(kind, "target user not in the directory")
	for g in a.goal.add:
		if not g in a.groups:
			_fail(kind, "goal group %s not offered" % g)
	# Untouched: Hold is right only when the goal is to hold, Done never is.
	if A.check(a, true).is_empty() != a.goal.hold or A.check(a, false).is_empty():
		_fail(kind, "untouched directory judged wrongly")
	var b: Dictionary = a.duplicate(true)
	if not a.goal.hold:  # do exactly what the goal asks, then Done must pass and Hold must not
		for u in b.users:
			if u.sam == a.goal.sam:
				if a.goal.unlock:
					u.locked = false
				u.reset = a.goal.reset
				u.must_change = a.goal.must_change
				for g in a.goal.add:
					u.groups.append(g)
				if a.goal.get("revoke", false):
					u.revoked = true
					u.sessions = []
				u.auth = u.get("auth", []).filter(func(m): return not m.id in a.goal.get("remove", []))
				u.rules = u.get("rules", []).filter(func(r): return not r.id in a.goal.get("drop", []))
				if a.goal.get("key", "") != "":
					u.read = [a.goal.key]
		for u in b.users:  # licence tickets: free the leaver's first, then assign
			if u.sam == a.goal.get("free", ""):
				u.licence = "None"
		for u in b.users:
			if u.sam == a.goal.sam and a.goal.has("licence"):
				if A.spare(b, a.goal.licence) < 1:
					_fail(kind, "no spare %s even after freeing the leaver's" % a.goal.licence)
				u.licence = a.goal.licence
		if not A.check(b, false).is_empty() or A.check(b, true).is_empty():
			_fail(kind, "solved directory doesn't pass: %s" % str(A.check(b, false)))
	if a.get("security", false):
		_check_security(kind, a)
	if a.get("bitlocker", false):
		_check_bitlocker(kind, t)
	if a.goal.has("licence"):
		_check_licence(kind, a)
	# Touching a colleague is always wrong.
	var c: Dictionary = a.duplicate(true)
	for u in c.users:
		if u.sam != a.goal.sam:
			u.must_change = true
			break
	if A.check(c, a.goal.hold).is_empty():
		_fail(kind, "changing another user wasn't caught")


## BitLocker tickets: exactly one key (the caller's) may start with the ID on their screen, it must exist
## only when the ticket is doable, and reading out any other key (or any key on a hold) must be caught.
func _check_bitlocker(kind: String, t: Dictionary) -> void:
	var A = load("res://scripts/accounts.gd")
	var a: Dictionary = t.acct
	var goal: Dictionary = a.goal
	if a.screen.length() != 8 or not a.screen in t.info:
		_fail(kind, "bitlocker: the screen's key ID isn't in the call notes")
	var matches: Array = []
	for u in a.users:
		for d in u.devices:
			for k in d.keys:
				if k.id.begins_with(a.screen):
					matches.append(k.id)
				if k.pwd.split("-").size() != 8:
					_fail(kind, "bitlocker: recovery password isn't 8 blocks")
				for b in k.pwd.split("-"):
					if b.length() != 6 or int(b) % 11 != 0:
						_fail(kind, "bitlocker: block %s isn't a valid recovery block" % b)
	if goal.key == "":
		if not goal.hold:
			_fail(kind, "bitlocker: no key to read but not a hold")
		if not matches.is_empty():
			_fail(kind, "bitlocker: a key matches the screen on a no-key ticket")
	elif matches != [goal.key]:
		_fail(kind, "bitlocker: %d keys match the screen (want just the caller's)" % matches.size())
	for u in a.users:
		for d in u.devices:
			for k in d.keys:
				if k.id == goal.key and goal.hold == false:
					continue
				var w: Dictionary = a.duplicate(true)
				for x in w.users:
					if x.sam == goal.sam and goal.key != "" and not goal.hold:
						x.read = [goal.key]
				for x in w.users:
					if x.sam == u.sam:
						x.read.append(k.id)
				if A.check(w, goal.hold).is_empty():
					_fail(kind, "bitlocker: reading out key %s wasn't caught" % k.id.substr(0, 8))


## Licence tickets: the stock must match the case (spare / leaver / buy), and every other licence for
## the starter, or taking one from someone still working there, must be caught.
func _check_licence(kind: String, a: Dictionary) -> void:
	var A = load("res://scripts/accounts.gd")
	var goal: Dictionary = a.goal
	var spare: int = A.spare(a, goal.licence)
	if (spare > 0) == (goal.hold or goal.free != ""):
		_fail(kind, "licence stock doesn't match the case")
	var tier: int = -1
	for i in a.skus.size():
		if a.skus[i].name == goal.licence:
			tier = i
	for i in a.skus.size():
		var s: Dictionary = a.skus[i]
		if A.spare(a, s.name) < 0:
			_fail(kind, "more %s in use than owned" % s.name)
		if i > tier and spare == 0 and A.spare(a, s.name) > 0:
			_fail(kind, "a higher licence is spare when the needed one isn't (two right answers)")
	if not goal.hold:  # switching off the onboarding password change must be caught
		var w: Dictionary = a.duplicate(true)
		for u in w.users:
			if u.sam == goal.free:
				u.licence = "None"
			if u.sam == goal.sam:
				u.licence = goal.licence
				u.must_change = false
		if A.check(w, false).is_empty():
			_fail(kind, "turning off the starter's password change wasn't caught")
	for u in a.users:
		if u.sam == goal.free and (u.licence != goal.licence or not u.has("left")):
			_fail(kind, "leaver doesn't hold the needed licence")
		if u.sam != goal.free and u.has("left"):
			_fail(kind, "unexpected leaver")
	for s in a.skus:  # the starter on any other licence is wrong
		if s.name == goal.licence:
			continue
		var w: Dictionary = a.duplicate(true)
		for u in w.users:
			if u.sam == goal.sam:
				u.licence = s.name
		if A.check(w, false).is_empty() or A.check(w, true).is_empty():
			_fail(kind, "wrong licence %s wasn't caught" % s.name)
	for u in a.users:  # taking it from someone who still works there is wrong
		if u.sam != goal.sam and u.sam != goal.free and u.licence == goal.licence:
			var w: Dictionary = a.duplicate(true)
			for x in w.users:
				if x.sam == u.sam:
					x.licence = "None"
				if x.sam == goal.sam:
					x.licence = goal.licence
			if A.check(w, false).is_empty():
				_fail(kind, "taking a colleague's licence wasn't caught")


## Toolbox > Remote Control tickets: Done / Hold; the right install must pass, nothing must fail,
## and installing on the wrong PC, the wrong model or arch, or the ad must each be caught.
func _check_rc(kind: String, t: Dictionary) -> void:
	var R = load("res://scripts/remote.gd")
	var r: Dictionary = t.rc
	var goal: Dictionary = r.goal
	if t.options.size() != 2 or t.answer != (1 if goal.hold else 0):
		_fail(kind, "rc options must be Done / Hold, answer matching goal.hold")
	var with_dev: Array = r.pcs.filter(func(pc: Dictionary) -> bool: return pc.has_device)
	if with_dev.size() != 1 or with_dev[0].name != goal.pc or with_dev[0].user != t.user or with_dev[0].arch != goal.arch:
		_fail(kind, "rc: the scanner must be on the caller's PC only, matching goal")
	var m: Dictionary = {}
	for x in r.models:
		if x.model == goal.model:
			m = x
	if m.is_empty() or m.pid != r.device.pid:
		_fail(kind, "rc: device PID doesn't match the goal model")
		return
	if goal.hold != (not goal.arch in m.archs):
		_fail(kind, "rc: hold must mean no driver for this arch")
	if R.check(r, true).is_empty() != goal.hold or R.check(r, false).is_empty():
		_fail(kind, "rc: untouched PC judged wrongly")
	var right := "%s|%s" % [goal.model, goal.arch]
	var bad: Array = [{"pc": goal.pc, "pkg": "fixer"}]
	for pc in r.pcs:
		if pc.name != goal.pc:
			bad.append({"pc": pc.name, "pkg": "%s|%s" % [goal.model, pc.arch]})
	for x in r.models:
		for a in x.archs:
			if "%s|%s" % [x.model, a] != right:
				bad.append({"pc": goal.pc, "pkg": "%s|%s" % [x.model, a]})
	for b in bad:  # each wrong install alone (plus the right one when there is one) must fail
		var c: Dictionary = r.duplicate(true)
		c.installs = [b] if goal.hold else [b, {"pc": goal.pc, "pkg": right}]
		if R.check(c, goal.hold).is_empty():
			_fail(kind, "rc: wrong install %s wasn't caught" % str(b))
	if not goal.hold:
		var ok: Dictionary = r.duplicate(true)
		ok.installs = [{"pc": goal.pc, "pkg": right}]
		if not R.check(ok, false).is_empty() or R.check(ok, true).is_empty():
			_fail(kind, "rc: right install doesn't pass: %s" % str(R.check(ok, false)))


## Toolbox > Mail Console tickets: Done / Hold; doing exactly what the goal needs must pass, and every
## action the goal forbids, skipping a must-do, or acting on another email must each be caught.
func _check_mail(kind: String, t: Dictionary) -> void:
	var M = load("res://scripts/mail.gd")
	var m: Dictionary = t.mail
	var goal: Dictionary = m.goal
	var hold: bool = goal.kind == "hold"
	if t.options.size() != 2 or t.answer != (1 if hold else 0):
		_fail(kind, "mail options must be Done / Hold, answer matching the goal")
	var target: Dictionary = M._msg_in(m.msgs, goal.id)
	if target.is_empty() or target.recips[0].name != t.user or not target.subject in t.body:
		_fail(kind, "mail: reported message missing or not the caller's")
		return
	var subjects := {}
	for x in m.msgs:
		if subjects.has(x.subject):
			_fail(kind, "mail: two messages share a subject")
		subjects[x.subject] = true
	var quar: bool = target.recips.any(func(r: Dictionary) -> bool: return r.folder == "Quarantine")
	if goal.release and (not quar or goal.kind != "legit"):
		_fail(kind, "mail: release goal without a quarantined legit copy")
	var musts: Array = ["purge"] if goal.kind == "phish" else []
	if goal.release:
		musts.append("release")
	var oks: Array = []
	var bads: Array = []
	for k in goal.blocks:
		var need: int = goal.blocks[k][0]
		if need == 1:
			musts.append(k)
		elif need == -1:
			bads.append(k)
		elif k != "url" or target.url_host != "":
			oks.append(k)
		if need != 0 and str(goal.blocks[k][1]).strip_edges() == "":
			_fail(kind, "mail: block rule %s has no reason" % k)
		if need == 1 and k == "url" and target.url_host == "":
			_fail(kind, "mail: must block a link that isn't there")
	if goal.kind == "legit":
		bads.append("purge")
	if goal.kind == "phish" and quar:
		bads.append("release")
	if hold:
		musts.clear()
		oks.clear()
		bads = ["purge", "addr", "domain"] + (["url"] if target.url_host != "" else []) + (["release"] if quar else [])
	var run := func(acts: Array, held: bool, on_id := -1) -> Array:
		var c: Dictionary = m.duplicate(true)
		var node = M.new()
		node.mail = c
		node.selected = goal.id if on_id < 0 else on_id
		for a in acts:
			node.act(a)
		node.free()
		return M.check(c, held)
	# Untouched: right only when nothing needs doing
	if run.call([], hold).is_empty() != musts.is_empty():
		_fail(kind, "mail: untouched console judged wrongly")
	if not hold and run.call([], true).is_empty():
		_fail(kind, "mail: holding a clear-cut email wasn't caught")
	if hold and run.call([], false).is_empty():
		_fail(kind, "mail: marking a hold done wasn't caught")
	var right: Array = run.call(musts, hold)
	if not right.is_empty():
		_fail(kind, "mail: doing it right doesn't pass: %s" % str(right))
	if not run.call(musts + oks, hold).is_empty():
		_fail(kind, "mail: optional blocks were judged wrong")
	for k in musts:
		var less: Array = musts.filter(func(x: String) -> bool: return x != k)
		if run.call(less, hold).is_empty():
			_fail(kind, "mail: skipping %s wasn't caught" % k)
	for k in bads:
		if run.call(musts + [k], hold).is_empty():
			_fail(kind, "mail: doing %s wasn't caught" % k)
	for x in m.msgs:  # acting on another email is always wrong
		if x.id != goal.id:
			var c: Dictionary = m.duplicate(true)
			var node = M.new()
			node.mail = c
			node.selected = goal.id
			for a in musts:
				node.act(a)
			node.selected = x.id
			node.act("addr")
			node.free()
			if M.check(c, hold).is_empty():
				_fail(kind, "mail: acting on another email wasn't caught")


func _check_options(kind: String, opts: Array, answer: int) -> void:
	if opts.size() < 2 or opts.size() > 4:
		_fail(kind, "%d options (need 2-4, answered with keys 1-4)" % opts.size())
	if answer < 0 or answer >= opts.size():
		_fail(kind, "answer index %d out of range" % answer)
	var seen := {}
	for o in opts:
		if str(o).strip_edges() == "":
			_fail(kind, "empty option")
		if seen.has(o):
			_fail(kind, "duplicate option '%s'" % o)
		seen[o] = true


func _fail(kind: String, msg: String) -> void:
	fails += 1
	if fails <= 20:
		printerr("FAIL [%s] %s" % [kind, msg])


## MFA tickets: every user has a security page; the attacker's items exist when the goal says so;
## and each harmful move on top of the right fix (removing the user's own method or rule, turning
## MFA off, trusting the attacker's IP, leaving sign-in blocked, skipping a must-do) is caught.
func _check_security(kind: String, a: Dictionary) -> void:
	var A = load("res://scripts/accounts.gd")
	for u in a.users:
		for k in ["signins", "sessions", "auth", "rules", "blocked", "revoked", "mfa_off", "trusted"]:
			if not u.has(k):
				_fail(kind, "security user missing '%s'" % k)
				return
	var t: Dictionary = {}
	for u in a.users:
		if u.sam == a.goal.sam:
			t = u
	for id in a.goal.remove:
		if not t.auth.any(func(m): return m.id == id):
			_fail(kind, "goal removes a method that isn't there")
	for id in a.goal.drop:
		if not t.rules.any(func(r): return r.id == id):
			_fail(kind, "goal drops a rule that isn't there")
	if not t.rules.any(func(r): return r.id == "own") or t.get("foreign_ip", "") == "":
		_fail(kind, "caller needs an own rule and the attacker's IP")
	if a.goal.revoke != t.signins.any(func(l): return "APPROVED" in l):
		_fail(kind, "revoke goal doesn't match the sign-in log")
	var solve := func() -> Dictionary:
		var b: Dictionary = a.duplicate(true)
		for u in b.users:
			if u.sam == a.goal.sam:
				u.reset = true
				u.must_change = true
				if a.goal.revoke:
					u.revoked = true
					u.sessions = []
				u.auth = u.auth.filter(func(m): return not m.id in a.goal.remove)
				u.rules = u.rules.filter(func(r): return not r.id in a.goal.drop)
		return b
	var harms := [
		func(u): u.rules = u.rules.filter(func(r): return r.id != "own"),
		func(u): u.auth = u.auth.filter(func(m): return m.id != "app"),
		func(u): u.mfa_off = true,
		func(u): u.trusted = u.foreign_ip,
		func(u): u.blocked = true,
		func(u): u.must_change = false,
		func(u): u.reset = false,
		func(u): u.auth = u.auth.filter(func(m): return m.id != "sms") if u.auth.any(func(m): return m.id == "sms") else [],
	]
	if a.goal.revoke:
		harms.append(func(u): u.revoked = false)
	if not a.goal.remove.is_empty():
		harms.append(func(u): u.auth = a.orig.filter(func(o): return o.sam == a.goal.sam)[0].auth.duplicate(true))
	if not a.goal.drop.is_empty():
		harms.append(func(u): u.rules = a.orig.filter(func(o): return o.sam == a.goal.sam)[0].rules.duplicate(true))
	for i in harms.size():
		var b: Dictionary = solve.call()
		for u in b.users:
			if u.sam == a.goal.sam:
				harms[i].call(u)
		if A.check(b, false).is_empty():
			_fail(kind, "harmful change %d on top of the fix wasn't caught" % i)
	var other: Dictionary = solve.call()  # touching a colleague's account is caught too
	for u in other.users:
		if u.sam != a.goal.sam:
			u.revoked = true
			break
	if A.check(other, false).is_empty():
		_fail(kind, "changing a colleague's account wasn't caught")

