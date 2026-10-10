extends Node

## Player-facing options + input map bootstrap. Persisted to user://settings.cfg.

signal changed

enum ControlScheme { ARCADE, ASSISTED }
enum AimAssist { OFF, LOW, MEDIUM }

const PATH := "user://settings.cfg"

var control_scheme: int = ControlScheme.ARCADE
var aim_assist: int = AimAssist.MEDIUM
var camera_shake := true
var speed_fov := true
var look_sensitivity := 1.0
var aim_sensitivity := 0.7
var left_handed := false
var show_touch_ui := false

func _ready() -> void:
	_setup_input_map()
	load_settings()
	show_touch_ui = show_touch_ui or OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	control_scheme = clampi(cf.get_value("controls", "scheme", control_scheme), 0, 1)
	aim_assist = clampi(cf.get_value("controls", "aim_assist", aim_assist), 0, 2)
	camera_shake = bool(cf.get_value("camera", "shake", camera_shake))
	speed_fov = bool(cf.get_value("camera", "speed_fov", speed_fov))
	look_sensitivity = clampf(cf.get_value("controls", "look_sens", look_sensitivity), 0.2, 3.0)
	aim_sensitivity = clampf(cf.get_value("controls", "aim_sens", aim_sensitivity), 0.2, 3.0)
	left_handed = bool(cf.get_value("controls", "left_handed", left_handed))
	show_touch_ui = bool(cf.get_value("controls", "touch_ui", show_touch_ui))

func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("controls", "scheme", control_scheme)
	cf.set_value("controls", "aim_assist", aim_assist)
	cf.set_value("camera", "shake", camera_shake)
	cf.set_value("camera", "speed_fov", speed_fov)
	cf.set_value("controls", "look_sens", look_sensitivity)
	cf.set_value("controls", "aim_sens", aim_sensitivity)
	cf.set_value("controls", "left_handed", left_handed)
	cf.set_value("controls", "touch_ui", show_touch_ui)
	cf.save(PATH)
	changed.emit()

func _setup_input_map() -> void:
	_bind(&"move_forward", [KEY_W, KEY_UP], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_bind(&"move_back", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	_bind(&"move_left", [KEY_A, KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_bind(&"move_right", [KEY_D, KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_bind(&"throttle", [KEY_W, KEY_UP], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_bind(&"brake", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_bind(&"handbrake", [KEY_SPACE], [JOY_BUTTON_B], [])
	_bind(&"sprint", [KEY_SHIFT], [JOY_BUTTON_LEFT_STICK], [])
	_bind(&"dodge", [KEY_SPACE], [JOY_BUTTON_B], [])
	_bind(&"interact", [KEY_E], [JOY_BUTTON_Y], [])
	_bind(&"reload", [KEY_R], [JOY_BUTTON_X], [])
	_bind(&"heal", [KEY_H], [JOY_BUTTON_DPAD_UP], [])
	_bind(&"refuel", [KEY_T], [JOY_BUTTON_DPAD_DOWN], [])
	_bind(&"lure", [KEY_G], [JOY_BUTTON_DPAD_LEFT], [])
	_bind(&"melee", [KEY_F, KEY_V], [JOY_BUTTON_RIGHT_SHOULDER], [])
	_bind(&"weapon_next", [KEY_Q, KEY_TAB], [JOY_BUTTON_DPAD_RIGHT], [])
	_bind(&"weapon_1", [KEY_1], [], [])
	_bind(&"weapon_2", [KEY_2], [], [])
	_bind(&"weapon_3", [KEY_3], [], [])
	_bind(&"cam_recenter", [KEY_C], [JOY_BUTTON_RIGHT_STICK], [])
	_bind(&"toggle_tuning", [KEY_F1], [], [])
	_bind(&"toggle_debug", [KEY_F3], [], [])
	_bind(&"toggle_scheme", [KEY_F2], [], [])
	_bind(&"respawn", [KEY_BACKSPACE], [JOY_BUTTON_BACK], [])
	_bind(&"pause", [KEY_ESCAPE], [JOY_BUTTON_START], [])
	_bind_mouse(&"fire", MOUSE_BUTTON_LEFT, [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_bind_mouse(&"aim", MOUSE_BUTTON_RIGHT, [[JOY_AXIS_TRIGGER_LEFT, 1.0]])

func _bind(action: StringName, keys: Array, buttons: Array, axes: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for b in buttons:
		var j := InputEventJoypadButton.new()
		j.button_index = b
		InputMap.action_add_event(action, j)
	for a in axes:
		var m := InputEventJoypadMotion.new()
		m.axis = a[0]
		m.axis_value = a[1]
		InputMap.action_add_event(action, m)

func _bind_mouse(action: StringName, button: MouseButton, axes: Array) -> void:
	_bind(action, [], [], axes)
	var e := InputEventMouseButton.new()
	e.button_index = button
	InputMap.action_add_event(action, e)
