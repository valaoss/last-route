class_name TreeImpostor
extends RefCounted

## Far-forest cards: a procedurally painted two-cell atlas (fir | broadleaf) and
## a Y-locked billboard quad. Trees switch to one card each beyond NEAR metres.

const NEAR := 80.0
const W := 128
const H := 256
## Card size relative to tree height (width, height).
const FIR_SIZE := Vector2(0.46, 1.0)
const LEAF_SIZE := Vector2(0.8, 1.05)

static var _mat: ShaderMaterial
static var _quad: QuadMesh


static func mesh() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(1, 1)
		_quad.center_offset = Vector3(0, 0.5, 0)
	return _quad


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = preload("res://src/art/tree_impostor.gdshader")
		_mat.set_shader_parameter(&"atlas", ImageTexture.create_from_image(_paint()))
		_mat.set_shader_parameter(&"near_dist", NEAR)
	return _mat


## Instance transform + colour for a tree of height `h` at `pos`.
static func xform(pos: Vector3, h: float, broadleaf: bool) -> Transform3D:
	var s := (LEAF_SIZE if broadleaf else FIR_SIZE) * h
	return Transform3D(Basis.IDENTITY.scaled(Vector3(s.x, s.y, 1.0)), pos)


static func _paint() -> Image:
	var img := Image.create(W * 2, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.25, 0.17, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	_paint_fir(img, rng)
	_paint_leaf(img, rng)
	img.generate_mipmaps()
	return img


static func _paint_fir(img: Image, rng: RandomNumberGenerator) -> void:
	var base := Color("34402c")
	var jag := PackedFloat32Array()
	for i in H:
		jag.append(rng.randf_range(0.8, 1.0))
	for y in H:
		var v := 1.0 - float(y) / (H - 1)
		for x in W:
			var u := (float(x) / (W - 1)) * 2.0 - 1.0
			var c := Color(0, 0, 0, 0)
			if absf(u) < 0.05 and v < 0.3:
				c = Color("4a3a2c")
			for i in 6:
				var t := i / 5.0
				var y0 := lerpf(0.22, 0.82, t)
				var th := lerpf(0.3, 0.24, t)
				if v < y0 or v > y0 + th:
					continue
				var k := (v - y0) / th
				var half := lerpf(0.95, 0.3, t) * (1.0 - k) * jag[y]
				if absf(u) <= half:
					var shade := lerpf(0.7, 1.15, k) * lerpf(1.08, 0.9, (u / maxf(half, 0.01)) * 0.5 + 0.5)
					c = base * lerpf(0.85, 1.1, t) * shade
					c.a = 1.0
			img.set_pixel(x, y, c)


static func _paint_leaf(img: Image, rng: RandomNumberGenerator) -> void:
	var base := Color("53613a")
	var clumps := []
	for i in 12:
		var t := float(i) / 12.0
		var a := rng.randf() * TAU
		var r := lerpf(0.33, 0.2, t) * rng.randf_range(0.85, 1.15)
		var cu := cos(a) * lerpf(0.55, 0.25, t) * rng.randf_range(0.2, 1.0)
		clumps.append(Vector3(cu, lerpf(0.42, 0.88, t), r))
	for y in H:
		var v := 1.0 - float(y) / (H - 1)
		for x in W:
			var u := (float(x) / (W - 1)) * 2.0 - 1.0
			var c := Color(0, 0, 0, 0)
			if absf(u) < 0.07 and v < 0.5:
				c = Color("4a3a2c")
			for cl in clumps:
				var d := Vector2((u - cl.x) * 0.4, (v - cl.y) * 1.05)
				var rr: float = cl.z * 0.4 * 0.86
				if d.length() < rr * (0.9 + 0.1 * sin(u * 37.0 + v * 53.0)):
					var shade := lerpf(0.72, 1.15, clampf(d.y / rr * 0.5 + 0.5, 0.0, 1.0))
					c = base * shade * lerpf(0.9, 1.1, cl.y)
					c.a = 1.0
			img.set_pixel(W + x, y, c)
