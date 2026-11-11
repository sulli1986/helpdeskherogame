extends SceneTree
## Ticket sanity test. Run: godot --headless -s tools/test_tickets.gd   (exit code 1 on failure)
## Generates thousands of tickets of every kind and checks the structure is sound, so a broken
## ticket type can never ship. It can't judge technical accuracy; that's the daily fact-check.

const PER_KIND := 500
const REQUIRED := ["kind", "priority", "client", "user", "subject", "body", "info_title", "info", "question", "options", "answer", "explain"]
# Country/city-specific terms that shouldn't appear (the game is global and generic).
const BANNED := ["perth", "nbn", "g'day", ".com.au", "fremantle", "freo", "telstra", "optus"]

# Commands run against every simulated terminal (tickets with "term"); each must print something.
const COMMANDS := ["ipconfig", "ipconfig /all", "ipconfig/all", "ipconfig /renew", "ipconfig /release",
	"ipconfig /bogus", "ping 192.168.1.1", "ping 1.1.1.1", "ping -n 2 1.1.1.1", "ping google.com",
	"ping dc01", "ping 192.168.1.77", "nslookup google.com", "nslookup google.com 8.8.8.8",
	"nslookup 192.168.1.10", "nslookup 1.1.1.1", "nslookup dc01", "tracert 1.1.1.1", "tracert dc01",
	"tracert google.com", "foo", "help"]

var fails := 0


func _init() -> void:
	var T = load("res://scripts/tickets.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var g = T.new(rng)
	for kind in T.KINDS:
		var answers := {}
		for i in PER_KIND:
			var t: Dictionary = g.make(kind)
			_check(kind, t)
			if t.has("options") and t.has("answer") and t.answer >= 0 and t.answer < t.options.size():
				answers[t.options[t.answer]] = true
		# A ticket type whose right answer never varies is a memory test, not a puzzle.
		if answers.size() < 2:
			_fail(kind, "right answer never changes across %d tickets" % PER_KIND)
	print("tickets: %d kinds x %d, %d failure(s)" % [T.KINDS.size(), PER_KIND, fails])
	quit(1 if fails > 0 else 0)


func _check(kind: String, t: Dictionary) -> void:
	for k in REQUIRED:
		if not t.has(k):
			_fail(kind, "missing field '%s'" % k)
			return
	if t.kind != kind:
		_fail(kind, "kind is '%s'" % t.kind)
	if not (t.priority is int) or t.priority < 1 or t.priority > 4:
		_fail(kind, "priority %s not 1-4" % str(t.priority))
	var opts: Array = t.options
	if opts.size() < 2 or opts.size() > 4:
		_fail(kind, "%d options (need 2-4, answered with keys 1-4)" % opts.size())
	if t.answer < 0 or t.answer >= opts.size():
		_fail(kind, "answer index %d out of range" % t.answer)
	var seen := {}
	for o in opts:
		if str(o).strip_edges() == "":
			_fail(kind, "empty option")
		if seen.has(o):
			_fail(kind, "duplicate option '%s'" % o)
		seen[o] = true
	for k in ["subject", "body", "info", "question", "explain", "client", "user"]:
		if str(t[k]).strip_edges() == "":
			_fail(kind, "empty '%s'" % k)
	var text := " ".join([t.subject, t.body, t.info, t.question, t.explain, t.client, " ".join(opts)]).to_lower()
	if t.has("term"):
		var Terminal = load("res://scripts/terminal.gd")
		if not t.has("prompt"):
			_fail(kind, "terminal ticket has no prompt")
		for cmd in COMMANDS:
			var out: String = Terminal.run(cmd, t.term)
			if out.strip_edges() == "":
				_fail(kind, "terminal printed nothing for '%s'" % cmd)
			if "%s" in out or "%d" in out:
				_fail(kind, "unfilled placeholder in terminal output for '%s'" % cmd)
			text += " " + out.to_lower()
	for b in BANNED:
		if b in text:
			_fail(kind, "region-specific term '%s'" % b)
	if "%" in text.replace("%%", "") and ("%s" in text or "%d" in text):
		_fail(kind, "unfilled format placeholder")


func _fail(kind: String, msg: String) -> void:
	fails += 1
	if fails <= 20:
		printerr("FAIL [%s] %s" % [kind, msg])
