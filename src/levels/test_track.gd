extends LevelBase

## Riding test loop (~1.4 km): long straight, hard 90° right, wide sweeper,
## town section with a 3.5 m alley, dirt + mud + gravel, a crest jump and a
## wreck slalom. Built from the shared kit so it already follows the art bible.

const W := 8.0

var kit: WorldKit
var lap_gate := Vector3(0, 0, -6)


func _init() -> void:
	bike_spawn = Transform3D(Basis.IDENTITY, Vector3(0, 0.15, 6))
	player_spawn = Transform3D(Basis.IDENTITY, Vector3(-1.6, 0.15, 7.5))


func build_world() -> void:
	kit = WorldKit.new(geo, 11)
	kit.ground(1400.0)
	_straight()
	_corner_and_sweeper()
	_town()
	_dirt()
	_return_leg()
	_scatter_nature()
	kit.flush()


func _straight() -> void:
	kit.road(Vector2(0, 30), Vector2(0, -404), W)
	kit.dashed_line(Vector2(0, 25), Vector2(0, -395))
	for z in range(0, -400, -40):
		kit.lamp_post(Vector3(5.6, 0, z), 0.0 if z % 80 == 0 else 180.0)
	# start area: abandoned checkpoint
	kit.barrier(Vector3(-3.0, 0.02, -14), 15.0)
	kit.barrier(Vector3(3.4, 0.02, -16), -10.0)
	kit.car_wreck(Vector3(-7.5, 0.0, -30), 12.0)
	MeshKit.static_box(geo, Vector3(6.0, 2.6, 0.3), Vector3(-9.5, 1.3, -22), Palette.mat(&"concrete"), &"concrete", Vector3(0, 8.0, 0))
	kit.graffiti(Vector3(-9.45, 1.5, -21.8), 8.0, "ROUTE 9 → SAFE?", Color("9a2f22"), 80)
	# convoy of abandoned cars on the shoulder — environmental story
	for i in 6:
		kit.car_wreck(Vector3(6.8 + kit.rng.randf_range(-0.3, 0.6), 0.0, -120 - i * 7.5), 180.0 + kit.rng.randf_range(-8, 8))
	kit.car_wreck(Vector3(-2.2, 0.0, -230), 63.0, &"", 4.0)   # one blocking half the lane
	kit.barrier(Vector3(2.6, 0.02, -300), 90.0)


func _corner_and_sweeper() -> void:
	# hard 90° right at the end of the straight
	kit.road(Vector2(-4, -400), Vector2(150, -400), W)
	kit.dashed_line(Vector2(6, -400), Vector2(148, -400))
	kit.curb(Vector2(-4.2, -404.4), Vector2(150, -404.4))
	kit.building(Vector3(-14, 0, -418), Vector3(16, 9, 12), 0.0, &"brick", "HARLOW GARAGE")
	kit.building(Vector3(20, 0, -416), Vector3(12, 6, 9), 0.0, &"plaster")
	# wide 180° sweeper, radius 60, around (150, -340)
	kit.road_arc(Vector2(150, -340), 60.0, -90.0, 90.0, W, &"asphalt", &"asphalt", 24)
	for i in 9:
		var a := deg_to_rad(-80.0 + i * 20.0)
		kit.barrier(Vector3(150 + cos(a) * 65.5, 0.02, -340 + sin(a) * 65.5), -rad_to_deg(a) + 90.0)


func _town() -> void:
	# westbound along z = -280, narrowing to a 3.5 m alley between buildings
	kit.road(Vector2(150, -280), Vector2(112, -280), W)
	kit.road(Vector2(112, -280), Vector2(50, -280), 3.6, &"asphalt_worn")
	kit.sidewalk(Vector2(150, -285.5), Vector2(112, -285.5), 3.0)
	kit.sidewalk(Vector2(150, -274.5), Vector2(112, -274.5), 3.0)
	var x := 110.0
	var i := 0
	while x > 52.0:
		var w := kit.rng.randf_range(8.0, 13.0)
		var h := kit.rng.randf_range(7.0, 15.0)
		var mats := [&"brick", &"plaster", &"concrete"]
		var signs := ["", "", "PHARMACY", "", "KOVAC & SONS", "", "LAUNDRY"]
		kit.building(Vector3(x - w * 0.5, 0, -280 + 1.85 + 5.0), Vector3(w - 0.2, h, 10.0), 180.0, mats[i % 3], signs[i % signs.size()] if i % 2 == 0 else "")
		kit.building(Vector3(x - w * 0.5, 0, -280 - 1.85 - 5.0), Vector3(w - 0.2, kit.rng.randf_range(6.0, 12.0), 10.0), 0.0, mats[(i + 1) % 3])
		x -= w
		i += 1
	kit.graffiti(Vector3(84, 2.0, -281.9), 0.0, "THEY FOLLOW THE NOISE", Color("2b2b2b"), 70)
	kit.graffiti(Vector3(70, 1.7, -278.1), 180.0, "HELP 2F", Color("8c2a1f"), 110)
	kit.barrel(Vector3(96, 0.02, -281.2))
	kit.barrel(Vector3(74, 0.02, -278.8), true)
	kit.crate(Vector3(62, 0.02, -281.0), 0.8, 20.0)


func _dirt() -> void:
	# dirt road west of town with a mud pocket and a gravel stretch
	kit.road(Vector2(50, -280), Vector2(-10, -280), 7.0, &"dirt", &"dirt", 0.03)
	MeshKit.static_box(geo, Vector3(7.0, 0.3, 14.0), Vector3(20, -0.12, -280), Palette.mat(&"mud"), &"mud", Vector3(0, 90, 0))
	kit.road(Vector2(-10, -280), Vector2(-80, -280), 7.0, &"gravel", &"gravel", 0.03)
	kit.road_arc(Vector2(-70, -270), 10.0, 180.0, 270.0, 7.0, &"gravel", &"gravel", 6)
	# small kicker ramps on the dirt — optional line
	kit.ramp(Vector2(0, -277), Vector2(-3, -277), 0.03, 0.32, 2.4, &"wood", &"concrete")


func _return_leg() -> void:
	# southbound along x = -80 back toward the start, with hill crest and wreck slalom
	kit.road(Vector2(-80, -272), Vector2(-80, -200), W, &"asphalt_worn")
	kit.ramp(Vector2(-80, -200), Vector2(-80, -170), 0.02, 2.4, W, &"asphalt_worn")
	kit.road(Vector2(-80, -170), Vector2(-80, -160), W, &"asphalt_worn", &"asphalt", 2.4, 2.8)
	kit.ramp(Vector2(-80, -160), Vector2(-80, -144), 2.4, 0.02, W, &"asphalt_worn")
	kit.road(Vector2(-80, -144), Vector2(-80, -16), W, &"asphalt_worn")
	kit.dashed_line(Vector2(-80, -140), Vector2(-80, -20))
	for k in 7:
		var z := -125.0 + k * 13.0
		var side := -2.4 if k % 2 == 0 else 2.4
		kit.car_wreck(Vector3(-80 + side, 0.0, z), 90.0 + kit.rng.randf_range(-20, 20), &"", kit.rng.randf_range(-3, 3))
	kit.road_arc(Vector2(-70, -20), 10.0, 180.0, 90.0, W, &"asphalt_worn", &"asphalt", 8)
	kit.road(Vector2(-70, -10), Vector2(0, -10), W, &"asphalt_worn")


func _scatter_nature() -> void:
	# forest edges along the dirt road and the return leg, grass on the verges
	for n in 160:
		var p := Vector3(kit.rng.randf_range(-140, 60), 0, kit.rng.randf_range(-330, -300))
		kit.tree(p, -1.0, false)
	for n in 140:
		var p := Vector3(kit.rng.randf_range(-130, -92), 0, kit.rng.randf_range(-260, 0))
		kit.tree(p, -1.0, false)
	for n in 60:
		var p := Vector3(kit.rng.randf_range(-40, -12), 0, kit.rng.randf_range(-390, -20))
		kit.tree(p, -1.0, false)
	for n in 2200:
		var side := -1.0 if kit.rng.randf() < 0.5 else 1.0
		var z := kit.rng.randf_range(-395, 25)
		kit.grass_tuft(Vector3(side * kit.rng.randf_range(4.3, 14.0), 0.0, z))
	for n in 1600:
		var p := Vector3(kit.rng.randf_range(-92, -68), 0, kit.rng.randf_range(-270, -14))
		if absf(p.x + 80) > 4.4:
			kit.grass_tuft(p)
	for n in 1200:
		var p := Vector3(kit.rng.randf_range(-80, 48), 0, kit.rng.randf_range(-296, -264))
		if absf(p.z + 280) > 3.8:
			kit.grass_tuft(p, 1.2)


func after_spawn() -> void:
	# a few targets to brush past or knock down
	for p in [Vector3(-7, 0.1, -175), Vector3(8, 0.1, -260), Vector3(90, 0.1, -283.5)]:
		spawn_zombie(ZombieData.Archetype.WALKER, p, kit.rng.randf() * TAU)
