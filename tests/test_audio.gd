extends GutTest
## Audio utilities and persisted player preferences; the project test runner is headless.

const Support := preload("res://tests/support.gd")

var _content: Node


func before_each() -> void:
	_content = Support.make_content()


func after_each() -> void:
	_content.free()


func test_rate_limiter_rejects_bursts_and_allows_after_interval() -> void:
	var last := {}
	assert_true(Audio.set_rate_limited("buy", 1.0, last, 0.1))
	assert_false(Audio.set_rate_limited("buy", 1.05, last, 0.1))
	assert_true(Audio.set_rate_limited("buy", 1.11, last, 0.1))


func test_audio_preferences_survive_state_roundtrip() -> void:
	var state := Support.new_state(_content)
	assert_eq(state.persist.settings.music_volume, 50.0)
	assert_eq(state.persist.settings.sfx_volume, 70.0)
	state.persist.settings.music_volume = 30
	state.persist.settings.sfx_volume = 90
	state.persist.settings.audio_mute = true
	var loaded := GameState.from_dict(_content, state.to_dict())
	assert_eq(loaded.persist.settings.music_volume, 30)
	assert_eq(loaded.persist.settings.sfx_volume, 90)
	assert_true(loaded.persist.settings.audio_mute)


func test_track_selection_uses_highest_unlocked_stage() -> void:
	var tracks := [
		{"file": "garage.ogg", "from_stage": 0},
		{"file": "models.ogg", "from_stage": 2},
		{"file": "future.ogg", "from_stage": 4},
	]
	assert_eq(Audio.track_for_stage(tracks, 1).file, "garage.ogg")
	assert_eq(Audio.track_for_stage(tracks, 3).file, "models.ogg")
	assert_eq(Audio.track_for_stage(tracks, 4).file, "future.ogg")
	assert_true(Audio.track_for_stage([], 4).is_empty())
	assert_eq(Audio.progression_stage([2, 1, 0, 0]), 2)
	assert_eq(Audio.progression_stage([3, 2, 4, 1]), 4, "the music era survives higher-layer resets")


func test_headless_audio_autoload_does_not_create_players() -> void:
	assert_eq(DisplayServer.get_name(), "headless")
	assert_true(Audio._players.is_empty())
	Audio.play("ui_tap")
