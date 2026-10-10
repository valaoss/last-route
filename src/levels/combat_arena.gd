extends LevelBase

## Combat test yard (warehouse lot, ~70 x 70 m): open plaza, low/high cover,
## a 2 m container corridor, a doorway choke point and a wave panel.
## F5 walker · F6 group of 6 · F7 runner · F8 brute · F9 clear · F10 horde (20)

var kit: WorldKit
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	use_navmesh = true
	bike_spawn = Transform3D(Basis(Vector3.UP, deg_to_rad(90)), Vector3(-26, 0.15, 24))
	player_spawn = Transform3D(Basis.IDENTITY, Vector3(-22, 0.15, 22))


func build_world() -> void:
	_rng.randomize()
	kit = WorldKit.new(geo, 5)
	kit.ground(300.0, &"grass", &"grass")
	MeshKit.static_box(geo, Vector3(72, 0.3, 72), Vector3(0, -0.13, 0), Palette.mat(&"asphalt_worn"), &"asphalt")
	# perimeter: warehouse walls and a fence line
	kit.building(Vector3(0, 0, -42), Vector3(70, 11, 12), 180.0, &"concrete", "NORTHSIDE FREIGHT", 0.6)
	kit.building(Vector3(-42, 0, 0), Vector3(12, 8, 70), 90.0, &"brick", "", 0.5)
	kit.building(Vector3(42, 0, 6), Vector3(12, 9, 58), -90.0, &"plaster", "", 0.5)
	for x in range(-34, 36, 4):
		if absf(x) > 6:
			MeshKit.static_box(geo, Vector3(4.0, 2.4, 0.12), Vector3(x, 1.2, 36), Palette.mat(&"rust_metal"), &"concrete")
	# central plaza cover: jersey barriers (low), wrecks, crates (high)
	kit.barrier(Vector3(-6, 0.02, 4), 0.0)
	kit.barrier(Vector3(-3.6, 0.02, 4.6), 20.0)
	kit.barrier(Vector3(7, 0.02, -2), 90.0)
	kit.car_wreck(Vector3(4, 0.0, 10), 30.0)
	kit.car_wreck(Vector3(-12, 0.0, -8), -70.0, &"rust_metal", 5.0)
	kit.crate(Vector3(12, 0.0, 8), 1.2, 10.0)
	kit.crate(Vector3(12.8, 1.2, 8.2), 0.9, 35.0)
	kit.crate(Vector3(13.4, 0.0, 9.4), 1.0, 0.0)
	for p in [Vector3(-2, 0, -12), Vector3(-1.3, 0, -12.6), Vector3(16, 0, -6)]:
		kit.barrel(p, false)
	kit.barrel(Vector3(0.5, 0, -11.5), true)
	# container corridor (2 m wide, 20 m long) on the east side
	for i in 3:
		kit.container(Vector3(22.0, 0.0, -18 + i * 6.3), 0.0, &"rust_metal" if i != 1 else &"painted_metal")
		kit.container(Vector3(26.45, 0.0, -18 + i * 6.3), 0.0, &"painted_metal" if i != 1 else &"rust_metal")
	# doorway choke point: wall with a 1.6 m gap on the west side
	MeshKit.static_box(geo, Vector3(0.4, 3.2, 10.0), Vector3(-24, 1.6, -11.0), Palette.mat(&"brick"), &"concrete")
	MeshKit.static_box(geo, Vector3(0.4, 3.2, 10.0), Vector3(-24, 1.6, 0.6), Palette.mat(&"brick"), &"concrete")
	MeshKit.static_box(geo, Vector3(0.4, 0.8, 1.6), Vector3(-24, 2.8, -5.2), Palette.mat(&"brick"), &"concrete")
	kit.graffiti(Vector3(-23.75, 1.7, -2.5), 90.0, "NO WAY OUT", Color("8c2a1f"), 90)
	kit.graffiti(Vector3(0, 3.0, -35.9), 0.0, "QUARANTINE ZONE 4", Color("d9cfb4"), 120)
	for n in 400:
		var p := Vector3(_rng.randf_range(-36, 36), 0.02, _rng.randf_range(-36, 36))
		if _rng.randf() < 0.5:
			kit.grass_tuft(p, 0.7)
	for n in 60:
		kit.tree(Vector3(_rng.randf_range(-90, 90), 0, _rng.randf_range(44, 90)), -1.0, false)
	kit.flush()


func after_spawn() -> void:
	spawn_zombie(ZombieData.Archetype.WALKER, Vector3(0, 0.1, -20), 0.0)
	hud.set_help("F5 walker · F6 grup(6) · F7 runner · F8 brute · F9 temizle · F10 sürü(20)")


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_F5: _spawn_near(ZombieData.Archetype.WALKER, 1)
		KEY_F6: _spawn_near(ZombieData.Archetype.WALKER, 6)
		KEY_F7: _spawn_near(ZombieData.Archetype.RUNNER, 1)
		KEY_F8: _spawn_near(ZombieData.Archetype.BRUTE, 1)
		KEY_F9:
			for e in get_tree().get_nodes_in_group(&"enemy"):
				e.queue_free()
		KEY_F10:
			for i in 20:
				_spawn_near(ZombieData.Archetype.RUNNER if i % 7 == 0 else ZombieData.Archetype.WALKER, 1, 24.0)


func wave(kind: int, count: int) -> void:
	_spawn_near(kind, count)


func _spawn_near(kind: int, count: int, dist := 16.0) -> void:
	var center := player.global_position
	var ahead := player.camera_flat_forward()
	for i in count:
		var a := _rng.randf_range(-0.9, 0.9)
		var dir := ahead.rotated(Vector3.UP, a)
		var p := center + dir * (dist + _rng.randf_range(-3, 4))
		p.x = clampf(p.x, -33, 33)
		p.z = clampf(p.z, -33, 33)
		p.y = 0.1
		var z := spawn_zombie(kind, p, _rng.randf() * TAU)
		z._last_known = center
		z._enter(Zombie.S.INVESTIGATE)
