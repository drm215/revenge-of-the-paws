extends Node

## Sound effects and music (autoload "Sound"; tools/make_audio.py makes the files). Browsers keep
## audio silent until the player's first tap; Godot starts it then.

const MUSIC_DB := -9.0
const VOICES := 10
const REPEAT_MSEC := 45  # the same effect again this soon (a blow landing on a whole pack) is skipped
const FADE := 0.5
const SETTINGS := "user://sound.cfg"

var muted := false
var current_music := ""

var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _music := AudioStreamPlayer.new()
var _music_fade: Tween
var _streams := {}
var _last_played := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for k in VOICES:
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		_voices.append(voice)
	add_child(_music)
	_music.finished.connect(_song_ended)
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		muted = cfg.get_value("sound", "muted", false)
	AudioServer.set_bus_mute(0, muted)


func _stream(sound_name: String) -> AudioStream:
	if not _streams.has(sound_name):
		var path := "res://audio/%s.wav" % sound_name
		_streams[sound_name] = load(path) if ResourceLoader.exists(path) else null
	return _streams[sound_name]


## Plays an effect. `vary` shifts its pitch at random by up to that share, so repeats don't grate.
func play(sound_name: String, vary := 0.0, volume_db := 0.0) -> void:
	var stream := _stream(sound_name)
	var now := Time.get_ticks_msec()
	if stream == null or now - int(_last_played.get(sound_name, -REPEAT_MSEC)) < REPEAT_MSEC:
		return
	_last_played[sound_name] = now
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = 1.0 + randf_range(-vary, vary)
	voice.play()


## Starts a loop ("map", "battle", "boss"), fading out whatever is playing; "" fades to silence.
func music(song: String) -> void:
	if song == current_music:
		return
	current_music = song
	if _music_fade:
		_music_fade.kill()
	if song == "":
		_music_fade = create_tween().set_ignore_time_scale(true)
		_music_fade.tween_property(_music, "volume_db", -60.0, FADE)
		_music_fade.tween_callback(_music.stop)
		return
	var stream := _stream("music_" + song)
	if stream == null:
		return
	_music_fade = create_tween().set_ignore_time_scale(true)
	if _music.playing:
		_music_fade.tween_property(_music, "volume_db", -60.0, FADE * 0.5)
	_music_fade.tween_callback(func() -> void:
		_music.stream = stream
		_music.volume_db = MUSIC_DB
		_music.play())


## Songs loop by themselves; this is for a browser that plays one through and stops.
func _song_ended() -> void:
	if current_music != "":
		_music.play()


func set_muted(on: bool) -> void:
	muted = on
	AudioServer.set_bus_mute(0, on)
	var cfg := ConfigFile.new()
	cfg.set_value("sound", "muted", on)
	cfg.save(SETTINGS)
