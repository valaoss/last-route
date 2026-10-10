class_name NbTown
extends RefCounted

## Street grid, closed city blocks, residential south, forest. The two central
## blocks are walled so the main road is the only short way north — which is
## what makes the raider checkpoint (and opening it in M04) matter.

const MAIN_W := 9.0
const CARSI_Z := 50.0
const KUZEY_Z := -110.0
const DERE_X := 95.0
const WEST := Rect2(-76, -102, 68, 144)     ## west block (x, z, w, d)
const EAST := Rect2(8, -102, 68, 144)

## Filler buildings: [side, centre along street, length, depth, height, mat, sign]
## side: "w_main" | "e_main" | "w_carsi" | "e_carsi" | "w_kuzey" | "e_kuzey" | "w_back" | "e_back"
const FILLERS := [
	["w_main", 19.0, 18.0, 12.0, 9.0, &"brick", "TERZİ"], ["w_main", 0.0, 17.0, 10.0, 6.0, &"plaster", ""],
	["w_main", -21.0, 18.0, 14.0, 7.0, &"plaster", ""], ["w_main", -40.0, 18.0, 12.0, 9.0, &"brick", ""],
	["w_main", -87.0, 28.0, 14.0, 9.5, &"plaster", "OTEL ÇAM"],
	["e_main", 18.0, 16.0, 12.0, 9.0, &"plaster", "BERBER"], ["e_main", 0.0, 17.0, 10.0, 6.0, &"brick", ""],
	["e_main", -21.0, 18.0, 14.0, 7.0, &"brick", ""], ["e_main", -40.0, 18.0, 12.0, 6.0, &"plaster", "KIRTASİYE"],
	["e_main", -61.0, 20.0, 12.0, 9.0, &"brick", ""], ["e_main", -87.0, 28.0, 14.0, 6.5, &"plaster", ""],
	["w_carsi", -38.0, 20.0, 12.0, 6.0, &"brick", "FIRIN"], ["w_carsi", -63.0, 24.0, 12.0, 9.0, &"plaster", ""],
	["e_carsi", 47.0, 22.0, 12.0, 9.0, &"brick", ""], ["e_carsi", 68.0, 14.0, 12.0, 6.0, &"plaster", "ÇAY OCAĞI"],
	["w_kuzey", -38.0, 22.0, 12.0, 6.0, &"brick", ""], ["w_kuzey", -64.0, 20.0, 10.0, 3.6, &"plaster", "LASTİKÇİ"],
	["e_kuzey", 63.0, 22.0, 10.0, 5.0, &"brick", ""],
	["w_back", 0.0, 30.0, 10.0, 6.0, &"plaster", ""], ["e_back", -30.0, 30.0, 10.0, 6.0, &"brick", ""],
]

## Wall-line gaps where walk-in buildings straddle the block perimeter: [edge, from, to].
const WALL_GAPS := [
	["w_s", -26.0, -9.0], ["w_e", 29.0, 42.0], ["w_e", -73.0, -49.0],
	["e_s", 11.0, 35.0], ["e_n", 29.0, 51.0],
]

var kit: WorldKit
var rng: RandomNumberGenerator
var avoid: Array[Rect2] = []     ## no trees here (x, z)


func _init(k: WorldKit) -> void:
	kit = k
	rng = k.rng


func build() -> void:
	kit.ground(1400.0)
	_roads()
	for b in [WEST, EAST]:
		avoid.append(b.grow(2.0))
	_block_walls()
	for f in FILLERS:
		_filler(f)
	_residential()
	_street_dressing()


func _roads() -> void:
	kit.road(Vector2(0, 162), Vector2(0, -205), MAIN_W, &"asphalt_worn")
	kit.dashed_line(Vector2(0, 155), Vector2(0, -200))
	kit.road(Vector2(-120, CARSI_Z), Vector2(120, CARSI_Z), 8.0)
	kit.dashed_line(Vector2(-115, CARSI_Z), Vector2(115, CARSI_Z))
	kit.road(Vector2(-135, KUZEY_Z), Vector2(140, KUZEY_Z), 8.0, &"asphalt_worn")
	kit.dashed_line(Vector2(-130, KUZEY_Z), Vector2(135, KUZEY_Z))
	kit.road(Vector2(DERE_X, CARSI_Z), Vector2(DERE_X, KUZEY_Z), 7.0, &"asphalt_worn")
	kit.road(Vector2(130, KUZEY_Z), Vector2(130, -142), 7.0, &"asphalt_worn")
	kit.road(Vector2(-128, KUZEY_Z), Vector2(-128, -141), 7.0, &"dirt", &"dirt", 0.03)
	for s in [-1.0, 1.0]:
		kit.sidewalk(Vector2(s * 6.0, 46), Vector2(s * 6.0, -106), 3.0)
		kit.sidewalk(Vector2(s * 9.0, 44.5), Vector2(s * 75.0, 44.5), 3.0)
		kit.sidewalk(Vector2(s * 9.0, -104.5), Vector2(s * 75.0, -104.5), 3.0)
	for r in [Rect2(-6, -205, 12, 367), Rect2(-120, 44, 240, 12), Rect2(-135, -116, 275, 12), Rect2(90, -114, 10, 168), Rect2(124, -145, 12, 35), Rect2(-133, -145, 10, 35)]:
		avoid.append(r.grow(4.0))


## Concrete walls just inside each block's facade line, gaps where walk-in buildings sit.
func _block_walls() -> void:
	var edges := {
		"w_s": [Vector2(-75, 41), Vector2(-9, 41)], "w_n": [Vector2(-75, -101), Vector2(-9, -101)],
		"w_e": [Vector2(-9, 41), Vector2(-9, -101)], "w_w": [Vector2(-75, 41), Vector2(-75, -101)],
		"e_s": [Vector2(9, 41), Vector2(75, 41)], "e_n": [Vector2(9, -101), Vector2(75, -101)],
		"e_e": [Vector2(75, 41), Vector2(75, -101)], "e_w": [Vector2(9, 41), Vector2(9, -101)],
	}
	for key in edges:
		var a: Vector2 = edges[key][0]
		var b: Vector2 = edges[key][1]
		var along_x := absf(a.y - b.y) < 0.1
		var lo := minf(a.x, b.x) if along_x else minf(a.y, b.y)
		var hi := maxf(a.x, b.x) if along_x else maxf(a.y, b.y)
		var cuts := []
		for g in WALL_GAPS:
			if g[0] == key:
				cuts.append([g[1], g[2]])
		cuts.sort_custom(func(x, y): return x[0] < y[0])
		var t := lo
		for c in cuts:
			_wall_run(along_x, a, t, c[0])
			t = c[1]
		_wall_run(along_x, a, t, hi)


func _wall_run(along_x: bool, a: Vector2, t0: float, t1: float) -> void:
	if t1 - t0 < 0.2:
		return
	var mid := (t0 + t1) * 0.5
	var p := Vector3(mid, 1.6, a.y) if along_x else Vector3(a.x, 1.6, mid)
	var s := Vector3(t1 - t0, 3.2, 0.4) if along_x else Vector3(0.4, 3.2, t1 - t0)
	var w := MeshKit.static_box(kit.root, s, p, Palette.mat(&"concrete"), &"concrete")
	MeshKit.box(w, s + Vector3(0.1, -3.05, 0.1), Vector3(0, 1.6, 0), Palette.mat(&"concrete_dark"))


func _filler(f: Array) -> void:
	var side: String = f[0]
	var c: float = f[1]
	var len: float = f[2]
	var depth: float = f[3]
	var size := Vector3(len, f[4], depth)
	var pos: Vector3
	var yaw: float
	match side:
		"w_main": pos = Vector3(-8.0 - depth * 0.5, 0, c); yaw = -90.0
		"e_main": pos = Vector3(8.0 + depth * 0.5, 0, c); yaw = 90.0
		"w_carsi", "e_carsi": pos = Vector3(c, 0, 42.0 - depth * 0.5); yaw = 180.0
		"w_kuzey", "e_kuzey": pos = Vector3(c, 0, -102.0 + depth * 0.5); yaw = 0.0
		"w_back": pos = Vector3(-76.0 + depth * 0.5, 0, c); yaw = 90.0
		_: pos = Vector3(76.0 - depth * 0.5, 0, c); yaw = -90.0
	kit.building(pos, size, yaw, f[5], f[6], rng.randf_range(0.2, 0.6))


func _residential() -> void:
	var houses := [Vector3(-20, 0, 78), Vector3(21, 0, 84), Vector3(-22, 0, 108), Vector3(20, 0, 116),
			Vector3(-21, 0, 140), Vector3(-48, 0, 70), Vector3(52, 0, 72), Vector3(-74, 0, 66), Vector3(76, 0, 68)]
	for i in houses.size():
		var p: Vector3 = houses[i]
		var yaw := (-90.0 if p.x < 0 else 90.0) if absf(p.x) < 30 else 180.0
		var s := Vector3(rng.randf_range(8, 11), rng.randf_range(5.5, 6.5), rng.randf_range(7, 9))
		kit.building(p, s, yaw, [&"plaster", &"brick"][i % 2], "", 0.6)
		avoid.append(Rect2(p.x - 9, p.z - 9, 18, 18))
		# garden fence toward the street
		var fx := p.x + (s.z * 0.5 + 3.0) * (1.0 if p.x < 0 else -1.0) if absf(p.x) < 30 else p.x
		if absf(p.x) < 30:
			for k in 6:
				if rng.randf() < 0.2:
					continue
				MeshKit.static_box(kit.root, Vector3(0.08, 1.0, 1.9), Vector3(fx, 0.5, p.z - 5 + k * 2.0), Palette.mat(&"wood"), &"concrete", Vector3(0, 0, rng.randf_range(-6, 6)))


func _street_dressing() -> void:
	for z in range(140, -200, -36):
		kit.lamp_post(Vector3(-5.2 if z % 72 == 0 else 5.2, 0, z), 90.0 if z % 72 == 0 else -90.0)
	for x in range(-100, 110, 40):
		kit.lamp_post(Vector3(x, 0, CARSI_Z + 4.8), 180.0)
	# abandoned traffic: Çarşı jam, dere yolu, south main road
	for i in 6:
		kit.car_wreck(Vector3(-90 + i * 26 + rng.randf_range(-3, 3), 0, CARSI_Z + rng.randf_range(-2.0, 2.0)), 90.0 + rng.randf_range(-25, 25))
	for z in [20.0, -35.0, -78.0]:
		kit.car_wreck(Vector3(DERE_X + rng.randf_range(-2.0, 2.0), 0, z), rng.randf_range(-20, 20))
	kit.car_wreck(Vector3(-2.5, 0, 98), 8.0, &"car_paint_a")
	kit.car_wreck(Vector3(2.8, 0, 62), -170.0, &"rust_metal", 2.0)
	kit.car_wreck(Vector3(-3, 0, -150), 30.0)
	kit.car_wreck(Vector3(40, 0, KUZEY_Z + 2), 75.0)
	kit.car_wreck(Vector3(-60, 0, KUZEY_Z - 1.5), -100.0, &"car_paint_b")
	kit.graffiti(Vector3(-8.0, 2.4, 6.0), -90.0, "KESTİRME YOK", Color("9a2f22"), 90)
	kit.graffiti(Vector3(DERE_X - 4.2, 1.8, 40), 90.0, "KUZEY →", Color("c9a646"), 80)
	for p in [Vector3(30, 0.02, 60), Vector3(-30, 0.02, 58), Vector3(5, 0.02, -60), Vector3(-5, 0.02, -95)]:
		kit.crate(p, rng.randf_range(0.7, 1.0), rng.randf() * 90.0)
	for p in [Vector3(-7, 0.02, 30), Vector3(7, 0.02, -8), Vector3(97, 0.02, -100)]:
		kit.barrel(p, rng.randf() < 0.4)


## Conifer forest around the town, denser toward the edges; grass along roads.
func nature(extra_avoid: Array[Rect2]) -> void:
	avoid.append_array(extra_avoid)
	var placed := 0
	var tries := 0
	while placed < 540 and tries < 6000:
		tries += 1
		var p := Vector3(rng.randf_range(-190, 200), 0, rng.randf_range(-230, 205))
		var core := absf(p.x) < 80 and p.z > -110 and p.z < 160
		if core and rng.randf() < 0.85:
			continue
		if _avoided(Vector2(p.x, p.z)):
			continue
		kit.tree(p, -1.0, true)
		placed += 1
	for n in 2800:
		var p := Vector3(rng.randf_range(-150, 160), 0, rng.randf_range(-200, 170))
		if _avoided(Vector2(p.x, p.z)):
			continue
		kit.grass_tuft(p)


func _avoided(p: Vector2) -> bool:
	for r in avoid:
		if r.has_point(p):
			return true
	return false
