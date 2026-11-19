extends VBoxContainer
## Toolbox › Mail Console: the client's message trace and the actions an admin takes on an email.
## Find the message the user reported among today's mail to them, read its headers and where every
## copy is now, then delete it from every mailbox, release it from quarantine, or block its sender
## address, sender domain or link. Actions can't be undone and go straight into mail.done; check()
## judges them when the ticket is closed on the Ticket tab with "Done" / "Hold".
## mail = {reporter, msgs: [msg], done: [{id, act}], goal: {...}}
## msg = {id, time, from_name, from_addr, reply_to, subject, auth, links, url_host ("" = no link),
##        attach, note, recips: [{name, folder}]}   folder: Inbox, Junk, Quarantine or Deleted
## goal = {id, kind ("phish" / "legit" / "hold"), release: bool, hold_why,
##         blocks: {addr|domain|url: [need, why]}}  need: 1 must block, 0 either way, -1 mustn't
## act = "purge" (soft delete every copy that's in a mailbox), "release" (quarantine to Inbox),
##       "addr", "domain" or "url" (add to the block list)

signal changed

const UI := preload("res://scripts/ui.gd")
const ACT_DONE := {"purge": "Deleted", "release": "Released", "addr": "Blocked the sender address of",
	"domain": "Blocked the sender domain of", "url": "Blocked the link in"}

var mail: Dictionary = {}
var selected := -1        # id of the open message
var touch := false
var _enabled := true
var _title: Label
var _body: VBoxContainer
var headers: Label        # the open message's headers (the demo scrolls to it)
var actions: Control      # its action buttons


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_title = UI.label(self, "", 14, UI.ACCENT)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	add_child(_body)
	UI.wrap(UI.label(self, "Actions can't be undone, so check you've got the right email first. Then close it on the Ticket tab: Done, or change nothing and hold.", 13, UI.MUTED))


func open(m: Dictionary, client: String, enabled := true) -> void:
	if not is_same(m, mail):
		selected = -1
	mail = m
	_enabled = enabled
	_title.text = "Toolbox  ›  Mail Console  ·  %s" % client
	_refresh()


func set_enabled(on: bool) -> void:
	_enabled = on
	_refresh()


# ------------------------------------------------------------------ actions (also used by the demo)
func select(id: int) -> void:
	selected = id
	_refresh()


func act(what: String) -> void:
	var m := _msg(selected)
	if not _enabled or m.is_empty() or not can(m, what):
		return
	match what:
		"purge":
			for r in m.recips:
				if r.folder != "Quarantine":
					r.folder = "Deleted"
		"release":
			for r in m.recips:
				if r.folder == "Quarantine":
					r.folder = "Inbox"
	mail.done.append({"id": m.id, "act": what})
	_refresh()
	changed.emit()


## Is this action available on this message right now?
func can(m: Dictionary, what: String) -> bool:
	if _did(mail, m.id, what):
		return false
	match what:
		"purge":
			return m.recips.any(func(r: Dictionary) -> bool: return r.folder in ["Inbox", "Junk"])
		"release":
			return m.recips.any(func(r: Dictionary) -> bool: return r.folder == "Quarantine")
		"url":
			return m.url_host != ""
	return true


## What's wrong, given the player finished ("Done") or held off. Empty = right.
static func check(m: Dictionary, held: bool) -> Array:
	var goal: Dictionary = m.goal
	var out: Array = []
	var acts: Array = []
	for d in m.done:
		if d.id != goal.id:
			var o := _msg_in(m.msgs, d.id)
			out.append("%s the \"%s\" email from %s too. That's not the one they reported" % [ACT_DONE[d.act], o.subject, o.from_name])
			continue
		acts.append(d.act)
	if goal.kind == "hold":
		if not acts.is_empty():
			out.push_front("Acted on it before it was verified: %s" % goal.hold_why)
		elif not held:
			out.push_front("Nothing to mark done: %s" % goal.hold_why)
		return out
	if held:
		out.push_front("Held it, but the headers settle this one")
		return out
	var t := _msg_in(m.msgs, goal.id)
	if goal.kind == "phish":
		var left: int = t.recips.filter(func(r: Dictionary) -> bool: return r.folder in ["Inbox", "Junk"]).size()
		if left > 0:
			out.append("The phish is still in %d mailbox%s: delete it from all of them" % [left, "" if left == 1 else "es"])
		if "release" in acts:
			out.append("Released a phish from quarantine into someone's inbox")
	else:
		if "purge" in acts:
			out.append("Deleted a legitimate email from everyone's mailbox")
		if goal.release and not "release" in acts:
			out.append("It's still in quarantine: release it so they get it")
	for k in ["addr", "domain", "url"]:
		var b: Array = goal.blocks[k]
		if b[0] == 1 and not k in acts:
			out.append(b[1])
		elif b[0] == -1 and k in acts:
			out.append(b[1])
	return out


static func _did(m: Dictionary, id: int, what: String) -> bool:
	for d in m.done:
		if d.id == id and d.act == what:
			return true
	return false


static func _msg_in(msgs: Array, id: int) -> Dictionary:
	for x in msgs:
		if x.id == id:
			return x
	return {}


static func domain_of(addr: String) -> String:
	return addr.get_slice("@", 1)


# ------------------------------------------------------------------ view
func _msg(id: int) -> Dictionary:
	return {} if mail.is_empty() else _msg_in(mail.msgs, id)


func _refresh() -> void:
	for c in _body.get_children():
		c.queue_free()
	headers = null
	actions = null
	if mail.is_empty():
		return
	UI.label(_body, "Message trace: mail to %s today (pick one to open it)" % mail.reporter, 13, UI.MUTED)
	for x in mail.msgs:
		var where := ""
		if x.recips.any(func(r: Dictionary) -> bool: return r.folder == "Quarantine"):
			where = "   [QUARANTINED]"
		elif x.recips.all(func(r: Dictionary) -> bool: return r.folder == "Deleted"):
			where = "   [DELETED]"
		var b := _button(_body, "%s  ·  %s  ·  %s%s" % [x.time, x.subject, x.from_name, where], select.bind(x.id), true)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if x.id == selected:
			b.add_theme_stylebox_override("normal", UI.box(UI.ROW_SEL, 6, 8, UI.ACCENT))
	var m := _msg(selected)
	if m.is_empty():
		return
	var lines: Array = [
		"From:       %s <%s>" % [m.from_name, m.from_addr],
		"Reply-To:   %s" % m.reply_to,
		"Subject:    %s" % m.subject,
		"Received:   today %s" % m.time,
		"Auth:       %s" % m.auth,
		"Links:      %s" % m.links,
		"Attachment: %s" % m.attach,
	]
	if m.note != "":
		lines.append("Note:       %s" % m.note)
	lines.append("")
	lines.append("Sent to %d %s (where each copy is now):" % [m.recips.size(), "person" if m.recips.size() == 1 else "people"])
	for r in m.recips:
		lines.append("  %-18s %s" % [r.name, "Deleted (Recoverable Items)" if r.folder == "Deleted" else r.folder])
	headers = _mono(_body, "\n".join(lines))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	_body.add_child(flow)
	actions = flow
	var live: int = m.recips.filter(func(r: Dictionary) -> bool: return r.folder in ["Inbox", "Junk"]).size()
	var quar: int = m.recips.filter(func(r: Dictionary) -> bool: return r.folder == "Quarantine").size()
	_act_button(flow, m, "purge", "Delete from %d mailbox%s" % [live, "" if live == 1 else "es"] if live > 0 else "Not in any mailbox")
	_act_button(flow, m, "release", "Release from quarantine" if quar > 0 else "Not quarantined")
	_act_button(flow, m, "addr", "Block address %s" % m.from_addr)
	_act_button(flow, m, "domain", "Block domain %s" % domain_of(m.from_addr))
	_act_button(flow, m, "url", "Block link %s" % m.url_host if m.url_host != "" else "No link to block")
	var blocked: Array = []
	for d in mail.done:
		var x := _msg(d.id)
		match d.act:
			"addr":
				blocked.append(x.from_addr)
			"domain":
				blocked.append(domain_of(x.from_addr))
			"url":
				blocked.append(x.url_host)
	UI.wrap(UI.label(_body, "Block list: %s" % (", ".join(blocked) if not blocked.is_empty() else "nothing added today"), 13, UI.MUTED))


func _act_button(parent: Control, m: Dictionary, what: String, text: String) -> void:
	var done := _did(mail, m.id, what)
	_button(parent, ("%s  ✓" % ACT_DONE[what] if what in ["purge", "release"] else "Blocked  ✓") if done else text,
		act.bind(what), _enabled and can(m, what))


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
