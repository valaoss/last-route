class_name PlayerCombat
extends Node

## Weapons, firing, reloading, melee combos and aim assist for the on-foot player.

signal weapon_changed(w: WeaponData)
signal ammo_changed(mag: int, reserve: int)

const SWITCH_TIME := 0.32
const MELEE_BUFFER := 0.25

var player: Player
var anim: PlayerAnim
var rig: CamRig

var weapons: Array[WeaponData] = []
var ammo: Dictionary = {}      # id -> [mag, reserve]
var current := 0
var melee := WeaponData.pipe()

var aiming := false
var aim_weight := 0.0
var cooldown := 0.0
var since_shot := 9.0
var reloading := false
var reload_t := 0.0
var reload_total := 0.0
var switching := 0.0
var recoil_debt := 0.0          ## accumulated climb to recover (rad)
var spread_bloom := 0.0

var melee_step := -1
var melee_t := 0.0
var melee_queued := false
var melee_hit_done := false
var _melee_buffer_t := -1.0
var _target: Node3D = null
var look_scale := 1.0


func setup(p: Player) -> void:
	player = p
	anim = p.anim
	rig = p.rig
	weapons = [WeaponData.pistol(), WeaponData.carbine(), WeaponData.shotgun()]
	for w in weapons:
		ammo[w.id] = [w.mag_size, w.reserve_start]
		anim.add_weapon_model(w)
	anim.add_weapon_model(melee)
	equip(0, true)


func weapon() -> WeaponData:
	return weapons[current]


func is_meleeing() -> bool:
	return melee_step >= 0


func equip(i: int, instant := false) -> void:
	if i == current and not instant:
		return
	current = clampi(i, 0, weapons.size() - 1)
	_cancel_reload()
	switching = 0.0 if instant else SWITCH_TIME
	anim.show_weapon(weapon().id)
	cooldown = maxf(cooldown, switching)
	recoil_debt = 0.0
	weapon_changed.emit(weapon())
	_emit_ammo()
	if not instant:
		Sfx.play_at(&"reload_out", player.global_position, -10.0)


func _emit_ammo() -> void:
	var a: Array = ammo[weapon().id]
	ammo_changed.emit(a[0], a[1])


# ------------------------------------------------------------------ per frame

func tick(dt: float, can_act: bool) -> void:
	cooldown = maxf(cooldown - dt, 0.0)
	switching = maxf(switching - dt, 0.0)
	since_shot += dt
	spread_bloom = maxf(spread_bloom - dt * 3.0, 0.0)

	aiming = can_act and Input.is_action_pressed(&"aim") and not is_meleeing()
	var want_aim := 1.0 if (aiming or since_shot < 0.6) else 0.0
	aim_weight = FeelMath.damp(aim_weight, want_aim, 16.0, dt)

	if can_act:
		if Input.is_action_just_pressed(&"weapon_next"):
			equip((current + 1) % weapons.size())
		for k in 3:
			if Input.is_action_just_pressed(StringName("weapon_%d" % (k + 1))):
				equip(k)
		if Input.is_action_just_pressed(&"reload"):
			start_reload()
		if Input.is_action_just_pressed(&"melee"):
			_melee_buffer_t = MELEE_BUFFER
		var w := weapon()
		var trigger := Input.is_action_pressed(&"fire") if w.automatic else Input.is_action_just_pressed(&"fire")
		if trigger and not is_meleeing():
			try_fire()
	_tick_reload(dt)
	_tick_melee(dt, can_act)
	_recover_recoil(dt)
	_aim_assist(dt)


# ------------------------------------------------------------------ firing

func try_fire() -> void:
	var w := weapon()
	var a: Array = ammo[w.id]
	if switching > 0.0 or cooldown > 0.0:
		return
	if reloading:
		if w.per_shell_reload and a[0] > 0:
			_cancel_reload()
		else:
			return
	if a[0] <= 0:
		Sfx.play_at(&"dry_fire", player.global_position, -6.0)
		cooldown = 0.25
		if a[1] > 0:
			start_reload()
		return
	a[0] -= 1
	cooldown = w.fire_interval
	since_shot = 0.0
	player.face_camera_now()
	_shoot(w)
	_emit_ammo()
	if w.kind == WeaponData.Kind.SHOTGUN:
		_animate_pump()


func _shoot(w: WeaponData) -> void:
	var muzzle := anim.weapon_marker(w.id, "Muzzle")
	var muzzle_pos := muzzle.global_position if muzzle else player.global_position + Vector3.UP * 1.4
	var cam := rig.camera
	var aimed := aim_weight > 0.5
	var moving := player.planar_speed() > 2.0
	var spread := w.spread_deg * (0.35 if aimed else 1.0) * (1.5 if moving else 1.0) + spread_bloom
	var space := player.get_world_3d().direct_space_state
	var cam_from := cam.global_position
	var base_dir := -cam.global_basis.z
	var hits_by_enemy := {}
	for p in w.pellets:
		var dir := _spread_dir(base_dir, spread)
		# camera ray finds what's under the crosshair...
		var q := PhysicsRayQueryParameters3D.create(cam_from, cam_from + dir * w.range, 1 | 16)
		q.collide_with_areas = true
		q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		var end: Vector3 = hit.position if not hit.is_empty() else cam_from + dir * w.range
		# ...then the muzzle must have line of sight to it (no shooting through walls)
		var q2 := PhysicsRayQueryParameters3D.create(muzzle_pos, end + (end - muzzle_pos).normalized() * 0.05, 1 | 16)
		q2.collide_with_areas = true
		q2.exclude = [player.get_rid()]
		var hit2 := space.intersect_ray(q2)
		if not hit2.is_empty():
			hit = hit2
			end = hit2.position
		Fx.instance.tracer(muzzle_pos, end)
		if hit.is_empty():
			continue
		var col: Object = hit.collider
		if col is Area3D and col.has_meta(&"enemy"):
			var enemy: Node = col.get_meta(&"enemy")
			var zone: StringName = col.get_meta(&"zone", &"torso")
			var dist := muzzle_pos.distance_to(end)
			var fall := 1.0
			if dist > w.falloff_start:
				fall = lerpf(1.0, w.falloff_min, clampf((dist - w.falloff_start) / maxf(w.falloff_end - w.falloff_start, 0.1), 0.0, 1.0))
			var mult := w.head_mult if zone == &"head" else (w.leg_mult if zone == &"legs" else 1.0)
			var entry: Dictionary = hits_by_enemy.get(enemy, {"damage": 0.0, "zone": zone, "point": end, "pellets": 0})
			entry.damage += w.damage * mult * fall
			entry.pellets += 1
			if zone == &"head":
				entry.zone = zone
			hits_by_enemy[enemy] = entry
			Fx.instance.impact(end, -dir, true)
		else:
			Fx.instance.impact(end, hit.normal, false)
	for enemy in hits_by_enemy:
		var e: Dictionary = hits_by_enemy[enemy]
		var power := w.stagger_power * (0.5 + 0.5 * float(e.pellets) / w.pellets)
		var res: Dictionary = enemy.take_hit({
			"damage": e.damage, "zone": e.zone, "dir": base_dir, "point": e.point,
			"power": power, "knockback": w.knockback, "weapon": w.id, "source": player})
		_confirm(res, e.zone)

	# feel: recoil climb, camera kick, body kick, flash, sound, noise
	var climb := w.recoil_pitch * (0.7 if aimed else 1.0)
	var yaw := randf_range(-w.recoil_yaw, w.recoil_yaw) + w.recoil_yaw_bias
	rig.add_recoil(climb, yaw)
	recoil_debt += deg_to_rad(climb) * 0.7
	rig.kick(w.kick_pitch, yaw * 0.5, w.kick_fov)
	rig.add_trauma(w.shake)
	anim.kick(w.body_kick)
	spread_bloom = minf(spread_bloom + w.spread_deg * 0.25, w.spread_deg * 1.5)
	if muzzle:
		Fx.instance.muzzle_flash(muzzle.global_transform, 1.4 if w.kind == WeaponData.Kind.SHOTGUN else 1.0)
	Sfx.play_at(w.id, muzzle_pos, 2.0 if w.kind == WeaponData.Kind.SHOTGUN else 0.0, 0.04)
	NoiseBus.emit_noise(player.global_position, w.noise_radius, NoiseBus.Priority.COMBAT, player)
	EventBus.weapon_fired.emit(w.id)
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(25 if w.kind != WeaponData.Kind.SHOTGUN else 60)


func _confirm(res: Dictionary, zone: StringName) -> void:
	if res.is_empty():
		return
	var killed: bool = res.get("killed", false)
	EventBus.hit_confirmed.emit(killed, zone == &"head")
	Sfx.play_ui(&"kill_tick" if killed else &"hit_tick", -10.0 if not killed else -6.0)


func _spread_dir(base: Vector3, deg: float) -> Vector3:
	if deg <= 0.0:
		return base
	var r := deg_to_rad(deg) * sqrt(randf())
	var a := randf() * TAU
	var right := base.cross(Vector3.UP).normalized()
	var up := right.cross(base).normalized()
	return (base + (right * cos(a) + up * sin(a)) * tan(r)).normalized()


func _recover_recoil(dt: float) -> void:
	if recoil_debt <= 0.0:
		return
	var w := weapon()
	if since_shot < w.fire_interval * 1.4:
		return
	var rate := deg_to_rad(9.0 if w.kind == WeaponData.Kind.PISTOL else 6.0)
	var r := minf(recoil_debt, rate * dt)
	recoil_debt -= r
	rig.pitch -= r


func _animate_pump() -> void:
	var pump := anim.weapon_marker(&"shotgun", "Pump")
	if pump == null:
		return
	var tw := player.create_tween()
	tw.tween_interval(0.18)
	tw.tween_callback(func(): Sfx.play_at(&"pump", player.global_position, -4.0))
	tw.tween_property(pump, "position:z", -0.24, 0.14).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(pump, "position:z", -0.36, 0.14).set_trans(Tween.TRANS_QUAD)


# ------------------------------------------------------------------ reload

func start_reload() -> void:
	var w := weapon()
	var a: Array = ammo[w.id]
	if reloading or a[0] >= w.mag_size or a[1] <= 0 or is_meleeing():
		return
	reloading = true
	reload_t = 0.0
	reload_total = w.reload_time if (a[0] > 0 or w.per_shell_reload) else w.reload_empty_time
	var len := anim.model.anim_length(&"Pistol_Reload")
	anim.model.set_param("reload_ts/scale", len / maxf(reload_total if not w.per_shell_reload else 0.9, 0.1))
	anim.model.fire(&"reload")
	Sfx.play_at(&"reload_out", player.global_position, -6.0)


func _tick_reload(dt: float) -> void:
	if not reloading:
		return
	if player.state == Player.State.DODGE:
		return  # dodge pauses a reload instead of cancelling it
	reload_t += dt
	var w := weapon()
	var a: Array = ammo[w.id]
	if reload_t >= reload_total:
		if w.per_shell_reload:
			a[0] += 1
			a[1] -= 1
			Sfx.play_at(&"reload_in", player.global_position, -8.0)
			_emit_ammo()
			if a[0] < w.mag_size and a[1] > 0:
				reload_t = 0.0
				if not anim.model.is_playing_shot(&"reload"):
					anim.model.fire(&"reload")
				return
		else:
			var need: int = w.mag_size - a[0]
			var take: int = mini(need, a[1])
			a[0] += take
			a[1] -= take
			Sfx.play_at(&"reload_in", player.global_position, -5.0)
			_emit_ammo()
		reloading = false


func _cancel_reload() -> void:
	if reloading:
		reloading = false
		anim.model.abort(&"reload")


# ------------------------------------------------------------------ melee

func _tick_melee(dt: float, can_act: bool) -> void:
	if _melee_buffer_t > 0.0:
		_melee_buffer_t -= dt
	if melee_step < 0:
		if _melee_buffer_t > 0.0 and can_act and player.state == Player.State.FOOT:
			_melee_buffer_t = -1.0
			_start_melee(0)
		return
	melee_t += dt
	var dur: float = melee.combo_times[melee_step]
	var f := melee_t / dur
	if _melee_buffer_t > 0.0 and f > 0.35:
		melee_queued = true
		_melee_buffer_t = -1.0
	# lunge + soft lock during the first 40 %
	if f < 0.4:
		var target_dir := player.facing_dir()
		if _target and is_instance_valid(_target):
			var to := (_target.global_position - player.global_position)
			to.y = 0.0
			if to.length() > 0.3:
				player.turn_toward(to.normalized(), 14.0, dt)
		player.push_velocity(player.facing_dir() * (0.6 / (dur * 0.4)))
	if not melee_hit_done and f >= 0.38:
		melee_hit_done = true
		_melee_strike()
	if f >= 1.0:
		if melee_queued and melee_step < melee.combo_times.size() - 1:
			_start_melee(melee_step + 1)
		else:
			_end_melee()
	elif melee_queued and f >= 0.7 and melee_step < melee.combo_times.size() - 1:
		_start_melee(melee_step + 1)


func _start_melee(step: int) -> void:
	_cancel_reload()
	melee_step = step
	melee_t = 0.0
	melee_queued = false
	melee_hit_done = false
	anim.show_weapon(&"pipe")
	_target = _find_melee_target()
	var shot: StringName = [&"m1", &"m2", &"m3"][step]
	var anim_name: StringName = [&"Sword_Attack", &"Punch_Cross", &"Sword_Attack"][step]
	var len := anim.model.anim_length(anim_name)
	anim.model.set_param("%s_ts/scale" % shot, len / melee.combo_times[step] * (0.85 if step == 2 else 1.0))
	anim.model.fire(shot)
	Sfx.play_at(&"swing", player.global_position + Vector3.UP, -4.0, 0.12)
	if _target == null:
		player.face_camera_now()


func _end_melee() -> void:
	melee_step = -1
	melee_queued = false
	anim.show_weapon(weapon().id)


func cancel_melee() -> void:
	if melee_step >= 0:
		for s in [&"m1", &"m2", &"m3"]:
			anim.model.abort(s)
		_end_melee()


func melee_cancel_window() -> bool:
	return melee_step >= 0 and melee_t / melee.combo_times[melee_step] > 0.5


func _find_melee_target() -> Node3D:
	var best: Node3D = null
	var best_score := INF
	var fwd := player.camera_flat_forward()
	for e in player.get_tree().get_nodes_in_group(&"enemy"):
		if not e.has_method("is_alive") or not e.is_alive():
			continue
		var to: Vector3 = e.global_position - player.global_position
		to.y = 0.0
		var d := to.length()
		if d > melee.reach + 1.2:
			continue
		var ang := rad_to_deg(fwd.angle_to(to.normalized()))
		if ang > 50.0:
			continue
		var score := d + ang * 0.03
		if score < best_score:
			best_score = score
			best = e
	return best


func _melee_strike() -> void:
	var dmg: float = melee.combo_damage[melee_step]
	var fwd := player.facing_dir()
	var any := false
	for e in player.get_tree().get_nodes_in_group(&"enemy"):
		if not e.has_method("is_alive") or not e.is_alive():
			continue
		var to: Vector3 = e.global_position - player.global_position
		to.y = 0.0
		if to.length() > melee.reach + 0.35:
			continue
		if rad_to_deg(fwd.angle_to(to.normalized())) > melee.arc_deg * 0.5:
			continue
		var power := 1.0 if melee_step < 2 else 2.0
		var res: Dictionary = e.take_hit({"damage": dmg, "zone": &"torso", "dir": to.normalized(), "point": e.global_position + Vector3.UP * 1.3,
			"power": power, "knockback": 1.0 if melee_step < 2 else 2.6, "weapon": &"pipe", "source": player, "melee": true})
		_confirm(res, &"torso")
		Fx.instance.impact(e.global_position + Vector3.UP * 1.3, -to.normalized(), true)
		any = true
	if any:
		Sfx.play_at(&"melee_hit", player.global_position + fwd + Vector3.UP, 0.0, 0.1)
		rig.add_trauma(melee.shake + (0.1 if melee_step == 2 else 0.0))
		rig.kick(-1.5, 0.0, 0.0)
	NoiseBus.emit_noise(player.global_position, melee.noise_radius, NoiseBus.Priority.MOVEMENT, player)


# ------------------------------------------------------------------ aim assist

## Friction (slow the look near a target) + weak magnetism (follow a moving target).
## Never snaps to heads; it only offsets the touch-screen disadvantage.
func _aim_assist(dt: float) -> void:
	_aim_assist_inner(dt)
	rig.look_scale = look_scale
	rig.aiming = aim_weight > 0.5


func _aim_assist_inner(dt: float) -> void:
	look_scale = 1.0
	var level := GameSettings.aim_assist
	if level == GameSettings.AimAssist.OFF or player.state != Player.State.FOOT:
		return
	var cam := rig.camera
	var fwd := -cam.global_basis.z
	var best: Node3D = null
	var best_ang := deg_to_rad(4.0 if level == GameSettings.AimAssist.MEDIUM else 2.5)
	for e in player.get_tree().get_nodes_in_group(&"enemy"):
		if not e.is_alive():
			continue
		var c: Vector3 = e.global_position + Vector3.UP * 1.15
		var to := c - cam.global_position
		var d := to.length()
		if d > 45.0:
			continue
		var ang := fwd.angle_to(to / d)
		if ang < best_ang:
			best_ang = ang
			best = e
	if best == null:
		return
	var strength := 0.45 if level == GameSettings.AimAssist.MEDIUM else 0.7
	look_scale = strength if aim_weight > 0.3 else lerpf(strength, 1.0, 0.5)
	# magnetism: only while the player is actively aiming/firing
	if aim_weight > 0.3:
		var c2: Vector3 = best.global_position + Vector3.UP * 1.15
		var to2 := c2 - cam.global_position
		var want_yaw := atan2(-to2.x, -to2.z)
		var k := 1.2 if level == GameSettings.AimAssist.MEDIUM else 0.6
		rig.yaw = FeelMath.damp_angle(rig.yaw, want_yaw, k, dt)
