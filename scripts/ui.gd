extends RefCounted
## Shared colours and tiny UI builders. Everything is built in code (no .tres themes).

const BG := Color("0b1020")
const PANEL := Color("141b2e")
const ROW := Color("1b2440")
const ROW_SEL := Color("233161")
const CONSOLE := Color("070a12")
const TEXT := Color("e8ecf5")
const MUTED := Color("8d97ad")
const ACCENT := Color("5cc8ff")
const GOOD := Color("4ade80")
const BAD := Color("ff5d6c")
const PRIORITY := {1: Color("ff4d5e"), 2: Color("ffa63d"), 3: Color("5cc8ff"), 4: Color("8d97ad")}

static var _mono: Font


static func box(colour: Color, radius := 8, margin := 12, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = colour
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	if border.a > 0.0:
		s.set_border_width_all(2)
		s.border_color = border
	return s


static func label(parent: Node, text: String, font_size := 16, colour := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", colour)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


static func wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func mono() -> Font:
	if _mono == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["DejaVu Sans Mono", "Consolas", "Menlo", "monospace"])
		_mono = f
	return _mono


static func money(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


static func theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 16
	t.set_stylebox("normal", "Button", box(ROW, 6, 8))
	t.set_stylebox("hover", "Button", box(ROW_SEL, 6, 8))
	t.set_stylebox("pressed", "Button", box(ACCENT.darkened(0.5), 6, 8))
	t.set_stylebox("disabled", "Button", box(ROW.darkened(0.2), 6, 8))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", MUTED)
	t.set_stylebox("normal", "LineEdit", box(CONSOLE, 6, 10))
	t.set_stylebox("focus", "LineEdit", box(CONSOLE, 6, 10, ACCENT))
	return t
