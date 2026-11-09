extends Node
## Talks to the Bunny Edge Script API. Base URL comes from window.GAME_API (set in the HTML shell).

signal logged_in(username: String, save: Dictionary)
signal auth_failed(message: String)
signal saved(ok: bool)
signal leaderboard_received(rows: Array)

const TOKEN_KEY := "helpdeskhero_token"
const DEV_BASE := "http://localhost:8787"

var base_url := DEV_BASE
var token := ""
var username := ""


func _ready() -> void:
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("window.GAME_API || ''", true)
		if v is String and v != "":
			base_url = v.strip_edges().trim_suffix("/")
			var local_dev := base_url.contains("://localhost") or base_url.contains("://127.0.0.1")
			if base_url.begins_with("http://") and not local_dev:
				base_url = "https://" + base_url.substr(7)
			elif not base_url.begins_with("http"):
				base_url = "https://" + base_url


func try_resume() -> void:
	token = _load_token()
	if token == "":
		return
	_request(HTTPClient.METHOD_GET, "/api/me", null, func(code: int, data: Dictionary) -> void:
		if code == 200:
			username = data.get("username", "")
			logged_in.emit(username, data.get("save", {}))
		else:
			token = ""
			_store_token(""))


func register(user: String, password: String) -> void:
	_auth("/api/register", user, password)


func login(user: String, password: String) -> void:
	_auth("/api/login", user, password)


var _unload_hooked := false
const LOCAL_SAVE_KEY := "helpdeskhero_save_"


## Browser copy of the latest save, per user, for reconciling with replica-lagged reads.
func cache_local(data: Dictionary) -> void:
	if OS.has_feature("web") and username != "":
		JavaScriptBridge.eval("localStorage.setItem(%s, %s)" % [JSON.stringify(LOCAL_SAVE_KEY + username.to_lower()), JSON.stringify(JSON.stringify(data))], true)


func load_local() -> Dictionary:
	if not OS.has_feature("web") or username == "":
		return {}
	var v = JavaScriptBridge.eval("localStorage.getItem(%s) || ''" % JSON.stringify(LOCAL_SAVE_KEY + username.to_lower()), true)
	var d = JSON.parse_string(v) if v is String and v != "" else null
	return d if d is Dictionary else {}


## Stash the latest save in the page; a pagehide/visibilitychange listener beacons it
## so coins collected just before closing or reloading the tab aren't lost.
func set_unload_save(data: Dictionary) -> void:
	if not OS.has_feature("web") or token == "":
		return
	if not _unload_hooked:
		_unload_hooked = true
		JavaScriptBridge.eval("""
			(function () {
				function flush() {
					var s = window.__ssSave;
					if (!s || !navigator.sendBeacon) return;
					navigator.sendBeacon(s.url, new Blob([s.body], { type: 'text/plain' }));
				}
				window.addEventListener('pagehide', flush);
				document.addEventListener('visibilitychange', function () {
					if (document.visibilityState === 'hidden') flush();
				});
			})();
		""", true)
	var body := data.duplicate()
	body["token"] = token
	var stash := {"url": base_url + "/api/save", "body": JSON.stringify(body)}
	JavaScriptBridge.eval("window.__ssSave = %s;" % JSON.stringify(stash), true)


func logout() -> void:
	token = ""
	username = ""
	_store_token("")


func save(data: Dictionary) -> void:
	if token == "":
		return
	_request(HTTPClient.METHOD_POST, "/api/save", data, func(code: int, _d: Dictionary) -> void:
		saved.emit(code == 200))


func request_leaderboard() -> void:
	_request(HTTPClient.METHOD_GET, "/api/leaderboard", null, func(code: int, data: Dictionary) -> void:
		if code == 200:
			leaderboard_received.emit(data.get("rows", [])))


func _auth(path: String, user: String, password: String) -> void:
	_request(HTTPClient.METHOD_POST, path, {"username": user, "password": password},
		func(code: int, data: Dictionary) -> void:
			if code == 200 and data.has("token"):
				token = data["token"]
				username = data.get("username", user)
				_store_token(token)
				logged_in.emit(username, data.get("save", {}))
			else:
				auth_failed.emit(str(data.get("error", "Server unreachable (%d)" % code))))


func _request(method: int, path: String, body, cb: Callable) -> void:
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	http.request_completed.connect(func(_result: int, code: int, _h: PackedStringArray, bytes: PackedByteArray) -> void:
		http.queue_free()
		var parsed = JSON.parse_string(bytes.get_string_from_utf8()) if bytes.size() > 0 else {}
		cb.call(code, parsed if parsed is Dictionary else {}))
	var headers := PackedStringArray(["Content-Type: application/json"])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	var payload := "" if body == null else JSON.stringify(body)
	var err := http.request(base_url + path, headers, method, payload)
	if err != OK:
		http.queue_free()
		cb.call(0, {"error": "Request failed"})


func _load_token() -> String:
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("localStorage.getItem('%s') || ''" % TOKEN_KEY, true)
		return v if v is String else ""
	return ""


func _store_token(t: String) -> void:
	if not OS.has_feature("web"):
		return
	if t == "":
		JavaScriptBridge.eval("localStorage.removeItem('%s')" % TOKEN_KEY, true)
	else:
		# Token is hex only, safe to inline.
		JavaScriptBridge.eval("localStorage.setItem('%s', '%s')" % [TOKEN_KEY, t], true)
