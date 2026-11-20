extends VBoxContainer
## Toolbox › Network Map: the client's office network, device by device, with live status.
## FW01 (firewall + DHCP server), SW01 (switch ports), PRINT01 (print server: queues, ports, ping,
## the printer's web page) and each printer (the caller reads its control panel and does the hands-on
## jobs). Actions can't be undone and go into net.done; check() judges them when the ticket is closed
## on the Ticket tab with "Done" (printing again) / "Hold" (waiting on the vendor or a part).
## net = {caller, users, mfps: [mfp], leases: [lease], changes: [String], spare: bool, done: [act], goal}
## mfp = {name, ip, port_ip, mac, dhcp, link, down_since, sw_port, state ("ready"/"toner"/"fuser"),
##        paused, stuck ({} or {doc, mb}), jobs, oldest, black, last_job}
## lease = {ip, host, mac, reserved, when}
## act = {act, dev, arg}: cancel / resume / port (arg = new IP) / spooler (arg = jobs it threw away) /
##       reserve (dev = host) / bounce / cable / spare / order / service
## goal = {fault ("job"/"paused"/"ip"/"cable"/"toner_spare"/"toner_order"/"fuser"), mfp, other, new_ip, hold, hold_why}

signal changed

const UI := preload("res://scripts/ui.gd")
const SAY := Color("ffd27a")     # what the caller says on the phone

var net: Dictionary = {}
var selected := ""        # device on show: FW01, SW01, PRINT01 or a printer's name
var touch := false
var last_msg := ""        # result of the last action or check
var panel_read := {}      # printers whose control panel the caller has read out
var _enabled := true
var _title: Label
var _body: VBoxContainer
var _port_edit := {}      # printer name -> its port LineEdit on PRINT01
var focus: Control        # the panel of the device on show (the demo scrolls to it)


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_title = UI.label(self, "", 14, UI.ACCENT)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	add_child(_body)
	UI.wrap(UI.label(self, "Changes can't be undone, so find the fault before you fix it. Then close it on the Ticket tab: Done once it's printing, or Hold while it waits on the vendor or a part.", 13, UI.MUTED))


func open(n: Dictionary, client: String, enabled := true) -> void:
	if not is_same(n, net):
		selected = ""
		last_msg = ""
		panel_read = {}
	net = n
	_enabled = enabled
	_title.text = "Toolbox  ›  Network Map  ·  %s" % client
	_refresh()


func set_enabled(on: bool) -> void:
	_enabled = on
	_refresh()


# ------------------------------------------------------------------ actions (also used by the demo)
func select(dev: String) -> void:
	selected = dev
	last_msg = ""
	_refresh()


func ping(name: String) -> void:
	var m := mfp_in(net, name)
	var hit := device_at(net, m.port_ip)
	if hit.is_empty():
		last_msg = "PRINT01> ping %s\nReply from 192.168.10.5: Destination host unreachable.  (x4)\nPackets: Sent = 4, Received = 4, Lost = 0 (0%% loss)\n(Those replies come from PRINT01 itself: nothing answers at %s.)" % [m.port_ip, m.port_ip]
	else:
		last_msg = "PRINT01> ping %s\nReply from %s: bytes=32 time=1ms TTL=64  (x4)\nPackets: Sent = 4, Received = 4, Lost = 0 (0%% loss)" % [m.port_ip, m.port_ip]
	_refresh()


func web_page(name: String) -> void:
	var m := mfp_in(net, name)
	var hit := device_at(net, m.port_ip)
	if hit.is_empty():
		last_msg = "http://%s\nThis site can't be reached: %s took too long to respond." % [m.port_ip, m.port_ip]
	else:
		last_msg = "http://%s  ·  %s web page\n%s\nSupplies:  black %d%%, cyan %d%%, magenta %d%%, yellow %d%%" % [
			m.port_ip, hit.name, _status_line(net, hit), hit.black, hit.cmy[0], hit.cmy[1], hit.cmy[2]]
	_refresh()


func read_panel(name: String) -> void:
	panel_read[name] = true
	_refresh()


func act(what: String, dev: String, arg = null) -> void:
	if not _enabled or net.is_empty():
		return
	if what == "port":
		arg = str(arg).strip_edges()
		if not _valid_ip(arg):
			last_msg = "\"%s\" isn't an IPv4 address." % arg
			_refresh()
			return
		if arg == mfp_in(net, dev).port_ip:
			last_msg = "The port already points at %s." % arg
			_refresh()
			return
	last_msg = apply(net, what, dev, arg)
	_refresh()
	changed.emit()


## Do an action on the network and record it. Returns what happened (static: the test uses it too).
static func apply(n: Dictionary, what: String, dev: String, arg = null) -> String:
	var m := mfp_in(n, dev)
	var who: String = n.caller
	var msg := ""
	match what:
		"cancel":
			m.stuck = {}
			msg = "Job 1 cancelled."
		"resume":
			m.paused = false
			msg = "Printing resumed on %s." % dev
		"port":
			m.port_ip = arg
			msg = "%s's port now sends to %s." % [dev, arg]
		"spooler":
			var lost := 0
			for x in n.mfps:
				lost += x.jobs
				x.jobs = 0
				x.stuck = {}
			arg = lost
			msg = "Print Spooler restarted and C:\\Windows\\System32\\spool\\PRINTERS cleared: %d waiting jobs deleted from every queue." % lost
		"reserve":
			for l in n.leases:
				if l.host == dev:
					l.reserved = true
					msg = "Reservation added: %s (%s) always gets %s." % [l.host, l.mac, l.ip]
		"bounce":
			msg = ("Port %d shut and re-enabled: still no link." % m.sw_port) if not m.link else ("Port %d dropped for a few seconds and came back up." % m.sw_port)
		"cable":
			if not m.link:
				m.link = true
				msg = "%s: \"It was hanging out of the wall socket behind the new desk. It's back in and the light's on.\"" % who
			else:
				msg = "%s: \"It's plugged in firmly at both ends and the little light's on.\"" % who
		"spare":
			if not n.spare:
				msg = "%s: \"There isn't one. The cupboard's empty.\"" % who
			elif m.state != "toner":
				msg = "%s: \"It says black is at %d%%. It doesn't need one.\"" % [who, m.black]
			else:
				n.spare = false
				m.state = "ready"
				m.black = 100
				msg = "%s: \"Done, it's warming up... and it's printing!\"" % who
		"order":
			msg = "Black toner for %s ordered on the print contract: delivery in 1-2 business days." % dev
		"service":
			msg = "Service call logged with the print vendor for %s: a technician is booked for tomorrow morning." % dev
	n.done.append({"act": what, "dev": dev, "arg": arg})
	if not m.is_empty() and printing(m):
		m.jobs = 0
	return msg


## Can the print server reach this printer and get its jobs out?
static func printing(m: Dictionary) -> bool:
	return m.link and m.port_ip == m.ip and m.state == "ready" and not m.paused and m.stuck.is_empty()


static func mfp_in(n: Dictionary, name: String) -> Dictionary:
	for m in n.mfps:
		if m.name == name:
			return m
	return {}


## The printer that answers at this IP, if any.
static func device_at(n: Dictionary, ip: String) -> Dictionary:
	for m in n.mfps:
		if m.ip == ip and m.link:
			return m
	return {}


## What's wrong, given the player finished ("Done") or held it. Empty = right.
static func check(n: Dictionary, held: bool) -> Array:
	var goal: Dictionary = n.goal
	var out: Array = []
	var did := {}
	for d in n.done:
		var m := mfp_in(n, d.dev)
		match d.act:
			"spooler":
				if d.arg > 0:
					out.append("Restarted the Print Spooler and cleared the spool folder: that threw away %d waiting jobs on every queue, so everyone has to print again" % d.arg)
				else:
					out.append("Restarted the Print Spooler and cleared the spool folder for no reason: anyone printing right then lost their job")
			"port":
				if d.arg != m.ip:
					out.append("Pointed %s's port at %s, but that printer is at %s" % [d.dev, d.arg, m.ip])
			"order":
				if d.dev != goal.mfp or not goal.fault.begins_with("toner"):
					out.append("Ordered toner %s doesn't need" % d.dev)
			"service":
				if d.dev != goal.mfp or goal.fault != "fuser":
					out.append("Logged a chargeable vendor call-out for %s, but %s" % [d.dev,
						"that printer is fine" if d.dev != goal.mfp else "it isn't a hardware fault"])
		if d.dev == goal.mfp:
			did[d.act] = true
	var t := mfp_in(n, goal.mfp)
	if goal.hold:
		var need := "order" if goal.fault == "toner_order" else "service"
		if not did.has(need):
			out.push_front("Nothing's been done to get it fixed: %s" % goal.hold_why)
		elif not held:
			out.push_front("It isn't printing yet: %s. Hold the ticket until it's fixed" % goal.hold_why)
		return out
	if not printing(t):
		out.push_front("%s still isn't printing: %s" % [t.name, why_not(t)])
	elif held:
		out.push_front("Held it, but it's printing again: close it as done")
	if goal.fault == "ip":
		var res := false
		for l in n.leases:
			if l.host == goal.mfp and l.reserved:
				res = true
		if not res:
			out.append("No DHCP reservation for %s, so it can move to another address again when its lease runs out" % goal.mfp)
	return out


static func why_not(m: Dictionary) -> String:
	if not m.link:
		return "it still has no network link"
	if m.port_ip != m.ip:
		return "its queue sends to %s, but it's at %s" % [m.port_ip, m.ip]
	if m.paused:
		return "its queue is still paused"
	if not m.stuck.is_empty():
		return "the failed job is still blocking its queue"
	if m.state == "toner":
		return "it's still out of black toner"
	return "it has a hardware fault"


## The printer's own status, as its web page and control panel show it.
static func _status_line(_n: Dictionary, m: Dictionary) -> String:
	match m.state:
		"toner":
			return "Status:    Error. Replace black toner cartridge. Printing stopped"
		"fuser":
			return "Status:    Error E-542: fuser fault. Turn off and contact service"
	if printing(m):
		return "Status:    Ready. Printing normally"
	return "Status:    Ready. No errors. Last job received: %s" % m.last_job


## The queue on PRINT01, as Print Management shows it.
static func queue_status(n: Dictionary, m: Dictionary) -> String:
	if m.paused:
		return "Paused"
	if not m.stuck.is_empty():
		return "Error - Printing"
	if device_at(n, m.port_ip).is_empty():
		return "Offline (no response from the printer)"
	if m.state == "toner":
		return "Toner/ink is out"
	if m.state == "fuser":
		return "Error"
	return "Ready"


static func _valid_ip(s: String) -> bool:
	var p := s.split(".")
	if p.size() != 4:
		return false
	for x in p:
		if not x.is_valid_int() or int(x) < 0 or int(x) > 255 or str(int(x)) != x:
			return false
	return true


# ------------------------------------------------------------------ view
func _refresh() -> void:
	_port_edit.clear()
	for c in _body.get_children():
		c.queue_free()
	focus = null
	if net.is_empty():
		return
	UI.label(_body, "Recent changes", 13, UI.MUTED)
	_mono(_body, "\n".join(net.changes))
	UI.label(_body, "Devices (pick one to open it)", 13, UI.MUTED)
	var devs: Array = [["FW01", "Firewall + DHCP server  ·  internet up", 0],
		["SW01", "Switch  ·  %d ports up" % (12 + net.mfps.filter(func(m: Dictionary) -> bool: return m.link).size()), 0],
		["PRINT01", "Print server  ·  %s" % _print01_summary(), 0 if net.mfps.all(func(m: Dictionary) -> bool: return queue_status(net, m) == "Ready") else 1]]
	for m in net.mfps:
		devs.append([m.name, "Printer  ·  switch port %d: %s" % [m.sw_port, "link up" if m.link else "NO LINK"], 0 if m.link else 2])
	for d in devs:
		var dot: String = ["●", "▲", "✖"][d[2]]
		var b := _button(_body, "%s  %s   %s" % [dot, d[0], d[1]], select.bind(d[0]), true)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_color_override("font_color", [UI.TEXT, Color(1, 0.8, 0.35), UI.BAD][d[2]])
		if d[0] == selected:
			b.add_theme_stylebox_override("normal", UI.box(UI.ROW_SEL, 6, 8, UI.ACCENT))
	if selected == "":
		return
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.box(Color("1c2233"), 6, 10))
	_body.add_child(panel)
	focus = panel
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	match selected:
		"FW01":
			_fw(v)
		"SW01":
			_switch(v)
		"PRINT01":
			_print01(v)
		_:
			_printer(v, mfp_in(net, selected))
	if last_msg != "":
		var res := PanelContainer.new()
		res.add_theme_stylebox_override("panel", UI.box(UI.CONSOLE, 4, 8))
		v.add_child(res)
		var l := UI.wrap(UI.label(res, last_msg, 13, SAY if last_msg.begins_with(net.caller + ":") else Color("b8f5c8")))
		l.add_theme_font_override("font", UI.mono())


func _print01_summary() -> String:
	var bad: Array = []
	for m in net.mfps:
		if queue_status(net, m) != "Ready":
			bad.append(m.name)
	return "all queues ready" if bad.is_empty() else "problem on %s" % ", ".join(bad)


func _fw(v: VBoxContainer) -> void:
	UI.label(v, "FW01  ·  Firewall  ›  DHCP server", 14, UI.TEXT)
	_mono(v, "Scope:     192.168.10.100 - 192.168.10.199   lease time 8 days\nServing:   since last week (took over from DC01)\nGateway:   192.168.10.1   DNS: 192.168.10.10 (DC01)")
	UI.label(v, "Leases", 13, UI.MUTED)
	for l in net.leases:
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 8)
		v.add_child(row)
		var t := UI.label(row, "%-15s  %-16s  %s  %s" % [l.ip, l.host, l.mac, l.when], 13, Color("b8f5c8"))
		t.add_theme_font_override("font", UI.mono())
		if l.reserved:
			UI.label(row, "Reserved  ✓", 13, UI.GOOD)
		else:
			_button(row, "Add reservation", act.bind("reserve", l.host), _enabled)


func _switch(v: VBoxContainer) -> void:
	UI.label(v, "SW01  ·  Switch  ›  Ports", 14, UI.TEXT)
	var up_desks := 10
	var lines: Array = ["Port  Device        Link             MAC learned", "1     FW01          up  1 Gbps       (uplink)",
		"2     PRINT01       up  1 Gbps       00:15:5d:0a:10:05", "3-13  desks         %d of 11 up" % up_desks]
	for m in net.mfps:
		lines.append("%-5d %-13s %-16s %s" % [m.sw_port, m.name, "up  100 Mbps" if m.link else "DOWN %s" % m.down_since, m.mac if m.link else "-"])
	_mono(v, "\n".join(lines))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	v.add_child(row)
	for m in net.mfps:
		_button(row, "Bounce port %d (%s)" % [m.sw_port, m.name], act.bind("bounce", m.name), _enabled)


func _print01(v: VBoxContainer) -> void:
	UI.label(v, "PRINT01  ·  Print Management  ›  Printers", 14, UI.TEXT)
	for m in net.mfps:
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", UI.box(UI.ROW, 6, 8))
		v.add_child(box)
		var q := VBoxContainer.new()
		q.add_theme_constant_override("separation", 6)
		box.add_child(q)
		var st := queue_status(net, m)
		UI.label(q, "%s  ·  %s" % [m.name, st], 14, UI.GOOD if st == "Ready" else Color(1, 0.8, 0.35))
		var lines: Array = ["Port:     IP_%s (Standard TCP/IP)" % m.port_ip]
		if m.jobs == 0:
			lines.append("Jobs:     none waiting")
		elif not m.stuck.is_empty():
			lines.append("Job 1:    %s  (%d MB)  Error - Printing, %d min ago" % [m.stuck.doc, m.stuck.mb, m.oldest])
			lines.append("Jobs 2-%d: waiting behind job 1" % m.jobs)
		else:
			lines.append("Jobs:     %d waiting, the oldest for %d min" % [m.jobs, m.oldest])
		_mono(q, "\n".join(lines))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 6)
		row.add_theme_constant_override("v_separation", 6)
		q.add_child(row)
		_button(row, "Ping printer", ping.bind(m.name), true)
		_button(row, "Open web page", web_page.bind(m.name), true)
		if not m.stuck.is_empty():
			_button(row, "Cancel job 1", act.bind("cancel", m.name), _enabled)
		if m.paused:
			_button(row, "Resume printing", act.bind("resume", m.name), _enabled)
		var prow := HFlowContainer.new()
		prow.add_theme_constant_override("h_separation", 6)
		prow.add_theme_constant_override("v_separation", 6)
		q.add_child(prow)
		var e := LineEdit.new()
		e.text = m.port_ip
		e.custom_minimum_size = Vector2(170, 44 if touch else 32)
		e.add_theme_font_override("font", UI.mono())
		e.editable = _enabled
		e.text_submitted.connect(func(s: String) -> void: act("port", m.name, s))
		prow.add_child(e)
		_port_edit[m.name] = e
		_button(prow, "Change port IP", func() -> void: act("port", m.name, e.text), _enabled)
	_button(v, "Restart Print Spooler and clear the spool folder", act.bind("spooler", "PRINT01"), _enabled)


func _printer(v: VBoxContainer, m: Dictionary) -> void:
	UI.label(v, "%s  ·  on the phone with %s, who's standing at it" % [m.name, net.caller], 14, UI.TEXT)
	if not panel_read.has(m.name):
		_button(v, "Ask %s to read out its control panel" % net.caller, read_panel.bind(m.name), true)
	else:
		var lines: Array = [_status_line(net, m).replace("Status:    ", "Screen:    "),
			"Network:   %s" % ("IP %s (%s), connected" % [m.ip, "DHCP" if m.dhcp else "static"] if m.link else "IP %s (%s), no network cable connected" % [m.ip, "DHCP" if m.dhcp else "static"]),
			"Toner:     black %d%%" % m.black]
		_mono(v, "\n".join(lines))
		var said := ""
		if not m.link:
			said = "\"Someone moved the desks around it last night, if that matters.\""
		elif m.state == "fuser":
			said = "\"I turned it off and on twice. It comes back during warm-up.\""
		if said != "":
			UI.wrap(UI.label(v, "%s: %s" % [net.caller, said], 13, SAY))
	UI.label(v, "Hands-on jobs", 13, UI.MUTED)
	_button(v, "Ask %s to check its network cable at both ends" % net.caller, act.bind("cable", m.name), _enabled)
	_button(v, "Ask %s to fit the spare black toner from the cupboard" % net.caller, act.bind("spare", m.name), _enabled)
	_button(v, "Order black toner on the print contract", act.bind("order", m.name), _enabled)
	_button(v, "Log a service call with the print vendor (on-site service is on the contract)", act.bind("service", m.name), _enabled)


func _mono(parent: Control, text: String) -> Label:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.box(UI.CONSOLE, 4, 8))
	parent.add_child(box)
	var l := UI.wrap(UI.label(box, text, 13, Color("b8f5c8")))
	l.add_theme_font_override("font", UI.mono())
	return l


## Buttons in a column wrap long text (phones); buttons in a row stay one line.
func _button(parent: Control, text: String, fn: Callable, on: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not on
	if parent is VBoxContainer:
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(0, 44 if touch else 32)
	b.pressed.connect(fn)
	parent.add_child(b)
	return b
