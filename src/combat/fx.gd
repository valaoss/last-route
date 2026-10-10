class_name Fx
extends Node3D

## Pooled combat effects: muzzle flash, tracers, impact puffs, blood mist, decals.
## One instance per level; everything is preallocated so firing never allocates.

static var instance: Fx

const TRACERS := 24
const PUFFS := 16
const DECALS := 48

var _tracers: Array[MeshInstance3D] = []
var _tracer_life: Array[float] = []
var _puffs: Array[CPUParticles3D] = []
var _blood: Array[CPUParticles3D] = []
var _decals: Array[MeshInstance3D] = []
var _flash_light: OmniLight3D
var _flash_mesh: MeshInstance3D
var _flash_time := 0.0
var _ti := 0
var _pi := 0
var _bi := 0
var _di := 0


func _ready() -> void:
	instance = self
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.albedo_color = Color(1.0, 0.85, 0.55, 0.85)
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var tmesh := BoxMesh.new()
	tmesh.size = Vector3(0.012, 0.012, 1.0)
	for i in TRACERS:
		var t := MeshInstance3D.new()
		t.mesh = tmesh
		t.material_override = tm.duplicate()
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.visible = false
		t.top_level = true
		add_child(t)
		_tracers.append(t)
		_tracer_life.append(0.0)
	for i in PUFFS:
		_puffs.append(_make_particles(Color(0.55, 0.52, 0.47, 0.8), 10, 0.5, 2.5, 0.25))
		_blood.append(_make_particles(Color(0.22, 0.04, 0.03, 0.9), 12, 0.45, 3.0, 0.12))
	var dm := StandardMaterial3D.new()
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(0.05, 0.045, 0.04, 0.85)
	dm.albedo_texture = MotoVisual._soft_puff()
	dm.roughness = 1.0
	var dq := QuadMesh.new()
	dq.size = Vector2(0.09, 0.09)
	for i in DECALS:
		var d := MeshInstance3D.new()
		d.mesh = dq
		d.material_override = dm
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		d.visible = false
		d.top_level = true
		add_child(d)
		_decals.append(d)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.75, 0.45)
	_flash_light.omni_range = 6.0
	_flash_light.light_energy = 0.0
	_flash_light.top_level = true
	add_child(_flash_light)
	_flash_mesh = MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(0.32, 0.32)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.albedo_texture = _star_texture()
	fm.albedo_color = Color(1.0, 0.8, 0.5)
	fq.material = fm
	_flash_mesh.mesh = fq
	_flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash_mesh.visible = false
	_flash_mesh.top_level = true
	add_child(_flash_mesh)


func _make_particles(c: Color, amount: int, life: float, vel: float, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.95
	p.direction = Vector3(0, 0, 1)
	p.spread = 30.0
	p.initial_velocity_min = vel * 0.4
	p.initial_velocity_max = vel
	p.gravity = Vector3(0, -6.0, 0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var g := Gradient.new()
	g.set_color(0, c)
	g.set_color(1, Color(c, 0.0))
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = MotoVisual._soft_puff()
	q.material = m
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.top_level = true
	add_child(p)
	return p


static func _star_texture() -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5) / 32.0
			var r := d.length()
			var ang := absf(sin(atan2(d.y, d.x) * 3.0))
			var a := clampf(1.0 - r / (0.35 + 0.65 * pow(ang, 6.0)), 0.0, 1.0)
			a = pow(a, 1.6)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func muzzle_flash(at: Transform3D, strength := 1.0) -> void:
	_flash_mesh.global_position = at.origin
	_flash_mesh.scale = Vector3.ONE * (0.8 + 0.6 * strength) * randf_range(0.8, 1.2)
	_flash_mesh.rotation.z = randf() * TAU
	_flash_mesh.visible = true
	_flash_light.global_position = at.origin
	_flash_light.light_energy = 2.5 * strength
	_flash_time = 0.05


func tracer(from: Vector3, to: Vector3) -> void:
	var len := from.distance_to(to)
	if len < 1.5:
		return
	var t := _tracers[_ti]
	_tracer_life[_ti] = 0.07
	_ti = (_ti + 1) % TRACERS
	var start := from.lerp(to, 0.12)
	var mid := (start + to) * 0.5
	t.global_transform = Transform3D(Basis.looking_at(to - start, Vector3.UP), mid)
	t.scale = Vector3(1, 1, start.distance_to(to))
	t.visible = true


func impact(pos: Vector3, normal: Vector3, flesh: bool) -> void:
	var p: CPUParticles3D
	if flesh:
		p = _blood[_bi]
		_bi = (_bi + 1) % PUFFS
	else:
		p = _puffs[_pi]
		_pi = (_pi + 1) % PUFFS
		var d := _decals[_di]
		_di = (_di + 1) % DECALS
		var up := Vector3.UP if absf(normal.y) < 0.95 else Vector3.FORWARD
		d.global_transform = Transform3D(Basis.looking_at(-normal, up), pos + normal * 0.01)
		d.visible = true
	p.global_transform = Transform3D(Basis.looking_at(-normal if normal.length() > 0.1 else Vector3.FORWARD, Vector3.UP if absf(normal.y) < 0.95 else Vector3.FORWARD), pos)
	p.restart()


func _process(dt: float) -> void:
	if _flash_time > 0.0:
		_flash_time -= dt
		if _flash_time <= 0.0:
			_flash_mesh.visible = false
			_flash_light.light_energy = 0.0
	for i in TRACERS:
		if _tracer_life[i] > 0.0:
			_tracer_life[i] -= dt
			var t := _tracers[i]
			(t.material_override as StandardMaterial3D).albedo_color.a = clampf(_tracer_life[i] / 0.07, 0.0, 1.0) * 0.85
			if _tracer_life[i] <= 0.0:
				t.visible = false
