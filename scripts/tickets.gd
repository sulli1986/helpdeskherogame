extends RefCounted
## Ticket generator. Each ticket is a Dictionary:
##   kind, priority (1 = P1 .. 4 = P4), client, user, subject, body,
##   info_title, info (evidence shown in a monospace box), question,
##   options (Array[String]), answer (index into options), explain (shown after answering)
##   hints: three "Ask a Senior" nudges, each more specific (where to look, what the evidence means,
##   what to do); every step has its own. Each one the player reveals costs part of that step's pay.
##   Optional: term + prompt (a simulated command prompt the player types into; see terminal.gd)
##   Optional: steps (Array of later steps on the same ticket, each with name, info_add, question,
##   options, answer, explain). The top-level question is step 1; info_add is appended to the evidence
##   when that step opens. Each step pays out; a wrong step escalates the ticket. A step with
##   live = true reopens the command prompt; term_fault (if set) changes what the PC sees first.
## New ticket types: add a _make_<kind>() and list it in KINDS. Keep answers technically right;
## the players are often real IT people.

const KINDS := ["phish", "lockout", "share", "printer", "network", "licence", "mfa", "driver", "bitlocker"]

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
		if st.has("options") and not st.has("net"):  # console and Toolbox steps keep their order
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
	var hint2 := ""   # Ask a Senior: what the evidence means, then what to do
	var hint3 := ""
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
			hint2 = "Look past the quarantine verdict: SPF, DKIM and DMARC all pass for post.xero.com (an invoicing service suppliers send through), the link goes to xero.com, and the note says it matches a real PO."
			hint3 = "It's legitimate: Release from quarantine and block nothing, then press Done on the Ticket tab."
			explain = "Legit, and the filter got it wrong. SPF, DKIM and DMARC all pass for post.xero.com (Xero sends invoices for its customers), the link goes to xero.com, and it matches a real PO. Release it, block nothing, and you can report the false positive to Microsoft."
		else:
			var grp: String = "Finance" if v == 1 else "Projects"
			m.merge({"from_name": "Microsoft on behalf of %s" % c.client, "from_addr": "MSSecurity-noreply@microsoft.com",
				"subject": "Action required: review access to the %s group" % grp, "auth": "SPF=pass  DKIM=pass (microsoft.com)  DMARC=pass",
				"links": "myaccess.microsoft.com/…", "url_host": "myaccess.microsoft.com",
				"note": "Your team started this quarter's Entra access review of the %s group this morning (ticket in PSA); %s is a reviewer" % [grp, c.first]}, true)
			hint2 = "Auth passes for microsoft.com, the link goes to Microsoft's own My Access portal, and the note says your team started this review this morning."
			hint3 = "It's legitimate: don't delete, release or block anything. Press Done on the Ticket tab and tell %s it's safe." % c.first
			explain = "Legit. Entra access reviews email reviewers from MSSecurity-noreply@microsoft.com \"on behalf of\" the organisation, auth passes for microsoft.com, the link is Microsoft's own My Access portal, and it matches the review your team started this morning. Nothing to delete or block: tell %s it's safe to do the review." % c.first
	elif kind == "hold":
		m.merge({"from_name": "%s Accounts" % sup[0], "from_addr": "accounts@%s" % sup[1], "reply_to": "accounts@%s" % sup[1],
			"subject": "Change of bank details for future payments", "auth": "SPF=pass  DKIM=pass (%s)  DMARC=pass" % sup[1],
			"attach": "Bank_details_letter.pdf (scanned clean)", "note": "%s is in the vendor list; a payment run to them is due this week" % sup[0]}, true)
		goal.hold_why = "a change of bank details must be confirmed by phoning %s on a number you already have (not one in the email) before anything is paid. Passing SPF, DKIM and DMARC only proves it came from their mail system, and supplier mailboxes get hacked" % sup[0]
		hint2 = "It passes SPF, DKIM and DMARC for %s's real domain, but it changes bank details. Passing auth only proves which mail system sent it, and supplier mailboxes get hacked." % sup[0]
		hint3 = "Change nothing in the Mail Console and press Hold, so accounts phone %s on a number already on file." % sup[0]
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
				hint2 = "Ignore the display name and read the sender's domain letter by letter. Does it really say microsoft?"
				hint3 = "\"rnicrosoft\" is r-n, not m: the attacker owns that domain. Delete it from every mailbox and block the domain rnicrosoft-secure.com, then Done."
				explain = "Phish. \"rnicrosoft\" is r-n, not m. SPF passing only proves the lookalike domain sent it. Delete every copy and block the whole domain: the attacker owns it."
			1:
				var boss_last: String = _pick(LAST.filter(func(l: String) -> bool: return l != c.last))
				var addr := "ceo.%s@gmail.com" % boss_last.to_lower()
				m.merge({"from_name": "%s %s (CEO)" % [_pick(FIRST), boss_last], "from_addr": addr, "reply_to": addr,
					"subject": "Urgent: need gift cards for clients today", "auth": "SPF=pass  DKIM=pass (gmail.com)  DMARC=pass  [EXTERNAL]"}, true)
				goal.blocks = {"url": [0, ""],
					"addr": [1, "%s wasn't blocked: block the scammer's address" % addr],
					"domain": [-1, "Blocked all of gmail.com: that stops every customer and supplier who uses Gmail. Block the scammer's address instead"]}
				hint2 = "The display name says it's the CEO. Look at the address it really came from, and at what it asks for."
				hint3 = "A Gmail address posing as the boss: delete it from every mailbox and block that one address (%s), never all of gmail.com. Then Done." % addr
				explain = "Phish (CEO fraud). The display name is the boss, but the address is a Gmail account, and it's urgent gift cards. Classic business email compromise. Delete every copy and block that one address, never gmail.com."
			2:
				var typo := d.replace(".com", "-accounts.co")  # lookalike of their own domain
				m.merge({"from_name": "Accounts", "from_addr": "accounts@%s" % typo, "reply_to": "payments@%s" % typo,
					"subject": "Updated bank details for next payment run", "auth": "SPF=softfail  DKIM=none  DMARC=none",
					"attach": "New_Bank_Details.pdf.html"}, true)
				goal.blocks = {"addr": [0, ""], "url": [0, ""],
					"domain": [1, "%s wasn't blocked: it's a lookalike of the client's own domain that the attacker owns, so block all of it" % typo]}
				hint2 = "Compare the sender's domain with the client's own (%s), then read the attachment's full name." % d
				hint3 = "%s is a lookalike the attacker owns: delete it from every mailbox and block that domain, then Done." % typo
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
				hint2 = "Auth passes, so it really came from %s's mailbox. So where does the link go, and how do they normally send statements?" % sup[0]
				hint3 = "Their mailbox was hacked: delete it from every mailbox and block the link %s, not their domain. Then Done, and phone %s on a known number." % [host, sup[0]]
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
		"hints": ["Open the Mail Console and find the email %s means in today's message trace: match the subject and the time (%s). Then read its headers." % [c.first, m.time],
			hint2, hint3],
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
		"hints": [
			"Verify the caller before you change anything: open %s in Accounts (watch for a colleague with the same first name) and compare their mobile on file with the number we called back." % c.user,
			("The mobile on file ends %s, the number we called back. They're verified." % on_file if genuine
				else "The mobile on file ends %s, but we called back %s, a number the caller gave us. That proves nothing." % [on_file, rang]),
			("On %s's profile: Unlock, Reset password and turn on Require change at next sign-in. Then press Done on the Ticket tab." % c.user if genuine
				else "Change nothing in Accounts. Press Refuse on the Ticket tab, then call back on the number on file and flag it to security."),
		],
		"explain": ("The callback number is the mobile on file, so the caller is verified. Unlock, reset the password and require a change at next sign-in so only they know the new one."
			if genuine else
			"The mobile on file ends %s, not %s. Calling back a number the caller gives you proves nothing: refuse, call back on the number on file and flag it to security." % [on_file, rang]),
	}


# ---------------------------------------------------------------- file share access
## Done in Toolbox > Accounts: tick the right group for the right user, or hold for approval.
## Done in Toolbox > Accounts after checking Toolbox > Client Wiki: only the data's owner or their
## listed deputy can approve access to a share (not a line manager, not another department's owner).
## Approved by one of them: add the one group that fits (Read or Modify) and nothing else. Otherwise hold.
const DEPTS := ["Finance", "HR", "Projects", "Marketing"]


func _make_share(c: Dictionary) -> Dictionary:
	var wiki := wiki_page(c.client)
	var guard := 0
	while c.user in wiki.people and guard < 200:  # the requester isn't on the client's wiki page
		guard += 1
		c.first = _pick(FIRST)
		c.last = _pick(LAST)
		c.user = "%s %s" % [c.first, c.last]
		c.sam = (c.first.substr(0, 1) + c.last).to_lower()
	var depts: Array = DEPTS.duplicate()
	_shuffle(depts)
	var dept: String = depts[0]
	var own: Dictionary = wiki.owners[dept]
	var edit := rng.randf() < 0.5
	var roll := rng.randf()
	var who: String = "owner" if roll < 0.3 else ("deputy" if roll < 0.5 else ("other" if roll < 0.7 else ("lead" if roll < 0.85 else "none")))
	var approver := ""
	var other_dept := ""
	if who == "owner":
		approver = own.owner
	elif who == "deputy":
		approver = own.deputy
	elif who == "other":
		other_dept = depts[1]
		approver = wiki.owners[other_dept].owner
	elif who == "lead":
		guard = 0
		while guard < 200:
			guard += 1
			approver = "%s %s" % [_pick(FIRST), _pick(LAST)]
			if not approver.begins_with(c.first + " ") and not approver in wiki.people:
				break
	var approved := who in ["owner", "deputy"]
	var right := "GG_%s_%s" % [dept, "Modify" if edit else "Read"]
	var acct := _directory(c, _pick(["Office Manager", "Accounts", "Reception", "Project Lead", "Designer"]), dept)
	acct.orig = acct.users.duplicate(true)
	var hold_why := "nobody approved it, and only the %s data's owner (%s) or deputy (%s) can" % [dept, own.owner, own.deputy]
	if who == "other":
		hold_why = "%s owns the %s data, not %s, so their approval doesn't count" % [approver, other_dept, dept]
	elif who == "lead":
		hold_why = "%s isn't the %s data's owner or deputy on the Client Wiki, so their approval doesn't count" % [approver, dept]
	acct.goal = {"hold": not approved, "sam": c.sam, "unlock": false, "reset": false, "must_change": false, "add": [right],
		"hold_why": hold_why}
	acct.erase("target")
	var approval_line := "Approval:  none. %s says \"my manager's fine with it\"" % c.first
	if who == "lead":
		approval_line = "Approval:  %s in the PSA: \"Approved, I'm %s's team leader\"" % [approver, c.first]
	elif who != "none":
		approval_line = "Approval:  %s in the PSA: \"Approved\"" % approver
	var meaning := ""
	match who:
		"owner": meaning = "%s is the %s data's owner on the Client Wiki, so the approval counts." % [approver, dept]
		"deputy": meaning = "%s is listed as the %s data's deputy on the Client Wiki, so the approval counts." % [approver, dept]
		"other": meaning = "%s is on the Client Wiki, but as the owner of the %s data, not %s. That approval doesn't count here." % [approver, other_dept, dept]
		"lead": meaning = "%s isn't the %s data's owner or deputy on the Client Wiki. A team leader can't approve access to data they don't own." % [approver, dept]
		"none": meaning = "There's no approval at all. \"My manager's fine with it\" from the requester isn't approval from the %s data's owner." % dept
	meaning += " Read & execute is enough to view files; editing them needs Modify."
	var explain := ""
	if approved:
		explain = "%s is the %s data's %s on the Client Wiki, so it's approved. Least privilege: add %s to %s and nothing more. They sign out and back in for the new group to apply." % [
			approver, dept, who, c.first, right]
	else:
		var why := "Nobody has approved it"
		if who == "other":
			why = "%s owns the %s data, not %s" % [approver, other_dept, dept]
		elif who == "lead":
			why = "%s is a team leader, not the %s data's owner or deputy" % [approver, dept]
		explain = "%s. Only the data's owner or their deputy can approve access to it (Client Wiki), so change nothing and ask %s or %s to approve it in the PSA." % [
			why, own.owner, own.deputy]
	return {
		"priority": 3,
		"subject": "Need access to the %s share" % dept,
		"body": "%s needs to %s files in \\\\FS01\\%s." % [c.user, "edit" if edit else "view", dept],
		"info_title": "Request",
		"info": "Share:     \\\\FS01\\%s\nNTFS:      GG_%s_Read (Read & execute), GG_%s_Modify (Modify)\nAsked for: %s access for %s\n%s\nPolicy:    the data's owner or deputy approves (Client Wiki)" % [dept, dept, dept, "edit" if edit else "read-only", c.user, approval_line],
		"acct": acct,
		"wiki": true,
		"question": "Check the Client Wiki (W), then grant it in Accounts (T) or hold",
		"options": [
			"Done: I've granted it in Accounts",
			"Hold: change nothing, get the %s data owner's approval first" % dept,
		],
		"answer": 1 if acct.goal.hold else 0,
		"hints": [
			"Open the Client Wiki tab and find who owns the %s data and who their deputy is. Then compare with who approved this request, and note whether %s needs to view files or edit them." % [dept, c.first],
			meaning,
			("Open %s in Accounts (not their namesake), tick %s and nothing else, then press Done." % [c.user, right] if approved
				else "Change nothing in Accounts and press Hold: %s or %s has to approve it in the PSA first." % [own.owner, own.deputy]),
		],
		"explain": explain,
	}


## Toolbox > Client Wiki: each client's page, the same every time for that client (seeded from its
## name, not the shift). Who owns each department's data (and their deputy), the client's procedures.
## people = every name on the page, so tickets can pick someone who isn't on it.
const WIKI_ABOUT := {
	"Greenfield Wines": "Family winery with a tasting room and a small office", "Ironbridge Freight": "Road freight depot and dispatch office",
	"Maple & Stone Legal": "Law firm: partners, lawyers and support staff", "Clearwater Dental": "Dental practice with two treatment rooms and a front desk",
	"Oakline Architects": "Architecture studio working on big CAD and image files", "Summit Physio": "Physiotherapy clinic with a reception desk and treatment rooms",
	"Bluepeak Logistics": "Warehouse and logistics office", "Riverbend Realty": "Real estate agency: sales and property management",
}
const OWNER_TITLES := {"Finance": ["Finance Manager", "Senior Accountant"], "HR": ["HR Manager", "HR Advisor"],
	"Projects": ["Projects Manager", "Senior Project Lead"], "Marketing": ["Marketing Manager", "Marketing Coordinator"]}


static func wiki_page(client: String) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = client.hash()
	var domain := ""
	for c in CLIENTS:
		if c[0] == client:
			domain = c[1]
	var people: Array = []
	var sams: Array = []
	while people.size() < 9:  # a director, then an owner and a deputy for each department's data
		var f: String = FIRST[r.randi() % FIRST.size()]
		var l: String = LAST[r.randi() % LAST.size()]
		var sam := (f.substr(0, 1) + l).to_lower()
		if not sam in sams:
			sams.append(sam)
			people.append("%s %s" % [f, l])
	var owners := {}
	for i in DEPTS.size():
		var d: String = DEPTS[i]
		owners[d] = {"owner": people[1 + i * 2], "owner_title": OWNER_TITLES[d][0],
			"deputy": people[2 + i * 2], "deputy_title": OWNER_TITLES[d][1]}
	return {
		"client": client, "domain": domain, "about": WIKI_ABOUT.get(client, "Small business"),
		"hours": "%d:%s am to 5:%s pm, Monday to Friday" % [7 + r.randi() % 2, ["00", "30"][r.randi() % 2], ["00", "30"][r.randi() % 2]],
		"director": people[0], "owners": owners, "people": people,
		"servers": ["DC01: domain controller and DNS", "FS01: file server (the Finance, HR, Projects and Marketing shares)",
			"PRINT01: print server", "FW01: firewall and internet link"],
		"procedures": [
			"Access to a share: only that data's owner or their deputy (below) can approve it, in writing in the PSA. Nobody else can: not a line manager, a team leader, or another department's owner. Grant the least access that does the job.",
			"Identity checks before you act on a caller's request (unlock or reset their password, change their MFA, read out a BitLocker key): call back on the mobile on file in Accounts, never on a number the caller gives you. Containing a compromised account (reset the password, revoke sessions, remove the attacker's methods) doesn't wait for a callback: do it straight away.",
			"Supplier bank details: never change them because of an email. The client's accounts team confirms by phoning the supplier on the number already in their accounting system.",
		],
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
	var clue: String = {
		"job": "%s answers ping and its web page says Ready, but one job at the top of its queue has errored and everything is waiting behind it." % t.name,
		"paused": "The printer's fine: %s's queue on PRINT01 is paused. Recent changes says why." % t.name,
		"ip": "%s doesn't answer at %s any more. DHCP moved to FW01 last week: look for the printer in FW01's leases." % [t.name, t.port_ip],
		"cable": "%s's switch port shows no link since yesterday evening, so nothing can reach it." % t.name,
		"toner_spare": "%s's own screen and web page say it's out of black toner." % t.name,
		"toner_order": "%s's own screen and web page say it's out of black toner." % t.name,
		"fuser": "%s's panel shows E-542, a fuser fault, and it comes back after a power cycle: that's hardware." % t.name,
	}[fault]
	var fix: String = {
		"job": "Cancel job 1 on the queue, then press Done. Don't clear the spool folder: that loses everyone's jobs.",
		"paused": "Resume printing on the queue, then press Done.",
		"ip": "Change %s's port IP to %s, then Add reservation for its lease so it can't move again. Then press Done." % [t.name, new_ip],
		"cable": "Ask %s to check the printer's network cable at both ends, then press Done." % c.first,
		"toner_spare": "Ask %s to fit the spare black toner from the cupboard, then press Done." % c.first,
		"toner_order": "The cupboard's empty: order black toner on the print contract, then press Hold. People can use %s meanwhile." % other.name,
		"fuser": "Log a service call with the print vendor, then press Hold. Urgent jobs can go to %s." % other.name,
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
		"hints": ["Work from the queue outwards on the Network Map: open PRINT01 and look at %s's queue, then ping the printer and open its web page. Is it the queue, the network or the printer itself?" % t.name,
			clue, fix],
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
		"hints": [
			"Work outwards from the PC: ipconfig for its address and gateway, ping the gateway (192.168.1.1), ping an outside IP (1.1.1.1), then nslookup google.com to test names.",
			["Outside IPs answer, but names don't resolve through DC01. Try nslookup google.com 8.8.8.8 to compare.",
				"The gateway answers, but nothing past it does: ping 1.1.1.1 times out and tracert stops after the first hop.",
				"Look at the address: 169.254.x.x with no gateway means the PC never got a lease."][v],
			"Pick \"%s\"." % ["DNS: the DC can't resolve outside names", "WAN/ISP: the internet link is down", "DHCP: PCs aren't getting a lease"][v],
		],
		"explain": ["IPs answer (ping 1.1.1.1 replies, tracert completes) but outside names don't resolve. nslookup shows the DC answering for its own domain but returning \"Server failed\" for everything else, so its forwarding is broken (nslookup google.com 8.8.8.8 works, proving it). Next: find out why it can't forward.",
			"The gateway replies but nothing past it does: ping 1.1.1.1 times out and tracert dies after hop 1. Names fail too, only because the DNS server can't reach the internet either. It's the WAN link. Next: find out why.",
			"ipconfig shows a 169.254 address with no gateway, and renewing the lease can't reach a DHCP server: the PC has no lease. Next: find out why the DHCP server isn't answering."][v],
		"step_name": "Diagnose",
		"steps": [_network_fix(fault, term, c), _network_verify(fault, c.first)],
	}


## Step 2 of a network ticket: done in Toolbox > Network Map (netmap_office.gd). The diagnosis says
## what broke; the map shows why (ISP status, modem lights, FW01's links, rules and log, DC01's forwarders,
## DHCP console, services and event log) and has the fixes, plus traps. Closed Fixed / Hold (ISP outage).
func _network_fix(fault: String, term: Dictionary, c: Dictionary) -> Dictionary:
	var sub := rng.randi() % 2
	var first: String = c.first
	var net := {
		"mode": "office", "caller": first, "domain": c.domain, "isp_eta": "%d:%02d" % [rng.randi_range(12, 15), [0, 15, 30, 45][rng.randi() % 4]],
		"ref": "F%d" % rng.randi_range(100000, 999999), "public_ip": "198.51.100.%d" % rng.randi_range(2, 250),
		"backup": rng.randf() < 0.5, "modem_power": true, "modem_read": false, "on_wan2": false, "reset": false,
		"rules": [
			{"name": "Guest Wi-Fi: block LAN", "note": "BLOCK  Guest Wi-Fi: block LAN   192.168.50.0/24 -> 192.168.1.0/24 any", "on": true, "culprit": false},
			{"name": "Default: allow out", "note": "ALLOW  Default: allow out      192.168.1.0/24 -> any  any", "on": true, "culprit": false},
		],
		"allow_dns": false, "fwd": ["1.1.1.1", "8.8.8.8"], "fwd_ok": true,
		"dhcp_running": true, "recovery": "Take No Action", "authorized": true, "scope_dns": "192.168.1.10",
		"changes": [], "log": [], "events": [], "done": [],
		"goal": {"fault": fault, "sub": sub, "hold": fault == "wan" and sub == 0},
	}
	var changes: Array = [_pick(["Last week: a new Wi-Fi access point was fitted in the meeting room",
		"Monday:    two new laptops joined the domain", "Last week: FW01's firmware was updated, tested OK"])]
	var fw_log: Array = []
	if fault == "dns":
		fw_log.append("%s -> 1.1.1.1 icmp ALLOW (%s)" % [term.ip, term.host])
	elif fault == "dhcp":
		fw_log.append_array(["192.168.1.10 -> 1.1.1.1 udp/53 ALLOW", "192.168.1.10 -> 13.107.4.50 tcp/443 ALLOW"])
	var events: Array = ["Information  Service Control Manager 7036: The Windows Update service entered the stopped state."]
	var explain := ""
	match fault:
		"dns":
			if sub == 0:
				net.fwd = ["203.0.113.53"]
				net.fwd_ok = false
				changes.append("Last month: the client moved to a new ISP")
				fw_log.append_array(["192.168.1.10 -> 203.0.113.53 udp/53 ALLOW (no reply)", "192.168.1.10 -> 203.0.113.53 udp/53 ALLOW (no reply)"])
				explain = "DC01's only forwarder was the old ISP's resolver, 203.0.113.53. The firewall let the queries out, but that ISP no longer answers them, and root hints are off, so DC01 had nowhere to send outside lookups. Replacing the forwarders fixes it (clearing the server cache is a harmless extra). Pointing PCs at 8.8.8.8 would break Active Directory, which needs the DC for DNS."
			else:
				net.rules.insert(0, {"name": "Servers: HTTPS out only", "note": "BLOCK  Servers: HTTPS out only  192.168.1.10-19 -> any  all except TCP 443   (added yesterday)", "on": true, "culprit": true})
				changes.append("Yesterday: rule \"Servers: HTTPS out only\" added on FW01 (security review)")
				fw_log.append_array(["192.168.1.10 -> 1.1.1.1 udp/53 DENY (rule \"Servers: HTTPS out only\")",
					"192.168.1.10 -> 8.8.8.8 udp/53 DENY (rule \"Servers: HTTPS out only\")",
					"%s -> 8.8.8.8 udp/53 ALLOW (%s)" % [term.ip, term.host]])
				explain = "The forwarders were fine, but yesterday's rule only lets the servers out on HTTPS, so DC01's DNS queries were dropped (PCs could still reach 8.8.8.8, which is why that nslookup worked). A narrow rule above it allowing DNS out from DC01 fixes it and keeps the lockdown. Rolling back the whole rule undoes the security review; pointing PCs at 8.8.8.8 would break Active Directory."
		"wan":
			if sub == 0:
				fw_log.append_array(["WAN1: DHCP request to the ISP: no reply", "WAN1: DHCP request to the ISP: no reply"])
				explain = "The modem had power and line, FW01's link was up but the ISP gave it no address, and the ISP's status page showed an outage. Log the fault so you're on their list and have a reference, fail over to the 4G/5G backup if the site has one, and hold the ticket with the ETA. A factory reset only loses the router's config."
				if net.backup:
					explain = explain.replace("if the site has one", "(this site has one)")
			else:
				net.modem_power = false
				changes.append("Last night: the cleaners were in the network cabinet")
				fw_log.append_array(["WAN1: link down (no carrier)", "WAN1: link down (no carrier)"])
				explain = "WAN1 had no carrier and the modem was dark, while the ISP reported no issues and FW01, on the UPS, was fine. The modem's own power strip had been switched off. Getting someone onsite to check the power fixes it at no cost; logging an ISP fault first wastes time and can mean a charge for a technician visit."
		_:  # dhcp
			if sub == 0:
				net.dhcp_running = false
				changes.append("Last night: Windows updates installed on DC01; it restarted at 02:10")
				events.push_front("Error        Service Control Manager 7034 (02:16): The DHCP Server service terminated unexpectedly. It has done this 1 time(s).")
				explain = "The DHCP Server service crashed a few minutes after last night's post-update restart, and its recovery was set to take no action, so nothing restarted it. Start it and set recovery to restart the service; PCs pick up leases on their next retry or an ipconfig /renew. Changing DNS or the firewall wouldn't help."
			else:
				net.authorized = false
				changes.append("Last night: DHCP migrated to DC01 from the old server")
				events.push_front("Error        DHCP-Server 1046: The DHCP/BINL service on the local machine, belonging to the Windows Administrative domain %s, has determined that it is not authorized to service clients on this network." % c.domain)
				explain = "The service was running, but in an Active Directory domain a Windows DHCP server won't hand out leases until it's authorised in AD, and last night's migration missed that step. Authorise it in the DHCP console. Restarting the router won't help: DC01 is the DHCP server here, not FW01."
	var key := "%s%d" % [fault, sub]
	var hints: Array = [
		"Start with Recent changes on the Network Map, then open %s." % {
			"dns": "DC01 (its DNS forwarders) and FW01 (its rules and log)",
			"wan": "the ISP's status page, then ask %s to read out the modem's lights, then FW01's links" % first,
			"dhcp": "DC01: its DHCP console, its services and its event log"}[fault],
		{"dns0": "DC01's only DNS forwarder is the old ISP's resolver, 203.0.113.53, and it doesn't answer any more.",
			"dns1": "FW01's log shows DC01's DNS queries denied by yesterday's new rule, \"Servers: HTTPS out only\".",
			"wan0": "The ISP's status page shows an outage in the client's area, with an ETA. Nothing at the office is broken.",
			"wan1": "The ISP reports no issues, but WAN1 has no carrier. Something's wrong at the modem itself.",
			"dhcp0": "DC01's event log shows the DHCP Server service crashed after last night's restart, and its Services entry shows recovery set to Take No Action.",
			"dhcp1": "DC01's event log has event 1046: the DHCP server isn't authorised in Active Directory, so it won't hand out leases."}[key],
		{"dns0": "On DC01, replace the forwarders with 1.1.1.1 and 8.8.8.8, then press Fixed. Don't point the PCs at 8.8.8.8.",
			"dns1": "On FW01, add the rule allowing DC01 out on DNS (port 53), and leave the security rule on. Then press Fixed.",
			"wan0": "Log a fault with the ISP%s, then press Hold and give the client the ETA. Don't factory-reset anything." % (", fail FW01 over to its 4G/5G backup (WAN2)" if net.backup else ""),
			"wan1": "Ask %s to check the modem's power and cable, then press Fixed. No need to log an ISP fault." % first,
			"dhcp0": "On DC01, start the DHCP Server service and set its recovery to Restart the Service. Then press Fixed.",
			"dhcp1": "Authorize the server in DC01's DHCP console, then press Fixed. The router isn't the DHCP server here."}[key],
	]
	if rng.randf() < 0.5:
		changes.reverse()
	net.changes = changes
	net.log = fw_log
	net.events = events
	return {
		"name": "Fix",
		"info_add": "\n--- Diagnosis done. Now find out why it broke, and fix it, on the Network Map tab ---\n",
		"question": "On the Network Map tab (T): find out why and fix it, then close this step here",
		"options": ["Fixed: test it from %s's PC" % first, "Hold: it's waiting on the ISP. Give the client the ETA"],
		"answer": 1 if net.goal.hold else 0,
		"hints": hints,
		"explain": explain,
		"net": net,
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
	var why: String = {
		"dns": "Before the fix, DC01 couldn't resolve outside names. Repeat that exact test: nslookup google.com, answered by DC01.",
		"wan": "Before the fix, nothing past the router answered. Repeat that: ping 1.1.1.1 and tracert past the first hop.",
		"dhcp": "The PC keeps its old 169.254 address until it asks again: run ipconfig /renew first, then test the internet.",
	}.get(fault, "")
	return {
		"name": "Verify",
		"info_add": "\n--- %s Back on the phone with %s: prove it from their PC before you close it ---\n" % [
			"The internet link is back up." if fault == "wan" else "Fix applied.", first],
		"question": "Which result proves it's fixed?",
		"options": options,
		"answer": 0,
		"hints": ["Prove it with the test that failed before the fix, run on %s's PC. Anything that worked while it was broken proves nothing." % first,
			why, "Pick \"%s\"." % options[0]],
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
		"hints": [
			"Read what %s needs in the request and find the cheapest licence that covers it. Then check the Licences panel in Accounts for a spare one." % c.first,
			why,
			{"spare": "There's a spare %s: open %s (not their namesake) and assign it, then press Done." % [short, c.user],
				"leaver": "No %s spare, but %s has left and their mailbox is already a shared mailbox: remove their licence, then assign it to %s. Then press Done." % [short, leaver_name, c.user],
				"buy": "No %s spare and no leaver to free one from: assign nothing and press Hold, asking %s to approve buying one." % [short, mgr]}[stock],
		],
		"explain": "%s %s" % [why, how],
	}


# ---------------------------------------------------------------- MFA fatigue
## Done in Toolbox > Accounts (acct.security): read the caller's sign-in log, sessions, MFA methods and
## inbox rules, then contain it. Always reset the password with a change at next sign-in (each push
## followed a correct password). If a push was approved: revoke their sessions, and remove whatever the
## attacker set up (their own Authenticator, a hidden inbox rule, both or neither). Never touch the
## user's own methods or rules, turn MFA off, or trust the attacker's IP; don't leave sign-in blocked.
const PHONES := ["iPhone 15", "Pixel 8", "Galaxy S23", "iPhone 13"]
const OWN_RULES := [
	["Newsletters", "mail from news@ addresses moves to Newsletters"],
	["Receipts", "mail with \"receipt\" in the subject moves to Receipts"],
	["Team", "mail sent to the all-staff list moves to Team"],
]


func _make_mfa(c: Dictionary) -> Dictionary:
	var got_in := rng.randf() < 0.6
	var foothold: String = _pick(["both", "both", "method", "rule", "none"]) if got_in else "none"
	var start_min := rng.randi_range(5, 20)
	var tries := rng.randi_range(9, 24)
	var approved := start_min + 18
	var ip := "203.0.113.%d" % rng.randi_range(2, 250)
	var office := "198.51.100.%d" % rng.randi_range(2, 250)
	var keyword: String = _pick(["invoice", "payment", "bank"])
	var acct := _directory(c, _pick(["Office Manager", "Accounts", "Project Lead", "Director"]))
	for u in acct.users:  # everyone gets a normal-looking security page, so the log is what tells them apart
		var phone: String = _pick(PHONES)
		var own_rule: Array = _pick(OWN_RULES)
		u.methods = "Enforced (number matching)"
		u.auth = [{"id": "app", "text": "Authenticator app on %s (added last year)" % phone}]
		if rng.randf() < 0.4:
			u.auth.append({"id": "sms", "text": "Phone (SMS) to the mobile ending %s (added last year)" % u.mobile})
		u.rules = [{"id": "own", "text": "\"%s\" (created last year): %s" % own_rule}] if rng.randf() < 0.6 else []
		u.signins = ["Yesterday 16:%02d  %s (office)  Outlook  Success" % [rng.randi_range(10, 59), office],
			"Yesterday 08:%02d  %s (office)  Windows sign-in  Success" % [rng.randi_range(30, 59), office]]
		u.sessions = ["%s, office, since yesterday" % u.device.get_slice(" ", 0), "Outlook and Teams on their %s, since last week" % phone]
		u.blocked = false
		u.revoked = false
		u.mfa_off = false
		u.trusted = ""
		u.phone = phone
	var u: Dictionary = acct.users[acct.target]
	var own: String = u.phone
	var rogue_phone: String = _pick(PHONES.filter(func(p: String) -> bool: return p != own))
	if u.rules.is_empty():  # the caller always has a rule of their own to leave alone
		u.rules = [{"id": "own", "text": "\"%s\" (created last year): %s" % _pick(OWN_RULES)}]
	var attempts := "Today 02:%02d-02:%02d  %s (hosting provider, never seen before)  %d sign-ins: password correct, MFA push denied" % [
		start_min, approved - 1 if got_in else approved, ip, tries - 1 if got_in else tries]
	if got_in:
		u.signins.push_front(attempts)
		u.signins.push_front("Today 02:%02d  %s (hosting provider, never seen before)  password correct, MFA push APPROVED (number matched)  Success" % [approved, ip])
		u.sessions.push_front("Browser on Linux, %s (hosting provider), since today 02:%02d" % [ip, approved])
	else:
		u.signins.push_front(attempts)
	if foothold in ["both", "method"]:
		u.auth.append({"id": "rogue", "text": "Authenticator app on %s (added today 02:%02d)" % [rogue_phone, approved + 3]})
	if foothold in ["both", "rule"]:
		u.rules.append({"id": "rogue", "text": "\".\" (created today 02:%02d): mail containing \"%s\" moves to RSS Feeds, marked as read" % [approved + 8, keyword]})
	u.foreign_ip = ip
	acct.security = true
	acct.orig = acct.users.duplicate(true)
	acct.goal = {"hold": false, "sam": c.sam, "unlock": false, "reset": true, "must_change": true, "add": [],
		"revoke": got_in, "remove": ["rogue"] if foothold in ["both", "method"] else [],
		"drop": ["rogue"] if foothold in ["both", "rule"] else [], "hold_why": "",
		"held_msg": "Held it, but a stranger has the password%s: contain it now, don't wait for %s" % [" and got in" if got_in else "", c.first]}
	acct.erase("target")
	var reach := rng.randf()
	var says := ""
	if reach < 0.35:
		says = "emailed this at 07:%02d, then went into a client meeting\n            until lunch: they can't be reached" % rng.randi_range(5, 40)
	elif got_in:
		says = "a man rang at 02:%02d saying he was from IT and read out a\n            number to type into the app \"to stop the prompts\", so they did" % (approved - 1)
	elif rng.randf() < 0.5:
		says = "a man rang saying he was from IT and tried to read them a\n            number to type into the app; they hung up"
	else:
		says = "they denied every prompt and nobody else contacted them"
	var what: String = {
		"both": "The attacker then registered their own Authenticator on another phone (%s) and made a hidden inbox rule: remove both, but leave %s's own Authenticator and their own rule alone." % [rogue_phone, c.first],
		"method": "The attacker then registered their own Authenticator on another phone (%s) so they can pass MFA again: remove it, but leave %s's own Authenticator alone. No new inbox rule." % [rogue_phone, c.first],
		"rule": "The attacker then made a hidden inbox rule (\".\" moving \"%s\" mail to RSS Feeds) to hide replies: delete it, but leave %s's own rule. No new MFA method." % [keyword, c.first],
		"none": "Nothing new on the account yet (no new MFA method or inbox rule), so there's nothing of theirs to remove: throwing them out is the fix.",
	}[foothold]
	var found: String = {
		"both": " Today they also added their own Authenticator (on a %s) and a hidden inbox rule named \".\"." % rogue_phone,
		"method": " Today they also added their own Authenticator, on a %s. No new inbox rule." % rogue_phone,
		"rule": " Today they also made a hidden inbox rule named \".\". No new MFA method.",
		"none": " Nothing new was added to the account.",
	}[foothold]
	var todo := "Reset password and turn on Require change at next sign-in"
	if got_in:
		todo += ", then Revoke all sessions"
		if foothold in ["both", "method"]:
			todo += ", remove the Authenticator on the %s" % rogue_phone
		if foothold in ["both", "rule"]:
			todo += ", delete the \".\" rule"
	todo += ". Leave %s's own phone and rules alone, don't turn MFA off or trust that IP, then press Done." % c.first
	var hints: Array = [
		"Open %s in Accounts and read their sign-in log: was any push APPROVED? Then check their sessions, MFA methods and inbox rules for anything added today." % c.user,
		("At 02:%02d a push was approved from %s: the attacker got in.%s" % [approved, ip, found] if got_in
			else "Every push was denied and nothing was added, but each one followed a correct password: the attacker knows it."),
		todo,
	]
	var explain := ""
	if got_in:
		explain = "The 02:%02d sign-in was approved, so the attacker got in. Reset the password with a change at next sign-in, then revoke all sessions: a reset doesn't reliably sign out sessions that are already open, and tokens already issued keep working until they expire. %s Then check what was sent from the mailbox." % [approved, what]
	else:
		explain = "Every push was denied and nothing changed on the account, but each one came after a correct password: the attacker knows it. Reset it with a change at next sign-in. Revoking sessions is extra caution, not required. Phishing-resistant MFA or Conditional Access would stop these prompts."
	explain += " Blocking sign-in while you work is fine, but unblock it before you close the ticket. Never turn MFA off or trust the attacker's IP."
	return {
		"priority": 1,
		"subject": "Authenticator prompts I didn't start",
		"body": "%s (%s): \"My phone kept buzzing with sign-in requests from about 2am. I wasn't logging in. What's going on?\"" % [c.user, u.title],
		"info_title": "Call notes",
		"info": "Caller:     %s\nSays:       %s\nPolicy:     a correct password from a stranger means it's leaked.\n            Check their sign-in log in Accounts (T) and contain it there" % [c.user, says],
		"acct": acct,
		"question": "Contain it on the Accounts tab (T), then close it",
		"options": [
			"Done: I've secured the account in Accounts",
			"Hold: change nothing until %s can confirm what they did" % c.first,
		],
		"answer": 0,
		"hints": hints,
		"explain": explain,
	}


# ---------------------------------------------------------------- BitLocker recovery
## Done in Toolbox > Accounts: check the callback number against the mobile on file, then open the
## caller's devices and read out only the recovery key whose ID matches the one on their screen.
## Hold (read out nothing) when the caller isn't verified, or when Entra has no key with that ID:
## no other key can unlock that drive.
func _make_bitlocker(c: Dictionary) -> Dictionary:
	var genuine := rng.randf() < 0.8
	var has_key := rng.randf() < 0.8
	var exec := rng.randf() < 0.25
	var title: String = "Director" if exec else _pick(["Office Manager", "Accounts", "Project Lead", "Designer"])
	var acct := _directory(c, title)
	var prefix: String = c.domain.substr(0, 3).to_upper()
	var used: Array = []
	for u in acct.users:  # everyone has a laptop with its key backed up, so the right person matters
		u.devices = [{"name": u.device.get_slice(" ", 0), "about": "Windows 11 laptop  ·  Entra joined  ·  in use",
			"keys": [_bl_key("Operating system drive", "%d days ago" % rng.randi_range(40, 400), used)]}]
		u.read = []
	var u: Dictionary = acct.users[acct.target]
	var lap: Dictionary = u.devices[0]
	var screen := ""
	var key_id := ""
	var extra := ""        # the explanation's note on keys that look right but aren't
	var stale := false
	if has_key:
		var k := _bl_key("Operating system drive", "%d days ago" % rng.randi_range(20, 200), used)
		lap.keys = [k]
		key_id = k.id
		screen = k.id.substr(0, 8)
		if rng.randf() < 0.4:  # an older key for the same drive, since rotated
			lap.keys.append(_bl_key("Operating system drive", "%d days ago" % rng.randi_range(300, 600), used))
			extra = "The older key for the same drive has since been replaced, with a different ID: it no longer unlocks it. "
	else:
		screen = _hex(8)
		while screen.substr(0, 4) in used:
			screen = _hex(8)
		used.append(screen.substr(0, 4))
		stale = rng.randf() < 0.5
		lap.keys = [_bl_key("Operating system drive", "%d days ago" % rng.randi_range(300, 600), used)] if stale else []
	if rng.randf() < 0.5:  # a second internal drive has its own key
		lap.keys.append(_bl_key("Fixed data drive", "%d days ago" % rng.randi_range(20, 400), used))
		extra += "The data drive's key is for the second drive, not the one Windows boots from. "
	if rng.randf() < 0.6:  # their last laptop is still in the list
		var old := _bl_key("Operating system drive", "%d days ago" % rng.randi_range(500, 900), used)
		if rng.randf() < 0.5:  # same first four characters: read the whole eight
			old.id = screen.substr(0, 4) + old.id.substr(4)
			while old.id.begins_with(screen):
				old.id = screen.substr(0, 4) + _hex(4) + old.id.substr(8)
		u.devices.append({"name": "%s-PC%02d" % [prefix, rng.randi_range(30, 49)], "about": "Windows 11 laptop  ·  Entra joined  ·  replaced, last sign-in months ago", "keys": [old]})
		extra += "%s is their old laptop. " % u.devices[1].name
	var on_file: String = u.mobile
	var rang := on_file
	if not genuine:
		rang = "%04d" % ((int(on_file) + rng.randi_range(11, 8000)) % 10000)
	acct.bitlocker = true
	acct.screen = screen
	acct.orig = acct.users.duplicate(true)
	var why_nokey := "no key in Entra has the ID on their screen (%s), so no key you have can unlock that drive" % screen
	acct.goal = {"hold": not (genuine and has_key), "sam": c.sam, "unlock": false, "reset": false, "must_change": false, "add": [],
		"key": key_id,
		"hold_why": ("the callback number isn't the one on file, so the caller was never verified. A recovery key unlocks the whole drive for whoever has the laptop"
			if not genuine else why_nokey),
		"held_msg": "Held it, but the caller is verified and the key with ID %s is in Entra: read it out so they can work" % screen}
	acct.erase("target")
	var explain := ""
	if not genuine:
		explain = "The mobile on file ends %s, not %s. Calling back a number the caller gives you proves nothing, and a recovery key unlocks the whole drive for whoever is holding the laptop: read out nothing, call back on the number on file and flag it to security." % [on_file, rang]
	elif has_key:
		explain = "The callback number is the mobile on file, so the caller is verified. Their screen's key ID starts %s: only the key on %s with that ID unlocks the drive. %sReading out a key that doesn't match exposes it for nothing. The key read over the phone should be rotated once they're in (Intune can do this automatically after a key is used)." % [screen, lap.name, extra]
	else:
		explain = "The caller is verified, but %s has %s. Without the key whose ID matches %s, no key can unlock that drive: read out nothing and hold. First try undoing what triggered it (unplug the new dock, put back any changed BIOS setting) in case the TPM unlocks it again, and check anywhere else the key may have been saved; if none of that works, the laptop has to be wiped and rebuilt, and anything not synced to OneDrive is lost." % [
			lap.name, "only an old key that has since been replaced, with a different ID" if stale else "no BitLocker key backed up to Entra at all", screen]
	var hints: Array = [
		"Verify the caller first: compare %s's mobile on file in Accounts with the number we called back. Then open their devices and look for a key whose ID starts %s, the one on their screen." % [c.user, screen],
		("The mobile on file ends %s, but we called back %s, a number the caller gave us. They aren't verified." % [on_file, rang] if not genuine
			else ("They're verified. Only one key, on %s, has an ID starting %s: check all eight characters, not just the first four." % [lap.name, screen] if has_key
			else "They're verified, but none of the keys in Entra has an ID starting %s." % screen)),
		("Read out nothing: press Hold, call back on the number on file and flag it to security." if not genuine
			else ("Show the key on %s with ID %s, read it out to the caller, then press Done." % [lap.name, key_id.substr(0, 8)] if has_key
			else "Read out nothing and press Hold: no other key can unlock that drive.")),
	]
	var cause: String = _pick(["after an update last night", "after a BIOS update last night", "since I plugged it into the new docking station"])
	return {
		"priority": 1 if exec else 2,
		"subject": "Laptop asking for a BitLocker recovery key",
		"body": "%s (%s) is on the phone: \"My laptop's on a blue screen asking for a BitLocker recovery key %s. I can't get into Windows at all!\"" % [c.user, title, cause],
		"info_title": "Call notes",
		"info": "Caller:     says they're %s (%s)\nCallback:   we rang the mobile ending %s that the caller gave us;\n            they answered and confirmed the request\nScreen:     BitLocker recovery, key ID starting %s\nPolicy:     only read out a recovery key once the caller is verified\n            (callback number = the mobile on file, Accounts tab)" % [c.user, title, rang, screen],
		"acct": acct,
		"question": "Find their key on the Accounts tab (T) and read it out, or hold",
		"options": [
			"Done: I read them the key that matches their screen",
			"Hold: read out nothing. Not verified, or no key matches",
		],
		"answer": 1 if acct.goal.hold else 0,
		"hints": hints,
		"explain": explain,
	}


## A BitLocker recovery key as Entra shows it: a key ID (a GUID) and a 48-digit recovery password in
## eight blocks of six digits, each block a multiple of 11 (as real recovery passwords are).
func _bl_key(drive: String, when: String, used: Array) -> Dictionary:
	var id := ""
	while id == "" or id.substr(0, 4) in used:
		id = "%s-%s-%s-%s-%s" % [_hex(8), _hex(4), _hex(4), _hex(4), _hex(12)]
	used.append(id.substr(0, 4))
	var blocks: Array = []
	for i in 8:
		blocks.append("%06d" % (11 * rng.randi_range(0, 65535)))
	return {"id": id, "drive": drive, "when": "backed up %s" % when, "pwd": "-".join(blocks)}


func _hex(n: int) -> String:
	var s := ""
	for i in n:
		s += "0123456789ABCDEF"[rng.randi() % 16]
	return s


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
	var hints: Array = [
		"On Remote Control, connect to %s's own PC (not their namesake's). In Device Manager, open the scanner's properties for its hardware ID, then check the processor in Settings." % c.user,
		"Hardware ID PID_%s is the %s%s, and Settings says %s processor." % [m.pid, m.model, " (not the %s the caller said)" % said if said != m.model else "",
			"an ARM-based" if arch == "ARM64" else "an x64-based"],
		("Kestrel has no ARM64 driver for the %s, and x64 drivers can't load on Arm. Install nothing and press Hold." % m.model if hold
			else "On the vendor's page, install the %s %s package (never the driver updater ad), then press Done." % [m.model, arch]),
	]
	return {
		"priority": 3,
		"subject": "New scanner isn't working",
		"body": "%s: \"I plugged in our new Kestrel %s scanner but my PC won't find it. The scan app just says no scanner found.\"" % [c.user, said],
		"info_title": "Call notes",
		"info": "Caller:    %s, signed in on their PC now\nDevice:    Kestrel %s (so they say), USB, plugged in today\nSymptom:   scan app: \"No scanner found\"\nDrivers:   %s (vendor site)\nAccess:    they're happy for us to remote on" % [c.user, said, rc.site],
		"rc": rc,
		"hints": hints,
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
