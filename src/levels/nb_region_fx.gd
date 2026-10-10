class_name NbRegionFx
extends RefCounted

## Town-scale signs of the region gauges, readable in daylight from the street:
## lit shop signs (infrastructure), a burn pile with a smoke column at the
## Çarşı (low threat), painted safe-route chevrons on the main road (route).

var root: Node3D
var built := {}


func _init(parent: Node3D) -> void:
	root = parent


func update(r: RegionState) -> Array[String]:
	var fresh: Array[String] = []
	var want := {
		"signs": r.get_value("infrastructure") >= 50.0,
		"pyre": r.get_value("threat") < 45.0,
		"route_paint": r.get_value("route") >= 40.0,
	}
	for k in want:
		if want[k] and not built.has(k):
			var n := Node3D.new()
			n.name = "RegionFx_" + k
			root.add_child(n)
			call("_" + k, n)
			MeshMerger.merge_rigid(n)
			built[k] = n
			fresh.append(k)
	return fresh


func _signs(n: Node3D) -> void:
	var green := StandardMaterial3D.new()
	green.albedo_color = Color("3a8a4a")
	green.emission_enabled = true
	green.emission = Color("4fe06a")
	green.emission_energy_multiplier = 2.6
	var c := Vector3(NbPlaces.PHARMACY.x + 5.5, 3.1, NbPlaces.PHARMACY.z + 6.2)
	MeshKit.box(n, Vector3(0.8, 0.26, 0.08), c, green, Vector3.ZERO, false)
	MeshKit.box(n, Vector3(0.26, 0.8, 0.08), c, green, Vector3.ZERO, false)
	var open := Label3D.new()
	open.text = "AÇIK"
	open.font_size = 96
	open.pixel_size = 0.008
	open.modulate = Color(2.4, 1.5, 0.6)
	open.shaded = false
	open.position = Vector3(NbPlaces.MARKET.x + 6.5, 3.3, NbPlaces.MARKET.z + 7.2)
	n.add_child(open)


func _pyre(n: Node3D) -> void:
	var c := Vector3(-62.0, 0.0, 53.0)
	for i in 7:
		var a := i * 0.9
		MeshKit.box(n, Vector3(1.6, 0.25, 0.3), c + Vector3(cos(a) * 0.4, 0.15 + (i % 3) * 0.18, sin(a) * 0.4), Palette.mat(&"bark"), Vector3(0, rad_to_deg(a), 8))
	MeshKit.sphere(n, 1.1, c + Vector3(0, 0.2, 0), Palette.mat(&"mud"), Vector3(1.0, 0.35, 0.9), 8)
	var smoke := CPUParticles3D.new()
	smoke.position = c + Vector3(0, 1.0, 0)
	smoke.amount = 26
	smoke.lifetime = 9.0
	smoke.preprocess = 9.0
	smoke.direction = Vector3(0.15, 1, 0)
	smoke.spread = 8.0
	smoke.gravity = Vector3(0.25, 0.6, 0)
	smoke.initial_velocity_min = 1.6
	smoke.initial_velocity_max = 2.4
	smoke.scale_amount_min = 2.0
	smoke.scale_amount_max = 3.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 2.6))
	smoke.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.32, 0.31, 0.3, 0.7))
	grad.set_color(1, Color(0.55, 0.56, 0.56, 0.0))
	smoke.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = MotoVisual._soft_puff()
	q.material = m
	smoke.mesh = q
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.visibility_aabb = AABB(Vector3(-12, -2, -12), Vector3(24, 60, 24))
	n.add_child(smoke)
	var fire := OmniLight3D.new()
	fire.light_color = Color("ff8a3a")
	fire.light_energy = 1.5
	fire.omni_range = 6.0
	fire.position = c + Vector3(0, 0.8, 0)
	n.add_child(fire)


func _route_paint(n: Node3D) -> void:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("6f9a52")
	paint.roughness = 0.8
	for z in [150.0, 120.0, 90.0, 30.0, 0.0, -45.0, -80.0]:
		for k in 2:
			var side := -1.0 if k == 0 else 1.0
			MeshKit.box(n, Vector3(0.18, 0.02, 1.6), Vector3(side * 0.55, 0.035, z), paint, Vector3(0, side * 35.0, 0), false)
