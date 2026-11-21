extends RefCounted
## Toolbox › Network Map, "office" mode: step 2 of an "internet is down" ticket. After diagnosing the
## fault from the caller's command prompt, the player finds out WHY on the client's network and fixes
## it: the ISP's status page, the ISP modem in the cabinet (the caller reads its lights), FW01 (router +
## firewall: WAN links, outbound rules, log) and DC01 (DNS forwarders, DHCP console, services, event log).
## netmap.gd draws the map and delegates here when net.mode == "office". Static, so the test can use it.
## net = {mode: "office", caller, domain, isp_eta, backup: bool, modem_power: bool, modem_read: bool,
##        on_wan2, reset, rules: [{name, note, on, culprit}], allow_dns, fwd: [ip], fwd_ok,
##        dhcp_running, recovery, authorized, scope_dns, changes: [String], log: [String],
##        events: [String], done: [act], goal: {fault ("dns"/"wan"/"dhcp"), sub (0/1), hold}}
## act = {act, dev}: isp_fault / modem_check / failover / restart_fw / factory / rule_off (dev = rule name) /
##       allow_dns / set_fwd / clear_cache / authorize / scope_dns / start_dhcp / recovery

const UI := preload("res://scripts/ui.gd")
const GOOD_FWD := ["1.1.1.1", "8.8.8.8"]


## The office's main link (WAN1) works: the modem has power, the ISP isn't down, the router has its config.
static func wan1_up(n: Dictionary) -> bool:
	return n.modem_power and not (n.goal.fault == "wan" and n.goal.sub == 0) and not n.reset


## Traffic gets out to the internet, over WAN1 or the 4G/5G backup.
static func online(n: Dictionary) -> bool:
	return not n.reset and (wan1_up(n) or n.on_wan2) and _rule_on(n, "Default: allow out")


static func _rule_on(n: Dictionary, name: String) -> bool:
	for r in n.rules:
		if r.name == name:
			return r.on
	return false


## DC01's outside lookups work: it's online, its forwarders answer, and the firewall lets its DNS out.
static func dns_ok(n: Dictionary) -> bool:
	var blocked := false
	for r in n.rules:
		if r.culprit and r.on and not n.allow_dns:
			blocked = true
	return online(n) and n.fwd_ok and not blocked and n.scope_dns == "192.168.1.10"


static func dhcp_ok(n: Dictionary) -> bool:
	return n.dhcp_running and n.authorized


## Do an action and record it. Returns what happened.
static func apply(n: Dictionary, what: String, dev: String) -> String:
	var who: String = n.caller
	var msg := ""
	match what:
		"isp_fault":
			if n.goal.fault == "wan" and n.goal.sub == 0:
				msg = "Fault logged with the ISP, reference %s. They confirm the area outage; ETA %s." % [n.ref, n.isp_eta]
			else:
				msg = "Fault logged with the ISP, reference %s. Their tests show the line is fine from their end; they'll charge for a technician visit if no fault is found." % n.ref
		"modem_check":
			if not n.modem_power:
				n.modem_power = true
				msg = "%s: \"Its power strip was switched off at the wall, behind the cleaners' vacuum. It's back on... lights are coming up. Internet light's on now.\"" % who
			else:
				msg = "%s: \"It's plugged in and the power light's on. Cable's in firmly.\"" % who
		"failover":
			n.on_wan2 = true
			msg = "FW01 now sends internet traffic over WAN2 (4G/5G backup). It fails back to WAN1 by itself once WAN1 is up."
		"restart_fw":
			msg = "FW01 restarted: everyone dropped off for three minutes, then it came back exactly as it was."
		"factory":
			n.reset = true
			n.on_wan2 = false
			msg = "FW01 reset to factory defaults: its WAN settings, rules, VPN and backup link are all gone. The office is offline until it's rebuilt."
		"rule_off":
			for r in n.rules:
				if r.name == dev:
					r.on = false
			msg = "Rule \"%s\" disabled." % dev
		"allow_dns":
			n.allow_dns = true
			msg = "Rule added above the others: allow 192.168.1.10 (DC01) to any, UDP and TCP 53 (DNS)."
		"set_fwd":
			n.fwd = GOOD_FWD.duplicate()
			n.fwd_ok = true
			msg = "Forwarders on DC01 are now 1.1.1.1 and 8.8.8.8."
		"clear_cache":
			msg = "DC01's DNS server cache cleared."
		"authorize":
			n.authorized = true
			msg = "dc01.%s authorised in Active Directory. The DHCP server starts answering clients within a minute." % n.domain
		"scope_dns":
			n.scope_dns = "8.8.8.8"
			msg = "Scope option 006 (DNS servers) is now 8.8.8.8. PCs pick it up as they renew."
		"start_dhcp":
			n.dhcp_running = true
			msg = "DHCP Server service started."
		"recovery":
			n.recovery = "Restart the Service"
			msg = "DHCP Server recovery: first, second and later failures now restart the service."
	n.done.append({"act": what, "dev": dev})
	return msg


## What's wrong, given the player closed the step as fixed or held it. Empty = right.
static func check(n: Dictionary, held: bool) -> Array:
	var goal: Dictionary = n.goal
	var isp_down: bool = goal.fault == "wan" and goal.sub == 0
	var out: Array = []
	var did := {}
	for d in n.done:
		did[d.act] = true
		match d.act:
			"factory":
				out.append("Factory-reset FW01: every rule, the WAN settings and the VPN are gone, so the office stays offline until someone rebuilds it")
			"scope_dns":
				out.append("Pointed every PC's DNS at 8.8.8.8: in an Active Directory domain PCs must use the DC for DNS, or sign-ins, Group Policy and file shares break")
			"rule_off":
				if d.dev == "Default: allow out":
					out.append("Disabled \"Default: allow out\": now nothing on the LAN can reach the internet")
				elif d.dev == "Servers: HTTPS out only":
					out.append("Rolled back the whole \"Servers: HTTPS out only\" rule: DNS works, but that undoes the security review. A narrow allow for DC01's DNS fixes it and keeps the lockdown")
				else:
					out.append("Disabled the firewall rule \"%s\": that switches off a security control the office still needs" % d.dev)
	if did.has("isp_fault") and not isp_down:
		out.append("Logged a fault with the ISP, but their service was fine: that wastes their time and can mean a charge for a technician visit")
	if did.has("failover") and goal.fault != "wan":
		out.append("Moved the office onto the metered 4G/5G backup while the main link was fine")
	if isp_down:
		if not did.has("isp_fault"):
			out.push_front("The ISP hasn't been told: log the fault so you're on their list and get an ETA")
		if n.backup and not n.on_wan2:
			out.push_front("The office is still offline: FW01 has a 4G/5G backup link on standby. Fail over to it while the ISP fixes WAN1")
		if not held and out.is_empty():
			out.push_front("Closed it as fixed, but WAN1 is still down until the ISP restores it: hold the ticket and give the client the ETA")
		return out
	var why := why_not(n)
	if why != "":
		out.push_front("It isn't fixed: %s" % why)
	elif held:
		out.push_front("Held it, but it's fixed: test it from %s's PC and close it" % n.caller)
	if goal.fault == "dhcp" and goal.sub == 0 and n.recovery != "Restart the Service":
		out.append("The DHCP Server service's recovery is still \"Take No Action\": if it crashes again, nobody knows until the phones ring")
	return out


## Why the office still can't get online ("" = working).
static func why_not(n: Dictionary) -> String:
	if n.reset:
		return "FW01 was factory-reset and has no configuration"
	if not n.modem_power:
		return ("the office is on the metered 4G/5G backup, but WAN1 is still down because the modem has no power" if online(n)
			else "WAN1 is still down because the modem has no power")
	if not online(n):
		return "nothing can get out to the internet" if not _rule_on(n, "Default: allow out") else "the internet link is still down"
	if not dhcp_ok(n):
		return "DC01 still isn't handing out addresses because %s" % ("the DHCP Server service is stopped" if not n.dhcp_running else "the DHCP server isn't authorised in Active Directory")
	if not n.fwd_ok:
		return "DC01's only forwarder, %s, still doesn't answer, so outside names still fail" % n.fwd[0]
	for r in n.rules:
		if r.culprit and r.on and not n.allow_dns:
			return "the firewall still drops DC01's DNS queries (rule \"%s\")" % r.name
	if n.scope_dns != "192.168.1.10":
		return "PCs are being handed 8.8.8.8 for DNS instead of DC01"
	return ""


# ------------------------------------------------------------------ view (nm = the netmap.gd tab)
## [name, summary, dot (0 ok, 1 warning, 2 down)] for each device on the map.
static func devices(n: Dictionary) -> Array:
	var wan := "WAN1 up"
	if n.reset:
		wan = "factory defaults: no config"
	elif not wan1_up(n):
		wan = "WAN1 DOWN" + ("  ·  on 4G/5G backup" if n.on_wan2 else "")
	var dc_bad: bool = not dhcp_ok(n) or (online(n) and not dns_ok(n))
	return [["ISP", "The client's internet provider  ·  status page, faults", 0],
		["MODEM", "ISP modem in the network cabinet  ·  %s can see it" % n.caller, 0 if wan1_up(n) or n.reset else 2],
		["FW01", "Router + firewall (192.168.1.1)  ·  %s" % wan, 0 if online(n) and wan1_up(n) else (1 if online(n) else 2)],
		["DC01", "Domain controller (192.168.1.10)  ·  DNS + DHCP", 1 if dc_bad else 0]]


static func build(nm: Node, v: VBoxContainer, dev: String) -> void:
	var n: Dictionary = nm.net
	var on: bool = nm._enabled
	if dev in ["FW01", "DC01"] and n.goal.fault == "wan":
		UI.wrap(UI.label(v, "The office is offline, so you can't remote in: %s is at the office logged in to it, reading it out and clicking what you say." % n.caller, 13, nm.SAY))
	match dev:
		"ISP":
			UI.label(v, "ISP  ·  service status and faults", 14, UI.TEXT)
			nm._mono(v, "Service status page, the client's area:\n%s" % (
				"OUTAGE: fibre cut affecting business services. Engineers on site, estimated fix %s" % n.isp_eta
				if n.goal.fault == "wan" and n.goal.sub == 0 else "No known issues"))
			nm._button(v, "Log a fault with the ISP (a technician visit is charged if no fault is found)", nm.act.bind("isp_fault", "ISP"), on)
		"MODEM":
			UI.label(v, "MODEM  ·  on the phone with %s, at the network cabinet" % n.caller, 14, UI.TEXT)
			if not n.modem_read:
				nm._button(v, "Ask %s to read out the modem's lights" % n.caller, nm.read_modem, true)
			else:
				var lights := "Power on, line on, internet on"
				if not n.modem_power:
					lights = "All lights off"
				elif n.goal.fault == "wan" and n.goal.sub == 0:
					lights = "Power on, line on, internet OFF"
				nm._mono(v, "Lights:  %s\nPower:   its own power adapter, on the power strip under the shelf\n         (FW01, DC01 and the switch are on the UPS)" % lights)
			nm._button(v, "Ask %s to check the modem's power and cable" % n.caller, nm.act.bind("modem_check", "MODEM"), on)
		"FW01":
			_fw(nm, v, n, on)
		"DC01":
			_dc(nm, v, n, on)


static func _fw(nm: Node, v: VBoxContainer, n: Dictionary, on: bool) -> void:
	UI.label(v, "FW01  ·  Router + firewall  ›  Interfaces", 14, UI.TEXT)
	if n.reset:
		nm._mono(v, "Factory defaults. No WAN settings, no rules.")
		return
	var w1 := "WAN1  (to the ISP modem)   Link: up   Public IP: %s" % n.public_ip
	if not n.modem_power:
		w1 = "WAN1  (to the ISP modem)   Link: DOWN (no carrier)"
	elif n.goal.fault == "wan" and n.goal.sub == 0:
		w1 = "WAN1  (to the ISP modem)   Link: up   Public IP: none (no reply from the ISP)"
	var lines: Array = [w1]
	if n.backup:
		lines.append("WAN2  (4G/5G backup)       %s   Failover: manual" % ("ACTIVE, carrying traffic" if n.on_wan2 else "Standby, signal good"))
	else:
		lines.append("WAN2  not configured (no backup link on this site)")
	lines.append("LAN   192.168.1.1/24")
	nm._mono(v, "\n".join(lines))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	v.add_child(row)
	if n.backup and not n.on_wan2:
		nm._button(row, "Fail over to WAN2", nm.act.bind("failover", "FW01"), on)
	nm._button(row, "Restart FW01", nm.act.bind("restart_fw", "FW01"), on)
	nm._button(row, "Factory-reset FW01", nm.act.bind("factory", "FW01"), on)
	UI.label(v, "Outbound rules (top to bottom, first match wins)", 13, UI.MUTED)
	if n.allow_dns:
		nm._mono(v, "ON   ALLOW  DC01 DNS out  192.168.1.10 -> any  UDP/TCP 53   (added just now)")
	for r in n.rules:
		var rr := HFlowContainer.new()
		rr.add_theme_constant_override("h_separation", 8)
		v.add_child(rr)
		var l := UI.label(rr, "%s  %s" % ["ON " if r.on else "off", r.note], 13, Color("b8f5c8") if r.on else UI.MUTED)
		l.add_theme_font_override("font", UI.mono())
		if r.on:
			nm._button(rr, "Disable", nm.act.bind("rule_off", r.name), on)
	if not n.allow_dns:
		nm._button(v, "Add rule: allow DC01 (192.168.1.10) out on DNS, UDP and TCP 53", nm.act.bind("allow_dns", "FW01"), on)
	UI.label(v, "Log (latest)", 13, UI.MUTED)
	nm._mono(v, "\n".join(n.log))


static func _dc(nm: Node, v: VBoxContainer, n: Dictionary, on: bool) -> void:
	UI.label(v, "DC01  ·  DNS Manager  ›  Forwarders", 14, UI.TEXT)
	var f: Array = []
	for ip in n.fwd:
		var ok: bool = n.fwd_ok and online(n) and not _dns_blocked(n)
		f.append("%-15s %s" % [ip, "OK" if ok else "<Timed out>"])
	f.append("Use root hints if no forwarders are available: off")
	nm._mono(v, "\n".join(f))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	v.add_child(row)
	if n.fwd != GOOD_FWD:
		nm._button(row, "Replace forwarders with 1.1.1.1 and 8.8.8.8", nm.act.bind("set_fwd", "DC01"), on)
	nm._button(row, "Clear cache", nm.act.bind("clear_cache", "DC01"), on)
	UI.label(v, "DC01  ·  DHCP", 14, UI.TEXT)
	nm._mono(v, "Server:   dc01.%s   %s\nScope:    192.168.1.50 - 192.168.1.199   %s\nOptions:  003 Router 192.168.1.1   006 DNS Servers %s" % [
		n.domain, "Authorized" if n.authorized else "NOT AUTHORIZED (red down arrow)",
		"Active" if dhcp_ok(n) else "Not serving", n.scope_dns])
	var drow := HFlowContainer.new()
	drow.add_theme_constant_override("h_separation", 6)
	drow.add_theme_constant_override("v_separation", 6)
	v.add_child(drow)
	if not n.authorized:
		nm._button(drow, "Authorize", nm.act.bind("authorize", "DC01"), on)
	if n.scope_dns != "8.8.8.8":
		nm._button(drow, "Set scope DNS (006) to 8.8.8.8", nm.act.bind("scope_dns", "DC01"), on)
	UI.label(v, "DC01  ·  Services", 14, UI.TEXT)
	nm._mono(v, "DHCP Server   %s   Startup: Automatic   Recovery: %s\nDNS Server    Running   Startup: Automatic" % [
		"Running" if n.dhcp_running else "Stopped", n.recovery])
	var srow := HFlowContainer.new()
	srow.add_theme_constant_override("h_separation", 6)
	srow.add_theme_constant_override("v_separation", 6)
	v.add_child(srow)
	if not n.dhcp_running:
		nm._button(srow, "Start DHCP Server", nm.act.bind("start_dhcp", "DC01"), on)
	if n.recovery != "Restart the Service":
		nm._button(srow, "Set recovery to Restart the Service", nm.act.bind("recovery", "DC01"), on)
	UI.label(v, "DC01  ·  Event Viewer  ›  System (latest)", 14, UI.TEXT)
	nm._mono(v, "\n".join(n.events))


static func _dns_blocked(n: Dictionary) -> bool:
	for r in n.rules:
		if r.culprit and r.on and not n.allow_dns:
			return true
	return false
