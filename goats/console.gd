class_name ArenaConsole
extends CanvasLayer

var list_variables: Callable
var set_variable: Callable
var load_level: Callable
var reset_level: Callable

@onready var _output: RichTextLabel = $Panel/Margin/Rows/Output
@onready var _input_field: LineEdit = $Panel/Margin/Rows/Input

# Keep command history when reset or load replaces the scene.
static var _history: Array[String] = []
var _history_index := -1


func _ready() -> void:
	var font := _output.get_theme_font("normal_font")
	var font_size := _output.get_theme_font_size("normal_font_size")
	_output.custom_minimum_size.y = ceilf(font.get_height(font_size)) * 10
	_input_field.text_submitted.connect(_run_command)


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
