class_name Moto
extends CharacterBody3D

## Arcade-sim motorcycle. The collision body only yaws; lean, pitch, suspension and
## steering are visual layers driven by the simulated state so balance is never the
## player's problem, while grip, weight transfer and slides still shape the handling.

signal crashed(impact: float)
signal gear_changed(gear: int, up: bool)
signal bumped(strength: float)

enum State { PARKED, RIDING, CRASHED }

const G := 9.81
const AIR_GRAVITY := 1.6

@export var tuning: MotoTuning

var state: int = State.PARKED
var v := 0.0                     ## signed forward speed along velocity heading
var heading := 0.0               ## body yaw (radians)
var vel_heading := 0.0           ## direction of travel (differs while sliding)
var yaw_rate := 0.0
var path_rate := 0.0              ## turn rate of the travel direction (drives lean)
var steer := 0.0                 ## smoothed input -1..1 (+ = left)
var throttle_in := 0.0
var brake_in := 0.0
var handbrake_in := false
var slip := 0.0                  ## radians between heading and travel
var slide_amount := 0.0          ## 0..1
var gear := 1
var rpm := 1100.0
var engine_load := 0.0           ## 0..1, for audio
var long_accel := 0.0            ## measured m/s², for rider/suspension
var surface: SurfaceData
var airborne_time := 0.0
var last_landing := 0.0
var crash_timer := 0.0
var fuel := 1.0                  ## 0..1 tank
var assist_brake := 0.0          ## scheme-B wall assist, exposed for debug
var noise_mult := 1.0            ## muffler upgrade lowers how far the engine carries
var offroad_kit := false         ## suspension upgrade: better on loose ground, softer landings

var _shift_timer := 0.0
var _prev_v := 0.0
var _noise_timer := 0.0
var _vy := 0.0
var _was_on_floor := true

@onready var visual: MotoVisual = $Visual
@onready var ram_area: Area3D = $Ram


func _ready() -> void:
	if tuning == null:
		tuning = MotoTuning.new()
	surface = SurfaceData.get_surface(&"asphalt")
	heading = rotation.y
	vel_heading = heading
	floor_max_angle = deg_to_rad(57.0)
	floor_snap_length = 0.45
	floor_constant_speed = true
	floor_block_on_wall = false
	safe_margin = 0.02
	ram_area.body_entered.connect(_on_ram_body)
	add_to_group(&"vehicle")


func is_ridden() -> bool:
	return state == State.RIDING


func set_ridden(on: bool) -> void:
	if on:
		state = State.RIDING
	elif state != State.CRASHED:
		state = State.PARKED


func speed_kmh() -> float:
	return absf(v) * 3.6


func forward() -> Vector3:
	return Vector3(-sin(heading), 0.0, -cos(heading))


func _physics_process(dt: float) -> void:
	_read_input(dt)
	_sample_ground()
	_update_steering(dt)
	_update_speed(dt)
	_move(dt)
	_update_engine(dt)
	_burn_fuel(dt)
	_emit_noise(dt)
	visual.update_dynamics(self, dt)


func _burn_fuel(dt: float) -> void:
	if state == State.RIDING:
		fuel = maxf(fuel - (0.08 + 0.92 * throttle_in) * dt / tuning.tank_seconds, 0.0)


func refuel(amount: float) -> void:
	fuel = clampf(fuel + amount, 0.0, 1.0)


# ------------------------------------------------------------------ input

func _read_input(dt: float) -> void:
	var target_steer := 0.0
	throttle_in = 0.0
	brake_in = 0.0
	handbrake_in = false
	assist_brake = 0.0
	if state == State.RIDING:
		var mv := PlayerInput.move_vector()
		target_steer = -mv.x
		if GameSettings.control_scheme == GameSettings.ControlScheme.ASSISTED and not PlayerInput.override_enabled:
			_assisted_input(mv)
		else:
			throttle_in = PlayerInput.throttle()
			brake_in = PlayerInput.brake()
			handbrake_in = PlayerInput.handbrake()
	elif state == State.PARKED:
		brake_in = 1.0
	# Tighter steering return when the stick is released keeps straights stable.
	steer = FeelMath.approach_asym(steer, target_steer, tuning.steer_rise_time, tuning.steer_return_time, dt)


## Control scheme B: stick magnitude is desired speed; the bike manages throttle,
## brake and corner entry speed, and brakes before walls.
func _assisted_input(mv: Vector2) -> void:
	handbrake_in = PlayerInput.handbrake()
	var boost := PlayerInput.throttle() > 0.5
	var want := maxf(mv.y, 0.0)
	if mv.length() > 0.2 and mv.y > -0.3:
		want = maxf(want, mv.length() * 0.6)
	var target := want * tuning.top_speed * (1.0 if boost else 0.82)
	var corner_cap := lerpf(tuning.top_speed, 8.5, pow(absf(mv.x), 1.4))
	target = minf(target, corner_cap)
	var probe := _wall_probe()
	if probe > 0.0:
		target = minf(target, probe)
		assist_brake = 1.0
	if mv.y < -0.4:
		brake_in = -mv.y
		return
	var err := target - v
	throttle_in = clampf(err * 0.45, 0.0, 1.0)
	if err < -2.5:
		brake_in = clampf(-err * 0.12, 0.0, 1.0)


func _wall_probe() -> float:
	if v < 6.0:
		return 0.0
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 0.6
	var to := from + forward() * v * 0.9
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty() or hit.normal.y > 0.6:
		return 0.0
	var dist := from.distance_to(hit.position)
	return maxf(dist / 0.9 - 2.0, 3.0)


# ------------------------------------------------------------------ ground

func _sample_ground() -> void:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.3, 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var id: StringName = &"asphalt"
	var col: Object = hit.collider
	if col and col.has_meta(&"surface"):
		id = col.get_meta(&"surface")
	surface = SurfaceData.offroad(id) if offroad_kit else SurfaceData.get_surface(id)


# ------------------------------------------------------------------ steering & slide

func yaw_rate_limit(speed: float) -> float:
	var s := absf(speed)
	var by_radius := s / tuning.min_turn_radius
	var by_grip := surface.grip * G * tuning.lateral_grip / maxf(s, 0.1)
	return minf(minf(by_radius, tuning.max_yaw_rate), by_grip)


func _update_steering(dt: float) -> void:
	var on_ground := is_on_floor()
	var limit := yaw_rate_limit(v)
	var target := steer * limit * signf(v if absf(v) > 0.05 else 1.0)
	var speed_frac := clampf(absf(v) / tuning.top_speed, 0.0, 1.0)
	target *= 1.0 - tuning.high_speed_steer * 0.35 * speed_frac * speed_frac

	var hb := handbrake_in and v > 4.0
	if hb:
		target *= tuning.handbrake_oversteer
	if state == State.CRASHED or not on_ground:
		target = 0.0

	var grip_limit := tuning.slide_threshold * surface.grip * G * tuning.lateral_grip * surface.slide_ease
	if hb:
		grip_limit *= 0.4
	var lateral_req := absf(v * target)
	var over := clampf((lateral_req / maxf(grip_limit, 0.01) - 1.0) * 3.0, 0.0, 1.0)
	if hb:
		over = maxf(over, 0.8)
	slide_amount = FeelMath.damp(slide_amount, over, 6.0, dt)

	yaw_rate = FeelMath.damp(yaw_rate, target, tuning.yaw_response, dt)
	heading = wrapf(heading + yaw_rate * dt, -PI, PI)

	var prev_vh := vel_heading
	if on_ground:
		var rec := lerpf(tuning.grip_recovery, tuning.slide_grip_recovery, slide_amount)
		vel_heading = FeelMath.damp_angle(vel_heading, heading, rec, dt)
		var max_slip := deg_to_rad(tuning.max_slip_deg)
		var d := angle_difference(heading, vel_heading)
		if absf(d) > max_slip:
			vel_heading = heading + signf(d) * max_slip
	slip = angle_difference(heading, vel_heading)
	path_rate = FeelMath.damp(path_rate, angle_difference(prev_vh, vel_heading) / dt, 14.0, dt)
	rotation.y = heading


# ------------------------------------------------------------------ longitudinal

func _update_speed(dt: float) -> void:
	var t := tuning
	var on_ground := is_on_floor()
	var a := 0.0
	var vmax := t.top_speed
	var x := clampf(v / vmax, 0.0, 1.1)
	var resist_top := t.coast_decel + t.air_drag * vmax * vmax

	if state == State.CRASHED:
		v = move_toward(v, 0.0, 9.0 * dt)
		_prev_v = v
		long_accel = 0.0
		return

	if on_ground:
		if throttle_in > 0.0 and v > -0.5:
			var drive := (t.launch_accel * (1.0 - x * x) + resist_top * x * x) * throttle_in * surface.power * (1.0 if fuel > 0.0 else t.reserve_power)
			if _shift_timer > 0.0:
				drive *= 0.15
			a += drive
		if brake_in > 0.0:
			if v > 0.4:
				a -= t.front_brake * brake_in * surface.brake
			elif throttle_in < 0.1 and state == State.RIDING:
				# hold brake at standstill → creep backwards (parking manoeuvres)
				a += (-t.reverse_speed - v) * 2.5 * brake_in
			else:
				a -= v * 6.0
		if handbrake_in and absf(v) > 0.2:
			a -= signf(v) * t.rear_brake * surface.brake
		var resist := t.coast_decel + surface.drag + t.air_drag * v * v
		a -= signf(v) * minf(resist, absf(v) / dt)
		# gravity along the slope
		var n := get_floor_normal()
		var f := forward()
		var f_on_plane := (f - n * f.dot(n)).normalized()
		a += -G * f_on_plane.y
		# sideways slip scrubs speed
		a -= signf(v) * absf(sin(slip)) * t.slide_scrub * (1.0 + absf(v) * 0.05)
	v += a * dt
	if state == State.PARKED and absf(v) < 0.3:
		v = 0.0
	long_accel = FeelMath.damp(long_accel, (v - _prev_v) / dt, 10.0, dt)
	_prev_v = v


func _move(dt: float) -> void:
	var dir := Vector3(-sin(vel_heading), 0.0, -cos(vel_heading))
	var horiz := dir * v
	var on_floor_before := is_on_floor()
	if on_floor_before:
		# keep upward momentum from ramps so crests launch the bike; downhill is handled by floor snap
		_vy = clampf(get_real_velocity().y, 0.0, 12.0) if _was_on_floor else 0.0
		if _vy < 0.3:
			_vy = -1.0   # keep contact; floor snap handles downhill
		airborne_time = 0.0
	else:
		_vy -= G * AIR_GRAVITY * dt
		airborne_time += dt
	velocity = Vector3(horiz.x, _vy, horiz.z)
	var pre_vel := velocity
	move_and_slide()
	if is_on_floor() and not on_floor_before and airborne_time > 0.18:
		last_landing = clampf(-pre_vel.y / 8.0, 0.0, 1.0)
		visual.on_landing(last_landing)
		bumped.emit(last_landing)
	_was_on_floor = is_on_floor()
	_handle_collisions(pre_vel)


func _handle_collisions(pre_vel: Vector3) -> void:
	var worst := 0.0
	var worst_n := Vector3.ZERO
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		if n.y > 0.6:
			continue
		var nh := Vector3(n.x, 0.0, n.z).normalized()
		var impact := -Vector3(pre_vel.x, 0.0, pre_vel.z).dot(nh)
		if impact > worst:
			worst = impact
			worst_n = nh
	if worst < 1.0:
		return
	var head_on := rad_to_deg(acos(clampf(forward().dot(-worst_n), -1.0, 1.0)))
	if state == State.RIDING and worst >= tuning.crash_impact and head_on < tuning.crash_max_angle_deg:
		_crash(worst)
		return
	var keep := lerpf(1.0, tuning.bump_speed_keep, clampf(worst / tuning.crash_impact, 0.0, 1.0))
	var tangent := Vector3(pre_vel.x, 0.0, pre_vel.z)
	tangent -= worst_n * tangent.dot(worst_n)
	if tangent.length() > 0.5:
		vel_heading = atan2(-tangent.x, -tangent.z)
		if v < 0.0:
			vel_heading = wrapf(vel_heading + PI, -PI, PI)
		heading = FeelMath.damp_angle(heading, vel_heading, 6.0, get_physics_process_delta_time())
	v *= keep
	var strength := clampf(worst / tuning.crash_impact, 0.0, 1.0)
	visual.on_bump(strength, worst_n)
	bumped.emit(strength)
	NoiseBus.emit_noise(global_position, 20.0 + 30.0 * strength, NoiseBus.Priority.COMBAT, self)


func _crash(impact: float) -> void:
	state = State.CRASHED
	crash_timer = 0.0
	v *= 0.35
	visual.on_crash()
	crashed.emit(impact)
	EventBus.bike_crashed.emit(self, impact)
	NoiseBus.emit_noise(global_position, 55.0, NoiseBus.Priority.COMBAT, self)


## Lifts a fallen bike back up when the player mounts it again.
func recover() -> void:
	if state == State.CRASHED:
		state = State.PARKED
		v = 0.0
		vel_heading = heading
		visual.on_recover()


# ------------------------------------------------------------------ engine

func _update_engine(dt: float) -> void:
	var t := tuning
	if _shift_timer > 0.0:
		_shift_timer -= dt
	var target_gear := gear
	var s := absf(v)
	if s > t.gear_top_speed(gear) * 0.97 and gear < t.gear_count:
		target_gear = gear + 1
	elif gear > 1 and s < t.gear_top_speed(gear - 1) * 0.78:
		target_gear = gear - 1
	if target_gear != gear:
		var up := target_gear > gear
		gear = target_gear
		if up and throttle_in > 0.3:
			_shift_timer = t.shift_cut_time
		gear_changed.emit(gear, up)

	var lo := t.gear_top_speed(gear - 1) * 0.55 if gear > 1 else 0.0
	var hi := t.gear_top_speed(gear)
	var frac := clampf((s - lo) / maxf(hi - lo, 0.1), 0.0, 1.0)
	var target_rpm := lerpf(t.idle_rpm + 900.0, t.redline_rpm, pow(frac, 0.9))
	if s < 1.5:
		target_rpm = t.idle_rpm + throttle_in * 4200.0
	if slide_amount > 0.4 and throttle_in > 0.5:
		target_rpm = minf(target_rpm + 1800.0 * slide_amount, t.redline_rpm)  # wheelspin flare
	if not is_on_floor() and throttle_in > 0.5:
		target_rpm = minf(target_rpm + 2500.0, t.redline_rpm)
	if _shift_timer > 0.0:
		target_rpm -= 1600.0
	if state != State.RIDING:
		target_rpm = 0.0
	rpm = FeelMath.damp(rpm, target_rpm, 9.0 if target_rpm > rpm else 6.0, dt)
	engine_load = FeelMath.damp(engine_load, throttle_in if _shift_timer <= 0.0 else 0.0, 14.0, dt)


func _emit_noise(dt: float) -> void:
	_noise_timer -= dt
	if _noise_timer > 0.0 or state != State.RIDING:
		return
	_noise_timer = 0.5
	var t := tuning
	var rpm_n := clampf((rpm - t.idle_rpm) / (t.redline_rpm - t.idle_rpm), 0.0, 1.0)
	var loud := clampf(engine_load * 0.6 + rpm_n * 0.5, 0.0, 1.0)
	var r := lerpf(t.noise_idle_radius, t.noise_full_radius, loud) * t.muffler * noise_mult
	NoiseBus.emit_noise(global_position, r, NoiseBus.Priority.ENGINE, self)


func noise_radius() -> float:
	var t := tuning
	var rpm_n := clampf((rpm - t.idle_rpm) / (t.redline_rpm - t.idle_rpm), 0.0, 1.0)
	return lerpf(t.noise_idle_radius, t.noise_full_radius, clampf(engine_load * 0.6 + rpm_n * 0.5, 0.0, 1.0)) * t.muffler * noise_mult


## Workbench upgrades: the visible part plus its effect.
func set_upgrade(id: String, on: bool) -> void:
	match id:
		"saddlebags":
			visual.set_saddlebags(on)
		"muffler":
			visual.set_silencer(on)
			noise_mult = UpgradeDB.MUFFLER_NOISE if on else 1.0
			var au: Node = get_node_or_null("Audio")
			if au and au.player:
				au.player.volume_db = -9.0 if on else -4.0
				au.player.attenuation_filter_cutoff_hz = 3200.0 if on else 6000.0
		"suspension":
			visual.set_suspension(on)
			offroad_kit = on


# ------------------------------------------------------------------ enemies

func _on_ram_body(body: Node) -> void:
	if not body.is_in_group(&"enemy") or not body.has_method("receive_vehicle_hit"):
		return
	var s := absf(v)
	if s < 1.2:
		return
	var heavy: bool = body.get(&"is_heavy") == true
	body.receive_vehicle_hit(self, forward() * v, s)
	if heavy:
		if s > tuning.zombie_knock_speed and state == State.RIDING:
			_crash(s)
		else:
			v *= 0.1
			visual.on_bump(0.7, -forward())
		return
	var loss := tuning.zombie_speed_loss * clampf(s / tuning.zombie_knock_speed, 0.3, 1.0)
	v *= 1.0 - loss
	visual.on_bump(0.35, -forward())
	bumped.emit(0.35)


func _process(_dt: float) -> void:
	if state == State.RIDING or state == State.PARKED:
		_push_slow_overlaps()


func _push_slow_overlaps() -> void:
	if absf(v) >= 1.2:
		return
	for b in ram_area.get_overlapping_bodies():
		if b.is_in_group(&"enemy") and b.has_method("push"):
			b.push(forward() * 0.6)
