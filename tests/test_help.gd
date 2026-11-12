extends GutTest
## Help content: every article resolves against live state, every inline icon exists, and every icon in
## assets/icons has a legend entry. Counts and wording are not checked, so the articles can change freely.

const Support := preload("res://tests/support.gd")
const HelpText := preload("res://src/ui/panels/parts/help_text.gd")
const ICON_DIR := "res://assets/icons"

var content: Node
var state: GameState


func before_each() -> void:
	content = autofree(Support.make_content())
	state = Support.new_state(content)


func _topics() -> Array:
	return content.get_all("help")


func _topic(id: String) -> HelpTopicDef:
	return content.get_def("help", id)


func _png_names(dir: String) -> Array:
	# Editor builds list NAME.png.import, exported builds NAME.png.remap; both map back to NAME.png.
	var names := {}
	for f in DirAccess.get_files_at(dir):
		var base := f.trim_suffix(".import").trim_suffix(".remap")
		if base.ends_with(".png"):
			names[base.get_basename()] = true
	return names.keys()


func test_every_topic_has_a_title_hint_and_body() -> void:
	assert_gt(_topics().size(), 0, "help topics exist")
	for d in _topics():
		assert_ne(d.title, "", "%s: title" % d.id)
		assert_ne(d.hint, "", "%s: hint" % d.id)
		assert_ne(d.body, "", "%s: body" % d.id)
		assert_ne(d.icon, "", "%s: icon" % d.id)
		assert_true(FileAccess.file_exists("res://assets/icons/%s.png" % d.icon) or
			FileAccess.file_exists("res://assets/icons/%s.png.import" % d.icon), "%s: icon %s exists" % [d.id, d.icon])


func test_every_unlock_condition_is_known() -> void:
	for d in _topics():
		for c in d.conditions:
			assert_true(c["type"] in Rules.CONDITION_TYPES, "%s: condition %s" % [d.id, c["type"]])


func test_every_token_resolves_on_a_fresh_save() -> void:
	for d in _topics():
		var text := HelpText.to_bbcode(d.body, content, state)
		assert_false(text.contains("UNKNOWN"), "%s: no unknown token" % d.id)


func test_every_token_resolves_on_an_advanced_save() -> void:
	state.add_cur("compute", BigNum.from_float(1e12))
	for d in _topics():
		var text := HelpText.to_bbcode(d.body, content, state)
		assert_false(text.contains("UNKNOWN"), "%s: no unknown token" % d.id)


func test_every_inline_icon_points_at_a_real_file() -> void:
	var re := RegEx.create_from_string(HelpText.RE_IMAGE)
	for d in _topics():
		for m in re.search_all(d.body):
			var folder := "icons" if m.get_string(1) == "icon" else "badges"
			var path := "res://assets/%s/%s.png" % [folder, m.get_string(2)]
			assert_true(FileAccess.file_exists(path) or FileAccess.file_exists(path + ".import"),
				"%s: %s exists" % [d.id, path])


func test_every_icon_in_the_folder_has_a_legend_entry() -> void:
	var legend := _topic("icons").body
	for name in _png_names(ICON_DIR):
		assert_true(legend.contains("[icon:%s]" % name), "legend explains icon %s" % name)


func test_training_table_has_one_row_per_run_type() -> void:
	var text := HelpText.to_bbcode(_topic("training").body, content, state)
	for d in content.get_all("training_runs"):
		assert_true(text.contains("%s: " % d.title), "training row for %s" % d.id)
		assert_true(text.contains("%s%% of compute" % str(int(float(d.spend_share) * 100.0))), "share shown for %s" % d.id)
	assert_false(text.contains("UNKNOWN"), "training help has no unresolved tokens")


func test_layer_list_names_every_reset_layer() -> void:
	var text := HelpText.to_bbcode("[layers]", content, state)
	for ld in content.get_all("layers"):
		assert_true(text.contains(ld.title), "layers list has %s" % ld.title)
