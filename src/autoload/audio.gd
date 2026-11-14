extends Node
## Music stages follow the HUD: Garage=0, Funding=1, Models=2, Paradigm=3, Singularity=4.

const SFX := "res://assets/audio/sfx/"
const MANIFEST := "res://assets/audio/music/tracks.json"
const GAP := {"ui_tap": 0.07, "buy": 0.09, "buy_bulk": 0.12, "cant_afford": 0.12, "tab_switch": 0.1}

var _players: Array[AudioStreamPlayer] = []
var _last := {}
var _rng := RandomNumberGenerator.new()
var _manifest: Array = []
var _music: AudioStreamPlayer
var _fading: AudioStreamPlayer
var _current_track := ""
var _stage := -1
var _unlocked := false
var _paused := false
var _auto_training := ""


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_rng.randomize()
	_setup_buses()
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_fading = AudioStreamPlayer.new()
	_fading.bus = "Music"
	_fading.volume_db = -60.0
	add_child(_fading)
	_manifest = read_manifest()
	_connect_game()
	_apply_volumes()
	if OS.has_feature("web"):
		_stage = -1
	else:
		call_deferred("_sync_stage")


func _setup_buses() -> void:
	for name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, name)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")


func _connect_game() -> void:
	var g = get_node_or_null("/root/Game")
	if g == null:
		return
	g.training_finished.connect(_training_result)
	g.training_auto_started.connect(func(id): _auto_training = id)
	g.offline_progress.connect(func(_summary): play("offline_card"))
	g.producer_bought.connect(func(_id, n): play("buy_bulk" if n > 1 else "buy"))
	g.staff_hired.connect(func(_id, _n): play("hire"))
	g.research_bought.connect(func(_id): play("upgrade"))
	g.upgrade_bought.connect(func(_id): play("upgrade"))
	g.launch_fired.connect(func(_id): play("launch"))
	g.layer_reset.connect(func(layer, _gain): play("reset_small" if layer == 1 else "reset_big"))
	g.paper_offered.connect(func(_id): play("paper_offered"))
	g.paper_resolved.connect(func(_id, _choice): play("paper_choice"))
	g.event_offered.connect(func(_id): play("event_good"))
	g.event_resolved.connect(func(_id, choice): play("event_good" if choice == 0 else "event_bad"))
	g.benchmark_unlocked.connect(func(_id, _badge): play("benchmark"))
	g.ending_reached.connect(func(_id): play("ending"))
	g.news_spawned.connect(func(_id): play("news_chip"))
	g.moonshot_started.connect(func(_id): play("moonshot_start"))
	g.moonshot_finished.connect(func(_id): play("moonshot_done"))
	g.agi_advanced.connect(func(_i): play("agi_stage"))
	g.settings_changed.connect(_setting_changed)
	g.started.connect(_sync_stage)
	g.layer_reset.connect(func(_layer, _gain): call_deferred("_sync_stage"))


func _input(_event: InputEvent) -> void:
	if OS.has_feature("web") and not _unlocked:
		_unlocked = true
		_sync_stage()


func _process(_dt: float) -> void:
	if _music == null or _paused:
		return
	var g = get_node_or_null("/root/Game")
	if g != null and g.state != null and _stage != progression_stage(g.state.persist.get("lifetime_resets", [])):
		_sync_stage()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or (what == NOTIFICATION_APPLICATION_FOCUS_OUT and _mobile_or_web()):
		_paused = true
		if _music != null: _music.stream_paused = true
		if _fading != null: _fading.stream_paused = true
	elif what == NOTIFICATION_APPLICATION_RESUMED or (what == NOTIFICATION_APPLICATION_FOCUS_IN and _mobile_or_web()):
		_paused = false
		if _music != null: _music.stream_paused = false
		if _fading != null: _fading.stream_paused = false


static func _mobile_or_web() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web")


func play(id: String, automation: bool = false) -> void:
	if _players.is_empty() or bool(Game.state.persist.settings.get("audio_mute", false)):
		return
	if automation and id in ["buy", "buy_bulk", "training_start"]:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if not set_rate_limited(id, now, _last, float(GAP.get(id, 0.16))):
		return
	var p: AudioStreamPlayer
	for voice in _players:
		if not voice.playing:
			p = voice
			break
	if p == null:
		p = _players[0]
	var path := SFX + id + ".wav"
	if not ResourceLoader.exists(path):
		return
	p.stream = load(path)
	p.pitch_scale = _rng.randf_range(0.97, 1.03) if id in ["buy", "buy_bulk"] else 1.0
	p.play()


func set_rate_limited(id: String, now: float, last: Dictionary, interval: float) -> bool:
	if now - float(last.get(id, -1000.0)) < interval:
		return false
	last[id] = now
	return true


static func read_manifest(path: String = MANIFEST) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var json := JSON.new()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or json.parse(f.get_as_text()) != OK or not (json.data is Array):
		return []
	return json.data


static func track_for_stage(tracks: Array, stage: int) -> Dictionary:
	var best := {}
	for item in tracks:
		if item is Dictionary and int(item.get("from_stage", -1)) <= stage and int(item.get("from_stage", -1)) >= int(best.get("from_stage", -1)):
			best = item
	return best


static func progression_stage(lifetime_resets: Array) -> int:
	var stage := 0
	for i in mini(lifetime_resets.size(), 4):
		if int(lifetime_resets[i]) > 0:
			stage = i + 1
	return stage


func _sync_stage() -> void:
	if _music == null or (OS.has_feature("web") and not _unlocked):
		return
	var g = get_node_or_null("/root/Game")
	if g == null or g.state == null:
		return
	_stage = progression_stage(g.state.persist.get("lifetime_resets", []))
	var track := track_for_stage(_manifest, _stage)
	if track.is_empty():
		_music.stop()
		_current_track = ""
		return
	var path := String(track.get("file", ""))
	if not path.begins_with("res://"):
		path = "res://assets/audio/music/" + path
	if path == _current_track or not ResourceLoader.exists(path):
		return
	_current_track = path
	var old := _music
	_music = _fading
	_fading = old
	var stream := load(path)
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	_music.stream = stream
	_music.volume_db = -60.0
	_music.play()
	var tween := create_tween()
	tween.tween_property(_music, "volume_db", 0.0, 2.0)
	if _fading.playing:
		tween.parallel().tween_property(_fading, "volume_db", -60.0, 2.0)
		tween.tween_callback(_fading.stop)


func _volume_db(value: float) -> float:
	return -60.0 if value <= 0.0 else linear_to_db(value / 100.0)


func _apply_volumes() -> void:
	if AudioServer.get_bus_index("Music") < 0:
		return
	var s: Dictionary = Game.state.persist.settings
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), _volume_db(float(s.get("music_volume", 50))))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), _volume_db(float(s.get("sfx_volume", 70))))
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), bool(s.get("audio_mute", false)))
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), bool(s.get("audio_mute", false)))


func apply_settings() -> void:
	_apply_volumes()


func _setting_changed(_key: String, _value: Variant) -> void:
	apply_settings()


func _training_result(r: Dictionary) -> void:
	if String(r.get("id", "")) == _auto_training:
		_auto_training = ""
		return
	if bool(r.get("ok", false)):
		play("training_success")
		if bool(r.get("new_all_time", false)): play("new_best")
	else:
		play("training_fail")
