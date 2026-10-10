class_name WorldKit
extends RefCounted

## Level-building kit. Repeated small props (windows, trees, grass, debris) are
## collected and flushed as MultiMeshes so dense scenes stay cheap on mobile.

var root: Node3D
var rng := RandomNumberGenerator.new()
var _batches: Dictionary = {}     # key -> {mesh, mat, xforms: Array, colors: Array, shadows}


func _init(parent: Node3D, seed_value := 1) -> void:
	root = parent
	rng.seed = seed_value


# ------------------------------------------------------------------ batching

## Instances are split into CHUNK-sized cells so off-screen parts get culled.
const CHUNK := 128.0
## Draw distance per batch family (0 = unlimited; fog hides the far forest).
const RANGES := {&"grass": 70.0, &"litter": 45.0, &"boards": 220.0, &"win_frame": 260.0, &"win_glass": 260.0,
	&"iwin_frame": 200.0, &"iwin_glass": 200.0, &"lane_paint": 160.0}
## 3D tree parts sit on a finer grid and stay drawn while their chunk centre is
## within NEAR + half a chunk diagonal, so every tree closer than NEAR is still
## 3D; the far cards hide themselves per tree (in the shader) inside NEAR and
## can use a coarse grid (few draws).
const TREE_CHUNK := 48.0
const TREE_NEAR_END := TreeImpostor.NEAR + TREE_CHUNK * 0.71
const FAR_CHUNK := 256.0
const TREE_FAMILIES := [&"needles", &"crowns", &"trunks"]

func batch(family: StringName, mesh: Mesh, mat: Material, xf: Transform3D, color := Color.WHITE, shadows := true) -> void:
	var size := TREE_CHUNK if family in TREE_FAMILIES else (FAR_CHUNK if family == &"tree_far" else CHUNK)
	var key := StringName("%s@%d_%d" % [family, floori(xf.origin.x / size), floori(xf.origin.z / size)])
	if not _batches.has(key):
		_batches[key] = {"mesh": mesh, "mat": mat, "xforms": [], "colors": [], "shadows": shadows}
	_batches[key].xforms.append(xf)
	_batches[key].colors.append(color)


func flush() -> void:
	for key in _batches:
		var b: Dictionary = _batches[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = b.mesh
		mm.instance_count = b.xforms.size()
		for i in b.xforms.size():
			mm.set_instance_transform(i, b.xforms[i])
			mm.set_instance_color(i, b.colors[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "MM_" + String(key)
		var family := StringName(String(key).get_slice("@", 0))
		if family in TREE_FAMILIES:
			mmi.visibility_range_end = TREE_NEAR_END
		elif family == &"tree_far":
			mmi.custom_aabb = mm.get_aabb().grow(8.0)   # cards turn toward the camera in the shader
		elif RANGES.has(family):
			mmi.visibility_range_end = RANGES[family]
			mmi.visibility_range_end_margin = 10.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mmi.multimesh = mm
		mmi.material_override = b.mat
		if not b.shadows:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
	_batches.clear()


# ------------------------------------------------------------------ ground & roads

func ground(size: float, mat := &"grass", surface := &"grass") -> void:
	MeshKit.static_box(root, Vector3(size, 1.0, size), Vector3(0, -0.5, 0), Palette.mat(mat), surface)


## Straight road slab between two XZ points (top surface at y = h).
func road(a: Vector2, b: Vector2, width: float, mat := &"asphalt", surface := &"asphalt", h := 0.02, thick := 0.3) -> StaticBody3D:
	var mid := (a + b) * 0.5
	var d := b - a
	var len := d.length()
	var yaw := atan2(-d.x, -d.y)
	return MeshKit.static_box(root, Vector3(width, thick, len + 0.4), Vector3(mid.x, h - thick * 0.5, mid.y), Palette.mat(mat), surface, Vector3(0, rad_to_deg(yaw), 0))


## Arc road made of short chords. Angles in degrees, measured from +X toward +Z.
func road_arc(center: Vector2, radius: float, from_deg: float, to_deg: float, width: float, mat := &"asphalt", surface := &"asphalt", steps := 16) -> void:
	for i in steps:
		var a0 := deg_to_rad(lerpf(from_deg, to_deg, float(i) / steps))
		var a1 := deg_to_rad(lerpf(from_deg, to_deg, float(i + 1) / steps))
		var p0 := center + Vector2(cos(a0), sin(a0)) * radius
		var p1 := center + Vector2(cos(a1), sin(a1)) * radius
		road(p0, p1, width, mat, surface)


## Ramp slab rising from a (height h0) to b (height h1).
func ramp(a: Vector2, b: Vector2, h0: float, h1: float, width: float, mat := &"asphalt", surface := &"asphalt") -> void:
	var d := b - a
	var len := d.length()
	var pitch := atan2(h1 - h0, len)
	var slope_len := sqrt(len * len + (h1 - h0) * (h1 - h0))
	var mid := (a + b) * 0.5
	var yaw := atan2(-d.x, -d.y)
	var thick := 0.6
	var body := StaticBody3D.new()
	body.set_meta(&"surface", surface)
	root.add_child(body)
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var center := Vector3(mid.x, (h0 + h1) * 0.5, mid.y) - basis.y * thick * 0.5
	body.global_transform = Transform3D(basis, center)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(width, thick, slope_len + 0.3)
	cs.shape = sh
	body.add_child(cs)
	MeshKit.box(body, sh.size, Vector3.ZERO, Palette.mat(mat))


func dashed_line(a: Vector2, b: Vector2, dash := 3.0, gap := 6.0, w := 0.14, color := Color("b8b09a"), h := 0.025) -> void:
	var d := b - a
	var len := d.length()
	var dir := d / len
	var yaw := atan2(-dir.x, -dir.y)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(w, 0.01, dash)
	var t := 0.0
	while t + dash < len:
		var p := a + dir * (t + dash * 0.5)
		if rng.randf() > 0.12:   # some dashes worn away completely
			var c := color * rng.randf_range(0.7, 1.0)
			batch(&"lane_paint", mesh, _paint_mat(), Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, h, p.y)), c, false)
		t += dash + gap


func _paint_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	return m


func curb(a: Vector2, b: Vector2, height := 0.15, width := 0.3) -> void:
	road(a, b, width, &"curb", &"concrete", height, height + 0.1)


func sidewalk(a: Vector2, b: Vector2, width := 2.5) -> void:
	road(a, b, width, &"concrete", &"concrete", 0.15, 0.25)


# ------------------------------------------------------------------ buildings

func building(pos: Vector3, size: Vector3, yaw_deg: float, mat_key: StringName, sign_text := "", boarded := 0.3) -> Node3D:
	var b := MeshKit.static_box(root, size, pos + Vector3(0, size.y * 0.5, 0), Palette.mat(mat_key), &"concrete", Vector3(0, yaw_deg, 0))
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var origin := pos
	# parapet / cornice band
	MeshKit.box(b, Vector3(size.x + 0.3, 0.35, size.z + 0.3), Vector3(0, size.y * 0.5 - 0.1, 0), Palette.mat(&"concrete_dark"))
	MeshKit.box(b, Vector3(size.x + 0.12, 0.18, size.z + 0.12), Vector3(0, -size.y * 0.5 + 3.1, 0), Palette.mat(&"concrete_dark"))
	# windows on all four faces
	var floors := int(size.y / 3.0)
	var glass := BoxMesh.new()
	glass.size = Vector3(1.1, 1.45, 0.08)
	var frame := BoxMesh.new()
	frame.size = Vector3(1.3, 1.65, 0.05)
	var board := BoxMesh.new()
	board.size = Vector3(1.2, 0.22, 0.05)
	for face in 4:
		var along := size.x if face % 2 == 0 else size.z
		var depth := size.z if face % 2 == 0 else size.x
		var face_yaw := face * PI * 0.5
		var fb := basis * Basis(Vector3.UP, face_yaw)
		var cols := int((along - 1.5) / 2.6)
		if cols < 1:
			continue
		var start := -(cols - 1) * 1.3
		for f in range(1, floors):
			for c in cols:
				if rng.randf() < 0.07:
					continue
				var local := Vector3(start + c * 2.6, f * 3.0 + 1.5, -depth * 0.5)
				var wp := origin + fb * local
				var xf := Transform3D(fb, wp + fb * Vector3(0, 0, 0.01))
				batch(&"win_frame", frame, Palette.mat(&"concrete_dark"), Transform3D(fb, wp + fb * Vector3(0, 0, -0.02)))
				var broken := rng.randf() < 0.25
				var g_col := Color(0.6, 0.65, 0.7) if not broken else Color(0.15, 0.15, 0.15)
				batch(&"win_glass", glass, _glass_mat(), xf, g_col * rng.randf_range(0.6, 1.0))
				if rng.randf() < boarded:
					for k in 4:
						var bx := Transform3D(fb * Basis(Vector3.BACK, rng.randf_range(-0.15, 0.15)), wp + fb * Vector3(0, -0.5 + k * 0.33, -0.06))
						batch(&"boards", board, Palette.mat(&"wood"), bx, Color.WHITE * rng.randf_range(0.75, 1.05))
	# ground floor door on face 0
	var door_p := origin + basis * Vector3(rng.randf_range(-size.x * 0.3, size.x * 0.3), 1.15, -size.z * 0.5 - 0.02)
	MeshKit.box(root, Vector3(1.3, 2.3, 0.1), door_p, Palette.mat(&"rust_metal"), Vector3(0, yaw_deg, 0))
	if sign_text != "":
		var sp := origin + basis * Vector3(0, 3.6, -size.z * 0.5 - 0.15)
		MeshKit.box(root, Vector3(minf(size.x * 0.7, 7.0), 0.9, 0.12), sp, Palette.mat(&"painted_metal"), Vector3(0, yaw_deg, 0))
		var l := Label3D.new()
		l.text = sign_text
		l.font_size = 72
		l.pixel_size = 0.006
		l.modulate = Color("d9cfb4")
		l.outline_size = 0
		l.position = sp + basis * Vector3(0, 0, -0.07)
		l.rotation = Vector3(0, deg_to_rad(yaw_deg) + PI, 0)
		l.shaded = true
		root.add_child(l)
	return b


var _glass: StandardMaterial3D
func _glass_mat() -> StandardMaterial3D:
	if _glass:
		return _glass
	var m := StandardMaterial3D.new()
	_glass = m
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color("2a3036")
	m.roughness = 0.12
	m.metallic = 0.4
	return m


func graffiti(pos: Vector3, yaw_deg: float, text: String, color := Color("8c2a1f"), size := 96) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.008
	l.modulate = color
	l.outline_size = 0
	l.shaded = true
	l.position = pos
	l.rotation = Vector3(0, deg_to_rad(yaw_deg), rng.randf_range(-0.06, 0.06))
	root.add_child(l)


# ------------------------------------------------------------------ props

func car_wreck(pos: Vector3, yaw_deg: float, paint := &"", tilt := 0.0) -> StaticBody3D:
	if paint == &"":
		paint = [&"car_paint_a", &"car_paint_b", &"car_paint_c", &"rust_metal"][rng.randi() % 4]
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation = Vector3(0, deg_to_rad(yaw_deg), deg_to_rad(tilt))
	body.set_meta(&"surface", &"concrete")
	root.add_child(body)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.8, 1.35, 4.4)
	cs.shape = sh
	cs.position.y = 0.72
	body.add_child(cs)
	var p := Palette.mat(paint)
	MeshKit.box(body, Vector3(1.8, 0.62, 4.4), Vector3(0, 0.62, 0), p)
	MeshKit.box(body, Vector3(1.62, 0.55, 2.2), Vector3(0, 1.2, 0.25), p)
	MeshKit.box(body, Vector3(1.64, 0.4, 2.0), Vector3(0, 1.22, 0.25), _glass_mat())
	MeshKit.box(body, Vector3(1.82, 0.2, 0.25), Vector3(0, 0.45, -2.2), Palette.mat(&"bike_frame"))
	MeshKit.box(body, Vector3(1.82, 0.2, 0.25), Vector3(0, 0.45, 2.2), Palette.mat(&"bike_frame"))
	for wx in [-0.82, 0.82]:
		for wz in [-1.35, 1.35]:
			if rng.randf() < 0.15:
				continue
			var flat := 0.06 if rng.randf() < 0.5 else 0.0
			MeshKit.cyl(body, 0.33, 0.24, Vector3(wx, 0.33 - flat, wz), Palette.mat(&"rubber"), Vector3(0, 0, 90), 14)
	return body


func barrier(pos: Vector3, yaw_deg: float) -> void:
	var b := MeshKit.static_box(root, Vector3(2.0, 0.85, 0.6), pos + Vector3(0, 0.425, 0), Palette.mat(&"barrier"), &"concrete", Vector3(0, yaw_deg, 0))
	MeshKit.box(b, Vector3(2.0, 0.08, 0.62), Vector3(0, 0.1, 0), Palette.mat(&"hazard"))


func barrel(pos: Vector3, tipped := false) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	if tipped:
		body.rotation = Vector3(deg_to_rad(90), rng.randf() * TAU, 0)
		body.position.y += 0.3
	else:
		body.position.y += 0.45
	root.add_child(body)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.3
	sh.height = 0.9
	cs.shape = sh
	body.add_child(cs)
	var m := Palette.mat([&"rust_metal", &"painted_metal", &"hazard"][rng.randi() % 3])
	MeshKit.cyl(body, 0.3, 0.9, Vector3.ZERO, m, Vector3.ZERO, 14)
	MeshKit.cyl(body, 0.31, 0.04, Vector3(0, 0.2, 0), Palette.mat(&"rust_metal"), Vector3.ZERO, 14)
	MeshKit.cyl(body, 0.31, 0.04, Vector3(0, -0.2, 0), Palette.mat(&"rust_metal"), Vector3.ZERO, 14)


func crate(pos: Vector3, s := 1.0, yaw_deg := 0.0) -> void:
	var b := MeshKit.static_box(root, Vector3.ONE * s, pos + Vector3(0, s * 0.5, 0), Palette.mat(&"wood"), &"concrete", Vector3(0, yaw_deg, 0))
	MeshKit.box(b, Vector3(s + 0.02, 0.08, s + 0.02), Vector3(0, s * 0.3, 0), Palette.mat(&"rust_metal"))


func container(pos: Vector3, yaw_deg: float, mat := &"rust_metal") -> void:
	var b := MeshKit.static_box(root, Vector3(2.45, 2.6, 6.1), pos + Vector3(0, 1.3, 0), Palette.mat(mat), &"concrete", Vector3(0, yaw_deg, 0))
	for i in 9:
		MeshKit.box(b, Vector3(2.5, 2.4, 0.08), Vector3(0, 0, -2.8 + i * 0.7), Palette.mat(mat))


func lamp_post(pos: Vector3, yaw_deg: float) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees.y = yaw_deg
	root.add_child(body)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.12
	sh.height = 6.0
	cs.shape = sh
	cs.position.y = 3.0
	body.add_child(cs)
	MeshKit.cyl(body, 0.09, 6.0, Vector3(0, 3.0, 0), Palette.mat(&"painted_metal"), Vector3.ZERO, 8)
	MeshKit.strut(body, Vector3(0, 5.8, 0), Vector3(0, 6.1, -1.4), 0.05, Palette.mat(&"painted_metal"))
	MeshKit.box(body, Vector3(0.3, 0.12, 0.6), Vector3(0, 6.05, -1.6), Palette.mat(&"painted_metal"))


var _cone: CylinderMesh
var _needle_mat: StandardMaterial3D
## Pacific-northwest style fir: stacked, slightly drooping tiers, dark and matte.
func conifer(pos: Vector3, h := -1.0, collide := true) -> void:
	if h < 0.0:
		h = rng.randf_range(8.0, 16.0)
	if _cone == null:
		_cone = CylinderMesh.new()
		_cone.top_radius = 0.0
		_cone.bottom_radius = 1.0
		_cone.height = 1.0
		_cone.radial_segments = 7
		_cone.rings = 1
		_needle_mat = StandardMaterial3D.new()
		_needle_mat.albedo_color = Color("34402c")
		_needle_mat.vertex_color_use_as_albedo = true
		_needle_mat.roughness = 1.0
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.06
	trunk.bottom_radius = 0.2
	trunk.height = 1.0
	trunk.radial_segments = 6
	batch(&"trunks", trunk, Palette.mat(&"bark"), Transform3D(Basis.IDENTITY.scaled(Vector3(1, h * 0.9, 1)), pos + Vector3(0, h * 0.45, 0)), Color.WHITE, false)
	var tiers := rng.randi_range(5, 7)
	var tint := Color(1, 1, 1) * rng.randf_range(0.8, 1.1)
	tint = tint.lerp(Color(0.9, 1.05, 0.95), rng.randf() * 0.5)
	var w := h * rng.randf_range(0.17, 0.23)
	for i in tiers:
		var t := float(i) / (tiers - 1)
		var y := lerpf(h * 0.22, h * 0.82, t)
		var r := w * lerpf(1.0, 0.32, t) * rng.randf_range(0.9, 1.1)
		var th := h * lerpf(0.3, 0.24, t)
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.05, 0.05))
		batch(&"needles", _cone, _needle_mat, Transform3D(b.scaled(Vector3(r, th, r)), pos + Vector3(0, y + th * 0.5, 0)), tint * lerpf(0.85, 1.1, t))
	var far_tint := tint
	far_tint.a = 0.0
	batch(&"tree_far", TreeImpostor.mesh(), TreeImpostor.material(), TreeImpostor.xform(pos, h, false), far_tint, false)
	if collide:
		var body := StaticBody3D.new()
		body.position = pos + Vector3(0, 1.5, 0)
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 0.25
		sh.height = 3.0
		cs.shape = sh
		body.add_child(cs)
		root.add_child(body)


func tree(pos: Vector3, h := -1.0, collide := true) -> void:
	if rng.randf() < 0.72:
		conifer(pos, -1.0, collide)
		return
	if h < 0.0:
		h = rng.randf_range(6.0, 11.0)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.12
	trunk.bottom_radius = 0.22
	trunk.height = 1.0
	trunk.radial_segments = 7
	batch(&"trunks", trunk, Palette.mat(&"bark"), Transform3D(Basis.IDENTITY.scaled(Vector3(1, h * 0.65, 1)), pos + Vector3(0, h * 0.325, 0)), Color.WHITE, false)
	var crown := SphereMesh.new()
	crown.radius = 1.0
	crown.height = 2.0
	crown.radial_segments = 8
	crown.rings = 4
	# irregular crown: many small flattened clumps around a lopsided volume
	var base_tint := Color(1, 1, 1) * rng.randf_range(0.8, 1.1)
	base_tint = base_tint.lerp(Color(1.15, 1.05, 0.8), rng.randf() * 0.4)
	var spread := h * 0.24
	var clumps := rng.randi_range(7, 11)
	for i in clumps:
		var t := float(i) / clumps
		var y := h * lerpf(0.42, 0.95, t) + rng.randf_range(-0.4, 0.4)
		var rad := spread * (1.0 - t * 0.55)
		var a := rng.randf() * TAU
		var off := Vector3(cos(a), 0, sin(a)) * rad * rng.randf_range(0.2, 1.0)
		var r := h / 9.0 * rng.randf_range(0.7, 1.25) * lerpf(1.1, 0.6, t)
		var c := base_tint * rng.randf_range(0.82, 1.08) * lerpf(0.85, 1.12, t)
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3))
		batch(&"crowns", crown, _foliage_mat(), Transform3D(b.scaled(Vector3(r * 1.05, r * 0.86, r)), pos + off + Vector3(0, y, 0)), c)
	var far_tint := base_tint
	far_tint.a = 1.0
	batch(&"tree_far", TreeImpostor.mesh(), TreeImpostor.material(), TreeImpostor.xform(pos, h, true), far_tint, false)
	if collide:
		var body := StaticBody3D.new()
		body.position = pos + Vector3(0, 1.5, 0)
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 0.25
		sh.height = 3.0
		cs.shape = sh
		body.add_child(cs)
		root.add_child(body)


var _fol_mat: StandardMaterial3D
func _foliage_mat() -> StandardMaterial3D:
	if _fol_mat == null:
		_fol_mat = StandardMaterial3D.new()
		_fol_mat.albedo_color = Color("53613a")
		_fol_mat.vertex_color_use_as_albedo = true
		_fol_mat.roughness = 1.0
	return _fol_mat


var _grass_mat: ShaderMaterial
var _grass_mesh: QuadMesh
func grass_tuft(pos: Vector3, s := 1.0) -> void:
	if _grass_mesh == null:
		_grass_mesh = QuadMesh.new()
		_grass_mesh.size = Vector2(0.9, 0.55)
		_grass_mesh.center_offset = Vector3(0, 0.27, 0)
		_grass_mat = ShaderMaterial.new()
		_grass_mat.shader = preload("res://src/art/grass.gdshader")
		_grass_mat.set_shader_parameter(&"blades", _grass_texture())
	var yaw := rng.randf() * TAU
	var c := Color(1, 1, 1) * rng.randf_range(0.7, 1.15)
	c = c.lerp(Color(1.1, 1.0, 0.7), rng.randf() * 0.3)
	for k in 2:
		var b := Basis(Vector3.UP, yaw + k * PI * 0.5).scaled(Vector3.ONE * s * rng.randf_range(0.7, 1.2))
		batch(&"grass", _grass_mesh, _grass_mat, Transform3D(b, pos), c, false)


static func _grass_texture() -> Texture2D:
	var w := 64
	var h := 48
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := RandomNumberGenerator.new()
	r.seed = 42
	for blade in 26:
		var x0 := r.randf_range(4, w - 4)
		var lean := r.randf_range(-12, 12)
		var height := r.randf_range(h * 0.45, h - 1)
		var width := r.randf_range(1.2, 2.6)
		var shade := r.randf_range(0.65, 1.0)
		for y in int(height):
			var t := float(y) / height
			var cx := x0 + lean * t * t
			var half := width * (1.0 - t)
			for x in range(int(cx - half - 1), int(cx + half + 2)):
				if x < 0 or x >= w:
					continue
				var a := clampf(half + 0.5 - absf(x - cx), 0.0, 1.0)
				if a <= 0.0:
					continue
				var col := Color(0.55, 0.62, 0.38) * shade * lerpf(0.6, 1.1, t)
				img.set_pixel(x, h - 1 - y, Color(col.r, col.g, col.b, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
