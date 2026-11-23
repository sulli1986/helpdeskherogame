extends VBoxContainer
## Toolbox › Accounts: the client's user directory. Pick a user to see their profile, then unlock,
## reset the password, require a change at next sign-in, or tick their groups. Changes go straight
## into the ticket's acct.users; check() compares them with acct.goal when the ticket is answered.
## acct = {users: [user], orig: [user] (untouched copy), groups: [String], goal: {...}}
## user = {name, sam, upn, title, locked, lock_info, pwd, reset, must_change, mobile, licence,
##         device, methods, groups: [String], left (optional: why they're disabled)}
## goal = {hold: bool, sam, unlock: bool, reset: bool, must_change: bool, add: [String], hold_why,
##         licence (optional: the licence the user must end up with), free (optional: the leaver whose
##         licence may be removed)}
## acct.skus (licence tickets only) = [{name, total, others}]: others = in use by staff not listed here.
## acct.security (MFA tickets): each user also has signins: [String] (newest first), sessions: [String],
##   auth: [{id, text}] (MFA methods), rules: [{id, text}] (inbox rules), blocked, revoked, mfa_off,
##   trusted (an IP made a trusted location), foreign_ip (optional: the attacker's IP in their log).
##   goal.revoke: sessions must be revoked; goal.remove / goal.drop: the auth / rule ids that are the
##   attacker's. Removing any other method or rule is wrong, and sign-in must not be left blocked.
## acct.bitlocker (BitLocker tickets): each user also has devices: [{name, about, keys: [{id, drive, when,
##   pwd}]}] and read: [key id] (keys read out to the caller). acct.screen = the first 8 characters of
##   the key ID on the caller's recovery screen; goal.key = the only key that may be read out.

signal changed

const UI := preload("res://scripts/ui.gd")

var acct: Dictionary = {}
var selected := ""        # sam of the open profile
var touch := false
var _enabled := true
var _list: VBoxContainer
var _profile: Label
var _actions: HFlowContainer
var _groups: VBoxContainer
var _title: Label
var _lic_head: Label
var _lic: VBoxContainer
var _sec: VBoxContainer   # MFA tickets: sign-in log, sessions, MFA methods, inbox rules
var sec_log: Control      # the sign-in log box (the demo scrolls to it)
var dev_head: Control     # BitLocker tickets: the Devices heading (the demo scrolls to it)
var shown := {}           # BitLocker key ids whose recovery password is on screen


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_title = UI.label(self, "", 14, UI.ACCENT)
	UI.label(self, "Users", 13, UI.MUTED)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	add_child(_list)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.box(UI.CONSOLE, 6, 10))
	add_child(box)
	_profile = UI.wrap(UI.label(box, "", 13, Color("b8f5c8")))
	_profile.add_theme_font_override("font", UI.mono())
	_actions = HFlowContainer.new()
	_actions.add_theme_constant_override("h_separation", 6)
	_actions.add_theme_constant_override("v_separation", 6)
	add_child(_actions)
	_sec = VBoxContainer.new()
	_sec.add_theme_constant_override("separation", 6)
	add_child(_sec)
	_lic_head = UI.label(self, "Licences (whole company)", 13, UI.MUTED)
	_lic = VBoxContainer.new()
	_lic.add_theme_constant_override("separation", 4)
	add_child(_lic)
	UI.label(self, "Groups (ticked = member)", 13, UI.MUTED)
	_groups = VBoxContainer.new()
	_groups.add_theme_constant_override("separation", 4)
	add_child(_groups)
	UI.wrap(UI.label(self, "Changes apply straight away. Then close it on the Ticket tab: Done, or change nothing and refuse / hold.", 13, UI.MUTED))


func open(a: Dictionary, client: String, enabled := true) -> void:
	if not is_same(a, acct):
		shown = {}
	acct = a
	_enabled = enabled
	_title.text = "Toolbox  ›  Accounts  ·  %s" % client
	if selected == "" or _user(selected).is_empty():
		selected = ""
	_refresh()


func set_enabled(on: bool) -> void:
	_enabled = on
	_refresh()


# ------------------------------------------------------------------ actions (also used by the demo)
func select(sam: String) -> void:
	selected = sam
	_refresh()


func unlock() -> void:
	var u := _user(selected)
	if _enabled and not u.is_empty() and u.locked:
		u.locked = false
		u.lock_info = ""
		_changed()


func reset_password() -> void:
	var u := _user(selected)
	if _enabled and not u.is_empty():
		u.reset = true
		u.pwd = "temporary password set just now (read it to them)"
		_changed()


func set_must_change(on: bool) -> void:
	var u := _user(selected)
	if _enabled and not u.is_empty():
		u.must_change = on
		_changed()


func set_group(g: String, on: bool) -> void:
	var u := _user(selected)
	if not _enabled or u.is_empty() or (g in u.groups) == on:
		return
	if on:
		u.groups.append(g)
	else:
		u.groups.erase(g)
	_changed()


## Give the open user this licence (it replaces the one they have). Needs one spare.
func assign_licence(sku: String) -> void:
	var u := _user(selected)
	if _enabled and not u.is_empty() and u.licence != sku and spare(acct, sku) > 0:
		u.licence = sku
		_changed()


func remove_licence() -> void:
	var u := _user(selected)
	if _enabled and not u.is_empty() and u.licence != "None":
		u.licence = "None"
		_changed()


func block_signin(on: bool) -> void:
	var u := _user(selected)
	if _enabled and not u.is_empty() and u.get("blocked", false) != on:
		u.blocked = on
		_changed()


## Sign them out everywhere: every refresh token and session is revoked.
func revoke_sessions() -> void:
	var u := _user(selected)
	if _enabled and not u.is_empty() and not u.get("revoked", false):
		u.revoked = true
		u.sessions = []
		_changed()


func remove_method(id: String) -> void:
	var u := _user(selected)
	if _enabled and not u.is_empty():
		u.auth = u.auth.filter(func(m: Dictionary) -> bool: return m.id != id)
		_changed()


func delete_rule(id: String) -> void:
	var u := _user(selected)
	if _enabled and not u.is_empty():
		u.rules = u.rules.filter(func(r: Dictionary) -> bool: return r.id != id)
		_changed()


func set_mfa_off(on: bool) -> void:
	var u := _user(selected)
	if _enabled and not u.is_empty() and u.get("mfa_off", false) != on:
		u.mfa_off = on
		_changed()


## Named locations are organisation-wide in Entra; the button sits on the user whose log shows the IP.
func trust_ip(on := true) -> void:
	var u := _user(selected)
	if _enabled and not u.is_empty() and u.get("foreign_ip", "") != "":
		u.trusted = u.foreign_ip if on else ""
		_changed()


## BitLocker: reveal a key's recovery password (Entra logs who looked, but nothing is disclosed yet).
func show_key(id: String) -> void:
	shown[id] = true
	_refresh()


## Read a shown recovery password out to the caller. It counts once said, right or wrong.
func read_key(id: String) -> void:
	var u := _user(selected)
	if _enabled and not u.is_empty() and shown.has(id) and not id in u.read:
		u.read.append(id)
		_changed()


## Unassigned licences of this kind the company has paid for.
static func spare(a: Dictionary, sku: String) -> int:
	for s in a.get("skus", []):
		if s.name == sku:
			var used: int = s.others
			for u in a.users:
				if u.licence == sku:
					used += 1
			return s.total - used
	return 0


## What's wrong with the directory now, given the player either finished ("Done") or held off.
## Empty = right. Every change is compared with the untouched copy in acct.orig.
static func check(a: Dictionary, held: bool) -> Array:
	var goal: Dictionary = a.goal
	var out: Array = []
	var touched := false
	for i in a.users.size():
		var u: Dictionary = a.users[i]
		var o: Dictionary = a.orig[i]
		var diffs := _diffs(u, o)
		if diffs.is_empty():
			continue
		if u.sam != goal.sam:
			if u.sam == goal.get("free", "") and not goal.hold and diffs == ["licence removed"]:
				continue  # freeing a leaver's licence is part of the job
			out.append("Changed %s's account too (%s). Nobody asked for that" % [u.name, ", ".join(diffs)])
			continue
		touched = true
		if goal.hold:
			continue
		for g in u.groups:
			if not g in o.groups and not g in goal.add:
				out.append("Shouldn't have added %s%s" % [g, ": never hand out admin rights for file access" if g == "Domain Admins" else ""])
		for g in o.groups:
			if not g in u.groups:
				out.append("Removed them from %s" % g)
		if u.reset and not o.reset and not goal.reset:
			out.append("Reset a password nobody asked to reset")
		if u.must_change and not o.must_change and not goal.must_change:
			out.append("Turned on a password change nobody asked for")
		if u.licence != o.licence and not goal.has("licence"):
			out.append("Changed their licence: nobody asked for that")
		for m in o.get("auth", []):
			if not _has_id(u.auth, m.id) and not m.id in goal.get("remove", []):
				out.append("Removed %s's own %s: they'd have to set it up again" % [u.name.get_slice(" ", 0), m.text.get_slice(" (", 0)])
		for r in o.get("rules", []):
			if not _has_id(u.rules, r.id) and not r.id in goal.get("drop", []):
				out.append("Deleted %s's own inbox rule %s" % [u.name.get_slice(" ", 0), r.text.get_slice(" (", 0)])
		if u.get("mfa_off", false):
			out.append("Turned MFA off on an account under attack: the leaked password alone would let them in")
		if u.get("trusted", "") != "":
			out.append("Made the attacker's IP %s a trusted location" % u.trusted)
		if u.get("blocked", false):
			out.append("Left sign-in blocked, so %s can't work: unblock it once it's contained" % u.name.get_slice(" ", 0))
	var t := _user_in(a.users, goal.sam)
	var read_any := false
	for x in a.users:
		for id in x.get("read", []):
			read_any = true
			if goal.hold:
				continue
			var k := _key_in(x, id)
			if x.sam != goal.sam:
				out.append("Read out %s's recovery key: that's someone else's laptop" % x.name)
			elif id != goal.key:
				out.append("Read out the key %s (%s, %s): its ID doesn't start %s like the one on their screen, so it can't unlock it and is now exposed" % [
					id.substr(0, 8), k.get("dev", "?"), k.get("drive", "?"), a.screen])
	if goal.hold:
		if read_any:
			out.push_front("Read out a recovery key: %s" % goal.hold_why)
		if touched:
			out.push_front("Changed %s's account: %s" % [t.name, goal.hold_why])
		elif not held:
			out.push_front("Nothing to mark done: %s" % goal.hold_why)
		return out
	if held:
		if goal.get("key", "") != "" and goal.key in t.get("read", []):
			out.push_front("You'd already read them the right key and they're back in: close it as Done")
		else:
			out.push_front(goal.get("held_msg", "Held it, but this one was fine to do"))
		return out
	if goal.unlock and t.locked:
		out.append("%s is still locked out" % t.name)
	if goal.reset and not t.reset:
		out.append("Password not reset")
	if goal.must_change and not t.must_change:
		out.append("No password change required at next sign-in")
	for g in goal.add:
		if not g in t.groups:
			out.append("%s isn't in %s" % [t.name, g])
	if goal.get("revoke", false) and not t.get("revoked", false):
		out.append("Sessions not revoked: the attacker's session is still signed in")
	for m in t.get("auth", []):
		if m.id in goal.get("remove", []):
			out.append("The attacker's %s is still registered" % m.text.get_slice(" (", 0))
	for r in t.get("rules", []):
		if r.id in goal.get("drop", []):
			out.append("The attacker's inbox rule %s is still hiding mail" % r.text.get_slice(" (", 0))
	if goal.get("key", "") != "" and not goal.key in t.get("read", []):
		out.append("Didn't read them the key with ID %s, so they still can't get into Windows" % a.screen)
	if goal.has("licence") and t.licence != goal.licence:
		out.append("%s has %s, but needs %s" % [t.name, "no licence" if t.licence == "None" else t.licence.trim_prefix("Microsoft 365 "), goal.licence.trim_prefix("Microsoft 365 ")])
	return out


static func _diffs(u: Dictionary, o: Dictionary) -> Array:
	var d: Array = []
	if u.locked != o.locked:
		d.append("unlocked")
	if u.reset != o.reset:
		d.append("password reset")
	if u.must_change != o.must_change:
		d.append("password change at sign-in")
	var a: Array = u.groups.duplicate()
	var b: Array = o.groups.duplicate()
	a.sort()
	b.sort()
	if a != b:
		d.append("groups")
	if u.licence != o.licence:
		d.append("licence removed" if u.licence == "None" else "licence changed")
	if u.get("blocked", false) != o.get("blocked", false):
		d.append("sign-in blocked" if u.blocked else "sign-in unblocked")
	if u.get("revoked", false) != o.get("revoked", false):
		d.append("sessions revoked")
	if u.get("auth", []).size() != o.get("auth", []).size():
		d.append("MFA method removed")
	if u.get("rules", []).size() != o.get("rules", []).size():
		d.append("inbox rule deleted")
	if u.get("mfa_off", false) != o.get("mfa_off", false):
		d.append("MFA turned off")
	if u.get("trusted", "") != o.get("trusted", ""):
		d.append("trusted location added")
	return d


static func _has_id(items: Array, id: String) -> bool:
	for x in items:
		if x.id == id:
			return true
	return false


## The key with this id on one of the user's devices, plus "dev" (the device's name).
static func _key_in(u: Dictionary, id: String) -> Dictionary:
	for d in u.get("devices", []):
		for k in d.keys:
			if k.id == id:
				var out: Dictionary = k.duplicate()
				out.dev = d.name
				return out
	return {}


static func _user_in(users: Array, sam: String) -> Dictionary:
	for u in users:
		if u.sam == sam:
			return u
	return {}


# ------------------------------------------------------------------ view
func _user(sam: String) -> Dictionary:
	return {} if acct.is_empty() else _user_in(acct.users, sam)


func _changed() -> void:
	_refresh()
	changed.emit()


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	for c in _actions.get_children():
		c.queue_free()
	for c in _groups.get_children():
		c.queue_free()
	for c in _lic.get_children():
		c.queue_free()
	for c in _sec.get_children():
		c.queue_free()
	sec_log = null
	dev_head = null
	_lic_head.visible = acct.has("skus")
	_lic.visible = acct.has("skus")
	if acct.is_empty():
		return
	for s in acct.get("skus", []):
		var n: int = spare(acct, s.name)
		UI.wrap(UI.label(_lic, "%s:  %d of %d in use, %s" % [s.name.trim_prefix("Microsoft 365 "), s.total - n, s.total,
			"%d spare" % n if n > 0 else "NONE SPARE"], 13, UI.TEXT if n > 0 else Color(1, 0.75, 0.3)))
	for u in acct.users:
		var b := Button.new()
		b.text = "%s  ·  %s%s" % [u.name, u.title, "   [LOCKED]" if u.locked else ("   [LEFT]" if u.has("left") else "")]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		b.custom_minimum_size = Vector2(0, 44 if touch else 32)
		if u.sam == selected:
			b.add_theme_stylebox_override("normal", UI.box(UI.ROW_SEL, 6, 8, UI.ACCENT))
		b.pressed.connect(select.bind(u.sam))
		_list.add_child(b)
	var u := _user(selected)
	if u.is_empty():
		_profile.text = "Pick a user to open their profile."
		return
	_profile.text = "\n".join([
		"Name:        %s (%s)" % [u.name, u.title],
		"Sign-in:     %s" % u.upn,
		"Status:      %s" % ("LOCKED OUT, %s" % u.lock_info if u.locked else ("Disabled: %s" % u.left if u.has("left") else ("SIGN-IN BLOCKED" if u.get("blocked", false) else "Enabled"))),
		"Password:    %s" % u.pwd,
		"Change at next sign-in: %s" % ("Yes" if u.must_change else "No"),
		"Mobile:      ending %s" % u.mobile,
		"MFA:         %s" % ("OFF" if u.get("mfa_off", false) else u.methods),
		"Licence:     %s" % u.licence,
		"Devices:     %s" % u.device,
	])
	_action(("Unlock" if u.locked else "Not locked"), unlock, u.locked)
	_action("Reset password", reset_password, true)
	_action("Require change at next sign-in: %s" % ("On" if u.must_change else "Off"),
		set_must_change.bind(not u.must_change), true)
	for s in acct.get("skus", []):
		var short: String = s.name.trim_prefix("Microsoft 365 ")
		var have: bool = u.licence == s.name
		_action(("Has %s" % short) if have else "Assign %s" % short, assign_licence.bind(s.name), not have and spare(acct, s.name) > 0)
	if acct.has("skus"):
		_action("Remove licence", remove_licence, u.licence != "None")
	if acct.get("security", false):
		_action("Unblock sign-in" if u.blocked else "Block sign-in", block_signin.bind(not u.blocked), true)
		_action("Turn MFA back on" if u.mfa_off else "Turn off MFA for this user", set_mfa_off.bind(not u.mfa_off), true)
		_build_security(u)
	if acct.get("bitlocker", false):
		_build_devices(u)
	for g in acct.groups:
		var cb := CheckBox.new()
		cb.text = g
		cb.button_pressed = g in u.groups
		cb.disabled = not _enabled
		cb.focus_mode = Control.FOCUS_NONE
		cb.custom_minimum_size = Vector2(0, 44 if touch else 30)
		cb.toggled.connect(func(on: bool) -> void: set_group(g, on))
		_groups.add_child(cb)


## MFA tickets: what Entra and Exchange show for this user, each item with its own action.
func _build_security(u: Dictionary) -> void:
	UI.label(_sec, "Sign-in log (newest first)", 13, UI.MUTED)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.box(UI.CONSOLE, 6, 10))
	_sec.add_child(box)
	sec_log = box
	var lg := UI.wrap(UI.label(box, "\n".join(u.signins), 13, Color("b8f5c8")))
	lg.add_theme_font_override("font", UI.mono())
	if u.get("foreign_ip", "") != "":
		_row(_sec, "Unknown IP %s in this log" % u.foreign_ip,
			"Remove trusted location" if u.trusted != "" else "Make it a trusted location (whole organisation)", trust_ip.bind(u.trusted == ""), true)
	UI.label(_sec, "Sessions", 13, UI.MUTED)
	if u.sessions.is_empty():
		UI.wrap(UI.label(_sec, "None: every session was revoked just now", 13, UI.TEXT))
	for s in u.sessions:
		UI.wrap(UI.label(_sec, s, 13, UI.TEXT))
	var rv := HFlowContainer.new()
	_sec.add_child(rv)
	var b := _button("Sessions revoked" if u.revoked else "Revoke all sessions (sign out everywhere)", revoke_sessions, not u.revoked)
	rv.add_child(b)
	UI.label(_sec, "MFA methods", 13, UI.MUTED)
	for m in u.auth:
		_row(_sec, m.text, "Remove", remove_method.bind(m.id), true)
	if u.auth.is_empty():
		UI.label(_sec, "None registered", 13, Color(1, 0.75, 0.3))
	UI.label(_sec, "Inbox rules (mailbox)", 13, UI.MUTED)
	for r in u.rules:
		_row(_sec, r.text, "Delete", delete_rule.bind(r.id), true)
	if u.rules.is_empty():
		UI.label(_sec, "No rules", 13, UI.TEXT)


## BitLocker tickets: the user's devices in Entra, each with its backed-up recovery keys.
func _build_devices(u: Dictionary) -> void:
	dev_head = UI.label(_sec, "Devices and BitLocker keys", 13, UI.MUTED)
	for d in u.devices:
		UI.wrap(UI.label(_sec, "%s  ·  %s" % [d.name, d.about], 14, UI.TEXT))
		if d.keys.is_empty():
			UI.label(_sec, "    No BitLocker keys backed up for this device", 13, Color(1, 0.75, 0.3))
		for k in d.keys:
			var box := PanelContainer.new()
			box.add_theme_stylebox_override("panel", UI.box(UI.CONSOLE, 6, 8))
			_sec.add_child(box)
			var lines: Array = ["Key ID:  %s" % k.id, "Drive:   %s, %s" % [k.drive, k.when]]
			if shown.has(k.id):
				lines.append("Recovery key:\n  %s" % k.pwd)
			var l := UI.wrap(UI.label(box, "\n".join(lines), 13, Color("b8f5c8")))
			l.add_theme_font_override("font", UI.mono())
			var row := HFlowContainer.new()
			row.add_theme_constant_override("h_separation", 6)
			_sec.add_child(row)
			if not shown.has(k.id):
				row.add_child(_button("Show recovery key", show_key.bind(k.id), true))
			elif k.id in u.read:
				var said := "They typed it in: Windows is starting." if k.id.begins_with(acct.screen) else "They typed it in: \"That key is wrong.\""
				UI.wrap(UI.label(row, "Read out.  " + said, 13, UI.GOOD if k.id.begins_with(acct.screen) else Color(1, 0.75, 0.3)))
			else:
				row.add_child(_button("Read it out to the caller", read_key.bind(k.id), true))


## A line of text with a button beside it (the button drops under the text on narrow screens).
func _row(parent: Node, text: String, btn: String, fn: Callable, on: bool) -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	parent.add_child(row)
	var l := UI.wrap(UI.label(row, text, 13, UI.TEXT))
	l.custom_minimum_size.x = 220
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_button(btn, fn, on))


func _button(text: String, fn: Callable, on: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not (on and _enabled)
	b.custom_minimum_size = Vector2(0, 44 if touch else 32)
	b.pressed.connect(fn)
	return b


func _action(text: String, fn: Callable, on: bool) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not (on and _enabled)
	b.custom_minimum_size = Vector2(0, 44 if touch else 34)
	b.pressed.connect(fn)
	_actions.add_child(b)
