class_name NbPlaces
extends RefCounted

## Landmarks of the first neighbourhood: garage safehouse, pharmacy, market,
## 2-storey apartment, workshop, gas station, radio hill and the raider
## checkpoint. Each builder records loot points, mission targets, lights and
## spawn spots in `refs`; the level turns those into live nodes.

const GARAGE := Vector3(0, 0, 172)
const PHARMACY := Vector3(-17.5, 0, 36)
const MARKET := Vector3(23, 0, 35)
const APARTMENT := Vector3(-16, 0, -61)
const WORKSHOP := Vector3(40, 0, -95)
const STATION := Vector3(130, 0, -160)
const HILL := Vector3(-128, 5, -188)
const TOWER := Vector3(-120, 5, -194)
const CHECKPOINT := Vector3(0, 0, -20)

var kit: WorldKit
var ik: InteriorKit
var rng: RandomNumberGenerator
var refs := {"loot": [], "targets": [], "lights": {}, "cover": [], "avoid": [] as Array[Rect2]}


func _init(k: WorldKit) -> void:
	kit = k
	ik = InteriorKit.new(k)
	rng = k.rng


func build() -> void:
	_garage()
	_pharmacy()
	_market()
	_apartment()
	_workshop()
	_station()
	_hill()
	_checkpoint()


func _loot(id: String, kind: StringName, pos: Vector3, table := &"", label := "", item := &"") -> void:
	refs.loot.append({"id": id, "kind": kind, "pos": pos, "table": table, "label": label, "item": item})


func _target(id: String, pos: Vector3, prompt: String, requires := {}, noise := 0.0) -> void:
	refs.targets.append({"id": id, "pos": pos, "prompt": prompt, "requires": requires, "noise": noise})


# ------------------------------------------------------------------ garage (safehouse)

func _garage() -> void:
	var size := Vector3(12, 4.6, 16)
	var a := ik.shell(GARAGE, size, 0.0, &"brick", [[0, 0.0, 5.2, 3.8]], "GARAJ")
	MeshKit.static_box(kit.root, Vector3(16, 0.3, 10), GARAGE + Vector3(0, -0.13, -13), Palette.mat(&"concrete"), &"concrete")
	refs.avoid.append(Rect2(GARAGE.x - 14, GARAGE.z - 22, 28, 34))
	refs.bike_spawn = Transform3D(Basis.IDENTITY, a.to_global(Vector3(0.6, 0.2, -1.5)))
	refs.player_spawn = Transform3D(Basis.IDENTITY, a.to_global(Vector3(-1.4, 0.2, 0.5)))
	# generator (back-left) — dead until M01
	var gen := MeshKit.static_box(a, Vector3(1.4, 0.9, 0.8), Vector3(-4.2, 0.5, 6.4), Palette.mat(&"car_paint_b"), &"concrete")
	MeshKit.cyl(gen, 0.28, 0.9, Vector3(0, 0.6, 0), Palette.mat(&"rust_metal"), Vector3(0, 0, 90), 12)
	MeshKit.box(gen, Vector3(0.3, 0.3, 0.05), Vector3(0.4, 0.1, -0.42), Palette.mat(&"hazard"))
	_target("generator", a.to_global(Vector3(-4.2, 0.05, 5.2)), "Karbüratörü tak", {&"carb_part": 1})
	refs.lights["gen"] = _light(a, Vector3(-4.2, 1.4, 6.0), Color("ffb060"), 0.0, 3.0)
	# workbench (back-right) — becomes the upgrade station in M05
	ik.table(a, Vector3(3.8, 0, 6.9), 0.0, Vector2(2.6, 0.9))
	MeshKit.box(a, Vector3(2.6, 1.2, 0.05), Vector3(3.8, 1.9, 7.7), Palette.mat(&"wood"))
	refs.tools_spot = a.to_global(Vector3(3.8, 0.84, 6.9))
	refs.tools_parent = a
	_target("workbench", a.to_global(Vector3(3.8, 0.05, 5.6)), "Tezgâhı kur", {&"toolbox": 1})
	_target("bench", a.to_global(Vector3(2.6, 0.05, 5.6)), "Tezgâh · motor ve üretim")
	# radio desk (right wall)
	ik.table(a, Vector3(5.1, 0, 0.5), 90.0, Vector2(1.4, 0.8))
	MeshKit.box(a, Vector3(0.45, 0.25, 0.3), Vector3(5.2, 0.95, 0.3), Palette.mat(&"bike_frame"))
	MeshKit.cyl(a, 0.01, 0.8, Vector3(5.3, 1.45, 0.45), Palette.mat(&"bike_chrome"), Vector3.ZERO, 4)
	_target("radio", a.to_global(Vector3(4.2, 0.05, 0.5)), "Telsizi dene")
	refs.lights["radio"] = _light(a, Vector3(5.0, 1.2, 0.3), Color("9fe08a"), 0.0, 1.6)
	# fuel drum (left wall) — free refuel once the power is on
	kit.barrel(a.to_global(Vector3(-5.1, 0.05, -3.2)))
	kit.barrel(a.to_global(Vector3(-5.2, 0.05, -2.4)))
	_target("refuel", a.to_global(Vector3(-4.2, 0.05, -2.8)), "Motorun deposunu doldur")
	# living corner: the bed ends the day
	ik.bed(a, Vector3(-0.6, 0, 6.6), 90.0)
	_target("rest", a.to_global(Vector3(-1.0, 0.05, 5.2)), "Dinlen · sabaha kadar")
	# region board (right wall)
	MeshKit.box(a, Vector3(0.05, 1.1, 1.6), Vector3(5.83, 1.75, -2.5), Palette.mat(&"wood"))
	MeshKit.box(a, Vector3(0.02, 0.9, 1.4), Vector3(5.8, 1.75, -2.5), Palette.mat(&"barrier"))
	for i in 4:
		MeshKit.box(a, Vector3(0.015, 0.02, 0.5 + i * 0.15), Vector3(5.785, 1.45 + i * 0.18, -2.6 + i * 0.05), Palette.mat(&"concrete_dark"), Vector3(i * 12 - 18, 0, 0))
	_target("board", a.to_global(Vector3(4.6, 0.05, -2.5)), "Bölge panosu")
	ik.shelf(a, Vector3(-5.5, 0, 2.4), 90.0, 3.0, 0.6)
	ik.cabinet(a, Vector3(5.5, 0, 4.0), -90.0)
	ik.litter(a, Vector3(0, 0, 2), 4.0, 10)
	kit.crate(a.to_global(Vector3(-4.6, 0.05, -6.6)), 0.9, 12.0)
	kit.graffiti(a.to_global(Vector3(3.6, 2.0, -8.2)), 180.0, "GÜVENLİ", Color("4f6b3a"), 110)
	refs.lights["garage"] = _light(a, Vector3(0, 4.1, 1.0), Color("ffd59a"), 0.35, 10.0)
	refs.lights["garage2"] = _light(a, Vector3(3.5, 3.6, 5.5), Color("ffcf8a"), 0.0, 6.0)
	refs.nilay_spot = a.to_global(Vector3(-2.2, 0.05, 3.6))
	refs.places_garage = a.to_global(Vector3(0, 0, 0))
	refs.garage = a
	refs.rest_spot = a.to_global(Vector3(-1.0, 0.2, 5.0))


# ------------------------------------------------------------------ çarşı: pharmacy + market

func _pharmacy() -> void:
	var size := Vector3(17, 4.2, 12)
	var a := ik.shell(PHARMACY, size, 180.0, &"plaster", [[0, 3.0, 1.8, 2.5]], "ECZANE")
	# back-room partition with a doorway
	MeshKit.static_box(a, Vector3(10.0, 4.0, 0.2), Vector3(-3.0, 2.0, 2.0), Palette.mat(&"plaster"), &"concrete")
	MeshKit.static_box(a, Vector3(4.6, 4.0, 0.2), Vector3(6.0, 2.0, 2.0), Palette.mat(&"plaster"), &"concrete")
	ik.counter(a, Vector3(-2.0, 0, -1.5), 0.0, 5.0)
	ik.shelf(a, Vector3(-3.0, 0, 1.6), 0.0, 6.0, 0.3)
	ik.shelf(a, Vector3(-7.9, 0, -2.0), 90.0, 3.0, 0.2)
	ik.shelf(a, Vector3(-4.0, 0, 5.6), 0.0, 6.0, 0.5)
	ik.table(a, Vector3(3.0, 0, 4.4), 0.0, Vector2(1.6, 0.8))
	ik.cabinet(a, Vector3(7.8, 0, 4.0), -90.0)
	ik.litter(a, Vector3(0, 0, -2.5), 5.0, 16)
	_loot("ph_meds", &"quest", a.to_global(Vector3(3.0, 0.84, 4.4)), &"pharmacy", "Arka oda dolabı", &"antibiotics")
	_loot("ph_front", &"med", a.to_global(Vector3(-3.0, 1.05, -1.5)))
	refs.lights["pharmacy"] = _light(a, Vector3(3.0, 3.6, 4.4), Color("cfe6ff"), 0.5, 6.0)


func _market() -> void:
	var size := Vector3(22, 4.6, 14)
	var a := ik.shell(MARKET, size, 180.0, &"brick", [[0, 0.0, 3.2, 2.6], [2, -7.0, 2.4, 3.0]], "MARKET")
	for row in 3:
		var z := -1.5 + row * 3.0
		ik.shelf(a, Vector3(-4.5, 0, z), 0.0, 6.0, 0.35)
		ik.shelf(a, Vector3(4.5, 0, z), 0.0, 6.0, 0.35)
	ik.counter(a, Vector3(-7.0, 0, -4.8), 90.0, 2.5)
	ik.shelf(a, Vector3(10.5, 0, 0.0), 90.0, 8.0, 0.25)
	ik.litter(a, Vector3(0, 0, 0), 8.0, 24)
	kit.crate(a.to_global(Vector3(8.0, 0.05, 5.6)), 0.9, 10.0)
	kit.crate(a.to_global(Vector3(7.0, 0.05, 6.0)), 0.7, 40.0)
	_loot("mk_1", &"cache", a.to_global(Vector3(-7.0, 1.05, -4.0)), &"market", "Kasa")
	_loot("mk_2", &"cache", a.to_global(Vector3(7.6, 0.05, 4.6)), &"market", "Depo kolileri")
	refs.lights["market"] = _light(a, Vector3(0, 4.0, 0), Color("dfe8ff"), 0.4, 9.0)


# ------------------------------------------------------------------ apartment (2 storeys)

func _apartment() -> void:
	var size := Vector3(22, 6.6, 16)
	var a := ik.shell(APARTMENT, size, -90.0, &"plaster", [[0, 0.0, 1.6, 2.4]], "", 2)
	ik.upper_floor(a, size, InteriorKit.STOREY, Rect2(-1.4, 4.6, 7.8, 2.0))
	ik.stairs(a, Vector3(6.2, 0.05, 5.6), Vector3(-1.2, InteriorKit.STOREY, 5.6), 1.6)
	# ground floor: mailboxes, rubble
	MeshKit.static_box(a, Vector3(2.4, 1.2, 0.3), Vector3(-4.0, 1.2, -7.6), Palette.mat(&"painted_metal"), &"concrete")
	ik.litter(a, Vector3(0, 0, -2), 6.0, 18)
	ik.table(a, Vector3(-7.5, 0, 2.0))
	ik.shelf(a, Vector3(-10.4, 0, -2.0), 90.0, 3.0, 0.3)
	_loot("ap_1", &"cache", a.to_global(Vector3(-7.5, 0.84, 2.0)), &"home", "Kapıcı dairesi")
	# upper floor: Nilay's flat behind a partition with a barricaded door
	var y := InteriorKit.STOREY
	MeshKit.static_box(a, Vector3(0.2, 3.2, 6.6), Vector3(-5.0, y + 1.6, -4.45), Palette.mat(&"plaster"), &"concrete")
	MeshKit.static_box(a, Vector3(0.2, 3.2, 8.0), Vector3(-5.0, y + 1.6, 3.75), Palette.mat(&"plaster"), &"concrete")
	MeshKit.static_box(a, Vector3(0.12, 2.2, 1.2), Vector3(-5.0, y + 1.1, -0.55), Palette.mat(&"wood"), &"concrete")
	MeshKit.box(a, Vector3(0.1, 0.2, 1.4), Vector3(-4.88, y + 1.2, -0.55), Palette.mat(&"wood"), Vector3(30, 0, 0))
	kit.graffiti(a.to_global(Vector3(-4.85, y + 2.4, -0.55)), -90.0, "3B", Color("2b2b2b"), 70)
	_target("apt_door", a.to_global(Vector3(-4.0, y + 0.05, -0.55)), "İlacı kapıya bırak", {&"antibiotics": 1})
	ik.bed(a, Vector3(-8.5, y, 4.0))
	ik.table(a, Vector3(-8.5, y, -4.0))
	ik.cabinet(a, Vector3(8.0, y, -6.8))
	ik.litter(a, Vector3(3, y, -3), 4.0, 10)
	_loot("ap_2", &"cache", a.to_global(Vector3(8.0, y + 0.05, -5.8)), &"home", "Dolap")
	refs.lights["apt"] = _light(a, Vector3(2.0, 2.9, -2.0), Color("b8c6d6"), 0.25, 9.0)
	refs.lights["apt_up"] = _light(a, Vector3(3.0, y + 2.8, -2.0), Color("b8c6d6"), 0.2, 8.0)
	refs.lights["nilay"] = _light(a, Vector3(-8.0, y + 2.6, 0.0), Color("ffc27a"), 0.0, 7.0)


# ------------------------------------------------------------------ workshop

func _workshop() -> void:
	var size := Vector3(20, 5.2, 14)
	var a := ik.shell(WORKSHOP, size, 0.0, &"plaster", [[0, -2.0, 5.0, 4.2]], "TAMİRHANE")
	MeshKit.static_box(kit.root, Vector3(20, 0.3, 4), WORKSHOP + Vector3(-2, -0.13, -9), Palette.mat(&"concrete"), &"concrete")
	# lift with a car on it
	for x in [-4.6, -0.6]:
		MeshKit.static_box(a, Vector3(0.3, 2.0, 0.3), Vector3(x, 1.0, 2.2), Palette.mat(&"hazard"), &"concrete")
	var car := kit.car_wreck(a.to_global(Vector3(-2.6, 1.3, 2.2)), 90.0, &"car_paint_c")
	car.rotation.y = a.rotation.y + PI * 0.5
	ik.table(a, Vector3(6.0, 0, 5.8), 0.0, Vector2(3.0, 1.0))
	MeshKit.box(a, Vector3(3.0, 1.4, 0.05), Vector3(6.0, 1.9, 6.7), Palette.mat(&"wood"))
	ik.cabinet(a, Vector3(9.4, 0, 2.0), -90.0, Vector3(1.2, 1.6, 0.6))
	ik.cabinet(a, Vector3(9.4, 0, -1.0), -90.0, Vector3(1.2, 1.6, 0.6))
	ik.shelf(a, Vector3(-9.4, 0, 1.0), 90.0, 5.0, 0.6)
	for i in 4:
		MeshKit.cyl(a, 0.36, 0.25, Vector3(7.6, 0.13 + i * 0.26, -4.6), Palette.mat(&"rubber"), Vector3.ZERO, 14)
	ik.litter(a, Vector3(2, 0, -2), 6.0, 14)
	_loot("ws_tools", &"quest", a.to_global(Vector3(6.0, 0.84, 5.8)), &"workshop", "Alet tezgâhı", &"toolbox")
	_loot("ws_cache", &"cache", a.to_global(Vector3(8.6, 0.05, -1.0)), &"workshop", "Dolap")
	refs.lights["workshop"] = _light(a, Vector3(4.0, 4.6, 3.0), Color("cfe6ff"), 0.35, 9.0)


# ------------------------------------------------------------------ gas station

func _station() -> void:
	var c := STATION
	MeshKit.static_box(kit.root, Vector3(34, 0.3, 28), c + Vector3(0, -0.13, 0), Palette.mat(&"asphalt"), &"asphalt")
	refs.avoid.append(Rect2(c.x - 20, c.z - 18, 46, 36))
	var cc := c + Vector3(-4, 0, 0)
	for x in [-6.0, 6.0]:
		for z in [-5.0, 5.0]:
			MeshKit.static_box(kit.root, Vector3(0.4, 5.0, 0.4), cc + Vector3(x, 2.5, z), Palette.mat(&"painted_metal"), &"concrete")
	# half-collapsed canopy: one side sags to the ground
	MeshKit.box(kit.root, Vector3(16, 0.7, 14), cc + Vector3(0, 5.2, 0), Palette.mat(&"painted_metal"), Vector3(0, 0, 4))
	MeshKit.box(kit.root, Vector3(16.1, 0.35, 14.1), cc + Vector3(0, 4.9, 0), Palette.mat(&"hazard"), Vector3(0, 0, 4))
	for z in [-3.0, 3.0]:
		MeshKit.static_box(kit.root, Vector3(6.0, 0.18, 1.4), cc + Vector3(0, 0.09, z), Palette.mat(&"curb"), &"concrete")
	MeshKit.static_box(kit.root, Vector3(0.9, 1.7, 0.6), cc + Vector3(-2, 1.0, -3), Palette.mat(&"car_paint_b"), &"concrete")
	MeshKit.static_box(kit.root, Vector3(0.9, 0.6, 1.7), cc + Vector3(2.6, 0.32, 1.8), Palette.mat(&"car_paint_b"), &"concrete", Vector3(0, 30, 0))
	var a := ik.shell(c + Vector3(17, 0, 0), Vector3(10, 4.0, 8), 90.0, &"plaster", [[0, 1.5, 1.6, 2.4]], "KOVAC YAKIT")
	ik.counter(a, Vector3(-1.5, 0, 0.0), 0.0, 3.5)
	ik.shelf(a, Vector3(2.5, 0, 2.6), 0.0, 4.0, 0.3)
	ik.litter(a, Vector3(0, 0, 0), 3.5, 10)
	_loot("st_part", &"part", a.to_global(Vector3(-1.5, 1.05, 0.0)))
	_loot("st_cache", &"cache", a.to_global(Vector3(2.5, 0.05, 1.8)), &"gas_station", "Raflar")
	_loot("st_fuel", &"fuel", cc + Vector3(-1.0, 0.2, 3.0))
	_loot("st_car", &"cache", c + Vector3(-12, 0.02, 10.5), &"car", "Araç bagajı")
	kit.car_wreck(c + Vector3(-12, 0, 8), 20.0, &"car_paint_c")
	kit.car_wreck(c + Vector3(-10, 0, -11), -60.0, &"rust_metal", 4.0)
	kit.container(c + Vector3(6, 0, -12), 90.0)
	kit.barrel(c + Vector3(10, 0.02, 9))
	kit.barrel(c + Vector3(10.7, 0.02, 9.6), true)
	kit.graffiti(c + Vector3(11.9, 2.2, 3.5), -90.0, "SESSİZ OL", Color("2b2b2b"), 80)
	refs.lights["station"] = _light(a, Vector3(0, 3.4, 0), Color("ffe0b0"), 0.3, 6.0)


# ------------------------------------------------------------------ radio hill

func _hill() -> void:
	MeshKit.static_box(kit.root, Vector3(36, 6, 30), Vector3(HILL.x, 2.0, HILL.z), Palette.mat(&"gravel"), &"gravel")
	kit.ramp(Vector2(HILL.x, -141), Vector2(HILL.x, -173.4), 0.02, 5.0, 7.0, &"dirt", &"dirt")
	refs.avoid.append(Rect2(HILL.x - 20, HILL.z - 17, 40, 70))
	# lattice tower
	var top := 26.0
	var steel := Palette.mat(&"painted_metal")
	var legs: Array[Vector3] = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var b := TOWER + Vector3(sx * 2.2, 0, sz * 2.2)
			var t := TOWER + Vector3(sx * 0.45, top, sz * 0.45)
			MeshKit.strut(kit.root, b, t, 0.09, steel)
			legs.append(b)
	for i in 6:
		var y0 := i * 4.2
		var y1 := y0 + 4.2
		var w0 := lerpf(2.2, 0.45, y0 / top)
		var w1 := lerpf(2.2, 0.45, y1 / top)
		for k in 4:
			var d0 := Vector3([1, 1, -1, -1][k], 0, [1, -1, -1, 1][k])
			var d1 := Vector3([1, -1, -1, 1][k], 0, [-1, -1, 1, 1][k])
			MeshKit.strut(kit.root, TOWER + d0 * w0 + Vector3(0, y0, 0), TOWER + d1 * w1 + Vector3(0, y1, 0), 0.04, steel)
			MeshKit.strut(kit.root, TOWER + d1 * w1 + Vector3(0, y1, 0), TOWER + d0 * w1 + Vector3(0, y1, 0), 0.04, steel)
	var col := StaticBody3D.new()
	col.position = TOWER + Vector3(0, 3, 0)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(4.2, 6, 4.2)
	cs.shape = sh
	col.add_child(cs)
	kit.root.add_child(col)
	MeshKit.box(kit.root, Vector3(0.6, 1.4, 0.3), TOWER + Vector3(0, top + 0.7, 0), steel)
	refs.beacon = MeshKit.sphere(kit.root, 0.22, TOWER + Vector3(0, top + 1.6, 0), Palette.mat(&"taillight"))
	refs.beacon.visible = false
	var bl := OmniLight3D.new()
	bl.light_color = Color("ff3a20")
	bl.light_energy = 0.0
	bl.omni_range = 14.0
	bl.position = TOWER + Vector3(0, top + 1.6, 0)
	kit.root.add_child(bl)
	refs.lights["beacon"] = bl
	MeshKit.static_box(kit.root, Vector3(0.9, 1.4, 0.4), TOWER + Vector3(3.0, 0.7, 0), Palette.mat(&"painted_metal"), &"concrete")
	_target("tower_panel", TOWER + Vector3(3.0, 0.05, -0.9), "Anteni tak", {&"antenna_part": 1}, 70.0)
	# shack
	var a := ik.shell(HILL + Vector3(-10, 0, -2), Vector3(6, 3.0, 5), -90.0, &"plaster", [[0, 0.0, 1.2, 2.2]])
	ik.table(a, Vector3(0, 0, 1.4), 0.0, Vector2(1.6, 0.8))
	ik.shelf(a, Vector3(2.6, 0, 0.0), 90.0, 3.0, 0.4)
	_loot("tw_part", &"quest", a.to_global(Vector3(0, 0.84, 1.4)), &"", "Yedek parça kutusu", &"antenna_part")
	_loot("tw_ammo", &"ammo", a.to_global(Vector3(-2.2, 0.05, 1.8)))
	kit.barrel(HILL + Vector3(6, 0.02, 8))
	kit.crate(HILL + Vector3(-4, 0.02, 9), 1.0, 20.0)


# ------------------------------------------------------------------ raider checkpoint

func _checkpoint() -> void:
	var z := CHECKPOINT.z
	for x in [-6.8, 3.8, 5.8, 7.6]:
		kit.barrier(Vector3(x, 0.02, z), 0.0)
	kit.car_wreck(Vector3(-3.8, 0, z), 90.0, &"rust_metal")
	# the gate car gets pushed aside in M04 (kept out of mesh merging; its nav tile is re-baked)
	refs.gate = kit.car_wreck(Vector3(0.6, 0, z), 90.0, &"car_paint_a")
	refs.gate.set_meta(&"no_merge", true)
	refs.gate_open = Transform3D(Basis(Vector3.UP, deg_to_rad(155)), Vector3(3.0, 0, z - 4.2))
	_target("gate", Vector3(0.6, 0.05, z + 1.6), "Aracı it", {}, 30.0)
	kit.graffiti(Vector3(-6.8, 0.6, z + 0.32), 0.0, "DUR", Color("9a2f22"), 80)
	kit.graffiti(Vector3(5.8, 0.6, z + 0.32), 0.0, "GERİ DÖN", Color("9a2f22"), 60)
	# camp behind the line
	for p in [Vector3(-4.5, 0, z - 13), Vector3(4.5, 0, z - 15)]:
		var t := MeshKit.static_box(kit.root, Vector3(3.0, 1.8, 2.4), p + Vector3(0, 0.9, 0), Palette.mat(&"canvas"), &"concrete")
		MeshKit.box(t, Vector3(3.2, 0.1, 2.8), Vector3(0, 0.95, 0), Palette.mat(&"canvas"), Vector3(0, 0, 6))
	kit.barrel(Vector3(0.0, 0.02, z - 8))
	refs.lights["camp_fire"] = _light(kit.root, Vector3(0.0, 1.3, z - 8), Color("ff9a3a"), 1.4, 7.0)
	kit.crate(Vector3(-2.5, 0.02, z - 9), 0.8, 15.0)
	_loot("cp_cache", &"cache", Vector3(-2.5, 0.9, z - 9), &"raider", "Haydut sandığı")
	for x in [-6.8, -3.8, 3.8, 5.8]:
		refs.cover.append(Vector3(x, 0, z - 1.3))
	refs.cover.append_array([Vector3(-4.5, 0, z - 11.5), Vector3(4.5, 0, z - 13.5)])
	refs.lanterns = [Vector3(-7.5, 1.2, z + 1.5), Vector3(7.5, 1.2, z + 1.5), Vector3(-5.5, 1.2, z - 40), Vector3(5.5, 1.2, z - 40)]


func _light(parent: Node3D, p: Vector3, c: Color, energy: float, range_m: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = range_m
	l.position = p
	parent.add_child(l)
	return l
