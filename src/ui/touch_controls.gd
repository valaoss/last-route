class_name TouchControls
extends Control

## Multi-touch layer. Left half: floating joystick. Right half: drag to look.
## Context buttons (on foot vs riding). The FIRE button also steers the camera
## while held, so the player can correct aim without lifting the thumb.

const JOY_RADIUS := 90.0

var player: Player
var _joy_finger := -1
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _look_finger := -1
var _look_last := Vector2.ZERO
var _btn_fingers: Dictionary = {}   # finger -> button id
var _buttons: Array[Dictionary] = []
var _aim_toggle := false


func setup(p: Player) -> void:
	player = p
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _layout() -> void:
	var s := size
	var r := s.x - 40.0
	var b := s.y - 40.0
	var u := minf(s.y / 900.0, 1.4) * 1.0
	var mirror := GameSettings.left_handed
	_buttons.clear()
	if player.is_riding():
		_add(&"throttle", "GAZ", Vector2(r - 110 * u, b - 120 * u), 100 * u, true)
		_add(&"brake", "FREN", Vector2(r - 300 * u, b - 70 * u), 62 * u, true)
		_add(&"handbrake", "KAY", Vector2(r - 120 * u, b - 330 * u), 52 * u, true)
		_add(&"interact", "İN", Vector2(r - 300 * u, b - 250 * u), 46 * u, false)
	else:
		_add(&"fire", "ATEŞ", Vector2(r - 120 * u, b - 150 * u), 92 * u, true)
		_add(&"aim", "NİŞAN", Vector2(r - 300 * u, b - 90 * u), 56 * u, false)
		_add(&"dodge", "KAÇ", Vector2(r - 60 * u, b - 330 * u), 50 * u, false)
		_add(&"melee", "VUR", Vector2(r - 210 * u, b - 330 * u), 50 * u, false)
		_add(&"reload", "R", Vector2(r - 330 * u, b - 250 * u), 40 * u, false)
		_add(&"weapon_next", "SİLAH", Vector2(r - 60 * u, b - 470 * u), 40 * u, false)
		if player._prompt != "":
			_add(&"interact", "BİN", Vector2(r - 330 * u, b - 380 * u), 46 * u, false)
		if player.inventory.count(&"medkit") > 0 and player.health < player.max_health:
			_add(&"heal", "İLAÇ", Vector2(r - 190 * u, b - 470 * u), 40 * u, false)
		if player.inventory.count(&"lure") > 0:
			_add(&"lure", "TUZAK", Vector2(r - 320 * u, b - 500 * u), 40 * u, false)
	if mirror:
		for btn in _buttons:
			btn.pos.x = s.x - btn.pos.x


func _add(action: StringName, text: String, pos: Vector2, radius: float, hold: bool) -> void:
	_buttons.append({"action": action, "text": text, "pos": pos, "r": radius, "hold": hold})


func _input(event: InputEvent) -> void:
	if player == null:
		return
	if event is InputEventScreenTouch:
		var left_side: bool = event.position.x < size.x * 0.45
		if GameSettings.left_handed:
			left_side = not left_side
		if event.pressed:
			var btn := _hit_button(event.position)
			if not btn.is_empty():
				_btn_fingers[event.index] = btn.action
				if btn.action == &"aim":
					_aim_toggle = not _aim_toggle
					if _aim_toggle:
						Input.action_press(&"aim")
					else:
						Input.action_release(&"aim")
				else:
					Input.action_press(btn.action)
				if btn.action == &"fire":
					_look_last = event.position
				if btn.action == &"throttle":
					PlayerInput.touch_throttle = 1.0
				if btn.action == &"brake":
					PlayerInput.touch_brake = 1.0
			elif left_side and _joy_finger < 0:
				_joy_finger = event.index
				_joy_origin = event.position
				_joy_pos = event.position
			elif _look_finger < 0:
				_look_finger = event.index
				_look_last = event.position
		else:
			if _btn_fingers.has(event.index):
				var a: StringName = _btn_fingers[event.index]
				if a != &"aim":
					Input.action_release(a)
				if a == &"throttle":
					PlayerInput.touch_throttle = 0.0
				if a == &"brake":
					PlayerInput.touch_brake = 0.0
				_btn_fingers.erase(event.index)
			if event.index == _joy_finger:
				_joy_finger = -1
				PlayerInput.touch_move = Vector2.ZERO
			if event.index == _look_finger:
				_look_finger = -1
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == _joy_finger:
			_joy_pos = event.position
			var d: Vector2 = (_joy_pos - _joy_origin) / JOY_RADIUS
			if d.length() > 1.0:
				_joy_origin = _joy_pos - d.normalized() * JOY_RADIUS
				d = d.normalized()
			PlayerInput.touch_move = Vector2(d.x, -d.y)
		elif event.index == _look_finger or (_btn_fingers.get(event.index) == &"fire"):
			PlayerInput.add_touch_look(event.position - _look_last)
			_look_last = event.position
		elif _btn_fingers.get(event.index) == &"throttle":
			# slide down on GAS for partial throttle
			var btn := _find(&"throttle")
			if not btn.is_empty():
				PlayerInput.touch_throttle = clampf(1.0 - (event.position.y - btn.pos.y) / (btn.r * 1.6), 0.35, 1.0)
		get_viewport().set_input_as_handled()


func _hit_button(p: Vector2) -> Dictionary:
	for b in _buttons:
		if p.distance_to(b.pos) <= b.r * 1.15:
			return b
	return {}


func _find(action: StringName) -> Dictionary:
	for b in _buttons:
		if b.action == action:
			return b
	return {}


func _process(_dt: float) -> void:
	_layout()
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	for b in _buttons:
		var active: bool = b.action in _btn_fingers.values() or (b.action == &"aim" and _aim_toggle)
		draw_circle(b.pos, b.r, Color(0.05, 0.05, 0.05, 0.38 if not active else 0.55))
		draw_arc(b.pos, b.r, 0, TAU, 48, Color(0.9, 0.87, 0.8, 0.5 if not active else 0.9), 2.0, true)
		var ts := font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_CENTER, -1, 18)
		draw_string(font, b.pos - Vector2(ts.x * 0.5, -6), b.text, HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.95, 0.92, 0.85, 0.8))
	if _joy_finger >= 0:
		draw_circle(_joy_origin, JOY_RADIUS, Color(0.05, 0.05, 0.05, 0.25))
		draw_arc(_joy_origin, JOY_RADIUS, 0, TAU, 48, Color(0.9, 0.87, 0.8, 0.35), 2.0, true)
		draw_circle(_joy_pos, 34, Color(0.9, 0.87, 0.8, 0.45))
