class_name ShelterDecor
extends RefCounted

## The garage grows with the run: each set appears once its condition holds
## (mission flags or region gauges) and stays. Built at runtime under the
## garage anchor and merged per set (one draw per material).

const SETS := {
	"antenna": "çatıya anten",
	"tools": "alet panosu",
	"camp": "ikinci yatak ve ocak",
	"lights": "ampul dizisi",
	"defense": "kum torbası siperi",
	"garden": "sebze sandıkları",
}

var anchor: Node3D
var built := {}


func _init(a: Node3D) -> void:
	anchor = a


static func wanted(has_flag: Callable, r: RegionState) -> Array[String]:
	var out: Array[String] = []
	if has_flag.call("radio"):
		out.append("antenna")
	if has_flag.call("workbench"):
		out.append("tools")
	if r.get_value("survivors") >= 30.0:
		out.append("camp")
	if r.get_value("infrastructure") >= 50.0:
		out.append("lights")
	if r.get_value("route") >= 40.0:
		out.append("defense")
	if r.get_value("survivors") >= 45.0 and r.day >= 3:
		out.append("garden")
	return out


## Builds whatever is wanted and missing; returns the names of new sets.
func update(has_flag: Callable, r: RegionState) -> Array[String]:
	var fresh: Array[String] = []
	for s in wanted(has_flag, r):
		if built.has(s):
			continue
		var n := Node3D.new()
		n.name = "Decor_" + s
		anchor.add_child(n)
		call("_" + s, n)
		MeshMerger.merge_rigid(n)
		built[s] = n
		fresh.append(s)
	return fresh


func level() -> int:
	return built.size()


# ------------------------------------------------------------------ sets (garage-local, door at -Z)

func _antenna(n: Node3D) -> void:
	var steel := Palette.mat(&"bike_frame")
	var base := Vector3(4.2, 4.6, 5.2)
	MeshKit.strut(n, base, base + Vector3(0, 5.2, 0), 0.09, steel)
	for i in 3:
		var y := 2.6 + i * 1.0
		MeshKit.strut(n, base + Vector3(-0.8 + i * 0.2, y, 0), base + Vector3(0.8 - i * 0.2, y, 0), 0.03, steel)
	for c in [Vector3(-1.4, 0, -1.2), Vector3(1.4, 0, -1.2), Vector3(0, 0, 1.5)]:
		MeshKit.strut(n, base + c, base + Vector3(0, 3.4, 0), 0.012, steel)
	MeshKit.box(n, Vector3(0.3, 0.25, 0.25), base + Vector3(0, 5.3, 0), Palette.mat(&"taillight"))


func _tools(n: Node3D) -> void:
	var z := 7.64
	MeshKit.box(n, Vector3(0.05, 0.4, 0.02), Vector3(2.8, 1.95, z), Palette.mat(&"bike_chrome"), Vector3(0, 0, 18))
	MeshKit.box(n, Vector3(0.5, 0.14, 0.015), Vector3(3.5, 2.2, z), Palette.mat(&"bike_chrome"))
	MeshKit.box(n, Vector3(0.08, 0.3, 0.03), Vector3(4.2, 1.85, z), Palette.mat(&"wood"))
	MeshKit.box(n, Vector3(0.18, 0.07, 0.04), Vector3(4.2, 2.02, z), Palette.mat(&"bike_engine"))
	MeshKit.box(n, Vector3(0.03, 0.26, 0.03), Vector3(4.6, 1.9, z), Palette.mat(&"hazard"))
	MeshKit.box(n, Vector3(0.03, 0.22, 0.03), Vector3(4.75, 1.88, z), Palette.mat(&"car_paint_b"))
	for i in 3:
		MeshKit.cyl(n, 0.33, 0.22, Vector3(1.4, 0.12 + i * 0.23, 7.2), Palette.mat(&"rubber"), Vector3.ZERO, 14)


func _camp(n: Node3D) -> void:
	var b := MeshKit.static_box(n, Vector3(2.0, 0.45, 1.0), Vector3(-4.4, 0.22, -5.4), Palette.mat(&"wood"), &"concrete")
	MeshKit.box(b, Vector3(1.9, 0.16, 0.95), Vector3(0, 0.3, 0), Palette.mat(&"canvas"), Vector3.ZERO, false)
	MeshKit.box(b, Vector3(0.35, 0.1, 0.6), Vector3(-0.75, 0.42, 0), Palette.mat(&"barrier"), Vector3.ZERO, false)
	MeshKit.box(n, Vector3(0.5, 0.75, 0.5), Vector3(-2.7, 0.38, -6.5), Palette.mat(&"bike_engine"))
	MeshKit.cyl(n, 0.16, 0.2, Vector3(-2.7, 0.86, -6.5), Palette.mat(&"rust_metal"), Vector3.ZERO, 12)
	MeshKit.box(n, Vector3(0.8, 0.05, 0.4), Vector3(-2.0, 0.6, -6.6), Palette.mat(&"wood"))
	var fire := OmniLight3D.new()
	fire.light_color = Color("ff9a4a")
	fire.light_energy = 0.6
	fire.omni_range = 4.0
	fire.position = Vector3(-2.7, 1.1, -6.5)
	n.add_child(fire)


func _lights(n: Node3D) -> void:
	var bulb := Palette.mat(&"loot_glint")
	var prev := Vector3.ZERO
	for i in 13:
		var t := i / 12.0
		var p := Vector3(lerpf(-5.8, 5.8, t), 4.15 - sin(t * PI * 3.0) * 0.25 - 0.1, -8.35)
		MeshKit.sphere(n, 0.06, p, bulb, Vector3.ONE, 6)
		if i > 0:
			MeshKit.strut(n, prev, p, 0.006, Palette.mat(&"rubber"))
		prev = p
	var l := OmniLight3D.new()
	l.light_color = Color("ffc87a")
	l.light_energy = 0.9
	l.omni_range = 10.0
	l.position = Vector3(0, 3.6, -9.4)
	n.add_child(l)


func _defense(n: Node3D) -> void:
	for side in [-1.0, 1.0]:
		var cx: float = 4.6 * side
		var body := StaticBody3D.new()
		body.position = Vector3(cx, 0.4, -9.8)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(3.2, 0.8, 0.55)
		cs.shape = sh
		body.add_child(cs)
		n.add_child(body)
		for row in 3:
			for k in 5:
				var x: float = cx - 1.3 + k * 0.62 + (0.31 if row % 2 == 1 else 0.0)
				if absf(x - cx) > 1.55:
					continue
				MeshKit.box(n, Vector3(0.6, 0.24, 0.42), Vector3(x, 0.13 + row * 0.25, -9.8), Palette.mat(&"canvas"), Vector3(0, (k * 7 + row * 3) % 9 - 4, 0))


func _garden(n: Node3D) -> void:
	for i in 3:
		var z := -4.0 + i * 2.6
		MeshKit.box(n, Vector3(0.8, 0.45, 2.0), Vector3(6.75, 0.23, z), Palette.mat(&"wood"))
		MeshKit.box(n, Vector3(0.7, 0.06, 1.9), Vector3(6.75, 0.47, z), Palette.mat(&"dirt"))
		for k in 4:
			MeshKit.sphere(n, 0.17, Vector3(6.75 + (0.15 if k % 2 == 0 else -0.15), 0.6, z - 0.7 + k * 0.47), Palette.mat(&"foliage"), Vector3(1, 0.7, 1), 6)
