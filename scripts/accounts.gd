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
	var t := _user_in(a.users, goal.sam)
	if goal.hold:
		if touched:
			out.push_front("Changed %s's account: %s" % [t.name, goal.hold_why])
		elif not held:
			out.push_front("Nothing to mark done: %s" % goal.hold_why)
		return out
	if held:
		out.push_front("Held it, but this one was fine to do")
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
	return d


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
		"Status:      %s" % ("LOCKED OUT, %s" % u.lock_info if u.locked else ("Disabled: %s" % u.left if u.has("left") else "Enabled")),
		"Password:    %s" % u.pwd,
		"Change at next sign-in: %s" % ("Yes" if u.must_change else "No"),
		"Mobile:      ending %s" % u.mobile,
		"MFA:         %s" % u.methods,
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
	for g in acct.groups:
		var cb := CheckBox.new()
		cb.text = g
		cb.button_pressed = g in u.groups
		cb.disabled = not _enabled
		cb.focus_mode = Control.FOCUS_NONE
		cb.custom_minimum_size = Vector2(0, 44 if touch else 30)
		cb.toggled.connect(func(on: bool) -> void: set_group(g, on))
		_groups.add_child(cb)


func _action(text: String, fn: Callable, on: bool) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not (on and _enabled)
	b.custom_minimum_size = Vector2(0, 44 if touch else 34)
	b.pressed.connect(fn)
	_actions.add_child(b)
