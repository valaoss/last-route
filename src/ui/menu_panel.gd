class_name MenuPanel
extends PanelContainer

## Base for in-world menus (workbench, region board): pauses the game while
## open, frees the mouse, closes on E / Esc / Tab or the close button.

signal closed

const INK := Color("e6dfcf")
const DIM := Color(0.9, 0.87, 0.8, 0.6)
const AMBER := Color("e8b04a")
const BAD := Color("c8644a")
const GOOD := Color("9fbf7a")

var body: VBoxContainer
var _was_mouse := Input.MOUSE_MODE_CAPTURED


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(620, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.075, 0.07, 0.92)
	sb.border_color = Color(0.9, 0.7, 0.3, 0.35)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(22)
	sb.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", sb)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	add_child(body)


func open(parent: Node) -> void:
	parent.add_child(self)
	_was_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	refresh()
	reset_size.call_deferred()
	_center.call_deferred()


func _center() -> void:
	position = (get_viewport_rect().size - size) * 0.5


func close() -> void:
	if not is_inside_tree():
		return
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if GameSettings.show_touch_ui else _was_mouse
	closed.emit()
	queue_free()


## Override: rebuild rows.
func refresh() -> void:
	pass


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode in [KEY_ESCAPE, KEY_E, KEY_TAB]:
			get_viewport().set_input_as_handled()
			close.call_deferred()
		else:
			_on_key(e.physical_keycode)


## Override: number-key shortcuts.
func _on_key(_code: int) -> void:
	pass


func clear_body() -> void:
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()


func label(text: String, size := 16, color := INK, wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func button(text: String, enabled: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.custom_minimum_size = Vector2(120, 44)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(cb)
	return b


func close_row() -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(button("Kapat  (E)", true, close))
	body.add_child(row)
