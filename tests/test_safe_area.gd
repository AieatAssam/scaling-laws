extends GutTest
## Safe-area insets: the part of the display's safe area inside the window, as (left, top, right, bottom) in window px.

const MainScript := preload("res://src/ui/main.gd")


func test_full_safe_area_has_no_insets() -> void:
	var win := Rect2i(0, 0, 1080, 2400)
	assert_eq(MainScript.safe_insets_px(win, win), Vector4.ZERO)


func test_notch_and_gesture_bar_inset_the_top_and_bottom() -> void:
	assert_eq(MainScript.safe_insets_px(Rect2i(0, 90, 1080, 2250), Rect2i(0, 0, 1080, 2400)), Vector4(0, 90, 0, 60))


func test_landscape_cutout_insets_one_side() -> void:
	assert_eq(MainScript.safe_insets_px(Rect2i(120, 0, 2220, 1080), Rect2i(0, 0, 2340, 1080)), Vector4(120, 0, 0, 0))


func test_empty_or_outside_safe_area_gives_no_insets() -> void:
	var win := Rect2i(0, 0, 1080, 2400)
	assert_eq(MainScript.safe_insets_px(Rect2i(), win), Vector4.ZERO, "no safe area reported")
	assert_eq(MainScript.safe_insets_px(Rect2i(2000, 2000, 10, 10), win), Vector4.ZERO, "safe area off the window")


func test_window_position_is_taken_into_account() -> void:
	# A 800x600 window at (100, 50) on a 1280x720 screen; the safe area is a 100 px strip along the top.
	var insets := MainScript.safe_insets_px(Rect2i(0, 0, 1280, 100), Rect2i(100, 50, 800, 600))
	assert_eq(insets, Vector4(0, 0, 0, 550), "only the bottom of the strip is inside the window")
