class_name MotoVisual
extends Node3D

## Builds the scrambler model from primitives and animates every visual layer from
## the simulated state: lean (pivoting on the tyre contact line), pitch, heave,
## fork travel, swingarm, wheel spin, steering, headlight and surface dust.

const WHEEL_R := 0.34
const FRONT_Z := -0.83
const REAR_Z := 0.59
const HEAD := Vector3(0.0, 0.98, -0.52)
const RAKE_DEG := 26.0
const FORK_LEN := 0.712
const SWING_PIVOT := Vector3(0.0, 0.43, 0.06)
const KICKSTAND_LEAN := deg_to_rad(9.0)

var lean_spring := FeelMath.Spring.new(3.2, 0.72)
var pitch_spring := FeelMath.Spring.new(2.6, 0.6)
var heave_spring := FeelMath.Spring.new(3.4, 0.55)
var steer_angle := 0.0
var lean := 0.0
var fork_comp := 0.0
var rear_comp := 0.0
var crashed := false
var foot_down := 0.0           ## 0..1, rider reads this
var _crash_side := 1.0
var _rough_t := 0.0
var _noise := FastNoiseLite.new()

var lean_pivot: Node3D
var chassis: Node3D
var steer_yaw: Node3D
var fork_slider: Node3D
var front_spin: Node3D
var rear_spin: Node3D
var swingarm: Node3D
var kickstand: Node3D
var headlight: SpotLight3D
var tail_mat: StandardMaterial3D
var dust: CPUParticles3D
var saddlebags: Node3D
var muffler_can: Node3D
var silencer: Node3D            ## muffler upgrade: wrapped can over the stock pipe
var springs: Node3D             ## suspension upgrade: rear coil-overs
var gaiters: Node3D             ## suspension upgrade: front fork boots

var seat_socket: Marker3D
var grip_l: Marker3D
var grip_r: Marker3D
var peg_l: Marker3D
var peg_r: Marker3D


func _ready() -> void:
	_noise.frequency = 3.0
	_build()
	MeshMerger.merge_rigid(self)


# ------------------------------------------------------------------ build

func _build() -> void:
	var mid := (FRONT_Z + REAR_Z) * 0.5
	lean_pivot = Node3D.new()
	lean_pivot.name = "LeanPivot"
	lean_pivot.position = Vector3(0, 0, mid)
	add_child(lean_pivot)
	chassis = Node3D.new()
	chassis.name = "Chassis"
	lean_pivot.add_child(chassis)
	var frame_root := Node3D.new()
	frame_root.position = Vector3(0, 0, -mid)
	chassis.add_child(frame_root)

	var M := Palette
	# --- frame & bodywork
	MeshKit.strut(frame_root, HEAD + Vector3(0, -0.02, 0.02), Vector3(0, 0.86, 0.36), 0.032, M.mat(&"bike_frame"))
	MeshKit.strut(frame_root, HEAD + Vector3(0, -0.1, 0.03), Vector3(0, 0.36, -0.28), 0.03, M.mat(&"bike_frame"))
	MeshKit.strut(frame_root, Vector3(0, 0.36, -0.28), Vector3(0, 0.33, 0.12), 0.028, M.mat(&"bike_frame"))
	MeshKit.strut(frame_root, Vector3(0, 0.33, 0.12), Vector3(0, 0.86, 0.36), 0.026, M.mat(&"bike_frame"))
	MeshKit.strut(frame_root, Vector3(0.11, 0.84, 0.3), Vector3(0.11, 0.8, 0.72), 0.018, M.mat(&"bike_frame"))
	MeshKit.strut(frame_root, Vector3(-0.11, 0.84, 0.3), Vector3(-0.11, 0.8, 0.72), 0.018, M.mat(&"bike_frame"))
	var tank := MeshKit.capsule(frame_root, 0.15, 0.56, Vector3(0, 0.99, -0.2), M.mat(&"bike_tank"), Vector3(-84, 0, 0), Vector3(1.22, 1.0, 0.86))
	tank.name = "Tank"
	MeshKit.box(frame_root, Vector3(0.05, 0.02, 0.16), Vector3(0, 1.13, -0.24), M.mat(&"bike_chrome"))  # filler cap strip
	MeshKit.capsule(frame_root, 0.13, 0.62, Vector3(0, 0.885, 0.27), M.mat(&"bike_seat"), Vector3(-90, 0, 0), Vector3(1.05, 1.0, 0.45))
	MeshKit.box(frame_root, Vector3(0.2, 0.2, 0.2), Vector3(0, 0.74, 0.12), M.mat(&"bike_frame"))  # airbox / side covers
	MeshKit.box(frame_root, Vector3(0.23, 0.15, 0.17), Vector3(0, 0.73, 0.13), M.mat(&"bike_tank"))
	# --- engine
	MeshKit.box(frame_root, Vector3(0.3, 0.3, 0.4), Vector3(0, 0.5, -0.1), M.mat(&"bike_engine"))
	MeshKit.cyl(frame_root, 0.11, 0.08, Vector3(0.16, 0.48, -0.12), M.mat(&"bike_chrome"), Vector3(0, 0, 90))  # clutch cover
	MeshKit.cyl(frame_root, 0.09, 0.07, Vector3(-0.16, 0.46, -0.04), M.mat(&"bike_engine"), Vector3(0, 0, 90))
	var cyl_root := Node3D.new()
	cyl_root.position = Vector3(0, 0.64, -0.24)
	cyl_root.rotation_degrees = Vector3(-24, 0, 0)
	frame_root.add_child(cyl_root)
	for i in 6:
		MeshKit.box(cyl_root, Vector3(0.24 - i * 0.01, 0.018, 0.2 - i * 0.008), Vector3(0, i * 0.035, 0), M.mat(&"bike_engine"))
	MeshKit.box(cyl_root, Vector3(0.16, 0.07, 0.15), Vector3(0, 0.22, 0), M.mat(&"bike_chrome"))
	# --- exhaust (high scrambler pipe, right side)
	var ex := M.mat(&"bike_exhaust")
	MeshKit.strut(frame_root, Vector3(0.04, 0.62, -0.38), Vector3(0.14, 0.42, -0.36), 0.026, ex)
	MeshKit.strut(frame_root, Vector3(0.14, 0.42, -0.36), Vector3(0.19, 0.52, 0.02), 0.026, ex)
	MeshKit.strut(frame_root, Vector3(0.19, 0.52, 0.02), Vector3(0.2, 0.66, 0.34), 0.028, ex)
	muffler_can = MeshKit.cyl(frame_root, 0.055, 0.42, Vector3(0.2, 0.7, 0.52), M.mat(&"bike_engine"), Vector3(-78, 0, 0), 14)
	MeshKit.cyl(frame_root, 0.058, 0.05, Vector3(0.2, 0.74, 0.74), M.mat(&"bike_chrome"), Vector3(-78, 0, 0), 14)
	# --- rear fender, tail light, plate
	MeshKit.box(frame_root, Vector3(0.16, 0.012, 0.5), Vector3(0, 0.82, 0.78), M.mat(&"bike_frame"), Vector3(-12, 0, 0))
	var tail := MeshKit.box(frame_root, Vector3(0.1, 0.035, 0.03), Vector3(0, 0.78, 1.03), M.mat(&"taillight"))
	tail_mat = (M.mat(&"taillight") as StandardMaterial3D).duplicate()
	tail.material_override = tail_mat
	MeshKit.box(frame_root, Vector3(0.16, 0.1, 0.01), Vector3(0, 0.7, 1.02), M.mat(&"painted_metal"), Vector3(-15, 0, 0))
	# --- footpegs & kickstand
	MeshKit.cyl(frame_root, 0.018, 0.12, Vector3(0.2, 0.36, 0.08), M.mat(&"rubber"), Vector3(0, 0, 90), 8)
	MeshKit.cyl(frame_root, 0.018, 0.12, Vector3(-0.2, 0.36, 0.08), M.mat(&"rubber"), Vector3(0, 0, 90), 8)
	kickstand = Node3D.new()
	kickstand.position = Vector3(-0.14, 0.34, 0.02)
	frame_root.add_child(kickstand)
	MeshKit.strut(kickstand, Vector3.ZERO, Vector3(-0.17, -0.31, 0.12), 0.014, M.mat(&"bike_frame"))
	# --- saddlebags (upgrade, hidden by default)
	saddlebags = Node3D.new()
	saddlebags.visible = false
	frame_root.add_child(saddlebags)
	for sx in [-1.0, 1.0]:
		MeshKit.box(saddlebags, Vector3(0.13, 0.27, 0.4), Vector3(0.25 * sx, 0.64, 0.5), M.mat(&"canvas"))
		MeshKit.box(saddlebags, Vector3(0.14, 0.05, 0.41), Vector3(0.25 * sx, 0.79, 0.5), M.mat(&"bike_seat"))
	# --- silencer (upgrade, hidden by default): fat wrapped can with clamps
	silencer = Node3D.new()
	silencer.visible = false
	frame_root.add_child(silencer)
	MeshKit.cyl(silencer, 0.085, 0.5, Vector3(0.2, 0.71, 0.56), M.mat(&"canvas"), Vector3(-78, 0, 0), 14)
	for k in [-0.17, 0.0, 0.17]:
		MeshKit.cyl(silencer, 0.09, 0.025, Vector3(0.2, 0.71, 0.56) + Vector3(0, 0.035, 1.0) * k, M.mat(&"bike_chrome"), Vector3(-78, 0, 0), 14)
	# --- markers for the rider
	seat_socket = _marker(frame_root, "SeatSocket", Vector3(0, 0.93, 0.2))
	peg_l = _marker(frame_root, "PegL", Vector3(-0.22, 0.37, 0.1))
	peg_r = _marker(frame_root, "PegR", Vector3(0.22, 0.37, 0.1))

	# --- steering assembly
	var steer_base := Node3D.new()
	steer_base.name = "SteerBase"
	steer_base.position = HEAD
	steer_base.rotation_degrees = Vector3(RAKE_DEG, 0, 0)
	frame_root.add_child(steer_base)
	steer_yaw = Node3D.new()
	steer_base.add_child(steer_yaw)
	MeshKit.box(steer_yaw, Vector3(0.2, 0.04, 0.09), Vector3(0, 0.0, 0), M.mat(&"bike_engine"))   # top clamp
	MeshKit.box(steer_yaw, Vector3(0.2, 0.04, 0.09), Vector3(0, -0.16, 0), M.mat(&"bike_engine")) # bottom clamp
	for sx in [-1.0, 1.0]:
		MeshKit.cyl(steer_yaw, 0.026, 0.3, Vector3(0.08 * sx, -0.1, 0), M.mat(&"bike_chrome"), Vector3.ZERO, 10)
	# handlebar: risers + swept bar
	MeshKit.cyl(steer_yaw, 0.014, 0.1, Vector3(0, 0.07, 0.03), M.mat(&"bike_chrome"), Vector3.ZERO, 8)
	MeshKit.strut(steer_yaw, Vector3(-0.2, 0.12, 0.03), Vector3(0.2, 0.12, 0.03), 0.013, M.mat(&"bike_chrome"))
	MeshKit.strut(steer_yaw, Vector3(0.2, 0.12, 0.03), Vector3(0.36, 0.15, 0.12), 0.013, M.mat(&"bike_chrome"))
	MeshKit.strut(steer_yaw, Vector3(-0.2, 0.12, 0.03), Vector3(-0.36, 0.15, 0.12), 0.013, M.mat(&"bike_chrome"))
	MeshKit.cyl(steer_yaw, 0.02, 0.11, Vector3(0.39, 0.152, 0.13), M.mat(&"rubber"), Vector3(0, 0, 90), 8)
	MeshKit.cyl(steer_yaw, 0.02, 0.11, Vector3(-0.39, 0.152, 0.13), M.mat(&"rubber"), Vector3(0, 0, 90), 8)
	grip_l = _marker(steer_yaw, "GripL", Vector3(-0.39, 0.152, 0.13))
	grip_r = _marker(steer_yaw, "GripR", Vector3(0.39, 0.152, 0.13))
	# headlight
	var hl := Node3D.new()
	hl.position = Vector3(0, -0.06, -0.14)
	hl.rotation_degrees = Vector3(-RAKE_DEG, 0, 0)
	steer_yaw.add_child(hl)
	MeshKit.cyl(hl, 0.095, 0.1, Vector3(0, 0, 0.0), M.mat(&"bike_frame"), Vector3(90, 0, 0), 18)
	MeshKit.cyl(hl, 0.08, 0.02, Vector3(0, 0, -0.05), M.mat(&"headlight"), Vector3(90, 0, 0), 18)
	MeshKit.box(hl, Vector3(0.16, 0.03, 0.03), Vector3(0, 0.11, 0.0), M.mat(&"bike_frame"))
	headlight = SpotLight3D.new()
	headlight.position = Vector3(0, 0, -0.08)
	headlight.rotation_degrees = Vector3(-6, 0, 0)
	headlight.spot_range = 34.0
	headlight.spot_angle = 30.0
	headlight.spot_attenuation = 0.8
	headlight.light_energy = 3.0
	headlight.light_color = Color("fff0d0")
	headlight.shadow_enabled = false
	headlight.visible = false
	hl.add_child(headlight)
	# fork sliders + front wheel
	fork_slider = Node3D.new()
	fork_slider.position = Vector3(0, -FORK_LEN, 0)
	steer_yaw.add_child(fork_slider)
	for sx in [-1.0, 1.0]:
		MeshKit.cyl(fork_slider, 0.034, 0.34, Vector3(0.08 * sx, 0.17, 0), M.mat(&"bike_frame"), Vector3.ZERO, 10)
	gaiters = Node3D.new()
	gaiters.visible = false
	fork_slider.add_child(gaiters)
	for sx in [-1.0, 1.0]:
		for k in 4:
			MeshKit.cyl(gaiters, 0.046 - (k % 2) * 0.008, 0.045, Vector3(0.08 * sx, 0.24 + k * 0.045, 0), M.mat(&"rubber"), Vector3.ZERO, 10)
	var fender := MeshKit.box(fork_slider, Vector3(0.15, 0.012, 0.42), Vector3(0, 0.42, -0.06), M.mat(&"bike_tank"), Vector3(-RAKE_DEG + 8, 0, 0))
	fender.name = "FrontFender"
	var fw := Node3D.new()
	fw.rotation_degrees = Vector3(-RAKE_DEG, 0, 0)
	fork_slider.add_child(fw)
	front_spin = _wheel(fw, true)

	# --- swingarm + rear wheel
	swingarm = Node3D.new()
	swingarm.position = SWING_PIVOT
	frame_root.add_child(swingarm)
	var axle := Vector3(0, WHEEL_R - SWING_PIVOT.y, REAR_Z - SWING_PIVOT.z)
	for sx in [-1.0, 1.0]:
		MeshKit.strut(swingarm, Vector3(0.09 * sx, 0, 0), axle + Vector3(0.09 * sx, 0, 0), 0.022, M.mat(&"bike_frame"))
		# shocks: swingarm → subframe
		MeshKit.strut(swingarm, axle * 0.8 + Vector3(0.1 * sx, 0.02, 0), Vector3(0.1 * sx, 0.42, 0.38), 0.022, M.mat(&"bike_engine"))
	springs = Node3D.new()
	springs.visible = false
	swingarm.add_child(springs)
	for sx in [-1.0, 1.0]:
		var lo := axle * 0.8 + Vector3(0.1 * sx, 0.02, 0)
		var hi := Vector3(0.1 * sx, 0.42, 0.38)
		MeshKit.strut(springs, lo.lerp(hi, 0.25), lo.lerp(hi, 0.8), 0.04, M.mat(&"hazard"))
	var rw := Node3D.new()
	rw.position = axle
	swingarm.add_child(rw)
	rear_spin = _wheel(rw, false)

	# --- dust
	dust = CPUParticles3D.new()
	dust.position = Vector3(0, 0.08, REAR_Z + 0.25)
	dust.amount = 48
	dust.lifetime = 1.4
	dust.emitting = false
	dust.local_coords = false
	dust.direction = Vector3(0, 0.6, 1)
	dust.spread = 35.0
	dust.initial_velocity_min = 1.0
	dust.initial_velocity_max = 2.6
	dust.gravity = Vector3(0, 0.25, 0)
	dust.damping_min = 1.2
	dust.damping_max = 2.2
	dust.scale_amount_min = 0.5
	dust.scale_amount_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 1.6))
	dust.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.55))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	dust.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(0.8, 0.8)
	var dm := StandardMaterial3D.new()
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.vertex_color_use_as_albedo = true
	dm.albedo_texture = _soft_puff()
	q.material = dm
	dust.mesh = q
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dust)


func _wheel(parent: Node3D, front: bool) -> Node3D:
	var spin := Node3D.new()
	parent.add_child(spin)
	var M := Palette
	MeshKit.torus(spin, 0.235, 0.34, Vector3.ZERO, M.mat(&"rubber"), Vector3(0, 0, 90))
	MeshKit.torus(spin, 0.215, 0.245, Vector3.ZERO, M.mat(&"bike_engine"), Vector3(0, 0, 90))
	MeshKit.cyl(spin, 0.05, 0.12, Vector3.ZERO, M.mat(&"bike_engine"), Vector3(0, 0, 90), 12)
	for i in 12:
		var a := TAU * i / 12.0
		var tip := Vector3(0, cos(a), sin(a)) * 0.218
		var root := Vector3((0.035 if i % 2 == 0 else -0.035), cos(a + 0.2) * 0.04, sin(a + 0.2) * 0.04)
		MeshKit.strut(spin, root, tip, 0.004, M.mat(&"bike_chrome"))
	if front:
		MeshKit.cyl(spin, 0.13, 0.008, Vector3(-0.06, 0, 0), M.mat(&"bike_chrome"), Vector3(0, 0, 90), 20)
	else:
		MeshKit.cyl(spin, 0.1, 0.008, Vector3(0.06, 0, 0), M.mat(&"bike_chrome"), Vector3(0, 0, 90), 20)
	return spin


func _marker(parent: Node3D, n: String, pos: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = n
	m.position = pos
	parent.add_child(m)
	return m


static func _soft_puff() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


# ------------------------------------------------------------------ per-frame

func update_dynamics(bike: Moto, dt: float) -> void:
	var t := bike.tuning
	lean_spring.frequency = t.lean_frequency
	lean_spring.damping = t.lean_damping
	heave_spring.frequency = t.suspension_frequency
	heave_spring.damping = t.suspension_damping

	var s := bike.v
	var ridden := bike.state == Moto.State.RIDING
	# --- lean target
	var target_lean := 0.0
	if bike.state == Moto.State.CRASHED:
		target_lean = deg_to_rad(78.0) * _crash_side
	elif bike.state == Moto.State.PARKED:
		target_lean = KICKSTAND_LEAN
	else:
		# lean follows the curvature actually travelled, so slides stand the bike up
		target_lean = atan(s * bike.path_rate / Moto.G * t.lean_scale)
		var max_l := deg_to_rad(t.max_lean_deg)
		target_lean = clampf(target_lean, -max_l, max_l)
		# at a standstill the rider props the bike on the left foot
		var stop := 1.0 - clampf((absf(s) - 0.4) / 1.4, 0.0, 1.0)
		foot_down = FeelMath.damp(foot_down, stop, 8.0, dt)
		target_lean = lerpf(target_lean, deg_to_rad(4.0), foot_down)
		# low-speed balance wobble
		_rough_t += dt
		target_lean += _noise.get_noise_1d(_rough_t * 0.7) * deg_to_rad(1.2) * clampf(1.0 - absf(s) / 6.0, 0.0, 1.0) * (1.0 - foot_down)
	if not ridden:
		foot_down = FeelMath.damp(foot_down, 0.0, 8.0, dt)
	lean = lean_spring.step(target_lean, dt)
	lean_pivot.rotation.z = lean
	kickstand.rotation.x = FeelMath.damp(kickstand.rotation.x, 0.0 if bike.state == Moto.State.PARKED else -1.4, 10.0, dt)

	# --- ground under each wheel (body-local heights)
	var hf := _ground_height(bike, FRONT_Z)
	var hr := _ground_height(bike, REAR_Z)
	var airborne := not bike.is_on_floor()
	if airborne:
		hf = -t.suspension_travel
		hr = -t.suspension_travel
	var terrain_pitch := atan2(hf - hr, REAR_Z - FRONT_Z)
	if airborne:
		terrain_pitch = 0.04
	var a := bike.long_accel
	var dyn := a * (t.brake_dive if a < 0.0 else 0.006)
	dyn = clampf(dyn, -0.13, 0.07)
	var pitch := pitch_spring.step(terrain_pitch + dyn, dt)
	var base_h := (hf + hr) * 0.5
	# dive compresses the front, squat the rear: heave follows the average
	var rough := 0.0
	if not airborne and absf(s) > 0.5:
		_rough_t += dt * (1.0 + absf(s) * 0.4)
		rough = _noise.get_noise_1d(_rough_t * 9.0) * bike.surface.roughness * clampf(absf(s) / 15.0, 0.0, 1.0) * 0.035
	var heave := heave_spring.step(base_h - absf(dyn) * 0.25 + rough, dt)
	if bike.state == Moto.State.CRASHED:
		heave = lerpf(heave, -0.12, 0.5)
	chassis.position.y = heave
	chassis.rotation.x = pitch

	# --- suspension: keep wheels on the ground inside their travel
	var chassis_front := heave + tan(pitch) * ((REAR_Z - FRONT_Z) * 0.5)
	var chassis_rear := heave - tan(pitch) * ((REAR_Z - FRONT_Z) * 0.5)
	fork_comp = clampf(hf - chassis_front, -t.suspension_travel, t.suspension_travel)
	rear_comp = clampf(hr - chassis_rear, -t.suspension_travel, t.suspension_travel)
	fork_slider.position.y = -FORK_LEN + fork_comp / cos(deg_to_rad(RAKE_DEG))
	swingarm.rotation.x = asin(clampf(rear_comp / (REAR_Z - SWING_PIVOT.z), -0.5, 0.5))

	# --- wheels & steering
	var spin := s / WHEEL_R * dt
	front_spin.rotation.x -= spin
	rear_spin.rotation.x -= spin * (1.0 + bike.slide_amount * bike.throttle_in * 0.6)
	var geo_steer := atan((REAR_Z - FRONT_Z) * bike.yaw_rate / maxf(absf(s), 1.2))
	var target_steer := clampf(geo_steer, -0.55, 0.55) + bike.slip * 0.9
	if not ridden:
		target_steer = 0.35 if bike.state == Moto.State.PARKED else steer_angle
	steer_angle = FeelMath.damp(steer_angle, target_steer, 14.0, dt)
	steer_yaw.rotation.y = steer_angle

	# --- lights & dust
	headlight.visible = ridden
	tail_mat.emission_energy_multiplier = 2.6 if bike.brake_in > 0.1 and ridden else (0.8 if ridden else 0.0)
	var dusty := bike.surface.dust_color.a > 0.0 and not airborne and (absf(s) > 4.0 or bike.slide_amount > 0.3 or (bike.throttle_in > 0.6 and absf(s) < 4.0 and ridden))
	dust.emitting = dusty
	if dusty:
		dust.color = Color(bike.surface.dust_color, 1.0)


func _ground_height(bike: Moto, z: float) -> float:
	var space := bike.get_world_3d().direct_space_state
	var from := bike.global_transform * Vector3(0, 0.8, z)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.4, 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return -0.3
	return (bike.global_transform.affine_inverse() * hit.position).y


func on_bump(strength: float, _normal: Vector3) -> void:
	heave_spring.impulse(-strength * 0.8)
	lean_spring.impulse((randf() - 0.5) * strength * 2.0)
	pitch_spring.impulse(-strength * 0.6)


func on_landing(strength: float) -> void:
	heave_spring.impulse(-strength * 1.6)
	pitch_spring.impulse(-strength * 0.4)


func on_crash() -> void:
	_crash_side = 1.0 if lean >= 0.0 else -1.0
	lean_spring.impulse(_crash_side * 4.0)


func on_recover() -> void:
	lean_spring.reset(KICKSTAND_LEAN)


func set_saddlebags(on: bool) -> void:
	saddlebags.visible = on


func set_silencer(on: bool) -> void:
	silencer.visible = on


func set_suspension(on: bool) -> void:
	springs.visible = on
	gaiters.visible = on
