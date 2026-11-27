extends VBoxContainer
## Toolbox › Imaging Bench: the laptops waiting on the MSP's bench for a client. Pick one, run its
## diagnostics, register it in Windows Autopilot with a group tag, assign it to its user, then reset
## it so Autopilot sets it up. Every reset counts (a wipe can't be undone); check() judges the bench
## when the ticket is closed on the Ticket tab with "Done" / "Hold".
## bench = {laptops: [lt], tags: [String], people: [String], goal: {hold, asset, tag, user, need_ram, dept, hold_why}}
## lt = {asset, model, cpu, ram, disk, edition, state, notes, fault ("" / home / ram / reserved / hrhold / battery),
##       battery (health %), diag: bool, ap: {registered, tag}, user, resets: [{registered, tag, user}]}

signal changed

const UI := preload("res://scripts/ui.gd")

var bench: Dictionary = {}
var selected := ""         # asset tag of the laptop on the bench mat
var last_msg := ""         # result of the last action
var touch := false
var detail: Control        # the selected laptop's panel (the demo scrolls to it)
var actions: Control       # its Autopilot actions (the demo scrolls to them)
var _enabled := true
var _title: Label
var _body: VBoxContainer


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_title = UI.label(self, "", 14, UI.ACCENT)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	add_child(_body)
	UI.wrap(UI.label(self, "Every reset counts and a wipe can't be undone, so set it up right before you reset it. Then close it on the Ticket tab: Done, or set nothing up and hold.", 13, UI.MUTED))


func open(b: Dictionary, client: String, enabled := true) -> void:
	if not is_same(b, bench):
		selected = ""
		last_msg = ""
	bench = b
	_enabled = enabled
	_title.text = "Toolbox  ›  Imaging Bench  ·  %s" % client
	_refresh()


func set_enabled(on: bool) -> void:
	_enabled = on
	_refresh()


# ------------------------------------------------------------------ actions (also used by the demo)
func select(asset: String) -> void:
	selected = asset
	last_msg = ""
	_refresh()


func diagnose() -> void:
	var lt := _lt(selected)
	if lt.is_empty() or not _enabled:
		return
	lt.diag = true
	if lt.fault == "battery":
		last_msg = "Diagnostics: memory, storage, keyboard and screen passed. Battery FAILED: health %d%% of its design capacity. Replace the battery before this laptop goes to anyone." % lt.battery
	else:
		last_msg = "Diagnostics passed: memory, storage, keyboard, screen, and the battery at %d%% of its design capacity." % lt.battery
	_refresh()
	changed.emit()


## Upload the hardware hash to Autopilot with this group tag, or change the tag if it's registered.
func set_tag(tag: String) -> void:
	var lt := _lt(selected)
	if lt.is_empty() or not _enabled:
		return
	if lt.ap.registered and lt.ap.tag == tag:
		last_msg = "%s is already registered in Autopilot with group tag %s." % [lt.asset, tag]
	elif lt.ap.registered:
		last_msg = "Group tag changed from %s to %s in Autopilot. Its deployment profile follows once the group updates, and applies the next time the laptop is reset." % [lt.ap.tag if lt.ap.tag != "" else "(none)", tag]
	else:
		last_msg = "Hardware hash uploaded: %s is now registered in Windows Autopilot with group tag %s. The tag's deployment profile is assigned once the group updates." % [lt.asset, tag]
	lt.ap.registered = true
	lt.ap.tag = tag
	_refresh()
	changed.emit()


func assign(person: String) -> void:
	var lt := _lt(selected)
	if lt.is_empty() or not _enabled:
		return
	if not lt.ap.registered:
		last_msg = "Can't assign a user: %s isn't registered in Autopilot yet." % lt.asset
	else:
		lt.user = person
		last_msg = "Assigned to %s in Autopilot: their name and sign-in show on the laptop's setup screen." % person
	_refresh()
	changed.emit()


## Wipe it back to the out-of-box screen and let Autopilot set it up with what it's registered as now.
func reset() -> void:
	var lt := _lt(selected)
	if lt.is_empty() or not _enabled:
		return
	lt.resets.append({"registered": lt.ap.registered, "tag": lt.ap.tag, "user": lt.user})
	var shared_tag: String = bench.tags[1]
	if lt.fault == "hrhold":
		last_msg = "Wiped. Everything that was on the returned laptop is gone, including what HR asked to keep."
	elif lt.edition.ends_with("Home"):
		last_msg = "Windows setup ran, but Windows 11 Home can't join Microsoft Entra ID or enrol in Intune, so Autopilot couldn't set it up. It finished as an unmanaged personal PC."
	elif not lt.ap.registered:
		last_msg = "No Autopilot profile for this device: Windows ran its normal setup, so it isn't joined to Entra ID or managed by Intune."
	elif lt.ap.tag == shared_tag:
		last_msg = "Autopilot set it up from the %s profile: a shared front-desk PC, self-deploying with no primary user. It's set up as a shared device, not as anyone's own laptop." % shared_tag
	elif lt.ap.tag == "":
		last_msg = "Autopilot found the device but no group tag, so none of this client's deployment profiles (assigned by group tag) applies to it. Windows ran its normal setup, unmanaged."
	else:
		last_msg = "Autopilot: joined to Microsoft Entra ID, enrolled in Intune, apps and policies installing. %s" % (
			"The setup screen greets %s." % lt.user if lt.user != "" else "No user assigned, so the sign-in screen greets nobody in particular.")
	_refresh()
	changed.emit()


## What's wrong, given the player finished ("Done") or held off. Empty = right.
static func check(b: Dictionary, held: bool) -> Array:
	var goal: Dictionary = b.goal
	var out: Array = []
	var good: Dictionary = {}
	for lt in b.laptops:
		if lt.asset == goal.asset:
			good = lt
			continue
		if lt.resets.is_empty():
			continue
		out.append("Reset %s: %s" % [lt.asset, _why_not(lt, goal)])
	if goal.hold:
		if not out.is_empty():
			out.push_front("Reset a laptop when none was fit: %s" % goal.hold_why)
		elif not held:
			out.push_front("Nothing to mark done: %s" % goal.hold_why)
		return out
	if held:
		out.push_front("Held it, but %s was fit to go out" % goal.asset)
		return out
	if good.resets.is_empty():
		out.push_front("%s was never reset, so Autopilot never set it up" % goal.asset)
		return out
	var last: Dictionary = good.resets.back()  # only the last reset counts: that's how the laptop is now
	if not good.diag:
		out.append("Didn't run the bench diagnostics on %s before it went out (the client's procedure)" % good.asset)
	if not last.registered:
		out.append("%s wasn't registered in Autopilot when you reset it, so it isn't joined or managed" % good.asset)
	elif last.tag != goal.tag:
		out.append("%s was reset with group tag %s; the Client Wiki says staff laptops use %s" % [good.asset,
			last.tag if last.tag != "" else "(none)", goal.tag])
	if last.registered and last.user != goal.user:
		out.append("%s at reset: assigned to %s, not %s" % [good.asset, last.user if last.user != "" else "nobody", goal.user])
	return out


static func _why_not(lt: Dictionary, goal: Dictionary) -> String:
	match lt.fault:
		"home":
			return "it runs Windows 11 Home, which can't join Entra ID or be set up by Autopilot"
		"ram":
			return "it has %d GB of RAM and %s staff need %d GB (Client Wiki)" % [lt.ram, goal.dept, goal.need_ram]
		"reserved":
			return "it's reserved for %s" % lt.for_who
		"hrhold":
			return "HR asked for that returned laptop to be kept unwiped, and the wipe can't be undone"
		"battery":
			return "it failed its battery test (%d%% health)" % lt.battery
	return "it wasn't the one to use"


# ------------------------------------------------------------------ view
func _lt(asset: String) -> Dictionary:
	for lt in bench.get("laptops", []):
		if lt.asset == asset:
			return lt
	return {}


func _refresh() -> void:
	for c in _body.get_children():
		c.queue_free()
	detail = null
	actions = null
	if bench.is_empty():
		return
	UI.label(_body, "On the bench (pick one)", 13, UI.MUTED)
	for lt in bench.laptops:
		var b := _button(_body, "%s  ·  %s  ·  %d GB  ·  %s" % [lt.asset, lt.model, lt.ram, lt.state], select.bind(lt.asset), true)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if lt.asset == selected:
			b.add_theme_stylebox_override("normal", UI.box(UI.ROW_SEL, 6, 8, UI.ACCENT))
	var lt := _lt(selected)
	if lt.is_empty():
		return
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.box(UI.ROW, 6, 12))
	_body.add_child(panel)
	detail = panel
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	UI.label(col, "%s  ·  %s" % [lt.asset, lt.model], 15, UI.ACCENT)
	_mono(col, "\n".join([
		"Processor   %s" % lt.cpu,
		"Memory      %d GB" % lt.ram,
		"Storage     %s" % lt.disk,
		"Windows     %s" % lt.edition,
		"State       %s" % lt.state,
		"Battery     %s" % ("%d%% of design capacity%s" % [lt.battery, "  FAILED" if lt.fault == "battery" else ""] if lt.diag else "not tested yet"),
		"Autopilot   %s" % ("registered, group tag %s" % (lt.ap.tag if lt.ap.tag != "" else "(none)") if lt.ap.registered else "not registered"),
		"User        %s" % (lt.user if lt.user != "" else "(none)"),
	]))
	if lt.notes != "":
		UI.wrap(UI.label(col, "Bench note: %s" % lt.notes, 14, Color("ffd27a")))
	var act := VBoxContainer.new()
	act.add_theme_constant_override("separation", 6)
	col.add_child(act)
	actions = act
	_button(act, "Run diagnostics", diagnose, _enabled)
	UI.label(act, "Autopilot group tag (registers the hardware hash if it isn't registered yet)", 13, UI.MUTED)
	var tags := HFlowContainer.new()
	tags.add_theme_constant_override("h_separation", 6)
	tags.add_theme_constant_override("v_separation", 6)
	act.add_child(tags)
	for tag in bench.tags:
		_button(tags, "Tag: %s" % tag, set_tag.bind(tag), _enabled)
	UI.label(act, "Assign to a user (the client's people)", 13, UI.MUTED)
	var ppl := HFlowContainer.new()
	ppl.add_theme_constant_override("h_separation", 6)
	ppl.add_theme_constant_override("v_separation", 6)
	act.add_child(ppl)
	for p in bench.people:
		_button(ppl, p, assign.bind(p), _enabled)
	var rb := _button(act, "Wipe and reset: Autopilot sets it up as registered now", reset, _enabled)
	rb.add_theme_color_override("font_color", Color("ffb4bc"))
	if last_msg != "":
		var res := PanelContainer.new()
		res.add_theme_stylebox_override("panel", UI.box(UI.CONSOLE, 4, 8))
		col.add_child(res)
		UI.wrap(UI.label(res, last_msg, 13, Color("b8f5c8")))


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
