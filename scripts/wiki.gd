extends VBoxContainer
## Toolbox › Client Wiki: the MSP's notes on each client, the same page every time for that client
## (tickets.gd wiki_page()). Read-only: who owns each department's data and their deputy (the only
## people who can approve access to it), the client's procedures, servers and key contacts.
## Opens on the current ticket's client; the client buttons at the top open any other page.

const UI := preload("res://scripts/ui.gd")
const Tickets := preload("res://scripts/tickets.gd")

var client := ""          # the page on show
var owners_head: Label    # the data owners table's heading (the demo scrolls to it)
var _title: Label
var _clients: HFlowContainer
var _body: VBoxContainer
var _client_btns := {}


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_title = UI.label(self, "", 14, UI.ACCENT)
	_clients = HFlowContainer.new()
	_clients.add_theme_constant_override("h_separation", 6)
	_clients.add_theme_constant_override("v_separation", 6)
	add_child(_clients)
	for c in Tickets.CLIENTS:
		var b := Button.new()
		b.text = c[0]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
		b.custom_minimum_size = Vector2(0, 40 if DisplayServer.is_touchscreen_available() else 30)
		b.pressed.connect(show_client.bind(c[0]))
		_clients.add_child(b)
		_client_btns[c[0]] = b
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	add_child(_body)


## Open on this ticket's client (a different ticket's client resets the page).
func open(for_client: String) -> void:
	show_client(for_client)


func show_client(name: String) -> void:
	client = name
	_title.text = "Toolbox  ›  Client Wiki  ·  %s" % name
	for k in _client_btns:
		var on: bool = k == name
		_client_btns[k].add_theme_stylebox_override("normal", UI.box(UI.ROW_SEL if on else UI.ROW, 6, 8, UI.ACCENT if on else Color(0, 0, 0, 0)))
	for ch in _body.get_children():
		ch.queue_free()
	var p: Dictionary = Tickets.wiki_page(name)
	var top := _section("%s  ·  %s" % [name, p.domain])
	UI.wrap(UI.label(top, "%s. Office hours %s." % [p.about, p.hours], 14, UI.TEXT))
	UI.wrap(UI.label(top, "Managing Director: %s" % p.director, 14, UI.TEXT))

	var own := _section("Data owners: who approves access to each share")
	owners_head = own.get_child(0)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	own.add_child(grid)
	for h in ["Share", "Owner", "Deputy"]:
		UI.label(grid, h, 13, UI.MUTED)
	for d in Tickets.DEPTS:
		var o: Dictionary = p.owners[d]
		UI.label(grid, "FS01\\%s" % d, 14, UI.ACCENT)
		UI.wrap(UI.label(grid, "%s\n%s" % [o.owner, o.owner_title], 14, UI.TEXT))
		UI.wrap(UI.label(grid, "%s\n%s" % [o.deputy, o.deputy_title], 14, UI.TEXT))

	var proc := _section("Procedures")
	for line in p.procedures:
		UI.wrap(UI.label(proc, "•  " + line, 14, UI.TEXT))

	var srv := _section("Servers")
	for line in p.servers:
		var l := UI.wrap(UI.label(srv, line, 13, Color("b8f5c8")))
		l.add_theme_font_override("font", UI.mono())
	UI.wrap(UI.label(_body, "The wiki is read-only. Do the work in the ticket's own tool, then close it on the Ticket tab.", 13, UI.MUTED))


func _section(heading: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.box(UI.ROW, 6, 12))
	_body.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	UI.wrap(UI.label(col, heading, 15, UI.ACCENT))
	return col
