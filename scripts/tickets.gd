extends RefCounted
## Ticket generator. Each ticket is a Dictionary:
##   kind, priority (1 = P1 .. 4 = P4), client, user, subject, body,
##   info_title, info (evidence shown in a monospace box), question,
##   options (Array[String]), answer (index into options), explain (shown after answering)
##   Optional: term + prompt (a simulated command prompt the player types into; see terminal.gd)
##   Optional: steps (Array of later steps on the same ticket, each with name, info_add, question,
##   options, answer, explain). The top-level question is step 1; info_add is appended to the evidence
##   when that step opens. Each step pays out; a wrong step escalates the ticket.
## New ticket types: add a _make_<kind>() and list it in KINDS. Keep answers technically right;
## the players are often real IT people.

const KINDS := ["phish", "lockout", "share", "printer", "network", "licence", "mfa"]

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
	_shuffle_options(t)
	for st in t.get("steps", []):
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
func _make_lockout(c: Dictionary) -> Dictionary:
	var on_file := "%04d" % rng.randi_range(0, 9999)
	var genuine := rng.randf() < 0.65
	var said := on_file
	if not genuine:
		said = "%04d" % ((int(on_file) + rng.randi_range(11, 8000)) % 10000)
	var exec := rng.randf() < 0.3
	var title: String = "Director" if exec else _pick(["Office Manager", "Accounts", "Reception", "Project Lead"])
	var from: String = "their desk extension 2%02d" % rng.randi_range(10, 60) if genuine else _pick(["a private number", "a mobile not on file"])
	return {
		"priority": 1 if exec else 2,
		"subject": "Locked out of my account",
		"body": "%s (%s) is on the phone: \"I've been locked out and I've got a meeting in ten minutes!\"" % [c.user, title],
		"info_title": "Active Directory + call notes",
		"info": "User:          %s\\%s\nlockoutTime:   today 08:%02d\nbadPwdCount:   5\nMobile (AD):   04xx xxx %s\n\nCaller gave:   mobile ending %s\nCalling from:  %s" % [c.domain.get_slice(".", 0).to_upper(), c.sam, rng.randi_range(5, 55), on_file, said, from],
		"question": "What do you do?",
		"options": [
			"Identity checks out: unlock, temp password, force change at next logon",
			"Doesn't match: refuse, call back on the number on file, flag to security",
			"They sound stressed. Unlock it now and verify afterwards",
		],
		"answer": 0 if genuine else 1,
		"explain": ("Verified against the number on file, so unlock and force a password change." if genuine
			else "The mobile doesn't match AD. That's a social-engineering red flag: call back on the number on file."),
	}


# ---------------------------------------------------------------- file share access
func _make_share(c: Dictionary) -> Dictionary:
	var dept: String = _pick(["Finance", "HR", "Projects", "Marketing"])
	var edit := rng.randf() < 0.5
	var approved := rng.randf() < 0.75
	var manager := "%s %s" % [_pick(FIRST), _pick(LAST)]
	var right := "Add to GG_%s_%s" % [dept, "Modify" if edit else "Read"]
	var wrong := "Add to GG_%s_%s" % [dept, "Read" if edit else "Modify"]
	var approval_line := "Approved by %s (%s manager) in the PSA" % [manager, dept] if approved else "Approval: none. %s says \"my manager's fine with it\"" % c.first
	return {
		"priority": 3,
		"subject": "Need access to the %s share" % dept,
		"body": "%s needs to %s files in \\\\FS01\\%s." % [c.first, "edit" if edit else "view", dept],
		"info_title": "Request",
		"info": "Share:     \\\\FS01\\%s\nNTFS:      GG_%s_Read (RX), GG_%s_Modify (M)\nAsked for: %s access\n%s" % [dept, dept, dept, "edit" if edit else "read-only", approval_line],
		"question": "How do you grant it?",
		"options": [right, wrong, "Add to Domain Admins so it never happens again", "Hold: get the %s manager's approval first" % dept],
		"answer": 0 if approved else 3,
		"explain": ("Least privilege: approved, so add them to the %s group and nothing more." % right.get_slice(" ", 2) if approved
			else "No approval from the data owner. Get it in writing before granting access, however small."),
	}


# ---------------------------------------------------------------- printer
func _make_printer(c: Dictionary) -> Dictionary:
	var v := rng.randi() % 3
	var mfp := "MFP-%s" % _pick(["RECEPTION", "LEVEL1", "ACCOUNTS"])
	var info := ""
	match v:
		0:
			info = "Printer:     %s (online, ping OK)\nQueue:       %d jobs, status \"Error - Printing\"\nSpooler:     Running\nEvent 372:   Document failed to print, spooler stuck" % [mfp, rng.randi_range(12, 60)]
		1:
			info = "Printer:     %s on port IP_192.168.10.50\nping .50:    Request timed out\nDHCP leases: %s  MAC 00:1B:A9:..  ->  192.168.10.%d" % [mfp, mfp, rng.randi_range(70, 140)]
		_:
			info = "Printer:     %s (online, ping OK)\nQueue:       empty\nPanel:       \"Replace black toner cartridge (0%%)\"\nPage count:  %d" % [mfp, rng.randi_range(40000, 90000)]
	return {
		"priority": 3,
		"subject": "Printer not printing",
		"body": "%s: \"Nothing's coming out of the printer and accounts need invoices out today.\"" % c.first,
		"info_title": "Diagnostics",
		"info": info,
		"question": "Fix?",
		"options": [
			"Clear the queue and restart the Print Spooler service",
			"Point the port at the new IP and add a DHCP reservation",
			"Order toner on the managed print contract",
			"Reinstall the printer driver on every PC",
		],
		"answer": v,
		"explain": ["Stuck spooler with a full queue: clear it and restart the service.",
			"The printer picked up a new DHCP address. Fix the port, then reserve the IP so it doesn't move again.",
			"It's just out of toner. Order it on the contract; no technical fix needed."][v],
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
		"steps": [_network_fix(fault, term, c.first)],
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
func _make_mfa(c: Dictionary) -> Dictionary:
	var got_in := rng.randf() < 0.5
	var start_min := rng.randi_range(5, 20)
	var tries := rng.randi_range(9, 24)
	var ip := "203.0.113.%d" % rng.randi_range(2, 250)
	var upn := "%s@%s" % [c.sam, c.domain]
	var info := "Entra sign-ins:  %s\nFrom:            %s (hosting provider, never seen before)\nAttempts:        %d, 02:%02d-02:%02d, password correct each time\nMFA method:      Authenticator push (number matching)\n" % [upn, ip, tries, start_min, start_min + 18]
	if got_in:
		var rule: String = _pick(["invoice", "payment", "bank"])
		info += "MFA result:      denied x%d, APPROVED 02:%02d\n\nAudit 02:%02d:     User registered security info (Authenticator)\nExchange 02:%02d:  Inbox rule moves mail containing \"%s\" to RSS Feeds\nCall notes:      a \"helpdesk\" caller read them a number to enter" % [tries - 1, start_min + 18, start_min + 21, start_min + 26, rule]
	else:
		info += "MFA result:      denied x%d (every prompt)\n\nAudit log:       no changes to security info or mailbox rules\nCall notes:      %s denied them all; nobody else contacted them" % [tries, c.first]
	return {
		"priority": 1,
		"subject": "Authenticator prompts I didn't start",
		"body": "%s: \"My phone kept buzzing with sign-in requests from about 2am. I wasn't logging in. What's going on?\"" % c.first,
		"info_title": "Sign-in + audit logs",
		"info": info,
		"question": "What's happened, and what do you do?",
		"options": [
			"Password is known but MFA held: reset the password and revoke sessions",
			"Attacker is in: block sign-in, revoke sessions, reset password, remove their MFA method and inbox rule",
			"Tell them to approve one so the prompts stop, then keep an eye on it",
			"Turn MFA off for this user until the prompts die down",
		],
		"answer": 1 if got_in else 0,
		"explain": ("The 02:%02d approval let them in, then they added their own Authenticator and a rule to hide replies. Contain it: block, revoke, reset, remove both, then check what was sent. Never enter a number someone gives you." % (start_min + 18) if got_in
			else "Each push came after a correct password, so it's compromised even though MFA held. Reset it and revoke sessions; Conditional Access or phishing-resistant MFA cuts this off."),
	}


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
