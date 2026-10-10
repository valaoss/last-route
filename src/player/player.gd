class_name Player
extends CharacterBody3D

## On-foot locomotion, dodge, mount/dismount/riding hand-off and damage.
## Combat lives in PlayerCombat, presentation in PlayerAnim.

signal health_changed(hp: float, max_hp: float)
signal prompt_changed(text: String)

enum State { FOOT, DODGE, MOUNTING, RIDING, DISMOUNTING, KNOCKED, DEAD }

const WALK := 1.8
const JOG := 4.2
const SPRINT := 6.2
const AIM_MOVE := 2.6
const ACCEL := 34.0
const DECEL := 42.0
const TURN_RATE := 12.5
const SPRINT_TURN := 6.3
const GRAVITY := 20.0
const MOUNT_TIME := 0.5
const MOUNT_CONTROL_AT := 0.35
const DISMOUNT_TIME := 0.45
const DODGE_TIME := 0.6
const DODGE_DIST := 3.2
const IFRAME_START := 0.06
const IFRAME_END := 0.34
const DODGE_CANCEL := 0.42
const MOUNT_RANGE := 2.4
const KNOCK_TIME := 1.4

static var PROF_FOOT := CamProfile.on_foot()
static var PROF_AIM := CamProfile.aiming()
static var PROF_RIDE := CamProfile.riding()

@export var rig_path: NodePath
@export var bike_path: NodePath

var rig: CamRig
var bike: Moto
var anim: PlayerAnim
var combat: PlayerCombat
var inventory := Inventory.new()
var state: int = State.FOOT
var facing := 0.0
var max_health := 100.0
var health := 100.0
var stamina := 1.0

var _state_t := 0.0
var _lunge := Vector3.ZERO
var _dodge_dir := Vector3.ZERO
var _invuln := 0.0
var _step_acc := 0.0
var _face_cam_t := 0.0
var _stamina_rest := 0.0
var _mount_from: Transform3D
var _spawn: Transform3D
var _ride_offset := Vector3(0, -0.5, 0.05)
var _ride_offset_ready := false
var _ride_chains := false
var _ride_w := 0.0
var _controls_given := false
var _foot_l_target: Node3D
var _prompt := ""
var _flash := 0.0
var _col_layer := 2
var _col_mask := 1 | 4 | 8
var _restock_t := 0.0


func _ready() -> void:
	add_to_group(&"player")
	anim = PlayerAnim.new()
	anim.name = "Presentation"
	add_child(anim)
	anim.setup()
	rig = get_node(rig_path)
	rig.follow = self
	rig.exclude(self)
	if not bike_path.is_empty():
		bike = get_node(bike_path)
		rig.exclude(bike)
	combat = PlayerCombat.new()
	combat.name = "Combat"
	add_child(combat)
	combat.setup(self)
	inventory.ammo = combat.ammo
	facing = rotation.y
	rotation.y = 0.0
	_spawn = Transform3D(Basis(Vector3.UP, facing), global_position)
	rig.snap_behind(facing)
	_foot_l_target = Node3D.new()
	_foot_l_target.top_level = true
	add_child(_foot_l_target)
	EventBus.bike_crashed.connect(_on_bike_crashed)
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50.0)
	health_changed.emit(health, max_health)


# ------------------------------------------------------------------ helpers (used by combat/AI)

func facing_dir() -> Vector3:
	return Vector3(-sin(facing), 0.0, -cos(facing))


func camera_flat_forward() -> Vector3:
	return Vector3(-sin(rig.yaw), 0.0, -cos(rig.yaw))


func planar_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func face_camera_now() -> void:
	_face_cam_t = 0.6


func turn_toward(dir: Vector3, rate: float, dt: float) -> void:
	facing = FeelMath.damp_angle(facing, atan2(-dir.x, -dir.z), rate, dt)


func push_velocity(v: Vector3) -> void:
	_lunge = v


func is_targetable() -> bool:
	return state != State.DEAD


func is_riding() -> bool:
	return state == State.RIDING or state == State.MOUNTING


func target_point() -> Vector3:
	return global_position + Vector3.UP * 1.2


func is_invulnerable() -> bool:
	if _invuln > 0.0:
		return true
	return state == State.DODGE and _state_t >= IFRAME_START and _state_t <= IFRAME_END


# ------------------------------------------------------------------ main loop

func _physics_process(dt: float) -> void:
	_state_t += dt
	_invuln = maxf(_invuln - dt, 0.0)
	_face_cam_t = maxf(_face_cam_t - dt, 0.0)
	match state:
		State.FOOT: _foot(dt)
		State.DODGE: _dodge(dt)
		State.MOUNTING: _mounting(dt)
		State.RIDING: _riding(dt)
		State.DISMOUNTING: _dismounting(dt)
		State.KNOCKED: _knocked(dt)
		State.DEAD: _dead(dt)
	combat.tick(dt, state == State.FOOT)
	_restock(dt)
	_update_presentation(dt)
	_update_prompt()
	if Input.is_action_just_pressed(&"respawn"):
		respawn()


func _foot(dt: float) -> void:
	var mv := PlayerInput.move_vector()
	var yaw := rig.yaw
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var wish := right * mv.x + fwd * mv.y
	var mag := mv.length()
	var aimish := combat.aim_weight > 0.5 or _face_cam_t > 0.0
	var touch_sprint := PlayerInput.touch_move.length() > 0.97
	var sprinting := (Input.is_action_pressed(&"sprint") or touch_sprint) and not aimish and mag > 0.5 and stamina > 0.02 and not combat.is_meleeing()

	var target_speed := 0.0
	if mag > 0.1:
		if aimish:
			target_speed = AIM_MOVE * minf(mag / 0.8, 1.0)
		elif sprinting:
			target_speed = SPRINT
		elif mag < 0.55:
			target_speed = WALK * mag / 0.55
		else:
			target_speed = lerpf(WALK, JOG, (mag - 0.55) / 0.45)
	if stamina <= 0.02:
		target_speed *= 0.8
	if combat.is_meleeing():
		target_speed *= 0.25
	# stamina
	if sprinting:
		stamina = maxf(stamina - 0.12 * dt, 0.0)
		_stamina_rest = 0.0
	else:
		_stamina_rest += dt
		if _stamina_rest > 0.8:
			stamina = minf(stamina + 0.28 * dt, 1.0)

	var h := Vector3(velocity.x, 0.0, velocity.z)
	var target_v := wish.normalized() * target_speed if mag > 0.1 else Vector3.ZERO
	var rate := ACCEL if target_v.length() >= h.length() else DECEL
	h = h.move_toward(target_v, rate * dt)
	var move_h := h + _lunge
	_lunge = Vector3.ZERO

	# facing
	if aimish or (combat.is_meleeing() and _face_cam_t > 0.0):
		facing = FeelMath.damp_angle(facing, yaw, 22.0, dt)
	elif combat.is_meleeing():
		pass
	elif h.length() > 0.3:
		var target_face := atan2(-h.x, -h.z)
		facing = rotate_toward(facing, target_face, (SPRINT_TURN if sprinting else TURN_RATE) * dt)

	velocity = Vector3(move_h.x, velocity.y - GRAVITY * dt, move_h.z)
	if is_on_floor() and velocity.y < 0.0:
		velocity.y = -1.0
	move_and_slide()
	velocity.x = h.x
	velocity.z = h.z
	_footsteps(h.length(), dt)

	if Input.is_action_just_pressed(&"dodge") and stamina >= 0.12 and (not combat.is_meleeing() or combat.melee_cancel_window()):
		_start_dodge(wish if mag > 0.2 else -facing_dir())
	elif Input.is_action_just_pressed(&"heal"):
		use_medkit()
	elif Input.is_action_just_pressed(&"refuel"):
		refuel_bike()
	elif Input.is_action_just_pressed(&"lure"):
		throw_lure()
	elif Input.is_action_just_pressed(&"interact"):
		var it := nearest_interactable()
		if it:
			it.interact(self)
		else:
			_try_mount()


func _footsteps(speed: float, dt: float) -> void:
	if speed < 0.4 or not is_on_floor():
		return
	_step_acc += speed * dt
	var stride := lerpf(0.7, 1.5, clampf(speed / SPRINT, 0.0, 1.0))
	if _step_acc >= stride:
		_step_acc = 0.0
		Sfx.play_at(&"step", global_position, lerpf(-22.0, -9.0, speed / SPRINT), 0.12)
		NoiseBus.emit_noise(global_position, speed * 2.6, NoiseBus.Priority.MOVEMENT, self)


# ------------------------------------------------------------------ dodge

func _start_dodge(dir: Vector3) -> void:
	combat.cancel_melee()
	state = State.DODGE
	_state_t = 0.0
	_dodge_dir = dir.normalized()
	facing = atan2(-_dodge_dir.x, -_dodge_dir.z)
	stamina = maxf(stamina - 0.2, 0.0)
	_stamina_rest = 0.0
	var len := anim.model.anim_length(&"Roll")
	anim.model.set_param("roll_ts/scale", len / (DODGE_TIME * 1.25))
	anim.model.fire(&"roll")
	Sfx.play_at(&"swing", global_position, -14.0, 0.1)
	NoiseBus.emit_noise(global_position, 6.0, NoiseBus.Priority.MOVEMENT, self)


func _dodge(dt: float) -> void:
	var f := clampf(_state_t / DODGE_TIME, 0.0, 1.0)
	var spd := 2.0 * DODGE_DIST / DODGE_TIME * (1.0 - f)
	velocity = Vector3(_dodge_dir.x * spd, velocity.y - GRAVITY * dt, _dodge_dir.z * spd)
	move_and_slide()
	var wants_out := Input.is_action_pressed(&"aim") or Input.is_action_just_pressed(&"fire") or Input.is_action_just_pressed(&"dodge")
	if f >= 1.0 or (_state_t >= DODGE_CANCEL and wants_out):
		state = State.FOOT
		_state_t = 0.0
		if Input.is_action_just_pressed(&"dodge") and stamina >= 0.12:
			var mv := PlayerInput.move_vector()
			var yaw := rig.yaw
			var wish := Vector3(cos(yaw), 0, -sin(yaw)) * mv.x + Vector3(-sin(yaw), 0, -cos(yaw)) * mv.y
			_start_dodge(wish if mv.length() > 0.2 else _dodge_dir)


# ------------------------------------------------------------------ mount / ride / dismount

func _try_mount() -> void:
	if bike == null or bike.state == Moto.State.RIDING:
		return
	if global_position.distance_to(bike.global_position) > MOUNT_RANGE or absf(bike.v) > 3.0:
		return
	combat.cancel_melee()
	combat._cancel_reload()
	anim.show_weapon(&"")
	bike.recover()
	_ensure_ride_rig()
	state = State.MOUNTING
	_state_t = 0.0
	_controls_given = false
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	_mount_from = anim.global_transform
	anim.top_level = true
	anim.global_transform = _mount_from
	rig.set_profile(PROF_RIDE)
	rig.vehicle = bike
	rig.follow = bike


func _seat_xform() -> Transform3D:
	return bike.visual.seat_socket.global_transform * Transform3D(Basis.IDENTITY, _ride_offset)


func _mounting(_dt: float) -> void:
	var f := clampf(_state_t / MOUNT_TIME, 0.0, 1.0)
	var e := f * f * (3.0 - 2.0 * f)
	var xf := _mount_from.interpolate_with(_seat_xform(), e)
	xf.origin.y += sin(PI * f) * 0.16
	anim.global_transform = xf
	_ride_w = e
	global_position = bike.global_position
	if not _controls_given and _state_t >= MOUNT_CONTROL_AT:
		_controls_given = true
		bike.set_ridden(true)
	if f >= 1.0:
		state = State.RIDING
		_state_t = 0.0
		anim.top_level = false
		anim.reparent(bike.visual.seat_socket, false)
		anim.transform = Transform3D(Basis.IDENTITY, _ride_offset)
		EventBus.player_mounted.emit(bike)


func _riding(_dt: float) -> void:
	global_position = bike.global_position
	facing = bike.heading
	_ride_w = 1.0
	rig.speed = absf(bike.v)
	if Input.is_action_just_pressed(&"interact"):
		if absf(bike.v) < 7.0:
			_start_dismount()
		else:
			_eject(0.0, true)


func _start_dismount() -> void:
	var spot := _free_side_spot()
	bike.set_ridden(false)
	state = State.DISMOUNTING
	_state_t = 0.0
	_mount_from = anim.global_transform
	anim.reparent(self, true)
	anim.top_level = true
	anim.global_transform = _mount_from
	global_position = spot
	facing = bike.heading
	velocity = Vector3.ZERO
	collision_layer = _col_layer
	collision_mask = _col_mask
	_back_to_foot_camera()


func _dismounting(dt: float) -> void:
	var f := clampf(_state_t / DISMOUNT_TIME, 0.0, 1.0)
	var e := f * f * (3.0 - 2.0 * f)
	var target := Transform3D(Basis(Vector3.UP, facing), global_position)
	var xf := _mount_from.interpolate_with(target, e)
	xf.origin.y += sin(PI * f) * 0.12
	anim.global_transform = xf
	_ride_w = 1.0 - e
	velocity.y -= GRAVITY * dt
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()
	if f >= 1.0:
		anim.top_level = false
		anim.transform = Transform3D.IDENTITY
		state = State.FOOT
		_state_t = 0.0
		EventBus.player_dismounted.emit(bike)


func _free_side_spot() -> Vector3:
	var space := get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = 1.8
	for side in [-0.95, 0.95, -1.4, 1.4]:
		var p: Vector3 = bike.global_transform * Vector3(side, 0.0, 0.0)
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = shape
		q.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 1.0)
		q.collision_mask = 1 | 4
		q.exclude = [bike.get_rid()]
		if space.intersect_shape(q, 1).is_empty():
			return p + Vector3.UP * 0.05
	return bike.global_position + Vector3.UP * 1.2


func _back_to_foot_camera() -> void:
	rig.set_profile(PROF_FOOT)
	rig.vehicle = null
	rig.follow = self


func _on_bike_crashed(b: Node, impact: float) -> void:
	if b == bike and state == State.RIDING:
		_eject(impact, false)


## Thrown off (crash) or bailing at speed.
func _eject(impact: float, bail: bool) -> void:
	var fwd := bike.forward()
	var spd := absf(bike.v)
	if bail:
		bike.set_ridden(false)
	anim.reparent(self, true)
	anim.top_level = false
	global_position = bike.global_position + Vector3.UP * 0.4 + bike.global_basis.x * -0.6
	anim.transform = Transform3D.IDENTITY
	collision_layer = _col_layer
	collision_mask = _col_mask
	velocity = fwd * spd * (0.5 if bail else 0.35) + Vector3.UP * 3.0
	facing = bike.heading
	_ride_w = 0.0
	state = State.KNOCKED
	_state_t = 0.0
	_back_to_foot_camera()
	anim.model.set_param("roll_ts/scale", anim.model.anim_length(&"Roll") / KNOCK_TIME)
	anim.model.fire(&"roll")
	rig.add_trauma(0.6)
	Sfx.play_at(&"bike_impact", global_position, 0.0)
	if not bail:
		take_damage(clampf(impact * 1.6, 8.0, 30.0), bike, -fwd, true)


func _knocked(dt: float) -> void:
	var h := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, 7.0 * dt)
	velocity = Vector3(h.x, velocity.y - GRAVITY * dt, h.z)
	move_and_slide()
	if _state_t >= KNOCK_TIME and state == State.KNOCKED:
		state = State.FOOT
		_state_t = 0.0


func _ensure_ride_rig() -> void:
	if not _ride_offset_ready:
		_ride_offset_ready = true
		_ride_offset = _compute_ride_offset()
	if _ride_chains:
		return
	_ride_chains = true
	var ik := anim.model.ik
	var v := bike.visual
	ik.add_chain(&"hand_l", "DEF-upper_arm.L", "DEF-forearm.L", "DEF-hand.L", v.grip_l, null, Vector3(0.7, -0.5, -0.4)).align_end = false
	ik.add_chain(&"hand_r", "DEF-upper_arm.R", "DEF-forearm.R", "DEF-hand.R", v.grip_r, null, Vector3(-0.7, -0.5, -0.4)).align_end = false
	ik.add_chain(&"foot_l", "DEF-thigh.L", "DEF-shin.L", "DEF-foot.L", _foot_l_target, null, Vector3(0.25, 0.0, 1.0)).align_end = false
	ik.add_chain(&"foot_r", "DEF-thigh.R", "DEF-shin.R", "DEF-foot.R", v.peg_r, null, Vector3(-0.25, 0.0, 1.0)).align_end = false


## Places the model so the hips of the "Driving" pose sit on the seat.
func _compute_ride_offset() -> Vector3:
	var m := anim.model
	var a := m.anim_player.get_animation(&"Driving")
	var sk := m.skeleton
	var hips := sk.find_bone("DEF-hips")
	var tr := a.find_track(NodePath("Rig/Skeleton3D:DEF-hips"), Animation.TYPE_POSITION_3D)
	if hips < 0 or tr < 0:
		return Vector3(0, -0.5, 0.05)
	var local_pos: Vector3 = a.position_track_interpolate(tr, 0.0)
	var parent := sk.get_bone_parent(hips)
	var skel_pos := local_pos
	if parent >= 0:
		skel_pos = sk.get_bone_global_rest(parent) * local_pos
	var rel := anim.global_transform.affine_inverse() * sk.global_transform
	var hips_in_anim := rel * skel_pos
	return -hips_in_anim + Vector3(0, 0.03, 0.0)


# ------------------------------------------------------------------ damage

func take_damage(amount: float, source: Node, dir := Vector3.ZERO, ignore_iframes := false) -> bool:
	if state == State.DEAD:
		return false
	if not ignore_iframes and is_invulnerable():
		return false
	if state == State.RIDING:
		amount *= 0.5
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	EventBus.player_damaged.emit(amount, source)
	anim.flinch(0.6)
	if state == State.FOOT:
		anim.model.fire(&"hit")
	rig.add_trauma(0.22 + amount * 0.01)
	_flash = 1.0
	Sfx.play_at(&"hurt", global_position + Vector3.UP, -2.0)
	_invuln = 0.35
	if health <= 0.0:
		_die()
	return true


func _die() -> void:
	if state == State.RIDING or state == State.MOUNTING:
		_eject(0.0, true)
	state = State.DEAD
	_state_t = 0.0
	combat.cancel_melee()
	anim.model.set_param("life/transition_request", "dead")
	EventBus.player_died.emit()


func _dead(dt: float) -> void:
	velocity = Vector3(0, velocity.y - GRAVITY * dt, 0)
	move_and_slide()
	if _state_t > 3.5:
		respawn()


func respawn() -> void:
	if state == State.RIDING or state == State.MOUNTING:
		anim.reparent(self, false)
		anim.top_level = false
		anim.transform = Transform3D.IDENTITY
		bike.set_ridden(false)
	state = State.FOOT
	_state_t = 0.0
	collision_layer = _col_layer
	collision_mask = _col_mask
	global_transform = Transform3D(Basis.IDENTITY, _spawn.origin)
	facing = _spawn.basis.get_euler().y
	velocity = Vector3.ZERO
	health = max_health
	stamina = 1.0
	_ride_w = 0.0
	health_changed.emit(health, max_health)
	anim.model.set_param("life/transition_request", "alive")
	_back_to_foot_camera()
	rig.snap_behind(facing)


# ------------------------------------------------------------------ presentation

func _update_presentation(dt: float) -> void:
	var on_foot := state == State.FOOT or state == State.DODGE or state == State.KNOCKED or state == State.DEAD
	if on_foot and not anim.top_level and anim.get_parent() == self:
		anim.rotation.y = facing
	var h := Vector3(velocity.x, 0.0, velocity.z) if on_foot else Vector3.ZERO
	var speed := h.length()
	var fwd := facing_dir()
	var aimish := combat.aim_weight > 0.5 or _face_cam_t > 0.0
	var backwards := aimish and h.dot(fwd) < -0.3
	var twist := 0.0
	if aimish and speed > 0.5:
		var ref := -fwd if backwards else fwd
		twist = clampf(ref.signed_angle_to(h.normalized(), Vector3.UP), deg_to_rad(-70.0), deg_to_rad(70.0))
	var w := combat.weapon()
	var long_gun := w.kind == WeaponData.Kind.CARBINE or w.kind == WeaponData.Kind.SHOTGUN
	var gun_ready := on_foot and not combat.is_meleeing() and state != State.DODGE and state != State.DEAD
	var sprinting := speed > JOG + 0.5 and not aimish
	var s := {
		"speed": speed,
		"backwards": backwards,
		"upper_weight": 0.0 if not on_foot else (0.35 if sprinting else 1.0),
		"melee_weapon": combat.is_meleeing(),
		"aim_weight": combat.aim_weight,
		"aim_pitch": clampf(rig.pitch / deg_to_rad(55.0), -1.0, 1.0),
		"ride": _ride_w,
		"ride_snap": state == State.MOUNTING or state == State.DISMOUNTING,
		"hips_twist": twist,
		"support_ik": (1.0 if long_gun and gun_ready and not combat.reloading else 0.0),
		"right_ik": (combat.aim_weight if long_gun and gun_ready else 0.0),
	}
	if long_gun and gun_ready:
		var sup := anim.weapon_marker(w.id, "Support")
		if sup:
			anim.support_target.global_transform = sup.global_transform
		var shoulder := anim.model.bone_global("DEF-upper_arm.R")
		var aim_dir := -rig.camera.global_basis.z
		anim.right_target.global_position = shoulder + aim_dir * 0.3 + Vector3.DOWN * 0.07
	if _ride_chains:
		var ride_w := _ride_w if (state == State.RIDING or state == State.MOUNTING or state == State.DISMOUNTING) else 0.0
		var ik := anim.model.ik
		for c in [&"hand_l", &"hand_r", &"foot_r"]:
			ik.set_weight(c, ride_w)
		ik.set_weight(&"foot_l", ride_w)
		if ride_w > 0.0:
			var fd := bike.visual.foot_down
			var peg := bike.visual.peg_l.global_transform
			var ground := _ground_under(bike.global_transform * Vector3(-0.42, 0.0, -0.08))
			_foot_l_target.global_transform = Transform3D(peg.basis, peg.origin.lerp(ground + Vector3.UP * 0.08, fd))
			s["ride_lean"] = bike.visual.lean
			s["ride_pitch"] = clampf(-bike.long_accel * 0.012, -0.07, 0.13) + 0.1
			s["ride_look"] = bike.visual.steer_angle * 0.6
	anim.update_pose(dt, s)
	if _flash > 0.0:
		_flash = maxf(_flash - dt * 6.0, 0.0)
		anim.model.mesh_instance.set_instance_shader_parameter(&"hit_flash", _flash * 0.6)
	if state != State.RIDING:
		rig.speed = speed


func _ground_under(p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.8, p + Vector3.DOWN * 1.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else p


func use_medkit() -> bool:
	if health >= max_health or state == State.DEAD or inventory.take(&"medkit") == 0:
		return false
	health = minf(health + 45.0, max_health)
	health_changed.emit(health, max_health)
	Sfx.play_at(&"pickup", global_position + Vector3.UP, -4.0)
	EventBus.toast.emit("İlk yardım kullanıldı  (+45)")
	return true


func throw_lure() -> NoiseLure:
	if state == State.DEAD or inventory.take(&"lure") == 0:
		return null
	anim.model.fire(&"interact")
	var dir := Vector3(-sin(rig.yaw), 0.0, -cos(rig.yaw))
	return NoiseLure.throw(get_parent(), global_position + Vector3.UP * 1.5 + dir * 0.5, dir, self)


func near_bike() -> bool:
	return bike != null and state == State.FOOT and global_position.distance_to(bike.global_position) < MOUNT_RANGE + 0.6


func refuel_bike() -> bool:
	if not near_bike() or bike.fuel > 0.95 or inventory.take(&"fuel_can") == 0:
		return false
	bike.refuel(0.5)
	anim.model.fire(&"interact")
	Sfx.play_at(&"pickup", bike.global_position, -2.0)
	EventBus.toast.emit("Depo dolduruldu  (%d%%)" % roundi(bike.fuel * 100.0))
	return true


## Standing by the bike pulls supplies from its bag into free pockets.
func _restock(dt: float) -> void:
	_restock_t -= dt
	if _restock_t > 0.0 or not near_bike():
		return
	_restock_t = 1.0
	var moved := inventory.restock_from_bag()
	if not moved.is_empty():
		var parts := PackedStringArray()
		for id in moved:
			parts.append("+%d %s" % [moved[id], Inventory.display_name(id)])
		combat._emit_ammo()
		EventBus.toast.emit("Çantadan: " + ", ".join(parts))


## Nodes in group "interactable" expose interact_prompt() -> String, interact_range: float, interact(p).
func nearest_interactable() -> Node3D:
	var best: Node3D = null
	var bd := INF
	for n in get_tree().get_nodes_in_group(&"interactable"):
		var d: float = global_position.distance_to(n.global_position)
		if d < n.interact_range and d < bd:
			bd = d
			best = n
	return best


func _update_prompt() -> void:
	var text := ""
	var it := nearest_interactable() if state == State.FOOT else null
	if it:
		text = it.interact_prompt()
	elif bike:
		if state == State.FOOT and global_position.distance_to(bike.global_position) < MOUNT_RANGE and bike.state != Moto.State.RIDING:
			text = "E  Bin" + ("   ·   T  Yakıt doldur" if inventory.count(&"fuel_can") > 0 and bike.fuel < 0.95 else "")
		elif state == State.RIDING and absf(bike.v) < 7.0:
			text = "E  İn"
	if text != _prompt:
		_prompt = text
		prompt_changed.emit(text)
	if state == State.FOOT or state == State.DODGE:
		var aim_now := state == State.FOOT and combat.aim_weight > 0.5
		rig.set_profile(PROF_AIM if aim_now else PROF_FOOT)
