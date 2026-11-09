extends Node
## Procedural sound effects: short blips synthesised into AudioStreamWAV buffers at startup
## (no audio files). WAV streams play as Web Audio samples in the single-threaded web build.
## play("new" | "right" | "wrong" | "warn"). M or the Sound button in the desk's top bar toggles mute (saved locally).

const RATE := 22050
const CFG := "user://settings.cfg"

signal mute_changed(is_muted: bool)

var muted := false
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	# Each sound is a list of notes: [frequency Hz, length s, wave ("sine"|"square"), volume 0-1]
	_streams["new"] = _make([[660.0, 0.07, "sine", 0.5], [880.0, 0.09, "sine", 0.5]])
	_streams["right"] = _make([[523.3, 0.07, "sine", 0.5], [659.3, 0.07, "sine", 0.5], [784.0, 0.16, "sine", 0.55]])
	_streams["wrong"] = _make([[220.0, 0.12, "square", 0.22], [165.0, 0.22, "square", 0.22]])
	_streams["warn"] = _make([[988.0, 0.06, "square", 0.18], [0.0, 0.05, "sine", 0.0], [988.0, 0.06, "square", 0.18]])
	for i in 4:  # a few voices so overlapping blips don't cut each other off
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	var cfg := ConfigFile.new()
	if cfg.load(CFG) == OK:
		muted = cfg.get_value("audio", "muted", false)


func play(id: String) -> void:
	if muted or not _streams.has(id):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[id]
	p.play()


func toggle_mute() -> void:
	muted = not muted
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	cfg.set_value("audio", "muted", muted)
	cfg.save(CFG)
	mute_changed.emit(muted)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_M:
		toggle_mute()
		get_viewport().set_input_as_handled()


func _make(notes: Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	for n in notes:
		var freq: float = n[0]
		var count := int(RATE * float(n[1]))
		var vol: float = n[3]
		var square: bool = n[2] == "square"
		for i in count:
			var t := float(i) / RATE
			var s := sin(TAU * freq * t)
			if square:
				s = 1.0 if s >= 0.0 else -1.0
			# 5ms attack, then decay to silence: no clicks between notes
			var env := minf(1.0, t / 0.005) * pow(1.0 - float(i) / count, 2.0)
			var v := int(clampf(s * env * vol, -1.0, 1.0) * 32767.0)
			data.append(v & 0xFF)
			data.append((v >> 8) & 0xFF)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
