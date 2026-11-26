extends VBoxContainer
## Toolbox › Messages: a chat with the ticket's caller, for the details a ticket leaves out (does a
## requester need to edit the files or only view them? which key ID is on the locked laptop's screen?).
## Pick a question, and the caller types a reply a moment later. Questions a ticket must have asked
## (ask.need) are judged by check() when the ticket is closed on the Ticket tab.
## chat = {with, about, log: [{me: bool, text}], asks: [{q, a, need, missing, asked, heard}], typing: bool}
##   need = the right outcome depends on this answer; missing = the problem shown if it wasn't asked

signal changed

const UI := preload("res://scripts/ui.gd")
const REPLY_DELAY := 1.6     # seconds of "typing..." before the caller answers

var chat: Dictionary = {}
var touch := false
var log_box: VBoxContainer   # the conversation (the demo scrolls to it)
var _enabled := true
var _title: Label
var _asks: VBoxContainer
var _typing: Label


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_title = UI.label(self, "", 14, UI.ACCENT)
	log_box = VBoxContainer.new()
	log_box.add_theme_constant_override("separation", 6)
	add_child(log_box)
	_typing = UI.label(self, "", 13, UI.MUTED)
	UI.label(self, "Ask them", 13, UI.MUTED)
	_asks = VBoxContainer.new()
	_asks.add_theme_constant_override("separation", 6)
	add_child(_asks)
	UI.wrap(UI.label(self, "Get what you need here, do the work in the tool the ticket needs, then close it on the Ticket tab.", 13, UI.MUTED))


func open(c: Dictionary, client: String, enabled := true) -> void:
	chat = c
	_enabled = enabled
	_title.text = "Toolbox  ›  Messages  ·  %s, %s" % [c.with, client]
	_refresh()


## Send question i; the caller's reply lands in the chat after REPLY_DELAY (also used by the demo).
func ask(i: int) -> void:
	if not _enabled or chat.get("typing", false) or i < 0 or i >= chat.asks.size() or chat.asks[i].get("asked", false):
		return
	var c := chat
	var a: Dictionary = c.asks[i]
	a.asked = true
	c.log.append({"me": true, "text": a.q})
	c.typing = true
	_refresh()
	changed.emit()
	await get_tree().create_timer(REPLY_DELAY).timeout
	c.typing = false
	a.heard = true
	c.log.append({"me": false, "text": a.a})
	if is_same(c, chat) and is_inside_tree():
		_refresh()
		changed.emit()


## Problems with how the conversation went: questions the outcome depended on that were never
## answered (a reply still being typed doesn't count: the player never saw it).
static func check(c: Dictionary) -> Array:
	var out: Array = []
	for a in c.get("asks", []):
		if a.get("need", false) and not a.get("heard", false):
			out.append(a.missing)
	return out


func _refresh() -> void:
	for ch in log_box.get_children():
		ch.queue_free()
	for ch in _asks.get_children():
		ch.queue_free()
	UI.wrap(UI.label(log_box, chat.get("about", ""), 13, UI.MUTED))
	for m in chat.log:
		var row := HBoxContainer.new()
		log_box.add_child(row)
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(40, 0)
		var bubble := PanelContainer.new()
		bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bubble.add_theme_stylebox_override("panel", UI.box(UI.ROW_SEL if m.me else UI.ROW, 10, 10))
		var col := VBoxContainer.new()
		bubble.add_child(col)
		UI.label(col, "You" if m.me else chat.with, 12, UI.ACCENT if m.me else UI.MUTED)
		UI.wrap(UI.label(col, m.text, 15, UI.TEXT))
		if m.me:
			row.add_child(pad)
			row.add_child(bubble)
		else:
			row.add_child(bubble)
			row.add_child(pad)
	_typing.text = "%s is typing..." % chat.with.get_slice(" ", 0) if chat.get("typing", false) else ""
	_typing.visible = chat.get("typing", false)
	var left := 0
	for i in chat.asks.size():
		var a: Dictionary = chat.asks[i]
		if a.get("asked", false):
			continue
		left += 1
		var b := Button.new()
		b.text = a.q
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 48 if touch else 36)
		b.disabled = not _enabled or chat.get("typing", false)
		b.pressed.connect(ask.bind(i))
		_asks.add_child(b)
	if left == 0:
		UI.label(_asks, "You've asked everything there is to ask.", 13, UI.MUTED)
