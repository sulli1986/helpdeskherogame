extends RefCounted
## Ticket generator. Each ticket is a Dictionary:
##   kind, priority (1 = P1 .. 4 = P4), client, user, subject, body,
##   info_title, info (evidence shown in a monospace box), question,
##   options (Array[String]), answer (index into options), explain (shown after answering)
##   Optional: term + prompt (a simulated command prompt the player types into; see terminal.gd)
##   Optional: steps (Array of later steps on the same ticket, each with name, info_add, question,
##   options, answer, explain). The top-level question is step 1; info_add is appended to the evidence
##   when that step opens. Each step pays out; a wrong step escalates the ticket. A step with
##   live = true reopens the command prompt; term_fault (if set) changes what the PC sees first.
##   A step can have actions (Array of {text, need}) instead of options/answer: an admin-console
##   checklist; it's right when every need = 1 action is ticked and no need = -1 one is.
## New ticket types: add a _make_<kind>() and list it in KINDS. Keep answers technically right;
## the players are often real IT people.

const KINDS := ["phish", "lockout", "share", "printer", "network", "licence", "mfa", "driver"]

const CLIENTS := [
	["Greenfield Wines", "greenfieldwines.com"],
	["Ironbridge Freight", "ironbridgefreight.com"],
	["Maple & Stone Legal", "maplestonelegal.com"],
	["Clearwater Dental", "clearwaterdental.com"],
	["Oakline Architects", "oaklinearch.com"],
	["Summit Physio", "summitphysio.com"],
	["Bluepeak Logistics", "bluepeaklogistics.com"],
	["Riverbend Realty", "riverbendrealty.com"],
]
const FIRST := ["Sarah", "Jayden", "Priya", "Tom", "Mei", "Liam", "Aisha", "Josh", "Chloe", "Raj", "Emma", "Nathan"]
const LAST := ["Nguyen", "Smith", "Patel", "Wilson", "Brown", "Taylor", "Chen", "Murphy", "Kelly", "Singh"]

var rng: RandomNumberGenerator


func _init(r: RandomNumberGenerator = null) -> void:
	rng = r if r else RandomNumberGenerator.new()
	if not r:
		rng.randomize()


func make(kind := "") -> Dictionary:
	if kind == "":
		kind = KINDS[rng.randi() % KINDS.size()]
	var c: Array = _pick(CLIENTS)
	var first: String = _pick(FIRST)
	var last: String = _pick(LAST)
	var ctx := {
		"client": c[0], "domain": c[1], "first": first, "last": last,
		"user": "%s %s" % [first, last],
		"sam": (first.substr(0, 1) + last).to_lower(),
	}
	var t: Dictionary = call("_make_" + kind, ctx)
	t["kind"] = kind
	t["client"] = ctx.client
	t["user"] = ctx.user
	if not t.has("acct") and not t.has("rc") and not t.has("mail") and not t.has("net"):  # Toolbox tickets keep "Done" / "Hold" in that order
		_shuffle_options(t)
	for st in t.get("steps", []):
		if st.has("options"):  # console steps ("actions") keep their admin-console order
			_shuffle_options(st)
	return t


# ---------------------------------------------------------------- phishing
## Done in Toolbox > Mail Console: find the reported email in today's message trace, read its headers,
## then delete a phish from every mailbox and block what fits (the scammer's address, the attacker's
## own domain, or the link; never a whole shared or genuine domain), release a legit email that was
## quarantined, or change nothing and hold when only a phone call to the sender can settle it.
const SUPPLIERS := [["Northgate Supplies", "northgatesupplies.com"], ["Copperleaf Catering", "copperleafcatering.com"],
	["Harbourline Cleaning", "harbourlinecleaning.com"]]


func _make_phish(c: Dictionary) -> Dictionary:
	var d: String = c.domain
	var roll := rng.randf()
	var kind := "phish" if roll < 0.55 else ("legit" if roll < 0.85 else "hold")
	var sup: Array = _pick(SUPPLIERS)
	var others: Array = []  # colleagues who got the same email
	while others.size() < 3:
		var n := "%s %s" % [_pick(FIRST), _pick(LAST)]
		if n != c.user and not n in others:
			others.append(n)
	var no := {"addr": [0, ""], "domain": [0, ""], "url": [0, ""]}
	var m := {"id": 1, "reply_to": "(none)", "links": "(none)", "url_host": "", "attach": "(none)", "note": "",
		"recips": [{"name": c.user, "folder": "Inbox"}]}
	var goal := {"id": 1, "kind": kind, "release": false, "hold_why": "", "blocks": no}
	var explain := ""
	var v := rng.randi() % 4
	if kind == "legit":
		var legit_bad := "Blocked a legitimate sender. Nothing about this email needed blocking"
		goal.blocks = {"addr": [-1, legit_bad], "domain": [-1, legit_bad], "url": [-1, legit_bad]}
		if v % 2 == 0:
			m.merge({"from_name": sup[0], "from_addr": "messaging-service@post.xero.com", "reply_to": "accounts@%s" % sup[1],
				"subject": "Invoice INV-%d from %s" % [rng.randi_range(4000, 9999), sup[0]],
				"auth": "SPF=pass  DKIM=pass (post.xero.com)  DMARC=pass", "links": "in.xero.com/…", "url_host": "in.xero.com",
				"note": "Quarantined (verdict: phish). %s is in the vendor list; the amount matches PO %d" % [sup[0], rng.randi_range(1000, 4999)]}, true)
			m.recips[0].folder = "Quarantine"
			goal.release = true
			explain = "Legit, and the filter got it wrong. SPF, DKIM and DMARC all pass for post.xero.com (Xero sends invoices for its customers), the link goes to xero.com, and it matches a real PO. Release it, block nothing, and you can report the false positive to Microsoft."
		else:
			var grp: String = "Finance" if v == 1 else "Projects"
			m.merge({"from_name": "Microsoft on behalf of %s" % c.client, "from_addr": "MSSecurity-noreply@microsoft.com",
				"subject": "Action required: review access to the %s group" % grp, "auth": "SPF=pass  DKIM=pass (microsoft.com)  DMARC=pass",
				"links": "myaccess.microsoft.com/…", "url_host": "myaccess.microsoft.com",
				"note": "Your team started this quarter's Entra access review of the %s group this morning (ticket in PSA); %s is a reviewer" % [grp, c.first]}, true)
			explain = "Legit. Entra access reviews email reviewers from MSSecurity-noreply@microsoft.com \"on behalf of\" the organisation, auth passes for microsoft.com, the link is Microsoft's own My Access portal, and it matches the review your team started this morning. Nothing to delete or block: tell %s it's safe to do the review." % c.first
	elif kind == "hold":
		m.merge({"from_name": "%s Accounts" % sup[0], "from_addr": "accounts@%s" % sup[1], "reply_to": "accounts@%s" % sup[1],
			"subject": "Change of bank details for future payments", "auth": "SPF=pass  DKIM=pass (%s)  DMARC=pass" % sup[1],
			"attach": "Bank_details_letter.pdf (scanned clean)", "note": "%s is in the vendor list; a payment run to them is due this week" % sup[0]}, true)
		goal.hold_why = "a change of bank details must be confirmed by phoning %s on a number you already have (not one in the email) before anything is paid. Passing SPF, DKIM and DMARC only proves it came from their mail system, and supplier mailboxes get hacked" % sup[0]
		explain = "Can't be settled from the headers. It really came from %s's mail system, but that's exactly what a hacked supplier mailbox looks like. Don't delete, release or block anything: hold it, and have accounts phone %s on the number already on file before changing any payment details." % [sup[0], sup[0]]
	else:
		var copies: int = rng.randi_range(1, 3)
		for i in copies:
			m.recips.append({"name": others[i], "folder": "Inbox"})
		var r := rng.randf()
		if r < 0.25:
			m.recips[-1].folder = "Junk"
		elif r < 0.5:
			m.recips[-1].folder = "Quarantine"  # the filter caught one copy: leave it there
		match v:
			0:
				m.merge({"from_name": "Microsoft 365", "from_addr": "alert@rnicrosoft-secure.com",
					"subject": "Password expires today: keep current password", "auth": "SPF=pass (rnicrosoft-secure.com)  DKIM=none  DMARC=none",
					"links": "rnicrosoft-secure.com/owa/login", "url_host": "rnicrosoft-secure.com"}, true)
				goal.blocks = {"addr": [0, ""], "url": [0, ""],
					"domain": [1, "rnicrosoft-secure.com wasn't blocked: it's the attacker's own lookalike domain, so block all of it, not just one address"]}
				explain = "Phish. \"rnicrosoft\" is r-n, not m. SPF passing only proves the lookalike domain sent it. Delete every copy and block the whole domain: the attacker owns it."
			1:
				var boss_last: String = _pick(LAST.filter(func(l: String) -> bool: return l != c.last))
				var addr := "ceo.%s@gmail.com" % boss_last.to_lower()
				m.merge({"from_name": "%s %s (CEO)" % [_pick(FIRST), boss_last], "from_addr": addr, "reply_to": addr,
					"subject": "Urgent: need gift cards for clients today", "auth": "SPF=pass  DKIM=pass (gmail.com)  DMARC=pass  [EXTERNAL]"}, true)
				goal.blocks = {"url": [0, ""],
					"addr": [1, "%s wasn't blocked: block the scammer's address" % addr],
					"domain": [-1, "Blocked all of gmail.com: that stops every customer and supplier who uses Gmail. Block the scammer's address instead"]}
				explain = "Phish (CEO fraud). The display name is the boss, but the address is a Gmail account, and it's urgent gift cards. Classic business email compromise. Delete every copy and block that one address, never gmail.com."
			2:
				var typo := d.replace(".com", "-accounts.co")  # lookalike of their own domain
				m.merge({"from_name": "Accounts", "from_addr": "accounts@%s" % typo, "reply_to": "payments@%s" % typo,
					"subject": "Updated bank details for next payment run", "auth": "SPF=softfail  DKIM=none  DMARC=none",
					"attach": "New_Bank_Details.pdf.html"}, true)
				goal.blocks = {"addr": [0, ""], "url": [0, ""],
					"domain": [1, "%s wasn't blocked: it's a lookalike of the client's own domain that the attacker owns, so block all of it" % typo]}
				explain = "Phish. A lookalike of their own domain, no DKIM or DMARC, SPF soft-fails, a bank-detail change by email, and a .pdf.html attachment (a web page posing as a PDF). Delete every copy and block the lookalike domain."
			_:
				var first: String = _pick(FIRST)
				var last: String = _pick(LAST)
				var host := "%s-docs.web.app" % sup[1].get_slice(".", 0)
				m.merge({"from_name": "%s %s" % [first, last], "from_addr": "%s.%s@%s" % [first.to_lower(), last.to_lower(), sup[1]],
					"subject": "Shared file: statement of account", "auth": "SPF=pass  DKIM=pass (%s)  DMARC=pass" % sup[1],
					"links": "%s/statement (opens a Microsoft 365 sign-in page)" % host, "url_host": host,
					"note": "%s is in the vendor list. They normally send statements as PDF attachments" % sup[0]}, true)
				goal.blocks = {"addr": [0, ""],
					"url": [1, "%s wasn't blocked: the fake sign-in page is the attack, so block the link" % host],
					"domain": [-1, "Blocked %s: they're a real supplier whose mailbox was hacked, so their genuine invoices would be blocked too. Block the link and tell them" % sup[1]]}
				explain = "Phish from a real supplier's hacked mailbox. SPF, DKIM and DMARC pass because it really came from their account. The giveaway is the link: a free web.app host showing a Microsoft 365 sign-in page. Delete every copy, block the link (not their domain), and phone %s on a known number so they can secure the mailbox." % sup[0]
	# Today's other mail to the reporter: find the one they mean
	var pool: Array = [
		{"from_name": others[0], "from_addr": "%s@%s" % [(others[0].substr(0, 1) + others[0].get_slice(" ", 1)).to_lower(), d],
			"subject": "Team lunch Friday?", "auth": "Internal (sent from your own organisation)"},
		{"from_name": "Brightline Office", "from_addr": "orders@brightlineoffice.com", "subject": "Your order #%d has shipped" % rng.randi_range(20000, 99999),
			"auth": "SPF=pass  DKIM=pass (brightlineoffice.com)  DMARC=pass", "links": "brightlineoffice.com/track/…", "url_host": "brightlineoffice.com"},
		{"from_name": "%s Payroll" % c.client, "from_addr": "payroll@%s" % d, "subject": "Timesheets due by Friday",
			"auth": "Internal (sent from your own organisation)"},
	]
	_shuffle(pool)
	var msgs: Array = [m]
	for i in rng.randi_range(2, 3):
		var x: Dictionary = pool[i]
		x.merge({"id": i + 2, "reply_to": "(none)", "links": "(none)", "url_host": "", "attach": "(none)", "note": "",
			"recips": [{"name": c.user, "folder": "Inbox"}]})
		msgs.append(x)
	var mins: Array = []
	while mins.size() < msgs.size():
		var t := rng.randi_range(7 * 60 + 30, 11 * 60 + 50)
		if not t in mins:
			mins.append(t)
	mins.sort()
	mins.reverse()  # newest first, like a message trace
	_shuffle(msgs)
	for i in msgs.size():
		@warning_ignore("integer_division")
		msgs[i].time = "%d:%02d" % [mins[i] / 60, mins[i] % 60]
	var held: bool = m.recips[0].folder == "Quarantine"
	return {
		"priority": 2,
		"subject": "Can you release this email?" if held else "Is this email legit?",
		"body": ("%s got a quarantine notice for \"%s\" from %s: \"We're expecting this one, can you release it?\"" if held
			else "%s reported \"%s\" from %s: \"Not sure about this one, can you check it before anyone clicks anything?\"") % [c.first, m.subject, m.from_name],
		"info_title": "Report",
		"info": "Reported by:  %s\nSubject:      %s\nReceived:     today %s\nLook it up:   Mail Console tab (message trace)" % [c.user, m.subject, m.time],
		"mail": {"reporter": c.user, "msgs": msgs, "done": [], "goal": goal},
		"question": "On the Mail Console tab (T): deal with the email, or hold",
		"options": [
			"Done: dealt with in the Mail Console. Tell %s the outcome" % c.first,
			"Hold: change nothing. Get it confirmed with the sender on a phone number you already have",
		],
		"answer": 1 if kind == "hold" else 0,
		"explain": explain + (" Never reply to a suspected phish; verify by a known phone number." if kind == "phish" else ""),
	}


# ---------------------------------------------------------------- account lockout
## Done in Toolbox > Accounts: check the callback number against the mobile on file, then either
## unlock + reset + require a change at next sign-in, or touch nothing and refuse.
func _make_lockout(c: Dictionary) -> Dictionary:
	var genuine := rng.randf() < 0.65
	var exec := rng.randf() < 0.3
	var title: String = "Director" if exec else _pick(["Office Manager", "Accounts", "Reception", "Project Lead"])
	var acct := _directory(c, title)
	var u: Dictionary = acct.users[acct.target]
	var on_file: String = u.mobile
	var rang := on_file
	if not genuine:
		rang = "%04d" % ((int(on_file) + rng.randi_range(11, 8000)) % 10000)
	u.locked = true
	u.pwd = "last set %d days ago" % rng.randi_range(20, 80)  # before the holidays they mention
	u.lock_info = "today 08:%02d after 5 bad passwords" % rng.randi_range(5, 55)
	acct.orig = acct.users.duplicate(true)
	acct.goal = {"hold": not genuine, "sam": c.sam, "unlock": true, "reset": true, "must_change": true, "add": [],
		"hold_why": "the callback number isn't the one on file, so the caller was never verified"}
	acct.erase("target")
	return {
		"priority": 1 if exec else 2,
		"subject": "Locked out of my account",
		"body": "%s (%s) is on the phone: \"I've been locked out. I think I forgot my password over the holidays, and I've got a meeting in ten minutes!\"" % [c.user, title],
		"info_title": "Call notes",
		"info": "Caller:     says they're %s (%s)\nCallback:   we rang the mobile ending %s that the caller gave us;\n            they answered and confirmed the request\nPolicy:     only act if the callback number matches the mobile\n            on file (Accounts tab)" % [c.user, title, rang],
		"acct": acct,
		"question": "Check the caller on the Accounts tab (T) and fix it there, or refuse",
		"options": [
			"Done: I've fixed the account in Accounts",
			"Refuse: touch nothing, call back on the number on file, flag to security",
		],
		"answer": 1 if acct.goal.hold else 0,
		"explain": ("The callback number is the mobile on file, so the caller is verified. Unlock, reset the password and require a change at next sign-in so only they know the new one."
			if genuine else
			"The mobile on file ends %s, not %s. Calling back a number the caller gives you proves nothing: refuse, call back on the number on file and flag it to security." % [on_file, rang]),
	}


# ---------------------------------------------------------------- file share access
## Done in Toolbox > Accounts: tick the right group for the right user, or hold for approval.
func _make_share(c: Dictionary) -> Dictionary:
	var dept: String = _pick(["Finance", "HR", "Projects", "Marketing"])
	var edit := rng.randf() < 0.5
	var approved := rng.randf() < 0.75
	var manager := "%s %s" % [_pick(FIRST), _pick(LAST)]
	var right := "GG_%s_%s" % [dept, "Modify" if edit else "Read"]
	var acct := _directory(c, _pick(["Office Manager", "Accounts", "Reception", "Project Lead", "Designer"]), dept)
	acct.orig = acct.users.duplicate(true)
	acct.goal = {"hold": not approved, "sam": c.sam, "unlock": false, "reset": false, "must_change": false, "add": [right],
		"hold_why": "nobody who owns the %s data approved it" % dept}
	acct.erase("target")
	var approval_line := "Approved by %s (%s manager) in the PSA" % [manager, dept] if approved else "Approval: none. %s says \"my manager's fine with it\"" % c.first
	return {
		"priority": 3,
		"subject": "Need access to the %s share" % dept,
		"body": "%s needs to %s files in \\\\FS01\\%s." % [c.user, "edit" if edit else "view", dept],
		"info_title": "Request",
		"info": "Share:     \\\\FS01\\%s\nNTFS:      GG_%s_Read (Read & execute), GG_%s_Modify (Modify)\nAsked for: %s access for %s\n%s" % [dept, dept, dept, "edit" if edit else "read-only", c.user, approval_line],
		"acct": acct,
		"question": "Grant it on the Accounts tab (T), or hold it",
		"options": [
			"Done: I've granted it in Accounts",
			"Hold: change nothing, get the %s manager's approval first" % dept,
		],
		"answer": 1 if acct.goal.hold else 0,
		"explain": ("Least privilege: approved, so add %s to %s and nothing more. They sign out and back in for the new group to apply." % [c.first, right] if approved
			else "No approval from the data owner. Get it in writing before granting access, however small."),
	}


## A small user directory for Toolbox > Accounts: the ticket's user plus four colleagues (one with
## the same first name, so you have to open the right profile). `dept` keeps the target out of
## that department's groups. Returns {users, groups, target (index)}.
func _directory(c: Dictionary, title: String, dept := "") -> Dictionary:
	var prefix: String = c.domain.substr(0, 3).to_upper()
	var depts: Array = ["Finance", "HR", "Projects", "Marketing"]
	var groups: Array = ["GG_Staff"]
	for d in depts:
		groups.append_array(["GG_%s_Read" % d, "GG_%s_Modify" % d])
	groups.append("Domain Admins")
	var names: Array = [[c.first, c.last]]
	var guard := 0
	while names.size() < 5 and guard < 200:
		guard += 1
		var f: String = c.first if names.size() == 1 else _pick(FIRST)  # a namesake to tell apart
		var l: String = _pick(LAST)
		var sam := (f.substr(0, 1) + l).to_lower()
		var clash := false
		for n in names:
			if (n[0].substr(0, 1) + n[1]).to_lower() == sam:
				clash = true
		if not clash:
			names.append([f, l])
	var users: Array = []
	var pcs: Array = range(1, 30)
	for i in names.size():
		var f: String = names[i][0]
		var l: String = names[i][1]
		var sam := (f.substr(0, 1) + l).to_lower()
		var g: Array = ["GG_Staff"]
		var home: String = _pick(depts)
		if not (i == 0 and home == dept):
			g.append("GG_%s_%s" % [home, _pick(["Read", "Modify"])])
		var pc: int = pcs.pop_at(rng.randi() % pcs.size())
		users.append({
			"name": "%s %s" % [f, l], "sam": sam, "upn": "%s@%s" % [sam, c.domain],
			"title": title if i == 0 else _pick(["Office Manager", "Accounts", "Reception", "Project Lead", "Designer", "Admin Officer"]),
			"locked": false, "lock_info": "", "pwd": "last set %d days ago" % rng.randi_range(3, 80),
			"reset": false, "must_change": false, "mobile": "%04d" % rng.randi_range(0, 9999),
			"methods": "Authenticator app (%s)" % _pick(["iPhone 15", "Pixel 8", "Galaxy S23", "iPhone 13"]),
			"licence": _pick(["Microsoft 365 Business Premium", "Microsoft 365 Business Standard"]),
			"device": "%s-PC%02d (Windows 11)" % [prefix, pc],
			"groups": g,
		})
	# Shuffle so the caller isn't always first in the list.
	var target_sam: String = users[0].sam
	for i in range(users.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = users[i]
		users[i] = users[j]
		users[j] = tmp
	var target := 0
	for i in users.size():
		if users[i].sam == target_sam:
			target = i
	return {"users": users, "groups": groups, "target": target}


# ---------------------------------------------------------------- printer
## Done in Toolbox > Network Map (scripts/netmap.gd): the queues on PRINT01, the switch ports, FW01's
## DHCP leases and the caller at the printer. Find why nothing prints, then fix it: cancel the failed
## job, resume a paused queue, re-point the port at the printer's new DHCP address (and reserve it), get
## the cable plugged back in or the spare toner fitted (Done), or order toner / log a vendor call (Hold).
const PRINTERS := ["MFP-RECEPTION", "MFP-LEVEL1", "MFP-ACCOUNTS", "MFP-LEVEL2"]
const FAULTS := ["job", "paused", "ip", "cable", "toner_spare", "toner_order", "fuser"]


func _make_printer(c: Dictionary) -> Dictionary:
	var fault: String = _pick(FAULTS)
	var names: Array = PRINTERS.duplicate()
	_shuffle(names)
	var mins := rng.randi_range(20, 55)
	var jobs := rng.randi_range(12, 40)
	var users := rng.randi_range(5, 14)
	var mfps: Array = []
	for i in 2:
		var mac := "02:5c:a1:%02x:%02x:%02x" % [rng.randi_range(16, 255), rng.randi_range(0, 255), rng.randi_range(0, 255)]
		mfps.append({"name": names[i], "ip": "192.168.10.%d" % (50 + i), "port_ip": "192.168.10.%d" % (50 + i),
			"mac": mac, "dhcp": false, "link": true, "down_since": "", "sw_port": 14 + i, "state": "ready",
			"paused": false, "stuck": {}, "jobs": 0, "oldest": 0, "black": rng.randi_range(25, 90),
			"cmy": [rng.randi_range(20, 95), rng.randi_range(20, 95), rng.randi_range(20, 95)],
			"last_job": "today %d:%02d" % [rng.randi_range(8, 9), rng.randi_range(0, 59)]})
	var t: Dictionary = mfps[0]
	var other: Dictionary = mfps[1]
	t.jobs = jobs
	t.oldest = mins
	t.last_job = "yesterday 17:%02d" % rng.randi_range(0, 30)
	var new_ip := ""
	match fault:
		"job":
			t.stuck = {"doc": _pick(["Invoices_Q3.pdf", "Price_list_scan.pdf", "Plans_full_set.pdf"]), "mb": rng.randi_range(300, 900)}
		"paused":
			t.paused = true
		"ip":
			t.dhcp = true
			new_ip = "192.168.10.%d" % rng.randi_range(100, 199)
			t.ip = new_ip
		"cable":
			t.link = false
			t.down_since = "since 17:%02d yesterday" % rng.randi_range(35, 55)
		"toner_spare", "toner_order":
			t.state = "toner"
			t.black = 0
		"fuser":
			t.state = "fuser"
	var spare: bool = fault == "toner_spare" or (fault != "toner_order" and rng.randf() < 0.5)
	# FW01's DHCP leases: laptops and phones, plus the printer when it's the one that moved
	var leases: Array = []
	var used := {}
	if fault == "ip":
		used[new_ip] = true
	var hosts: Array = ["%s-LT%02d" % [c.domain.substr(0, 3).to_upper(), rng.randi_range(1, 30)], "PHONE-%s" % _pick(FIRST).to_upper(),
		"%s-LT%02d" % [c.domain.substr(0, 3).to_upper(), rng.randi_range(31, 60)], "MEETING-ROOM-TV"]
	for h in hosts:
		var ip := new_ip
		while used.has(ip) or ip == "":
			ip = "192.168.10.%d" % rng.randi_range(100, 199)
		used[ip] = true
		leases.append({"ip": ip, "host": h, "reserved": false, "when": "leased %s" % _pick(["Mon 08:41", "Tue 09:02", "yesterday 08:15", "today 08:20"]),
			"mac": "%02x:%02x:%02x:%02x:%02x:%02x" % [rng.randi_range(0, 255) & 0xfc, rng.randi_range(0, 255), rng.randi_range(0, 255), rng.randi_range(0, 255), rng.randi_range(0, 255), rng.randi_range(0, 255)]})
	if fault == "ip":
		leases.insert(rng.randi_range(0, leases.size()), {"ip": new_ip, "host": t.name, "mac": t.mac, "reserved": false,
			"when": "leased today 07:%02d" % rng.randi_range(10, 50)})
	var changes: Array = ["Last week:  DHCP moved from DC01 to the new firewall, FW01"]
	if fault == "paused":
		changes.append("Last night: printer driver updated for %s on PRINT01 (queue paused for the update)" % t.name)
	else:
		changes.append("Last night: printer driver updated for %s on PRINT01, tested OK" % other.name)
	if rng.randf() < 0.5:
		changes.reverse()
	var hold := fault in ["toner_order", "fuser"]
	var hold_why := ("the black toner is on order and there's no spare onsite" if fault == "toner_order"
		else "the fuser has failed and needs the vendor's technician")
	var net := {"caller": c.first, "users": users, "mfps": mfps, "leases": leases, "changes": changes, "spare": spare,
		"done": [], "goal": {"fault": fault, "mfp": t.name, "other": other.name, "new_ip": new_ip, "hold": hold, "hold_why": hold_why}}
	if rng.randf() < 0.5:
		mfps.reverse()  # the broken one isn't always first on the map
	var explain: String = {
		"job": "PRINT01 could reach %s (ping replied, its web page said Ready and nothing received since yesterday), but one huge job had errored at the top of its queue and everything waited behind it. Cancel that job and the rest print. Restarting the spooler and clearing the spool folder is the last resort for a job that won't delete, and it throws away everyone's waiting jobs." % t.name,
		"paused": "The queue was paused for last night's driver update and never resumed, so Windows held every job. Resume printing on the queue. Restarting the spooler or the printer doesn't unpause a queue.",
		"ip": "DHCP moved to the new firewall last week. When %s's lease from DC01 came up for renewal and DC01 no longer answered, FW01 gave it a new address from its own range, %s, but the queue still sent to %s. Point the port at the new IP, then add a DHCP reservation so it can't move again." % [t.name, new_ip, t.port_ip],
		"cable": "%s's switch port went down at %s, when the desks were moved round it, and its panel said no cable. The cable had been knocked out of the wall socket; once it was back in, the link came up and the queue printed. Its IP never changed, so editing the port or DHCP wouldn't have helped." % [t.name, t.down_since.trim_prefix("since ")],
		"toner_spare": "%s was out of black toner, and there was a spare onsite, so %s fitted it and the queue carried on by itself. Ordering a replacement for the cupboard is fine; nothing on the server needed touching." % [t.name, c.first],
		"toner_order": "%s is out of black toner and the cupboard's empty: order it on the print contract and hold the ticket until it's fitted. The queue will carry on by itself; nothing on the server needs touching. Meanwhile people can print to %s." % [t.name, other.name],
		"fuser": "A fuser fault that comes back after a power cycle is a hardware failure for the vendor's technician, and on-site service is on the contract. Log the call and hold the ticket until they've been; meanwhile urgent jobs like the invoices can go to %s." % other.name,
	}[fault]
	return {
		"priority": 3,
		"subject": "Printer not printing",
		"body": "%s: \"Nothing's coming out of %s and accounts need invoices out today.\"" % [c.first, t.name],
		"info_title": "Call notes",
		"info": "Caller:    %s, at the office, on the phone\nPrinter:   %s, shared from PRINT01 to all %d people here\nSymptom:   jobs go to the queue but nothing comes out, for everyone\nOther:     %s is printing fine" % [c.user, t.name, users, other.name],
		"net": net,
		"question": "On the Network Map tab (T): find the fault and fix it, then close it here",
		"options": [
			"Done: it's printing again",
			"Hold: it's waiting on the vendor or a part. Tell the client",
		],
		"answer": 1 if hold else 0,
		"explain": explain,
	}


# ---------------------------------------------------------------- network
## The evidence starts hidden: the office is offline, so the tech is on the phone and the player types
## the commands the user runs in a simulated command prompt on their PC (scripts/terminal.gd) to find it. "term" holds the scenario the terminal plays out.
func _make_network(c: Dictionary) -> Dictionary:
	var v := rng.randi() % 3
	var fault: String = ["dns", "wan", "dhcp"][v]
	var host := "PC-%s" % c.sam.to_upper()
	var ip := ("169.254.%d.%d" % [rng.randi_range(1, 254), rng.randi_range(1, 254)] if fault == "dhcp"
		else "192.168.1.%d" % rng.randi_range(50, 199))
	var term := {
		"fault": fault, "ip": ip, "gw": "192.168.1.1", "dc": "192.168.1.10",
		"dns_name": "dc01.%s" % c.domain, "domain": c.domain, "host": host,
		"isp_hop": "100.64.%d.1" % rng.randi_range(0, 63), "ms": rng.randi_range(8, 24),
		"lease_ip": "192.168.1.%d" % rng.randi_range(50, 199),  # what ipconfig /renew gets once DHCP is fixed
	}
	return {
		"priority": 1,
		"subject": "The internet is down!",
		"body": "%s: \"Nobody in the office can get on the internet. Clients are waiting!\"" % c.first,
		"info_title": "On the phone: %s types what you read out (%s)" % [c.first, host],
		"info": "%s has a command prompt open on %s and will type whatever you tell them.\nRun a command below (try ipconfig, ping, nslookup, tracert).\n" % [c.first, host],
		"term": term,
		"prompt": "C:\\Users\\%s>" % c.sam,
		"question": "Where's the fault?",
		"options": [
			"DNS: the DC can't resolve outside names",
			"WAN/ISP: the internet link is down",
			"DHCP: PCs aren't getting a lease",
			"Reboot everyone's PC and see if it comes back",
		],
		"answer": v,
		"explain": ["IPs answer (ping 1.1.1.1 replies, tracert completes) but outside names don't resolve. nslookup shows the DC answering for its own domain but returning \"Server failed\" for everything else, so its forwarding is broken (nslookup google.com 8.8.8.8 works, proving it). Next: find out why it can't forward.",
			"The gateway replies but nothing past it does: ping 1.1.1.1 times out and tracert dies after hop 1. Names fail too, only because the DNS server can't reach the internet either. It's the WAN link. Next: find out why.",
			"ipconfig shows a 169.254 address with no gateway, and renewing the lease can't reach a DHCP server: the PC has no lease. Next: find out why the DHCP server isn't answering."][v],
		"step_name": "Diagnose",
		"steps": [_network_fix(fault, term, c.first), _network_verify(fault, c.first)],
	}


## Step 2 of a network ticket: you're now on the server/router, and the evidence says why it broke.
func _network_fix(fault: String, term: Dictionary, first: String) -> Dictionary:
	var sub := rng.randi() % 2
	var info := ""
	var options: Array = []
	var explain := ""
	match fault:
		"dns":
			options = [
				"Replace the dead forwarder with working resolvers, then clear the DNS server cache",
				"Allow DNS (UDP and TCP 53) out from DC01 on the firewall",
				"Point every PC's DNS straight at 8.8.8.8",
				"Run ipconfig /flushdns on every PC",
			]
			if sub == 0:
				info = "DNS Manager on DC01 > Forwarders:\n  203.0.113.53   <Timed out>   (old ISP's resolver; the client changed ISP last month)\n  Use root hints if no forwarders are available: off\nFirewall log: 192.168.1.10 -> 203.0.113.53 udp/53 ALLOW (no reply)"
				explain = "The only forwarder is the old ISP's resolver, which no longer answers, and root hints are off, so DC01 has nowhere to send outside lookups. Swap in working resolvers and clear the server cache. Pointing PCs at 8.8.8.8 would break Active Directory, which needs the DC for DNS."
			else:
				info = "DNS Manager on DC01 > Forwarders:\n  1.1.1.1   <Timed out>\n  8.8.8.8   <Timed out>\nFirewall log: 192.168.1.10 -> 1.1.1.1 udp/53 DENY (rule \"Servers: HTTPS out only\", added yesterday)\n              192.168.1.10 -> 8.8.8.8 udp/53 DENY (same rule)\n              %s -> 8.8.8.8 udp/53 ALLOW  (%s)" % [term.ip, term.host]
				explain = "The forwarders are fine, but yesterday's firewall rule only lets DC01 out on HTTPS, so its DNS queries are dropped (PCs can still reach 8.8.8.8, which is why that nslookup worked). Allow DNS out from the DC. Pointing PCs at 8.8.8.8 would break Active Directory."
		"wan":
			options = [
				"Log a fault with the ISP, fail over to the 4G/5G backup if there is one, and give the client an ETA",
				"Have someone onsite check the ISP modem's power and cabling before calling the ISP",
				"Factory-reset the office router",
				"Change DC01's DNS forwarders",
			]
			if sub == 0:
				info = "Router (%s) > WAN1:\n  Link: up   Public IP: none (no reply from the ISP)\n  ISP modem lights: power and line normal, internet off\nISP status page: outage reported in the client's area, ETA 2 hours" % term.gw
				explain = "The cable and modem are fine and the ISP has confirmed an outage. Log it so you're on their list, fail over to a backup link if the client has one, and tell the client the ETA. Factory-resetting the router just loses its config."
			else:
				info = "Router (%s) > WAN1:\n  Link: DOWN (no carrier)\n  ISP modem lights: all off\nISP status page: no known issues\nCabinet: router is on the UPS; the modem plugs into a separate power strip\nCall notes: the cleaners were in the network cabinet last night" % term.gw
				explain = "No carrier and a dark modem means it has no power, not an ISP fault. Get someone onsite to check the power and cable first; calling the ISP now wastes time and can cost a fee if they send a technician."
		_:  # dhcp
			options = [
				"Start the DHCP Server service and set it to restart on failure",
				"Authorise DC01's DHCP server in Active Directory",
				"Give every PC a static IP address",
				"Restart the office router",
			]
			if sub == 0:
				info = "DC01 > Services:\n  DHCP Server   Stopped   (Startup: Automatic, Recovery: Take No Action)\nSystem log, event 7031: the DHCP Server service terminated unexpectedly during last night's updates\nScope 192.168.1.50-192.168.1.199 (150 addresses): about 64 in use at yesterday's close"
				explain = "The DHCP Server service stopped and nothing restarted it. Start it and set its recovery options to restart on failure; PCs will pick up leases on their next retry or an ipconfig /renew. Static IPs for everyone is a maintenance nightmare."
			else:
				info = "DC01 > Services:\n  DHCP Server   Running\nSystem log, event 1046: the DHCP service has determined that it is not authorized to service clients on this network\nChange log: DHCP was migrated to DC01 from the old server last night"
				explain = "The service is running, but in an Active Directory domain a Windows DHCP server won't hand out leases until it's authorised in AD, and the migration missed that step. Authorise it (DHCP console > right-click the server > Authorize). Restarting the router won't help: DC01 is the DHCP server here, not the router."
	return {
		"name": "Fix",
		"info_add": ("\n--- %s opens the router's status page (http://%s) and reads it out ---\n%s\n" % [first, term.gw, info] if fault == "wan"
			else "\n--- You remote onto DC01 to find out why ---\n%s\n" % info),
		"question": "How do you fix it?",
		"options": options,
		"answer": sub,
		"explain": explain,
	}


## Step 3 of a network ticket: back on the PC's command prompt (now healed), prove the fix worked.
## The proof is the test that failed before; the wrong options all passed while it was still broken.
func _network_verify(fault: String, first: String) -> Dictionary:
	var options: Array = []
	var explain := ""
	match fault:
		"dns":
			options = [
				"nslookup google.com now gets an answer from DC01",
				"ping 1.1.1.1 replies",
				"nslookup google.com 8.8.8.8 answers",
				"ping dc01 replies",
			]
			explain = "The test that failed before has to pass now: DC01 itself resolving an outside name. Pinging 1.1.1.1, asking 8.8.8.8 and pinging DC01 all worked while it was broken, so they prove nothing. nslookup asks DC01 directly, so a stale entry in the PC's own cache can't mislead you."
		"wan":
			options = [
				"ping 1.1.1.1 replies and tracert gets past the gateway",
				"ping 192.168.1.1 (the router) replies and nslookup dc01 answers",
				"tracert dc01 completes",
				"ipconfig shows a 192.168.1.x address and a gateway",
			]
			explain = "The link was the fault, so prove traffic gets past the router: an outside address replies and tracert goes beyond hop 1. The router, DC01 and the PC's address all worked during the outage."
		_:  # dhcp
			options = [
				"After ipconfig /renew: a 192.168.1.x lease with a gateway, and ping 1.1.1.1 replies",
				"ipconfig still shows 169.254: the fix didn't work, escalate it",
				"DC01's DHCP Server service shows Running and the scope has free addresses",
				"ping 127.0.0.1 replies",
			]
			explain = "The PC keeps its 169.254 address until it asks again (Windows retries every few minutes), so have them run ipconfig /renew. A real lease with a gateway, then a reply from outside, proves clients get addresses. The service and scope status don't prove that, and loopback answers even with no network."
	return {
		"name": "Verify",
		"info_add": "\n--- %s Back on the phone with %s: prove it from their PC before you close it ---\n" % [
			"Later: the internet link is back up." if fault == "wan" else "Fix applied on DC01.", first],
		"question": "Which result proves it's fixed?",
		"options": options,
		"answer": 0,
		"explain": explain,
		"live": true,
		"term_fault": "renew" if fault == "dhcp" else "ok",
	}


# ---------------------------------------------------------------- M365 licence
## Done in Toolbox > Accounts: give the new starter the cheapest licence that covers their needs.
## Sometimes that licence has none spare: free one from a leaver whose mailbox is already a shared
## mailbox, or (no leaver) hold until the client approves buying one.
const SKUS := ["Microsoft 365 Business Basic", "Microsoft 365 Business Standard", "Microsoft 365 Business Premium"]


func _make_licence(c: Dictionary) -> Dictionary:
	var tier := rng.randi_range(0, 2)
	var sku: String = SKUS[tier]
	var stock: String = _pick(["spare", "spare", "leaver", "buy"])
	var acct := _directory(c, "New starter")
	var users: Array = acct.users
	var mgr := ""
	var guard := 0
	while mgr == "" and guard < 200:  # someone whose surname isn't in the directory, to avoid mix-ups
		guard += 1
		var l: String = _pick(LAST)
		mgr = "%s %s" % [_pick(FIRST), l]
		for x in users:
			if x.name.ends_with(" " + l):
				mgr = ""
	if mgr == "":
		mgr = "the client's manager"
	var u: Dictionary = users[acct.target]
	u.licence = "None"
	u.pwd = "temporary, set by onboarding (starts Monday)"
	u.must_change = true
	u.methods = "None yet (registers on day one)"
	u.groups = ["GG_Staff"]
	if tier == 0:
		u.device = "None (no PC, works from their phone)"
	var free := ""
	if stock == "leaver":
		var pool: Array = users.filter(func(x: Dictionary) -> bool: return not x.name.begins_with(c.first + " "))
		var l: Dictionary = pool[rng.randi() % pool.size()]  # not the namesake: that stays a trap
		l.licence = sku
		l.left = "left %d weeks ago. Mailbox converted to a shared mailbox (under 50 GB, no hold, no archive); OneDrive files handed to their manager" % rng.randi_range(2, 6)
		l.title = "Former staff"
		l.methods = "Removed at offboarding"
		l.device = "Returned"
		l.groups = []
		free = l.sam
	var skus: Array = []
	for k in SKUS:
		var in_dir := 0
		for x in users:
			if x.licence == k:
				in_dir += 1
		var spare_n: int = rng.randi_range(1, 3)
		if SKUS.find(k) >= tier and stock != "spare":
			spare_n = 0  # nothing spare at or above the tier they need, so there's only one right path
		var others: int = rng.randi_range(3, 18) if k != SKUS[0] else rng.randi_range(0, 6)
		skus.append({"name": k, "total": others + in_dir + spare_n, "others": others})
	acct.skus = skus
	acct.orig = users.duplicate(true)
	var short: String = sku.trim_prefix("Microsoft 365 ")
	acct.goal = {"hold": stock == "buy", "sam": c.sam, "unlock": false, "reset": false, "must_change": true, "add": [],
		"licence": sku, "free": free,
		"hold_why": "there's no spare %s, and buying one needs %s's approval" % [short, mgr]}
	acct.erase("target")
	var needs: String = [
		"email and Teams on their phone, Word and Excel in the browser.\n          No PC",
		"email, Teams, desktop Word, Excel and Outlook on a laptop.\n          The client doesn't use Intune or Defender for Business",
		"email, Teams, desktop Word, Excel and Outlook. The new laptop\n          must be Intune-managed with Defender for Business",
	][tier]
	var why: String = [
		"Business Basic has email, Teams and the web and mobile Office apps: all they need. Standard and Premium would pay for desktop apps they won't use.",
		"Desktop Office apps need Business Standard or Premium. Premium adds Intune and Defender for Business, which this client doesn't use, so Standard is the cheapest fit.",
		"Desktop apps plus Intune and Defender for Business means Business Premium. Standard has the desktop apps but neither of those.",
	][tier]
	var leaver_name := ""
	for x in users:
		if x.sam == free:
			leaver_name = x.name
	var how: String = {
		"spare": "There was a spare one: assign it to %s, not their namesake." % c.first,
		"leaver": "None spare, but %s has left and their mailbox is already a shared mailbox under 50 GB with no hold or archive, and their OneDrive files were handed over, so it needs no licence: remove theirs, then assign it to %s." % [leaver_name, c.first],
		"buy": "None spare and no leaver to free one from, so hold and ask %s to approve buying one. A cheaper licence that doesn't cover the needs isn't a fix, and never take one from someone who still works there." % mgr,
	}[stock]
	return {
		"priority": 3,
		"subject": "New starter Monday",
		"body": "%s (Office Manager): \"%s starts Monday. Their account's set up, can you get them licensed?\"" % [mgr, c.user],
		"info_title": "Request",
		"info": "Starter:  %s (account created, no licence yet)\nNeeds:    %s\nPolicy:   the cheapest licence that covers it. Buying more\n          needs %s's approval" % [c.user, needs, mgr],
		"acct": acct,
		"question": "License them on the Accounts tab (T), or hold",
		"options": [
			"Done: I've licensed them in Accounts",
			"Hold: assign nothing, ask %s to approve buying one" % mgr,
		],
		"answer": 1 if acct.goal.hold else 0,
		"explain": "%s %s" % [why, how],
	}


# ---------------------------------------------------------------- MFA fatigue
## Two steps: read the logs to work out whether MFA held, then contain it in the admin console by
## ticking the actions the account needs (desk.gd draws "actions" as a checklist with an Apply button).
## need: 1 = must do, 0 = fine either way, -1 = wrong (weakens security or deletes the user's own data).
func _make_mfa(c: Dictionary) -> Dictionary:
	var got_in := rng.randf() < 0.5
	var start_min := rng.randi_range(5, 20)
	var tries := rng.randi_range(9, 24)
	var ip := "203.0.113.%d" % rng.randi_range(2, 250)
	var upn := "%s@%s" % [c.sam, c.domain]
	var phones := ["iPhone 15", "Pixel 8", "Galaxy S23", "iPhone 13"]
	var own: String = _pick(phones)
	phones.erase(own)
	var rogue: String = _pick(phones)
	var rule: String = _pick(["invoice", "payment", "bank"])
	var approved := start_min + 18
	var info := "Entra sign-ins:  %s\nFrom:            %s (hosting provider, never seen before)\nAttempts:        %d, 02:%02d-02:%02d, password correct each time\nMFA method:      Authenticator push (number matching)\n" % [upn, ip, tries, start_min, approved]
	if got_in:
		info += "MFA result:      denied x%d, APPROVED 02:%02d\n\nAudit 02:%02d:     User registered security info (Authenticator)\nExchange 02:%02d:  New-InboxRule\nCall notes:      a \"helpdesk\" caller read them a number to enter" % [tries - 1, approved, approved + 3, approved + 8]
	else:
		info += "MFA result:      denied x%d (every prompt)\n\nAudit log:       no changes to security info or mailbox rules\nCall notes:      %s denied them all; nobody else contacted them" % [tries, c.first]
	var console := "Sign-in:         allowed\n"
	if got_in:
		console += "Sessions:        signed in from %s since 02:%02d\nAuth methods:    Authenticator on %s (added last year)\n                 Authenticator on %s (added today 02:%02d)\nInbox rules:     \"Newsletters\" (last year): mail from news@ to Newsletters\n                 \".\" (today 02:%02d): mail containing \"%s\" to RSS Feeds" % [ip, approved, own, rogue, approved + 3, approved + 8, rule]
	else:
		console += "Sessions:        none from %s\nAuth methods:    Authenticator on %s (added last year)\nInbox rules:     \"Newsletters\" (last year): mail from news@ to Newsletters" % [ip, own]
	var actions: Array = [
		{"text": "Block sign-in", "need": 0},
		{"text": "Revoke all sessions (sign out everywhere)", "need": 1 if got_in else 0},
		{"text": "Reset password, change required at next sign-in", "need": 1},
	]
	if got_in:
		actions.append({"text": "Remove the Authenticator on %s (added today)" % rogue, "need": 1})
		actions.append({"text": "Delete inbox rule \".\" (\"%s\" mail to RSS Feeds)" % rule, "need": 1})
	actions.append({"text": "Delete inbox rule \"Newsletters\"", "need": -1})
	actions.append({"text": "Turn off MFA for this user until it settles down", "need": -1})
	actions.append({"text": "Add %s as a trusted location" % ip, "need": -1})
	return {
		"priority": 1,
		"subject": "Authenticator prompts I didn't start",
		"body": "%s: \"My phone kept buzzing with sign-in requests from about 2am. I wasn't logging in. What's going on?\"" % c.first,
		"info_title": "Sign-in + audit logs",
		"info": info,
		"question": "What's happened?",
		"options": [
			"Someone has the password, but MFA held and nobody got in",
			"The attacker got in: a push was approved and they've set up a foothold",
			"Nothing to worry about: an Authenticator app glitch",
			"The user's phone has malware that's sending the prompts",
		],
		"answer": 1 if got_in else 0,
		"explain": ("The 02:%02d approval let them in. Then they registered their own Authenticator and made an inbox rule, so they keep access and hide replies. Never enter a number someone gives you. Next: contain it in the admin console." % approved if got_in
			else "Each push came after a correct password, so the password is compromised even though MFA held. The pushes came from an attacker's sign-in, not the phone. Next: lock it down in the admin console."),
		"step_name": "Diagnose",
		"steps": [{
			"name": "Contain",
			"info_add": "\n\n--- Admin console: %s ---\n%s\n" % [upn, console],
			"question": "Tick everything this account needs, then Apply",
			"actions": actions,
			"explain": ("Revoke the sessions and reset the password to throw them out, remove their Authenticator so they can't come back in, and delete their rule so replies stop being hidden. Blocking sign-in while you work is fine. Leave the user's own Newsletters rule, and never weaken MFA or trust the attacker's IP. Then check what was sent from the mailbox."
				if got_in else
				"Reset the password: the attacker knows it. MFA held and nothing was changed, so there's nothing of theirs to remove; revoking sessions or blocking sign-in is extra caution, not required. Leave the user's own Newsletters rule, and never weaken MFA or trust the attacker's IP. Conditional Access or phishing-resistant MFA would stop these prompts."),
		}],
	}


# ---------------------------------------------------------------- scanner driver
## Done in Toolbox > Remote Control: connect to the caller's PC (not their namesake's), read the
## hardware ID in Device Manager and the processor in Settings > About, then install the vendor
## driver for that model and architecture. Hold when the PC is ARM-based and the model has no
## ARM64 driver (x64 drivers can't load on Windows on Arm).
func _make_driver(c: Dictionary) -> Dictionary:
	var prefix: String = c.domain.substr(0, 3).to_upper()
	var models: Array = [
		{"model": "DS-410", "pid": "0410", "archs": ["x64", "x86"]},
		{"model": "DS-410W", "pid": "0411", "archs": ["x64"]},
		{"model": "DS-620", "pid": "0620", "archs": ["x64", "x86"]},
	]
	for m in models:
		if rng.randf() < 0.5:
			m.archs.insert(1, "ARM64")
	var m: Dictionary = _pick(models)
	var arch := "ARM64" if rng.randf() < 0.4 else "x64"
	var hold: bool = arch == "ARM64" and not "ARM64" in m.archs
	# The caller's PC, a colleague with the same first name, and two others
	var people: Array = [c.user, "%s %s" % [c.first, _pick(LAST.filter(func(l: String) -> bool: return l != c.last))]]
	while people.size() < 4:
		var n := "%s %s" % [_pick(FIRST), _pick(LAST)]
		if not n in people and not n.begins_with(c.first + " "):
			people.append(n)
	var nums: Array = range(1, 30)
	var pcs: Array = []
	for i in people.size():
		var a: String = arch if i == 0 else ("ARM64" if rng.randf() < 0.3 else "x64")
		pcs.append({
			"name": "%s-PC%02d" % [prefix, nums.pop_at(rng.randi() % nums.size())], "user": people[i], "arch": a,
			"cpu": "Snapdragon(R) X Plus - X1P42100 - Qualcomm(R) Oryon(TM) CPU   3.24 GHz" if a == "ARM64"
				else _pick(["13th Gen Intel(R) Core(TM) i5-1345U   1.60 GHz", "AMD Ryzen 5 7530U with Radeon Graphics   2.00 GHz", "12th Gen Intel(R) Core(TM) i7-12700   2.10 GHz"]),
			"has_device": i == 0,
		})
	var target: String = pcs[0].name
	_shuffle(pcs)  # the caller isn't always first in the list
	var said: String = "DS-620" if m.model == "DS-620" else "DS-410"  # users drop the W off the box
	var rc := {
		"pcs": pcs, "vendor": "Kestrel", "site": "support.kestrelscan.com",
		"device": {"name": "Kestrel Scanner", "vid": "2F7A", "pid": m.pid},
		"models": models, "installs": [],
		"goal": {"hold": hold, "pc": target, "model": m.model, "arch": arch,
			"hold_why": "the PC is ARM-based and Kestrel has no ARM64 driver for the %s. x64 drivers can't load on Windows on Arm" % m.model},
	}
	return {
		"priority": 3,
		"subject": "New scanner isn't working",
		"body": "%s: \"I plugged in our new Kestrel %s scanner but my PC won't find it. The scan app just says no scanner found.\"" % [c.user, said],
		"info_title": "Call notes",
		"info": "Caller:    %s, signed in on their PC now\nDevice:    Kestrel %s (so they say), USB, plugged in today\nSymptom:   scan app: \"No scanner found\"\nDrivers:   %s (vendor site)\nAccess:    they're happy for us to remote on" % [c.user, said, rc.site],
		"rc": rc,
		"question": "On the Remote Control tab (T): install the right driver, or hold",
		"options": [
			"Done: the right driver is installed and the scanner works",
			"Hold: install nothing; no driver exists for this PC. Tell the client and raise it with the vendor",
		],
		"answer": 1 if hold else 0,
		"explain": ("Device Manager shows Code 28 (no driver) with hardware ID PID_%s, which the vendor page says is the %s, and Settings shows an ARM-based processor. There's no ARM64 driver for it, and x64 drivers (kernel or user-mode) can't load on Windows on Arm, which needs ARM64 drivers: tell the client, ask Kestrel about an Arm driver, or swap the scanner for one that supports Arm." % [m.pid, m.model]
			if hold else
			"Device Manager shows Code 28 (no driver) with hardware ID PID_%s: that's the %s%s. Settings › About says %s, so the %s package. Always get drivers from the vendor's own site, never a \"driver updater\" ad." % [
				m.pid, m.model, ", whatever the caller calls it" if said != m.model else "",
				"ARM-based processor" if arch == "ARM64" else "x64-based processor", "ARM64" if arch == "ARM64" else "x64"]),
	}


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp


# ---------------------------------------------------------------- helpers
func _pick(a: Array):
	return a[rng.randi() % a.size()]


## Shuffle options so the right answer isn't always in the same slot.
func _shuffle_options(t: Dictionary) -> void:
	var opts: Array = t.options
	var right: String = opts[t.answer]
	for i in range(opts.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = opts[i]
		opts[i] = opts[j]
		opts[j] = tmp
	t.answer = opts.find(right)
