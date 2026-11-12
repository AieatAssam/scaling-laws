extends GutTest
## App lifecycle: time away is credited on return at offline efficiency, only for the part the sim did not already
## tick through, and the card only for absences of a minute or more. Uses its own Game node with a test save path.

const Support := preload("res://tests/support.gd")
const GameScript := preload("res://src/autoload/game.gd")
const PATH := "user://test_lifecycle.json"

var game: Node


func before_each() -> void:
	Support.remove_save_files(PATH)
	game = autofree(GameScript.new())
	game.save_path = PATH
	add_child(game)  # runs _ready: a fresh state
	game.state.persist["intro_seen"] = true
	game.running = true
	watch_signals(game)


func after_each() -> void:
	Support.remove_save_files(PATH)


## Leaves for `seconds`, as if the app had been in the background that long.
func _away_for(seconds: float) -> void:
	game._begin_away()
	game._away_since -= seconds
	game._end_away()


func test_absence_is_credited_and_reported_once() -> void:
	var t0 := float(game.state.persist["stats"]["time"])
	_away_for(120.0)
	assert_almost_eq(float(game.state.persist["stats"]["time"]) - t0, 120.0, 1.0, "the 120 s is simulated")
	assert_signal_emit_count(game, "offline_progress", 1)
	var summary = get_signal_parameters(game, "offline_progress", 0)[0]
	assert_almost_eq(float(summary["away"]), 120.0, 1.0, "the card reports the real time away")
	game._end_away()  # a second resume for the same absence
	assert_signal_emit_count(game, "offline_progress", 1, "no second credit or card")


func test_time_already_ticked_is_not_credited_again() -> void:
	var t0 := float(game.state.persist["stats"]["time"])
	game._begin_away()
	game._away_since -= 120.0
	game._ticked_since = 120.0  # the whole gap was already simulated frame by frame
	game._end_away()
	assert_almost_eq(float(game.state.persist["stats"]["time"]) - t0, 0.0, 0.001, "nothing extra simulated")
	assert_signal_not_emitted(game, "offline_progress")


func test_short_absence_is_credited_without_the_card() -> void:
	var t0 := float(game.state.persist["stats"]["time"])
	var saves0: int = get_signal_emit_count(game, "saved")
	_away_for(30.0)
	assert_almost_eq(float(game.state.persist["stats"]["time"]) - t0, 30.0, 1.0, "the 30 s is simulated")
	assert_signal_not_emitted(game, "offline_progress", "under a minute: no card")
	assert_gt(get_signal_emit_count(game, "saved"), saves0, "the credited state is saved")


func test_resume_at_launch_with_no_absence_does_nothing() -> void:
	game._end_away()
	assert_signal_not_emitted(game, "offline_progress")
	assert_almost_eq(float(game.state.persist["stats"]["time"]), 0.0, 0.001)


func test_a_stopped_sim_closes_the_absence_without_credit() -> void:
	game.running = false  # the intro is up
	_away_for(300.0)
	assert_signal_not_emitted(game, "offline_progress")
	assert_eq(game._away_since, 0.0, "the measurement is closed")


func test_ticks_during_a_frame_are_capped() -> void:
	var t0 := float(game.state.persist["stats"]["time"])
	game._process(3600.0)  # a frame that carries a whole hour of gap
	assert_almost_eq(float(game.state.persist["stats"]["time"]) - t0, GameScript.MAX_TICK_SECONDS, 0.001)
