extends Node

## Unified input source. Keyboard/mouse, gamepad and on-screen touch controls all
## write here; gameplay code reads only from this node. A bot/replay can override.

const MOUSE_SCALE := 0.0022
const STICK_LOOK_SPEED := 3.2

var touch_move := Vector2.ZERO
var touch_look_accum := Vector2.ZERO
var touch_throttle := 0.0
var touch_brake := 0.0

var override_enabled := false
var override_move := Vector2.ZERO
var override_throttle := 0.0
var override_brake := 0.0
var override_handbrake := false

var _mouse_accum := Vector2.ZERO
var _last_look_time := -100.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_accum += event.relative
		_last_look_time = _now()
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if not GameSettings.show_touch_ui:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed(&"pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## Planar move intent, x = right, y = forward. Length <= 1.
func move_vector() -> Vector2:
	if override_enabled:
		return override_move
	var v := Vector2(
		Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left"),
		Input.get_action_strength(&"move_forward") - Input.get_action_strength(&"move_back"))
	if touch_move.length_squared() > v.length_squared():
		v = touch_move
	return v.limit_length(1.0)

## Consumes accumulated look input; returns radians (yaw, pitch).
func consume_look(delta: float, aiming: bool) -> Vector2:
	var sens := GameSettings.aim_sensitivity if aiming else GameSettings.look_sensitivity
	var out := _mouse_accum * MOUSE_SCALE
	out += touch_look_accum * MOUSE_SCALE * 1.6
	_mouse_accum = Vector2.ZERO
	touch_look_accum = Vector2.ZERO
	var stick := Vector2.ZERO
	var rs := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if rs.length() > 0.15:
		stick = rs * rs.length()
		_last_look_time = _now()
	out += stick * STICK_LOOK_SPEED * delta
	if out != Vector2.ZERO:
		_last_look_time = _now()
	return out * sens

func add_touch_look(rel: Vector2) -> void:
	touch_look_accum += rel
	_last_look_time = _now()

func seconds_since_look() -> float:
	return _now() - _last_look_time

func throttle() -> float:
	if override_enabled:
		return override_throttle
	return maxf(Input.get_action_strength(&"throttle"), touch_throttle)

func brake() -> float:
	if override_enabled:
		return override_brake
	return maxf(Input.get_action_strength(&"brake"), touch_brake)

func handbrake() -> bool:
	if override_enabled:
		return override_handbrake
	return Input.is_action_pressed(&"handbrake")

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
