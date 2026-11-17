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
	if not t.has("acct") and not t.has("rc"):  # Toolbox tickets keep "Done" / "Hold" in that order
		_shuffle_options(t)
	for st in t.get("steps", []):
		if st.has("options"):  # console steps ("actions") keep their admin-console order
			_shuffle_options(st)
	return t


# ---------------------------------------------------------------- phishing
func _make_phish(c: Dictionary) -> Dictionary:
	var legit := rng.randf() < 0.4
	var d: String = c.domain
	var info := ""
	var explain := ""
	if legit:
		var v := rng.randi() % 2
		if v == 0:
			info = "From:      Xero <messaging-service@post.xero.com>\nReply-To:  (none)\nSubject:   Invoice INV-%d from Office Supplies Co\nAuth:      SPF=pass  DKIM=pass (xero.com)  DMARC=pass\nLinks:     in.xero.com/…\nNote:      Supplier is in the vendor list; amount matches the PO" % rng.randi_range(4000, 9999)
			explain = "Legit. SPF, DKIM and DMARC all pass for xero.com, the link goes to xero.com, and it matches a real PO."
		else:
			info = "From:      Microsoft 365 <no-reply@microsoft.com>\nReply-To:  (none)\nSubject:   Your MFA method was updated\nAuth:      SPF=pass  DKIM=pass (microsoft.com)  DMARC=pass\nLinks:     account.microsoft.com/…\nNote:      %s changed phones yesterday (ticket in PSA)" % c.first
			explain = "Legit. Auth passes for microsoft.com, the link is Microsoft's own, and it lines up with yesterday's phone change."
	else:
		var v := rng.randi() % 4
		match v:
			0:
				info = "From:      Microsoft 365 <alert@rnicrosoft-secure.com>\nReply-To:  (none)\nSubject:   Password expires today – keep current password\nAuth:      SPF=pass (rnicrosoft-secure.com)  DMARC=none\nLinks:     rnicrosoft-secure.com/owa/login"
				explain = "Phish. \"rnicrosoft\" is r-n, not m. SPF passing only proves the lookalike domain sent it."
			1:
				var boss_last: String = _pick(LAST)
				info = "From:      %s %s (CEO) <ceo.%s@gmail.com>\nReply-To:  ceo.%s@gmail.com\nSubject:   Urgent – need gift cards for clients today\nAuth:      SPF=pass (gmail.com)  [EXTERNAL]\nLinks:     (none)" % [_pick(FIRST), boss_last, boss_last.to_lower(), boss_last.to_lower()]
				explain = "Phish (CEO fraud). Display name is the boss, the address is Gmail, and it's urgent gift cards. Classic BEC."
			2:
				var typo := d.replace(".com", "-accounts.co")  # lookalike of their own domain
				info = "From:      Accounts <accounts@%s>\nReply-To:  payments@%s\nSubject:   Updated bank details for next payment run\nAuth:      SPF=softfail  DMARC=fail\nLinks:     (attachment: New_Bank_Details.pdf.html)" % [typo, typo]
				explain = "Phish. Lookalike of their own domain, DMARC fails, bank-detail change by email, and a .pdf.html attachment."
			_:
				info = "From:      DocuSign <dse@docusign.net>\nReply-To:  (none)\nSubject:   Please review and sign: Lease_Renewal.pdf\nAuth:      SPF=fail  DKIM=none  DMARC=fail\nLinks:     docusign-review.web.app/…"
				explain = "Phish. The From says docusign.net, but SPF and DMARC fail and the link goes to a free web.app host."
	return {
		"priority": 2,
		"subject": "Is this email legit?",
		"body": "%s forwarded an email: \"Not sure about this one, can you check before I click anything?\"" % c.first,
		"info_title": "Message headers",
		"info": info,
		"question": "Your call?",
		"options": [
			"Phish: quarantine, block sender, purge from all mailboxes",
			"Legitimate: release it and let them know it's safe",
			"Reply to the sender and ask if they really sent it",
		],
		"answer": 1 if legit else 0,
		"explain": explain + ("" if legit else " Never reply to a suspected phish; verify by a known phone number."),
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
## Two steps: from the outside (ping, web page, queue) work out whether the fault is the print queue,
## the network path to the printer, or the printer itself; then the fix step shows the detail.
func _make_printer(c: Dictionary) -> Dictionary:
	var v := rng.randi() % 3
	var fault: String = ["queue", "network", "device"][v]
	var mfp := "MFP-%s" % _pick(["RECEPTION", "LEVEL1", "ACCOUNTS"])
	var p := {"mfp": mfp, "ip": "192.168.10.50", "jobs": rng.randi_range(12, 60),
		"mins": rng.randi_range(20, 55), "users": rng.randi_range(5, 14)}
	var info := "Affected:      all %d people who print to %s\nQueue PRINT01: %s, %d jobs waiting, the oldest for %d min\n" % [p.users, mfp, mfp, p.jobs, p.mins]
	match fault:
		"queue":
			info += "Ping:          %s replies (from PRINT01)\nWeb page:      Ready. No errors. Last job received: yesterday 17:05" % p.ip
		"network":
			info += "Ping:          %s timed out (from PRINT01)\nWeb page:      http://%s can't be reached\nOn the phone:  %s: \"It's switched on and the screen says Ready.\"" % [p.ip, p.ip, c.first]
		_:
			info += "Ping:          %s replies (from PRINT01)\nWeb page:      Status: Error. Check the control panel. 1 job held at the printer" % p.ip
	return {
		"priority": 3,
		"subject": "Printer not printing",
		"body": "%s: \"Nothing's coming out of the printer and accounts need invoices out today.\"" % c.first,
		"info_title": "Diagnostics: %s, shared from PRINT01" % mfp,
		"info": info,
		"question": "Where's the fault?",
		"options": [
			"The print queue on PRINT01 is stuck; the printer and network are fine",
			"The network: PRINT01 can't reach the printer",
			"The printer itself: it's reporting a fault",
			"%s's PC: reinstall the printer driver on it" % c.first,
		],
		"answer": v,
		"explain": ["The printer answers ping and its web page says Ready with nothing received since yesterday, so the jobs are stuck on the server. It isn't one PC: everyone is affected. Next: open the queue on PRINT01.",
			"PRINT01 can't ping the printer or load its web page, yet it's switched on and Ready, so the path between them is broken. It isn't one PC: everyone is affected. Next: find out why.",
			"The printer is on the network and took the job, but its own status says Error and it's holding it, so the fault is in the printer. Next: read the control panel."][v],
		"step_name": "Diagnose",
		"steps": [_printer_fix(fault, p, c.first)],
	}


## Step 2 of a printer ticket: the detail behind the fault, and the fix.
func _printer_fix(fault: String, p: Dictionary, first: String) -> Dictionary:
	var sub := rng.randi() % 2
	var info := ""
	var options: Array = []
	var explain := ""
	var where := "You open the queue on PRINT01"
	match fault:
		"queue":
			options = [
				"Cancel the stuck job; if it won't go, stop the Print Spooler, clear the spool folder and start it",
				"Resume the paused printer queue",
				"Power-cycle the printer",
				"Change the printer port to a new IP address",
			]
			if sub == 0:
				info = "Queue status:  Printing\nJob 1:         Invoices_Q3.pdf  (%d MB)  Error - Printing   submitted %d min ago\nJobs 2-%d:     Waiting behind job 1\nPrintService/Admin log, event 372: the document failed to print" % [rng.randi_range(300, 900), p.mins, p.jobs]
				explain = "One huge job errored at the top of the queue and everything is waiting behind it. Cancel it; if it's stuck on \"Deleting\", stop the Print Spooler, clear C:\\Windows\\System32\\spool\\PRINTERS and start it again (that clears every queued job, so warn people). The printer is fine, so power-cycling it does nothing."
			else:
				info = "Queue status:  Paused\nJobs 1-%d:     Waiting\nChange log:    last night's maintenance paused %s to update its driver and didn't resume it" % [p.jobs, p.mfp]
				explain = "The queue was paused for last night's driver update and never resumed, so Windows holds every job. Resume it (Print Management on PRINT01: right-click %s > Resume Printing). Restarting the spooler or the printer won't help: a paused queue stays paused." % p.mfp
		"network":
			options = [
				"Point the printer port at its new IP and add a DHCP reservation",
				"Get someone onsite to reseat or replace the printer's network cable",
				"Clear the queue and restart the Print Spooler",
				"Order a replacement printer",
			]
			where = "%s reads the printer's network settings off its control panel" % first
			if sub == 0:
				var new_ip := "192.168.10.%d" % rng.randi_range(70, 140)
				info = "Printer panel: IP %s (DHCP), link up\nPRINT01 port:  IP_%s\nDHCP leases:   %s  ->  %s  (no reservation; leased this morning by the new firewall, which took over DHCP last week)\nPing:          %s replies (from PRINT01)" % [new_ip, p.ip, p.mfp, new_ip, new_ip]
				explain = "DHCP moved to the new firewall last week. It has no record of the old lease, so when the printer's old lease ran out this morning it was given a different address, but the queue still sends to the old one. Point the port at the new IP and add a DHCP reservation so it can't move again. The cable is fine: the link is up and the new IP replies."
			else:
				info = "Printer panel: IP %s (static), network: no link\nSwitch:        port 14 (%s) down since 17:40 yesterday\nCall notes:    desks were moved around the printer last night" % [p.ip, p.mfp]
				explain = "The printer still has the right IP, but it has no network link and its switch port went down while the desks were moved. Get someone onsite to check the cable is plugged in at both ends, or swap it. The IP didn't change, so editing the port won't help."
		_:  # device
			options = [
				"Fit a spare toner if there's one onsite, otherwise order one on the print contract",
				"Log a service call with the print vendor and move urgent jobs to another printer",
				"Clear the queue and restart the Print Spooler",
				"Reinstall the printer driver on PRINT01",
			]
			where = "%s reads the printer's control panel" % first
			if sub == 0:
				info = "Panel:         \"Replace black toner cartridge. Printing stopped\"\nToner levels:  black 0%%, cyan 64%%, magenta 58%%, yellow 71%%\nPage count:    %d" % rng.randi_range(40000, 90000)
				explain = "It's out of black toner and has stopped. Fit a spare if there is one, otherwise order it on the contract. The queue will carry on by itself once there's toner; nothing on the server needs touching."
			else:
				info = "Panel:         \"Error E-542: fuser fault. Turn off and contact service\"\nOn the phone:  %s: \"I turned it off and on twice. It comes back during warm-up.\"\nContract:      on-site service included" % first
				explain = "A fuser fault that returns after a power cycle is a hardware failure for the vendor's technician, and the service is covered by the contract. Log the call and move urgent jobs (the invoices) to another printer meanwhile. The server and drivers are fine."
	return {
		"name": "Fix",
		"info_add": "\n--- %s ---\n%s\n" % [where, info],
		"question": "How do you fix it?",
		"options": options,
		"answer": sub,
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
func _make_licence(c: Dictionary) -> Dictionary:
	var shared := rng.randf() < 0.35
	var name := "%s %s" % [_pick(FIRST), _pick(LAST)]
	var info := ("Request:  shared inbox accounts@%s\nUsers:    3 staff need to read/send as it\nSize:     ~4 GB expected" % c.domain if shared
		else "Starter:  %s, starts Monday\nNeeds:    email, desktop Word/Excel/Outlook, Teams\nDevice:   new laptop, must be Intune-managed + Defender" % name)
	return {
		"priority": 4,
		"subject": "Shared inbox for accounts" if shared else "New starter Monday",
		"body": ("%s wants a shared accounts@ mailbox for the team." % c.first if shared
			else "%s: \"%s starts Monday. Can you set them up with everything?\"" % [c.first, name]),
		"info_title": "Requirements",
		"info": info,
		"question": "Which licence?",
		"options": [
			"Microsoft 365 Business Premium",
			"Microsoft 365 Business Standard",
			"Microsoft 365 Business Basic",
			"No licence: a shared mailbox under 50 GB doesn't need one",
		],
		"answer": 3 if shared else 0,
		"explain": ("Shared mailboxes under 50 GB need no licence. Grant Full Access + Send As to the 3 users." if shared
			else "Desktop apps plus Intune and Defender means Business Premium. Standard has no Intune; Basic has no desktop apps."),
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
