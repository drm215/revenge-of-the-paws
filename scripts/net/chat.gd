extends Node

## Team chat (autoload "Chat", server/chat.sql): quick-chat phrases, map pings and typed messages
## between teammates. Polls every POLL_DELAY seconds while on a team and keeps the last KEEP.

## New messages arrived, or what's been read changed.
signal received
## A poll finished (callers waiting their turn go next).
signal _idle

const POLL_DELAY := 10.0
const MAX_LENGTH := 200
const KEEP := 100
const PING_MINUTES := 10  # a ping marks the map this long
const QUICK := ["Help!", "On my way", "Nice!", "Hold the line", "Thanks!", "Attacking next"]

## Tests point this elsewhere.
var state_path := "user://chat.cfg"
var messages: Array = []  # [{id, user_id, name, body, ping, created_at}], oldest first
var last_read := 0.0  # id of the newest message this player has seen

var _team_id := ""
var _busy := false
var _timer := Timer.new()


func _ready() -> void:
	_load_state()
	_timer.wait_time = POLL_DELAY
	_timer.timeout.connect(poll)
	add_child(_timer)
	_timer.start()
	var team := _team()
	if team:
		team.changed.connect(_on_team_changed)
	_on_team_changed()


func _team() -> Node:
	return get_node_or_null("/root/Team")


func _cloud() -> Node:
	return get_node_or_null("/root/Cloud")


func _on_team() -> bool:
	var team := _team()
	var cloud := _cloud()
	return team != null and team.on_team() and cloud != null and cloud.signed_in()


## A different team (or none): its chat starts fresh.
func _on_team_changed() -> void:
	var team := _team()
	var id: String = String(team.info.get("id", "")) if team else ""
	if id == _team_id:
		return
	_team_id = id
	messages.clear()
	last_read = 0.0
	_store_state()
	received.emit()
	poll()


## Fetches messages newer than the last one we have.
## A call while a poll is in flight waits for it, then asks again.
func poll() -> void:
	while _busy:
		await _idle
	if not _on_team():
		return
	_busy = true
	var after: float = messages[-1].id if not messages.is_empty() else 0.0
	var r: Dictionary = await _cloud().api(HTTPClient.METHOD_POST, "/rest/v1/rpc/team_messages_since", {"p_after": int(after)})
	if r.ok and r.data is Array and not (r.data as Array).is_empty():
		messages.append_array(r.data)
		messages = messages.slice(-KEEP)
		_store_state()
	_busy = false
	_idle.emit()  # after storing, so a waiting poll asks only for what's newer
	if r.ok and r.data is Array and not (r.data as Array).is_empty():
		received.emit()


## Posts a message (or a ping of territory `ping`). "" on success, else why not.
func send(body: String, ping := "") -> String:
	body = body.strip_edges().left(MAX_LENGTH)
	if body == "":
		return "Type a message first."
	if not _on_team():
		return "Join a team to chat."
	var r: Dictionary = await _cloud().api(HTTPClient.METHOD_POST, "/rest/v1/rpc/send_team_message", {"p_body": body, "p_ping": ping})
	if not r.ok:
		return _cloud().error_text(r)
	await poll()
	return ""


## Teammates' messages this player hasn't seen.
func unread() -> int:
	var n := 0
	var cloud := _cloud()
	for m: Dictionary in messages:
		if float(m.id) > last_read and (cloud == null or String(m.user_id) != cloud.user_id()):
			n += 1
	return n


func mark_read() -> void:
	if not messages.is_empty() and float(messages[-1].id) > last_read:
		last_read = float(messages[-1].id)
		_store_state()
		received.emit()


## Territory ids pinged in the last PING_MINUTES -> {who, why}. A message's ping is "id@why"
## ("open": the horde held it, "attack": it was under counterattack), or "-id" to clear it.
func recent_pings() -> Dictionary:
	var out := {}
	var now := Time.get_unix_time_from_system()
	for m: Dictionary in messages:
		var ping := String(m.get("ping", ""))
		if ping == "" or now - _posted(m) >= PING_MINUTES * 60:
			continue
		if ping.begins_with("-"):
			out.erase(ping.substr(1))
		else:
			out[ping.get_slice("@", 0)] = {"who": String(m.name).get_slice(" · ", 0), "why": ping.get_slice("@", 1)}
	return out


## When a message was posted (unix seconds, UTC).
static func _posted(m: Dictionary) -> float:
	return Time.get_unix_time_from_datetime_string(String(m.get("created_at", "")).left(19))


func _store_state() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("chat", "team", _team_id)
	cfg.set_value("chat", "messages", JSON.stringify(messages))
	cfg.set_value("chat", "last_read", last_read)
	cfg.save(state_path)


func _load_state() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(state_path) != OK:
		return
	_team_id = cfg.get_value("chat", "team", "")
	var parsed: Variant = JSON.parse_string(cfg.get_value("chat", "messages", "[]"))
	messages = parsed if parsed is Array else []
	last_read = cfg.get_value("chat", "last_read", 0.0)
