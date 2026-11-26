class_name ArenaConsole
extends CanvasLayer

const TEAMS_PATH := "user://teams.cfg"
const REMATCH_PATH := "user://rematch.cfg"
const MAX_GOAT_NAMES := 12

var list_variables: Callable
var set_variable: Callable
var load_level: Callable
var reset_level: Callable
var start_match: Callable

@onready var _output: RichTextLabel = $Panel/Margin/Rows/Output
@onready var _input_field: LineEdit = $Panel/Margin/Rows/Input

# Keep command history when reset or load replaces the scene.
static var _history: Array[String] = []
var _history_index := -1
var _teams: Array = []
var _teams_load_error := OK


func _ready() -> void:
	var font := _output.get_theme_font("normal_font")
	var font_size := _output.get_theme_font_size("normal_font_size")
	_output.custom_minimum_size.y = ceilf(font.get_height(font_size)) * 10
	_input_field.text_submitted.connect(_run_command)
	var config := ConfigFile.new()
	var load_error := config.load(TEAMS_PATH)
	if load_error == OK:
		var teams: Variant = config.get_value("teams", "rosters", [])
		if teams is Array:
			for team in teams:
				if not (team is Dictionary and team.get("name") is String
						and team.get("goats") is PackedStringArray
						and team["goats"].size() <= MAX_GOAT_NAMES):
					_teams_load_error = ERR_INVALID_DATA
					return
			_teams = teams
		else:
			_teams_load_error = ERR_INVALID_DATA
	elif load_error == ERR_FILE_NOT_FOUND:
		var defaults: Array = []
		for team_id in range(1, 3):
			var goats := PackedStringArray()
			for goat_id in range(1, MAX_GOAT_NAMES + 1):
				goats.append("Goat%d" % goat_id)
			defaults.append({"name": "Team%d" % team_id, "goats": goats})
		var save_error := _save_teams(defaults)
		if save_error != OK:
			show_message("Could not save default teams: " + error_string(save_error))
	else:
		_teams_load_error = load_error


func set_open(is_open: bool) -> void:
	visible = is_open
	if is_open:
		_input_field.grab_focus()
	else:
		_input_field.release_focus()


func recall_previous_command() -> bool:
	if not _input_field.has_focus() or _history.is_empty():
		return false
	if _history_index == -1:
		_history_index = _history.size()
	_history_index = maxi(0, _history_index - 1)
	_input_field.text = _history[_history_index]
	_input_field.caret_column = _input_field.text.length()
	return true


func show_message(message: String) -> void:
	var first_line := 0
	if not _output.text.is_empty():
		first_line = _output.get_line_count()
		_output.text += "\n"
	_output.text += message
	_output.scroll_to_line(first_line)


func _run_command(command: String) -> void:
	_input_field.clear()
	_history_index = -1
	var words := command.replace("\t", " ").split(" ", false)
	if words.is_empty():
		return

	_history.append(command)
	var lines := PackedStringArray(["> " + command])
	match words[0]:
		"team":
			lines.append(_run_team_command(words))
		"newmatch", "rematch":
			var error_message := _run_rematch(words) if words[0] == "rematch" else _run_new_match(words)
			if error_message.is_empty():
				return
			lines.append(error_message)
		"vars":
			if words.size() != 1:
				lines.append("Usage: vars")
			else:
				var variables: PackedStringArray = list_variables.call()
				lines.append_array(variables)
		"set":
			if words.size() != 3:
				lines.append("Usage: set varname value")
			else:
				lines.append(set_variable.call(words[1], words[2]))
		"load":
			var filename := command.strip_edges().substr(4).strip_edges()
			if filename.is_empty():
				lines.append("Usage: load level.png")
			else:
				var error_message: String = load_level.call(filename)
				if error_message.is_empty():
					return
				lines.append(error_message)
		"reset":
			if words.size() != 1:
				lines.append("Usage: reset")
			else:
				reset_level.call_deferred()
				return
		_:
			lines.append("Unknown command: " + words[0])

	show_message("\n".join(lines))


func _run_new_match(words: PackedStringArray) -> String:
	if words.size() < 6 or words.size() % 2 != 0:
		return "Usage: newmatch <level> <team> <goat count> <team> <goat count> [<team> <goat count> ...]"
	var filename := words[1]
	if filename.get_extension().to_lower() != "png":
		filename += ".png"
	return _start_match_with_teams(filename, words.slice(2))


func _run_rematch(words: PackedStringArray) -> String:
	if words.size() != 1:
		return "Usage: rematch"
	var config := ConfigFile.new()
	var error := config.load(REMATCH_PATH)
	if error == ERR_FILE_NOT_FOUND:
		return "No saved match. Start one with newmatch."
	if error != OK:
		return "Could not load rematch settings: " + error_string(error)

	var filename: Variant = config.get_value("match", "level", "")
	var team_ids: Variant = config.get_value("match", "team_ids", PackedInt32Array())
	if not (filename is String) or filename.is_empty() \
			or not (team_ids is PackedInt32Array) or team_ids.size() < 2:
		return "Invalid rematch settings. Start one with newmatch."
	var counts: Variant = config.get_value("match", "goats_per_team", PackedInt32Array())
	if not (counts is PackedInt32Array) or counts.size() != team_ids.size():
		return "Invalid rematch settings. Start one with newmatch."
	var selectors := PackedStringArray()
	for index in team_ids.size():
		selectors.append(str(team_ids[index]))
		selectors.append(str(counts[index]))
	return _start_match_with_teams(filename, selectors)


func _start_match_with_teams(filename: String, selectors: PackedStringArray) -> String:
	if _teams_load_error != OK:
		return "Could not load teams: " + error_string(_teams_load_error)

	var selected: Dictionary[int, Dictionary] = {}
	for index in range(0, selectors.size(), 2):
		var selector := selectors[index]
		var team_id := _match_team_id(selector)
		if team_id == -1:
			return "Ambiguous team name '%s'. Use a numeric ID from team list." % selector
		if team_id == 0:
			return "Unknown team '%s'. Use team list to see teams." % selector
		if selected.has(team_id):
			return "Team %d was selected more than once." % team_id
		var count_text := selectors[index + 1]
		var count := count_text.to_int()
		if not count_text.is_valid_int() or count < 1 or count > MAX_GOAT_NAMES:
			return "Goat count for '%s' must be a whole number from 1 to %d." % [selector, MAX_GOAT_NAMES]
		var roster: Dictionary = _teams[team_id - 1]
		var names: PackedStringArray = roster["goats"]
		var match_names := names.slice(0, count)
		var fallback_number := 1
		while match_names.size() < count:
			var fallback_name := "Goat%d" % fallback_number
			if not match_names.has(fallback_name):
				match_names.append(fallback_name)
			fallback_number += 1
		selected[team_id] = {"name": roster["name"], "goats": match_names}

	return start_match.call(filename, selected)


func _match_team_id(selector: String) -> int:
	if selector.is_valid_int():
		var team_id := selector.to_int()
		return team_id if team_id >= 1 and team_id <= _teams.size() else 0

	var match_id := 0
	for index in _teams.size():
		var team_name: String = _teams[index]["name"]
		if team_name.nocasecmp_to(selector) == 0:
			if match_id != 0:
				return -1
			match_id = index + 1
	return match_id


func _run_team_command(words: PackedStringArray) -> String:
	if _teams_load_error != OK:
		return "Could not load teams: " + error_string(_teams_load_error)

	if words.size() == 2 and words[1] == "list":
		var rows := PackedStringArray()
		for index in _teams.size():
			var team: Dictionary = _teams[index]
			var goats: PackedStringArray = team["goats"]
			var roster := ", ".join(goats) if not goats.is_empty() else "No goats"
			rows.append("%d. %s (%d/%d) | %s" % [
				index + 1, team["name"], goats.size(), MAX_GOAT_NAMES, roster,
			])
		return "\n".join(rows) if not rows.is_empty() else "No teams yet."

	if words.size() >= 2 and words[1] == "create":
		var team_id := _teams.size() + 1
		var team_name := "Team %d" % team_id
		if words.size() > 2:
			team_name = " ".join(words.slice(2))
		var updated_teams := _teams.duplicate()
		updated_teams.append({"name": team_name, "goats": PackedStringArray()})
		return _save_team_change(updated_teams, "Created team %d: %s" % [team_id, team_name])

	if words.size() >= 4 and words[1] in ["name", "add"]:
		var team_id := words[2].to_int()
		if not words[2].is_valid_int() or team_id < 1 or team_id > _teams.size():
			return "Unknown team ID. Use team list to see teams."

		var name_text := " ".join(words.slice(3))
		var updated_teams := _teams.duplicate()
		var team: Dictionary = _teams[team_id - 1].duplicate()
		updated_teams[team_id - 1] = team
		if words[1] == "name":
			team["name"] = name_text
			return _save_team_change(updated_teams, "Renamed team %d to %s" % [team_id, name_text])

		var goats: PackedStringArray = team["goats"]
		if goats.size() >= MAX_GOAT_NAMES:
			return "Team %d already has %d goat names." % [team_id, MAX_GOAT_NAMES]
		goats.append(name_text)
		team["goats"] = goats
		return _save_team_change(updated_teams, "Added %s to team %d." % [name_text, team_id])

	return "Usage: team create [name] | team name <id> <name> | team add <id> <goat name> | team list"


func _save_team_change(updated_teams: Array, message: String) -> String:
	var error := _save_teams(updated_teams)
	if error != OK:
		return "Could not save teams: " + error_string(error)
	return message


func _save_teams(updated_teams: Array) -> Error:
	var config := ConfigFile.new()
	config.set_value("teams", "rosters", updated_teams)
	var temporary_path := TEAMS_PATH + ".tmp"
	var error := config.save(temporary_path)
	if error == OK:
		error = DirAccess.rename_absolute(temporary_path, TEAMS_PATH)
	if error == OK:
		_teams = updated_teams
	return error
