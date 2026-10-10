class_name CamRig
extends Node3D

## Single third-person rig for every mode. Spring-followed pivot, profile blending,
## collision with fast pull-in / slow push-out, auto-recentre and look-ahead when
## riding, trauma shake and recoil springs.

@export var follow: Node3D
var profile: CamProfile = CamProfile.on_foot()
var vehicle: Moto
var speed := 0.0                       ## set by the follow target (m/s)
var crowd_factor := 0.0                ## 0..1 horde widening
var look_scale := 1.0                  ## aim-assist friction
var aiming := false

var yaw := 0.0
var pitch := deg_to_rad(-10.0)

var _dist := 3.2
var _height := 1.5
var _fov := 60.0
var _shoulder := 0.45
var _cur_dist := 3.2
var _pivot := FeelMath.Spring3.new(6.0, 1.0)
var _trauma := 0.0
var _shake_t := 0.0
var _noise := FastNoiseLite.new()
var _kick_pitch := FeelMath.Spring.new(5.5, 0.55)
var _kick_yaw := FeelMath.Spring.new(5.5, 0.55)
var _fov_punch := FeelMath.Spring.new(4.0, 0.6)
var _shape := SphereShape3D.new()
var _initialized := false
var _excludes: Array[RID] = []

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	top_level = true
	_noise.frequency = 1.6
	_shape.radius = 0.22
	camera.near = 0.06
	camera.far = 600.0
	EventBus.camera_impulse.connect(add_trauma)


func set_profile(p: CamProfile) -> void:
	profile = p


func exclude(body: CollisionObject3D) -> void:
	_excludes.append(body.get_rid())


func add_trauma(amount: float) -> void:
	if GameSettings.camera_shake:
		_trauma = clampf(_trauma + amount, 0.0, 1.0)


func kick(pitch_deg: float, yaw_deg: float, fov_punch := 0.0) -> void:
	_kick_pitch.impulse(deg_to_rad(pitch_deg) * 30.0)
	_kick_yaw.impulse(deg_to_rad(yaw_deg) * 30.0)
	_fov_punch.impulse(fov_punch * 30.0)


## Permanent aim offset from recoil (pattern climb) — added to pitch/yaw directly.
func add_recoil(pitch_deg: float, yaw_deg: float) -> void:
	pitch = clampf(pitch + deg_to_rad(pitch_deg), deg_to_rad(profile.pitch_min), deg_to_rad(profile.pitch_max))
	yaw += deg_to_rad(yaw_deg)


func snap_behind(heading: float) -> void:
	yaw = heading
	pitch = deg_to_rad(profile.pitch_default)


func _process(dt: float) -> void:
	if follow == null:
		return
	var p := profile
	var k := clampf(speed / maxf(p.speed_ref, 0.1), 0.0, 1.0)
	var blend := 7.0
	_dist = FeelMath.damp(_dist, lerpf(p.distance, p.distance_fast, k) + crowd_factor * 1.5, blend, dt)
	_height = FeelMath.damp(_height, lerpf(p.height, p.height_fast, k), blend, dt)
	var fov_target := p.fov + crowd_factor * 4.0
	if GameSettings.speed_fov:
		fov_target = lerpf(p.fov, p.fov_fast, k * k) + crowd_factor * 4.0
	_fov = FeelMath.damp(_fov, fov_target, blend, dt)
	var shoulder := p.shoulder * (-1.0 if GameSettings.left_handed else 1.0)
	_shoulder = FeelMath.damp(_shoulder, shoulder, blend, dt)
	_pivot.frequency = FeelMath.damp(_pivot.frequency, p.pivot_frequency, blend, dt)

	# --- look input
	var look := PlayerInput.consume_look(dt, aiming) * look_scale
	yaw -= look.x
	pitch = clampf(pitch - look.y, deg_to_rad(p.pitch_min), deg_to_rad(p.pitch_max))
	if Input.is_action_just_pressed(&"cam_recenter") and vehicle:
		snap_behind(vehicle.heading)

	# --- riding: recentre behind the bike, leading into turns
	if p.auto_center and vehicle and PlayerInput.seconds_since_look() > p.auto_center_delay:
		var lead := clampf(vehicle.yaw_rate * p.look_ahead, -deg_to_rad(p.look_ahead_max_deg), deg_to_rad(p.look_ahead_max_deg))
		var travel := vehicle.heading if vehicle.v >= -0.5 else vehicle.heading + PI
		var rate := p.auto_center_rate * clampf(absf(vehicle.v) / 6.0, 0.15, 1.0)
		yaw = FeelMath.damp_angle(yaw, travel + lead, rate, dt)
		pitch = FeelMath.damp(pitch, deg_to_rad(p.pitch_default), rate * 0.6, dt)

	# --- pivot follow
	var target_pos := follow.get_global_transform_interpolated().origin + Vector3(0, _height, 0)
	if not _initialized:
		_pivot.reset(target_pos)
		_cur_dist = _dist
		_initialized = true
	var pivot := _pivot.step(target_pos, dt)
	# never let the pivot lag so far the target leaves the frame
	var lag := pivot - target_pos
	if lag.length() > 1.2:
		pivot = target_pos + lag.limit_length(1.2)
		_pivot.value = pivot

	# --- shake & kicks
	_trauma = maxf(_trauma - dt * 1.4, 0.0)
	_shake_t += dt
	var sh := _trauma * _trauma
	var shake_pitch := _noise.get_noise_2d(_shake_t * 22.0, 0.0) * deg_to_rad(3.0) * sh
	var shake_yaw := _noise.get_noise_2d(0.0, _shake_t * 22.0) * deg_to_rad(3.0) * sh
	var kp := _kick_pitch.step(0.0, dt)
	var ky := _kick_yaw.step(0.0, dt)
	var fp := _fov_punch.step(0.0, dt)

	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var right := basis.x
	var shoulder_pivot := pivot + right * _shoulder
	var desired := shoulder_pivot + basis.z * _dist

	# --- collision: cast a sphere from the pivot out to the desired position
	var allowed := _dist
	var space := get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _shape
	params.transform = Transform3D(Basis.IDENTITY, pivot)
	params.motion = desired - pivot
	params.collision_mask = 1
	params.exclude = _excludes
	var res := space.cast_motion(params)
	if res.size() == 2 and res[0] < 1.0:
		allowed = maxf(pivot.distance_to(desired) * res[0] - 0.05, 0.35)
	var full := pivot.distance_to(desired)
	var allowed_frac := allowed / maxf(full, 0.001)
	var cur_frac := _cur_dist / maxf(_dist, 0.001)
	if allowed_frac < cur_frac:
		cur_frac = allowed_frac            # pull in immediately
	else:
		cur_frac = FeelMath.damp(cur_frac, allowed_frac, 3.5, dt)  # ease back out
	_cur_dist = cur_frac * _dist
	var cam_pos := pivot + (desired - pivot) * cur_frac

	global_position = cam_pos
	global_basis = Basis.from_euler(Vector3(pitch + kp + shake_pitch, yaw + ky + shake_yaw, 0.0))
	camera.fov = _fov + fp


## World point under the crosshair (ignores the excluded bodies).
func aim_point(max_dist := 150.0, mask := 1 | 8 | 16) -> Dictionary:
	var from := camera.global_position
	var dir := -camera.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * max_dist, mask)
	q.exclude = _excludes
	q.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return {"position": from + dir * max_dist, "collider": null, "normal": Vector3.UP}
	return hit
