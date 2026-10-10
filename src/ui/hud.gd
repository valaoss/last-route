class_name Hud
extends CanvasLayer

## Minimal HUD: dynamic crosshair + hit markers, ammo, health/stamina, riding
## gauges, context prompt, damage vignette, debug overlay (F3), tuning (F1),
## and touch controls on touch devices.

const INK := Color("e6dfcf")
const DIM := Color(0.9, 0.87, 0.8, 0.55)
const AMBER := Color("e8b04a")
const BLOOD := Color("b8322a")

var player: Player
var bike: Moto
var rig: CamRig

var _root: Control
var _cross: Control
var _hit_t := 0.0
var _hit_kill := false
var _ammo: Label
var _weapon: Label
var _reload_bar: ProgressBar
var _hp: ProgressBar
var _stam: ProgressBar
var _speed: Label
var _gear: Label
var _rpm: ProgressBar
var _ride_box: Control
var _prompt: Label
var _help: Label
var _debug: Label
var _vignette: ColorRect
var _vig_t := 0.0
var _tuning: TuningPanel
var _touch: TouchControls
var _scheme: Label
var _objective: Label
var _marker: Label
var _marker_pos := Vector3.ZERO
var _marker_on := false
var _banner: Label
var _fuel: ProgressBar
var _pockets: Label
var _toast: Label
var _toast_t := 0.0
var _banner_sub: Label
var _radio: Label
var _radio_q: Array = []        ## [speaker, text] waiting to be shown
var _radio_t := 0.0


func bind(p: Player, b: Moto, r: CamRig) -> void:
	player = p
	bike = b
	rig = r
	_build()
	player.health_changed.connect(_on_health)
	player.prompt_changed.connect(func(t): _prompt.text = t)
	player.combat.ammo_changed.connect(_on_ammo)
	player.combat.weapon_changed.connect(func(w): _weapon.text = w.display_name)
	EventBus.hit_confirmed.connect(_on_hit)
	EventBus.toast.connect(func(t): _toast.text = t; _toast_t = 3.0)
	EventBus.radio.connect(func(who, t): _radio_q.append([who, t]))
	player.inventory.changed.connect(_update_pockets)
	_update_pockets()
	EventBus.player_damaged.connect(func(_a, _s): _vig_t = 1.0)
	_weapon.text = player.combat.weapon().display_name
	var a: Array = player.combat.ammo[player.combat.weapon().id]
	_on_ammo(a[0], a[1])
	_on_health(player.health, player.max_health)


## Objective line (top centre) plus an on-screen waypoint; pass no position to hide it.
func set_objective(text: String, pos: Variant = null) -> void:
	_objective.text = text
	_marker_on = pos is Vector3
	if _marker_on:
		_marker_pos = pos
	_marker.visible = _marker_on


func show_banner(title: String, sub: String, color := INK) -> void:
	_banner.text = title
	_banner.add_theme_color_override("font_color", color)
	_banner_sub.text = sub
	_banner.visible = title != ""
	_banner_sub.visible = title != ""


## Opens an in-world menu (pauses the game until it closes).
func open_panel(p: MenuPanel) -> void:
	p.open(_root)


func set_help(text: String) -> void:
	_help.text = text + "\nWASD hareket/sürüş · Fare bakış · Sol tık ateş · Sağ tık nişan · Shift koş · Space kaçın/el freni · R doldur · H ilk yardım · T yakıt · G tuzak · F yakın dövüş · Q/1-3 silah · E bin/in · C kamera · F1 ayar · F2 kontrol şeması · F3 debug · Backspace yeniden doğ"


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = "shader_type canvas_item; uniform float amount = 0.0; uniform vec4 tint : source_color = vec4(0.45,0.03,0.02,1.0);\nvoid fragment(){ vec2 d = UV - 0.5; float v = smoothstep(0.25, 0.75, length(d * vec2(1.4, 1.0))); COLOR = vec4(tint.rgb, v * amount); }"
	var sm := ShaderMaterial.new()
	sm.shader = sh
	_vignette.material = sm
	_root.add_child(_vignette)

	_cross = Control.new()
	_cross.set_anchors_preset(Control.PRESET_CENTER)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross.draw.connect(_draw_cross)
	_root.add_child(_cross)

	# bottom-left vitals
	var vit := VBoxContainer.new()
	vit.position = Vector2(28, -86)
	vit.anchor_top = 1.0
	vit.anchor_bottom = 1.0
	vit.add_theme_constant_override("separation", 6)
	_root.add_child(vit)
	_hp = _bar(Color("b8a98a"), 240, 9)
	_stam = _bar(Color(0.8, 0.78, 0.7, 0.55), 180, 4)
	_pockets = _label(13, DIM, HORIZONTAL_ALIGNMENT_LEFT)
	vit.add_child(_pockets)
	vit.add_child(_hp)
	vit.add_child(_stam)
	vit.position.y -= 22

	# bottom-right weapon
	var wb := VBoxContainer.new()
	wb.anchor_left = 1.0
	wb.anchor_right = 1.0
	wb.anchor_top = 1.0
	wb.anchor_bottom = 1.0
	wb.position = Vector2(-260, -110)
	wb.custom_minimum_size = Vector2(230, 0)
	wb.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(wb)
	_weapon = _label(16, DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	_ammo = _label(34, INK, HORIZONTAL_ALIGNMENT_RIGHT)
	_reload_bar = _bar(AMBER, 230, 3)
	_reload_bar.visible = false
	wb.add_child(_weapon)
	wb.add_child(_ammo)
	wb.add_child(_reload_bar)

	# riding gauges (bottom centre)
	_ride_box = VBoxContainer.new()
	_ride_box.anchor_left = 0.5
	_ride_box.anchor_right = 0.5
	_ride_box.anchor_top = 1.0
	_ride_box.anchor_bottom = 1.0
	_ride_box.position = Vector2(-90, -112)
	_ride_box.custom_minimum_size = Vector2(180, 0)
	_root.add_child(_ride_box)
	_speed = _label(40, INK, HORIZONTAL_ALIGNMENT_CENTER)
	_gear = _label(14, DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_rpm = _bar(AMBER, 180, 3)
	_ride_box.add_child(_speed)
	_ride_box.add_child(_gear)
	_ride_box.add_child(_rpm)
	_fuel = _bar(Color("8fa070"), 180, 3)
	_ride_box.add_child(_fuel)

	_prompt = _label(20, INK, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 0.66
	_prompt.position = Vector2(-150, 0)
	_prompt.custom_minimum_size = Vector2(300, 0)
	_root.add_child(_prompt)

	_help = _label(13, Color(0.9, 0.87, 0.8, 0.5), HORIZONTAL_ALIGNMENT_LEFT)
	_help.position = Vector2(24, 18)
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.custom_minimum_size = Vector2(760, 0)
	_root.add_child(_help)
	set_help("")

	_scheme = _label(13, Color(0.9, 0.87, 0.8, 0.5), HORIZONTAL_ALIGNMENT_RIGHT)
	_scheme.anchor_left = 1.0
	_scheme.anchor_right = 1.0
	_scheme.position = Vector2(-330, 18)
	_scheme.custom_minimum_size = Vector2(300, 0)
	_root.add_child(_scheme)

	_debug = _label(13, Color("c8e6b0"), HORIZONTAL_ALIGNMENT_LEFT)
	_debug.position = Vector2(24, 110)
	_debug.visible = false
	_root.add_child(_debug)

	_toast = _label(16, INK, HORIZONTAL_ALIGNMENT_RIGHT)
	_toast.anchor_left = 1.0
	_toast.anchor_right = 1.0
	_toast.anchor_top = 0.5
	_toast.position = Vector2(-430, -40)
	_toast.custom_minimum_size = Vector2(400, 0)
	_root.add_child(_toast)

	_objective = _label(19, AMBER, HORIZONTAL_ALIGNMENT_CENTER)
	_objective.anchor_left = 0.5
	_objective.anchor_right = 0.5
	_objective.position = Vector2(-300, 64)
	_objective.custom_minimum_size = Vector2(600, 0)
	_root.add_child(_objective)
	_marker = _label(15, AMBER, HORIZONTAL_ALIGNMENT_CENTER)
	_marker.custom_minimum_size = Vector2(120, 0)
	_marker.visible = false
	_root.add_child(_marker)
	var bbox := VBoxContainer.new()
	bbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bbox.alignment = BoxContainer.ALIGNMENT_CENTER
	bbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bbox)
	_banner = _label(54, INK, HORIZONTAL_ALIGNMENT_CENTER)
	_banner_sub = _label(18, DIM, HORIZONTAL_ALIGNMENT_CENTER)
	for b: Label in [_banner, _banner_sub]:
		b.visible = false
		bbox.add_child(b)

	_radio = _label(18, INK, HORIZONTAL_ALIGNMENT_CENTER)
	_radio.anchor_left = 0.5
	_radio.anchor_right = 0.5
	_radio.anchor_top = 0.74
	_radio.position = Vector2(-380, 0)
	_radio.custom_minimum_size = Vector2(760, 0)
	_radio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_radio)

	_tuning = TuningPanel.new()
	_tuning.visible = false
	_root.add_child(_tuning)
	_tuning.setup(bike)

	if GameSettings.show_touch_ui:
		_touch = TouchControls.new()
		_root.add_child(_touch)
		_touch.setup(player)


func _label(size: int, color: Color, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _bar(color: Color, w: float, h: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(w, h)
	b.show_percentage = false
	b.max_value = 1.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.35)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _update_pockets() -> void:
	var inv := player.inventory
	var parts := PackedStringArray()
	for id in [&"medkit", &"fuel_can", &"lure", &"scrap", &"cloth", &"powder", &"alcohol", &"carb_part", &"antenna_part", &"antibiotics", &"toolbox"]:
		if inv.count(id) > 0:
			parts.append("%s %d" % [Inventory.display_name(id), inv.count(id)])
	var keys := PackedStringArray()
	if inv.count(&"medkit") > 0:
		keys.append("H iyileş")
	if inv.count(&"lure") > 0:
		keys.append("G tuzak at")
	_pockets.text = "   ·   ".join(parts) + ("   (%s)" % " · ".join(keys) if not keys.is_empty() else "")


func _on_health(hp: float, mx: float) -> void:
	_hp.value = hp / mx


func _on_ammo(mag: int, reserve: int) -> void:
	_ammo.text = "%d  /  %d" % [mag, reserve]


func _on_hit(kill: bool, _head: bool) -> void:
	_hit_t = 0.18 if not kill else 0.32
	_hit_kill = kill


func _process(dt: float) -> void:
	if player == null:
		return
	if Input.is_action_just_pressed(&"toggle_debug"):
		_debug.visible = not _debug.visible
	if Input.is_action_just_pressed(&"toggle_tuning"):
		_tuning.visible = not _tuning.visible
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _tuning.visible else Input.MOUSE_MODE_CAPTURED
	if Input.is_action_just_pressed(&"toggle_scheme"):
		GameSettings.control_scheme = 1 - GameSettings.control_scheme
		GameSettings.save_settings()
	_scheme.text = "Sürüş: " + ("A · Arcade" if GameSettings.control_scheme == 0 else "B · Asistanlı") + "   ·   Aim assist: " + ["Kapalı", "Düşük", "Orta"][GameSettings.aim_assist]
	_hit_t = maxf(_hit_t - dt, 0.0)
	_toast_t = maxf(_toast_t - dt, 0.0)
	_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	_update_radio(dt)
	_vig_t = maxf(_vig_t - dt * 1.6, 0.0)
	var low := 1.0 - clampf(player.health / player.max_health / 0.35, 0.0, 1.0)
	(_vignette.material as ShaderMaterial).set_shader_parameter(&"amount", maxf(_vig_t * 0.8, low * 0.45))
	_stam.value = player.stamina
	_stam.modulate.a = 0.0 if player.stamina >= 0.999 else 1.0
	var riding := player.is_riding()
	_ride_box.visible = riding
	_cross.visible = not riding and player.state != Player.State.DEAD
	var c := player.combat
	_reload_bar.visible = c.reloading
	if c.reloading:
		_reload_bar.value = c.reload_t / maxf(c.reload_total, 0.01)
	if riding:
		_speed.text = "%d" % roundi(bike.speed_kmh())
		_gear.text = "km/h   ·   %d. vites" % bike.gear
		_rpm.value = clampf(bike.rpm / bike.tuning.redline_rpm, 0.0, 1.0)
		_fuel.value = bike.fuel
		_fuel.modulate = Color(1, 0.35, 0.3) if bike.fuel < 0.15 else Color.WHITE
		if bike.fuel <= 0.0:
			_gear.text += "   ·   YAKIT BİTTİ"
	if _marker_on:
		_update_marker()
	_cross.queue_redraw()
	if _debug.visible:
		_debug.text = _debug_text()


## Radio / inner-voice subtitles, one line at a time, duration scales with length.
func _update_radio(dt: float) -> void:
	_radio_t -= dt
	if _radio_t <= 0.0 and not _radio_q.is_empty():
		var m: Array = _radio_q.pop_front()
		var who: String = m[0]
		_radio.text = ("[%s]  " % who if who != "" else "") + m[1]
		_radio.add_theme_color_override("font_color", Color("b9d0a8") if who.begins_with("Telsiz") else INK)
		_radio_t = clampf(1.8 + m[1].length() * 0.055, 2.5, 8.0)
	_radio.modulate.a = clampf(_radio_t * 2.0, 0.0, 1.0)


func is_radio_busy() -> bool:
	return _radio_t > 0.0 or not _radio_q.is_empty()


func _update_marker() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var p := _marker_pos + Vector3.UP * 2.5
	var sp := cam.unproject_position(p)
	if cam.is_position_behind(p):
		sp = vs - sp
		sp.y = vs.y - 60.0
	sp.x = clampf(sp.x, 70.0, vs.x - 70.0)
	sp.y = clampf(sp.y, 90.0, vs.y - 60.0)
	_marker.text = "◆
%d m" % roundi(player.global_position.distance_to(_marker_pos))
	_marker.position = sp - Vector2(60, 12)


func _draw_cross() -> void:
	var c := player.combat
	var w := c.weapon()
	var spread := w.spread_deg * (0.35 if c.aim_weight > 0.5 else 1.0) + c.spread_bloom
	if player.planar_speed() > 2.0:
		spread *= 1.5
	var px := tan(deg_to_rad(spread)) / tan(deg_to_rad(rig.camera.fov * 0.5)) * _root.size.y * 0.5
	var gap := 6.0 + px
	var col := Color(INK, 0.85 if c.aim_weight > 0.5 else 0.6)
	var ln := 7.0
	_cross.draw_line(Vector2(gap, 0), Vector2(gap + ln, 0), col, 2.0)
	_cross.draw_line(Vector2(-gap, 0), Vector2(-gap - ln, 0), col, 2.0)
	_cross.draw_line(Vector2(0, gap), Vector2(0, gap + ln), col, 2.0)
	_cross.draw_line(Vector2(0, -gap), Vector2(0, -gap - ln), col, 2.0)
	_cross.draw_circle(Vector2.ZERO, 1.5, col)
	if _hit_t > 0.0:
		var hc := BLOOD if _hit_kill else INK
		var s := 6.0 + (1.0 - _hit_t / 0.32) * 4.0
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			_cross.draw_line(d * s, d * (s + 7.0), hc, 2.5)


func _debug_text() -> String:
	var fps := Engine.get_frames_per_second()
	var t := "FPS %d   frame %.1f ms   phys %.1f ms\n" % [fps, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0]
	t += "draw calls %d   objects %d   prims %dk\n" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000)]
	var enemies := get_tree().get_nodes_in_group(&"enemy").size()
	t += "zombies %d   attack slots %d   noise events %d\n" % [enemies, AttackSlots.count(), NoiseBus.recent_noises().size()]
	if bike:
		var au: Node = bike.get_node_or_null("Audio")
		t += "bike v %.1f m/s  yaw %.2f  slip %.1f°  slide %.2f  lean %.1f°  surf %s  gear %d  rpm %d  air %.2f  audio %d µs  noise r %.0f m\n" % [
			bike.v, bike.yaw_rate, rad_to_deg(bike.slip), bike.slide_amount, rad_to_deg(bike.visual.lean), bike.surface.id, bike.gear, bike.rpm,
			bike.airborne_time, au.last_fill_usec if au else 0, bike.noise_radius()]
	t += "player %s  hp %d  stamina %.2f  aim %.2f" % [Player.State.keys()[player.state], player.health, player.stamina, player.combat.aim_weight]
	return t
