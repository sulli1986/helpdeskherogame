extends PanelContainer
## "What's new" panel. Reads CHANGELOG.md (bundled into the export) and build.txt (written by CI).

const SEEN_KEY := "helpdeskhero_seen_version"

var version := "dev"
var build := ""
var button: Button

var _text: RichTextLabel


func setup(button_parent: Control) -> void:
	_load()

	button = Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 14)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.pressed.connect(toggle)
	button_parent.add_child(button)
	_refresh_button()

	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(560, 420)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -280
	offset_right = 280
	offset_top = -210
	offset_bottom = 210
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.12, 0.95)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(20)
	add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "What's new"
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	if OS.has_feature("web"):
		var older := Button.new()
		older.text = "Play older days"
		older.focus_mode = Control.FOCUS_NONE
		older.pressed.connect(func() -> void: JavaScriptBridge.eval("window.open('/days/index.html', '_blank')", true))
		head.add_child(older)
	var close := Button.new()
	close.text = "Close (V)"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(toggle)
	head.add_child(close)

	var sub := Label.new()
	sub.text = "Build: %s%s" % [version, ("  ·  " + build) if build != "" else ""]
	sub.modulate = Color(1, 1, 1, 0.6)
	sub.add_theme_font_size_override("font_size", 13)
	box.add_child(sub)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_active = true
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.custom_minimum_size = Vector2(0, 320)
	_text.add_theme_font_size_override("normal_font_size", 15)
	_text.add_theme_font_size_override("bold_font_size", 18)
	box.add_child(_text)
	_text.text = _bbcode


func toggle() -> void:
	visible = not visible
	if visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_mark_seen()
		_refresh_button()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_V:
		toggle()
		get_viewport().set_input_as_handled()


# ---------- data ----------
var _bbcode := ""


func _load() -> void:
	var md := ""
	var f := FileAccess.open("res://CHANGELOG.md", FileAccess.READ)
	if f:
		md = f.get_as_text()
	var b := FileAccess.open("res://build.txt", FileAccess.READ)
	if b:
		build = b.get_as_text().strip_edges()

	var out := PackedStringArray()
	for line in md.split("\n"):
		var l := line.strip_edges()
		if l.begins_with("# "):
			continue
		if l.begins_with("## "):
			var h := l.substr(3)
			if version == "dev":
				version = h.get_slice(" — ", 0).strip_edges()
			out.append("\n[b]%s[/b]" % _esc(h))
		elif l.begins_with("- "):
			out.append("  •  " + _esc(l.substr(2)))
		elif l != "":
			out.append(_esc(l))
	_bbcode = "\n".join(out).strip_edges()
	if _bbcode == "":
		_bbcode = "No changelog bundled in this build."


func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


func _seen() -> String:
	if not OS.has_feature("web"):
		return version
	var v = JavaScriptBridge.eval("localStorage.getItem('%s') || ''" % SEEN_KEY, true)
	return v if v is String else ""


func _mark_seen() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("localStorage.setItem('%s', %s)" % [SEEN_KEY, JSON.stringify(version)], true)


func _refresh_button() -> void:
	var fresh := _seen() != version
	button.text = "%s · What's new%s  (V)" % [version, "  NEW" if fresh else ""]
	button.modulate = Color(1.0, 0.85, 0.3) if fresh else Color.WHITE
