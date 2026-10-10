class_name InteriorKit
extends RefCounted

## Walk-in buildings: wall shells with door openings, optional upper floor with
## a stair ramp, roof, window panels and furniture. Everything is placed in the
## building's local space (the returned anchor) so layouts read like floor plans.
## Face ids: 0 = front (-Z), 1 = right (+X), 2 = back (+Z), 3 = left (-X).

const WALL := 0.25
const STOREY := 3.2

var kit: WorldKit
var rng: RandomNumberGenerator
var _box := BoxMesh.new()


func _init(k: WorldKit) -> void:
	kit = k
	rng = k.rng


## openings: [[face, offset, width, height]] on the ground floor.
func shell(pos: Vector3, size: Vector3, yaw_deg: float, mat: StringName, openings: Array, sign_text := "", storeys := 1) -> Node3D:
	var a := Node3D.new()
	a.position = pos
	a.rotation.y = deg_to_rad(yaw_deg)
	kit.root.add_child(a)
	MeshKit.static_box(a, Vector3(size.x, 0.1, size.z), Vector3.ZERO, Palette.mat(&"concrete_dark"), &"concrete")
	for f in 4:
		var along := size.x if f % 2 == 0 else size.z - WALL * 2.0
		var ops := openings.filter(func(o): return int(o[0]) == f)
		ops.sort_custom(func(x, y): return x[1] < y[1])
		var t := -along * 0.5
		for o in ops:
			var o0: float = o[1] - o[2] * 0.5
			_wall(a, f, size, t, o0, 0.0, size.y, mat)
			_wall(a, f, size, o0, o0 + o[2], o[3], size.y, mat)
			t = o[1] + o[2] * 0.5
		_wall(a, f, size, t, along * 0.5, 0.0, size.y, mat)
		_windows(a, f, size, along, ops, storeys)
	MeshKit.static_box(a, Vector3(size.x + 0.4, 0.3, size.z + 0.4), Vector3(0, size.y + 0.15, 0), Palette.mat(&"concrete_dark"), &"concrete")
	MeshKit.box(a, Vector3(size.x + 0.5, 0.22, size.z + 0.5), Vector3(0, size.y - 0.1, 0), Palette.mat(&"concrete_dark"))
	if sign_text != "":
		var door: Array = openings.filter(func(o): return int(o[0]) == 0)
		var sx: float = door[0][1] if not door.is_empty() else 0.0
		var sp := Vector3(sx, minf(size.y - 0.7, 3.6), -size.z * 0.5 - 0.15)
		MeshKit.box(a, Vector3(minf(size.x * 0.6, 6.5), 0.85, 0.12), sp, Palette.mat(&"painted_metal"))
		var l := Label3D.new()
		l.text = sign_text
		l.font_size = 72
		l.pixel_size = 0.006
		l.modulate = Color("d9cfb4")
		l.outline_size = 0
		l.shaded = true
		l.position = sp + Vector3(0, 0, -0.07)
		l.rotation.y = PI
		a.add_child(l)
	return a


func _wall(a: Node3D, f: int, size: Vector3, t0: float, t1: float, y0: float, y1: float, mat: StringName) -> void:
	var len := t1 - t0
	if len < 0.05 or y1 - y0 < 0.05:
		return
	var t := (t0 + t1) * 0.5
	var y := (y0 + y1) * 0.5
	var p: Vector3
	var s: Vector3
	match f:
		0: p = Vector3(t, y, -size.z * 0.5 + WALL * 0.5); s = Vector3(len, y1 - y0, WALL)
		2: p = Vector3(t, y, size.z * 0.5 - WALL * 0.5); s = Vector3(len, y1 - y0, WALL)
		1: p = Vector3(size.x * 0.5 - WALL * 0.5, y, t); s = Vector3(WALL, y1 - y0, len)
		_: p = Vector3(-size.x * 0.5 + WALL * 0.5, y, t); s = Vector3(WALL, y1 - y0, len)
	MeshKit.static_box(a, s, p, Palette.mat(mat), &"concrete")


## Glazed (often boarded) window panels through the wall, skipping openings.
func _windows(a: Node3D, f: int, size: Vector3, along: float, ops: Array, storeys: int) -> void:
	var n := int((along - 1.5) / 3.0)
	if n < 1:
		return
	var face_basis := Basis(Vector3.UP, -f * PI * 0.5)
	var glass := BoxMesh.new()
	glass.size = Vector3(1.15, 1.3, WALL + 0.04)
	var frame := BoxMesh.new()
	frame.size = Vector3(1.35, 1.5, WALL + 0.02)
	var board := BoxMesh.new()
	board.size = Vector3(1.25, 0.2, 0.04)
	for s in storeys:
		for i in n:
			var t := -(n - 1) * 1.5 + i * 3.0
			if s == 0 and ops.any(func(o): return absf(t - o[1]) < o[2] * 0.5 + 0.9):
				continue
			if rng.randf() < 0.12:
				continue
			var y := s * STOREY + 1.75
			var local: Vector3
			match f:
				0: local = Vector3(t, y, -size.z * 0.5 + WALL * 0.5)
				2: local = Vector3(t, y, size.z * 0.5 - WALL * 0.5)
				1: local = Vector3(size.x * 0.5 - WALL * 0.5, y, t)
				_: local = Vector3(-size.x * 0.5 + WALL * 0.5, y, t)
			var b := a.basis * face_basis
			var wp := a.transform * local
			kit.batch(&"iwin_frame", frame, Palette.mat(&"concrete_dark"), Transform3D(b, wp))
			var broken := rng.randf() < 0.3
			kit.batch(&"iwin_glass", glass, kit._glass_mat(), Transform3D(b, wp), (Color(0.15, 0.15, 0.15) if broken else Color(0.6, 0.65, 0.7)) * rng.randf_range(0.6, 1.0))
			if rng.randf() < 0.35:
				var out := b * Vector3(0, 0, -(WALL * 0.5 + 0.04))
				for k in 4:
					var bx := Transform3D(b * Basis(Vector3.BACK, rng.randf_range(-0.15, 0.15)), wp + out + b * Vector3(0, -0.5 + k * 0.33, 0))
					kit.batch(&"boards", board, Palette.mat(&"wood"), bx, Color.WHITE * rng.randf_range(0.75, 1.05))


## Upper floor slab at height y with a rectangular stair gap (local XZ rect).
func upper_floor(a: Node3D, size: Vector3, y: float, gap: Rect2) -> void:
	var x0 := -size.x * 0.5 + WALL
	var x1 := size.x * 0.5 - WALL
	var z0 := -size.z * 0.5 + WALL
	var z1 := size.z * 0.5 - WALL
	var g0 := gap.position
	var g1 := gap.end
	var mat := Palette.mat(&"concrete_dark")
	for r in [Rect2(x0, z0, x1 - x0, g0.y - z0), Rect2(x0, g1.y, x1 - x0, z1 - g1.y),
			Rect2(x0, g0.y, g0.x - x0, g1.y - g0.y), Rect2(g1.x, g0.y, x1 - g1.x, g1.y - g0.y)]:
		if r.size.x > 0.05 and r.size.y > 0.05:
			MeshKit.static_box(a, Vector3(r.size.x, 0.25, r.size.y), Vector3(r.get_center().x, y - 0.125, r.get_center().y), mat, &"concrete")


## Straight ramp-stair between two local points (walkable, navmesh friendly).
func stairs(a: Node3D, from: Vector3, to: Vector3, width: float) -> void:
	var d := Vector2(to.x - from.x, to.z - from.z)
	var len := d.length()
	var rise := to.y - from.y
	var pitch := atan2(rise, len)
	var slope := sqrt(len * len + rise * rise)
	var thick := 0.3
	var b := Basis(Vector3.UP, atan2(-d.x, -d.y)) * Basis(Vector3.RIGHT, pitch)
	var body := MeshKit.static_box(a, Vector3(width, thick, slope + 0.2), Vector3.ZERO, Palette.mat(&"concrete"), &"concrete")
	body.transform = Transform3D(b, (from + to) * 0.5 - b.y * thick * 0.5)
	var steps := int(rise / 0.18)
	for i in steps:
		var t := (i + 0.5) / steps
		MeshKit.box(body, Vector3(width, 0.03, 0.06), Vector3(0, thick * 0.5 + 0.01, slope * 0.5 - t * slope), Palette.mat(&"concrete_dark"), Vector3.ZERO, false)


func lamp(a: Node3D, p: Vector3, color := Color("ffd59a"), energy := 1.0, range_m := 8.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.position = p
	a.add_child(l)
	MeshKit.box(a, Vector3(0.25, 0.12, 0.25), p + Vector3(0, 0.12, 0), Palette.mat(&"painted_metal"), Vector3.ZERO, false)
	return l


# ------------------------------------------------------------------ furniture (local space)

func shelf(a: Node3D, p: Vector3, yaw_deg: float, length := 2.4, stocked := 0.5) -> void:
	var b := MeshKit.static_box(a, Vector3(length, 2.0, 0.5), p + Vector3(0, 1.0, 0), Palette.mat(&"painted_metal"), &"concrete", Vector3(0, yaw_deg, 0))
	for k in 4:
		MeshKit.box(b, Vector3(length + 0.04, 0.04, 0.54), Vector3(0, -0.85 + k * 0.55, 0), Palette.mat(&"rust_metal"), Vector3.ZERO, false)
		var x := -length * 0.5 + 0.2
		while x < length * 0.5 - 0.2:
			if rng.randf() < stocked:
				var s := Vector3(rng.randf_range(0.15, 0.35), rng.randf_range(0.12, 0.35), 0.3)
				MeshKit.box(b, s, Vector3(x, -0.83 + k * 0.55 + s.y * 0.5, 0.0), Palette.mat([&"canvas", &"wood", &"car_paint_c", &"hazard"][rng.randi() % 4]), Vector3(0, rng.randf_range(-15, 15), 0), false)
			x += rng.randf_range(0.3, 0.5)


func counter(a: Node3D, p: Vector3, yaw_deg: float, length := 3.0) -> void:
	var b := MeshKit.static_box(a, Vector3(length, 1.0, 0.7), p + Vector3(0, 0.5, 0), Palette.mat(&"wood"), &"concrete", Vector3(0, yaw_deg, 0))
	MeshKit.box(b, Vector3(length + 0.1, 0.06, 0.8), Vector3(0, 0.52, 0), Palette.mat(&"concrete"), Vector3.ZERO, false)


func table(a: Node3D, p: Vector3, yaw_deg := 0.0, size := Vector2(1.6, 0.9)) -> void:
	var b := MeshKit.static_box(a, Vector3(size.x, 0.06, size.y), p + Vector3(0, 0.78, 0), Palette.mat(&"wood"), &"concrete", Vector3(0, yaw_deg, 0))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			MeshKit.box(b, Vector3(0.06, 0.75, 0.06), Vector3(sx * (size.x * 0.5 - 0.08), -0.4, sz * (size.y * 0.5 - 0.08)), Palette.mat(&"wood"), Vector3.ZERO, false)


func bed(a: Node3D, p: Vector3, yaw_deg := 0.0) -> void:
	var b := MeshKit.static_box(a, Vector3(1.0, 0.45, 2.0), p + Vector3(0, 0.22, 0), Palette.mat(&"wood"), &"concrete", Vector3(0, yaw_deg, 0))
	MeshKit.box(b, Vector3(0.95, 0.16, 1.9), Vector3(0, 0.3, 0), Palette.mat(&"canvas"), Vector3.ZERO, false)
	MeshKit.box(b, Vector3(0.6, 0.1, 0.35), Vector3(0, 0.42, -0.75), Palette.mat(&"barrier"), Vector3.ZERO, false)


func cabinet(a: Node3D, p: Vector3, yaw_deg := 0.0, size := Vector3(1.0, 1.9, 0.5)) -> void:
	var b := MeshKit.static_box(a, size, p + Vector3(0, size.y * 0.5, 0), Palette.mat(&"painted_metal"), &"concrete", Vector3(0, yaw_deg, 0))
	MeshKit.box(b, Vector3(0.02, size.y * 0.9, 0.02), Vector3(0, 0, -size.z * 0.5 - 0.01), Palette.mat(&"concrete_dark"), Vector3.ZERO, false)


## Flat litter (papers, cardboard, rags) — batched, no collision.
func litter(a: Node3D, center: Vector3, radius: float, count := 12) -> void:
	_box.size = Vector3(1, 1, 1)
	for i in count:
		var p := center + Vector3(rng.randf_range(-radius, radius), 0.07, rng.randf_range(-radius, radius))
		var s := Vector3(rng.randf_range(0.15, 0.5), 0.015, rng.randf_range(0.12, 0.4))
		var xf := a.transform * Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(s), p)
		kit.batch(&"litter", _box, Palette.mat(&"canvas"), xf, Color.WHITE * rng.randf_range(0.6, 1.3), false)
