extends VBoxContainer
## Toolbox › Remote Control: connect to one of the client's PCs and work on a mock Windows desktop.
## Apps on the taskbar: Device Manager, Settings (System › About) and a browser on the device
## vendor's support page. Installs go straight into rc.installs; check() judges them when the
## ticket is closed on the Ticket tab with "Done" / "Hold".
## rc = {pcs: [pc], device: {name, vid, pid}, vendor, site, models: [{model, pid, archs: [String]}],
##       installs: [{pc, pkg}], goal: {hold, pc, model, arch, hold_why}}
## pc = {name, user, arch ("x64" / "ARM64"), cpu, has_device}
## pkg = "<model>|<arch>" from the vendor page, or "fixer" (the "driver updater" ad)

signal changed

const UI := preload("res://scripts/ui.gd")
const ARCH_LABEL := {"x64": "Windows 11/10, 64-bit (x64)", "ARM64": "Windows 11 on Arm (ARM64)", "x86": "Windows 10, 32-bit (x86)"}
const SYSTEM_TYPE := {"x64": "64-bit operating system, x64-based processor", "ARM64": "64-bit operating system, ARM-based processor"}
const DESKTOP := Color("12407a")

var rc: Dictionary = {}
var connected := ""        # name of the PC we're remoted onto
var app := "devmgr"        # open window: devmgr, settings, browser
var props := false         # Device Manager: the scanner's Properties open
var last_msg := ""         # result of the last install, shown in the browser
var touch := false
var pkg_buttons := {}      # pkg -> its install Button on the vendor page (the demo scrolls to it)
var _enabled := true
var _title: Label
var _body: VBoxContainer


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_title = UI.label(self, "", 14, UI.ACCENT)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	add_child(_body)
	UI.wrap(UI.label(self, "Every install counts, so pick the right package first time. Then close it on the Ticket tab: Done, or install nothing and hold.", 13, UI.MUTED))


func open(r: Dictionary, client: String, enabled := true) -> void:
	if not is_same(r, rc):
		connected = ""
		app = "devmgr"
		props = false
		last_msg = ""
	rc = r
	_enabled = enabled
	_title.text = "Toolbox  ›  Remote Control  ·  %s" % client
	_refresh()


func set_enabled(on: bool) -> void:
	_enabled = on
	_refresh()


# ------------------------------------------------------------------ actions (also used by the demo)
func connect_to(pc: String) -> void:
	if _enabled:
		connected = pc
		app = "devmgr"
		props = false
		last_msg = ""
		_refresh()


func disconnect_pc() -> void:
	connected = ""
	_refresh()


func open_app(a: String) -> void:
	app = a
	_refresh()


func show_props(on := true) -> void:
	props = on
	_refresh()


func install(pkg: String) -> void:
	if not _enabled or connected == "":
		return
	rc.installs.append({"pc": connected, "pkg": pkg})
	var pc := _pc(connected)
	if pkg == "fixer":
		last_msg = "The \"driver updater\" from the ad installed. It \"found 47 outdated drivers\", wants a paid licence to fix them, and added itself to startup. The scanner still has no driver."
	else:
		var p := pkg.split("|")
		if p[1] != pc.arch:
			last_msg = "Setup failed: this driver package is for %s. This PC is %s." % [ARCH_LABEL[p[1]], SYSTEM_TYPE[pc.arch]]
		elif not pc.has_device or _model_pid(p[0]) != rc.device.pid:
			last_msg = "Setup finished, but no matching device was found. Nothing on this PC uses the %s driver." % p[0]
		else:
			last_msg = "Driver installed. Device Manager now shows the %s under Imaging devices, working properly." % p[0]
	_refresh()
	changed.emit()


## Is the scanner on this PC working (the right driver for its model and processor installed)?
func working(pc_name: String) -> bool:
	var pc := _pc(pc_name)
	return not pc.is_empty() and pc.has_device and "%s|%s" % [rc.goal.model, pc.arch] in _pkgs_on(rc, pc_name)


## What's wrong, given the player finished ("Done") or held off. Empty = right.
static func check(r: Dictionary, held: bool) -> Array:
	var goal: Dictionary = r.goal
	var out: Array = []
	var did_right := false
	var tried := false
	for ins in r.installs:
		var pkg: String = ins.pkg
		if pkg == "fixer":
			out.append("Installed the \"driver updater\" from an ad on the page. \"Driver updater\" tools are adware at best: only ever use the vendor's own driver")
			continue
		var p := pkg.split("|")
		if ins.pc != goal.pc:
			out.append("Installed a driver on %s, but the scanner is plugged into %s" % [ins.pc, goal.pc])
			continue
		tried = true
		if goal.hold:
			continue
		if p[0] != goal.model:
			out.append("Installed the %s driver, but the hardware ID (PID_%s) says it's a %s" % [p[0], r.device.pid, goal.model])
		elif p[1] != goal.arch:
			out.append("Installed the %s package on a PC that's %s" % [ARCH_LABEL[p[1]], SYSTEM_TYPE[goal.arch]])
		else:
			did_right = true
	if goal.hold:
		if tried:
			out.push_front("Tried to install a driver: %s" % goal.hold_why)
		elif not held:
			out.push_front("Nothing to mark done: %s" % goal.hold_why)
		return out
	if held:
		out.push_front("Held it, but there's a driver for this one")
		return out
	if not did_right:
		out.push_front("The scanner still has no working driver")
	return out


static func _pkgs_on(r: Dictionary, pc_name: String) -> Array:
	var out: Array = []
	for ins in r.installs:
		if ins.pc == pc_name:
			out.append(ins.pkg)
	return out


# ------------------------------------------------------------------ view
func _pc(name: String) -> Dictionary:
	for pc in rc.get("pcs", []):
		if pc.name == name:
			return pc
	return {}


func _model_pid(model: String) -> String:
	for m in rc.models:
		if m.model == model:
			return m.pid
	return ""


func _refresh() -> void:
	pkg_buttons.clear()
	for c in _body.get_children():
		c.queue_free()
	if rc.is_empty():
		return
	if connected == "":
		UI.label(_body, "Computers (pick one to connect)", 13, UI.MUTED)
		for pc in rc.pcs:
			var b := _button(_body, "%s  ·  signed in: %s" % [pc.name, pc.user], connect_to.bind(pc.name), _enabled)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		return
	var pc := _pc(connected)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_body.add_child(head)
	var l := UI.wrap(UI.label(head, "Connected to %s  ·  %s" % [pc.name, pc.user], 14, UI.GOOD))
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_button(head, "Disconnect", disconnect_pc, true)
	# The remote screen: an app window over the desktop, taskbar along the bottom.
	var screen := PanelContainer.new()
	screen.add_theme_stylebox_override("panel", UI.box(DESKTOP, 6, 8))
	_body.add_child(screen)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 8)
	screen.add_child(sv)
	var win := PanelContainer.new()
	win.add_theme_stylebox_override("panel", UI.box(Color("1c2233"), 4, 10))
	sv.add_child(win)
	var wv := VBoxContainer.new()
	wv.add_theme_constant_override("separation", 6)
	win.add_child(wv)
	var titles := {"devmgr": "Device Manager", "settings": "Settings  ›  System  ›  About", "browser": "Browser  ·  %s" % rc.site}
	UI.label(wv, titles[app], 14, UI.TEXT)
	match app:
		"devmgr":
			_devmgr(wv, pc)
		"settings":
			_mono(wv, "\n".join([
				"Device name     %s" % pc.name,
				"Processor       %s" % pc.cpu,
				"Installed RAM   16.0 GB",
				"System type     %s" % SYSTEM_TYPE[pc.arch],
				"",
				"Edition         Windows 11 Pro",
				"Version         25H2",
			]))
		"browser":
			_browser(wv)
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 6)
	bar.add_theme_constant_override("v_separation", 6)
	sv.add_child(bar)
	for a in [["devmgr", "Device Manager"], ["settings", "Settings"], ["browser", "Browser"]]:
		var b := _button(bar, a[1], open_app.bind(a[0]), true)
		if a[0] == app:
			b.add_theme_stylebox_override("normal", UI.box(UI.ROW_SEL, 6, 8, UI.ACCENT))


func _devmgr(parent: Control, pc: Dictionary) -> void:
	var ok := working(pc.name)
	var lines: Array = [pc.name, "  > Audio inputs and outputs", "  > Bluetooth", "  > Display adapters"]
	if pc.has_device and ok:
		lines.append("  v Imaging devices")
		lines.append("      %s %s" % [rc.vendor, rc.goal.model])
	lines.append_array(["  > Keyboards", "  > Network adapters"])
	if pc.has_device and not ok:
		lines.append("  v Other devices")
		lines.append("      (!) %s" % rc.device.name)
	lines.append_array(["  > Processors", "  > Universal Serial Bus controllers"])
	_mono(parent, "\n".join(lines))
	if not pc.has_device:
		UI.wrap(UI.label(parent, "No devices with problems on this PC.", 13, UI.MUTED))
		return
	var name: String = "%s %s" % [rc.vendor, rc.goal.model] if ok else rc.device.name
	_button(parent, "Hide properties" if props else "Properties: %s" % name, show_props.bind(not props), true)
	if props:
		var status := "This device is working properly." if ok else "The drivers for this device are not installed. (Code 28)"
		_mono(parent, "Device status:\n  %s\n\nDetails  ›  Hardware Ids:\n  USB\\VID_%s&PID_%s&REV_0100\n  USB\\VID_%s&PID_%s" % [
			status, rc.device.vid, rc.device.pid, rc.device.vid, rc.device.pid])


func _browser(parent: Control) -> void:
	# A "driver updater" ad, as found on real download pages
	var ad := PanelContainer.new()
	ad.add_theme_stylebox_override("panel", UI.box(Color("5a3a00"), 4, 8))
	parent.add_child(ad)
	var av := VBoxContainer.new()
	ad.add_child(av)
	UI.wrap(UI.label(av, "Ad  ·  Your PC has outdated drivers! Our free driver updater finds and fixes them all in one click.", 13, Color("ffd27a")))
	_button(av, "Download & install the free driver updater", install.bind("fixer"), _enabled)
	UI.label(parent, "%s scanner drivers" % rc.vendor, 16, UI.ACCENT)
	var id_lines: Array = ["Which model do I have? Device Manager  ›  Properties  ›", "Details  ›  Hardware Ids shows USB\\VID_%s&PID_...:" % rc.device.vid]
	for m in rc.models:
		id_lines.append("  PID_%s   %s" % [m.pid, m.model])
	_mono(parent, "\n".join(id_lines))
	for m in rc.models:
		UI.label(parent, m.model, 15, UI.TEXT)
		for a in ["x64", "ARM64", "x86"]:
			if a in m.archs:
				var pkg := "%s|%s" % [m.model, a]
				var b := _button(parent, "%s  ·  %s  ·  Download & install" % [m.model, ARCH_LABEL[a]], install.bind(pkg), _enabled)
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				pkg_buttons[pkg] = b
		if not "ARM64" in m.archs:
			UI.wrap(UI.label(parent, "No driver for Windows on Arm (ARM64) for this model.", 13, UI.MUTED))
	if last_msg != "":
		var res := PanelContainer.new()
		res.add_theme_stylebox_override("panel", UI.box(UI.CONSOLE, 4, 8))
		parent.add_child(res)
		UI.wrap(UI.label(res, last_msg, 13, Color("b8f5c8")))


func _mono(parent: Control, text: String) -> Label:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.box(UI.CONSOLE, 4, 8))
	parent.add_child(box)
	var l := UI.wrap(UI.label(box, text, 13, Color("b8f5c8")))
	l.add_theme_font_override("font", UI.mono())
	return l


## Buttons in a column wrap long text (phones); taskbar / header buttons stay one line.
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
