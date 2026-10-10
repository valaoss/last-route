extends Node

## Headless test suite: godot --headless res://tests/test_runner.tscn
## Exit code = number of failed checks.

var _fails := 0
var _passes := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_feel_math()
	_test_tuning()
	_test_weapons()
	_test_attack_slots()
	await _test_bike_physics()
	await _test_zombie_reactions()
	_test_inventory()
	_test_loot_table()
	_test_save()
	await _test_screamer()
	await _test_raider()
	await preload("res://tests/test_p2.gd").new().run(self)
	await preload("res://tests/test_p3.gd").new().run(self)
	print("\nRESULT: %d passed, %d failed" % [_passes, _fails])
	get_tree().quit(_fails)


func check(cond: bool, label: String) -> void:
	if cond:
		_passes += 1
		print("  ok   ", label)
	else:
		_fails += 1
		print("  FAIL ", label)


func _test_feel_math() -> void:
	print("FeelMath")
	var s := FeelMath.Spring.new(4.0, 1.0)
	for i in 120:
		s.step(1.0, 1.0 / 60.0)
	check(absf(s.value - 1.0) < 0.01, "critically damped spring settles in 2 s")
	var u := FeelMath.Spring.new(4.0, 0.3)
	var peak := 0.0
	for i in 60:
		peak = maxf(peak, u.step(1.0, 1.0 / 60.0))
	check(peak > 1.05, "under-damped spring overshoots")
	var st := 0.0
	for i in 6:
		st = FeelMath.approach_asym(st, 1.0, 0.1, 0.16, 1.0 / 60.0)
	check(is_equal_approx(st, 1.0), "steering reaches full lock in rise time (0.1 s)")
	check(absf(FeelMath.damp_angle(3.0, -3.0, 1000.0, 1.0) - (-3.0 + TAU)) < 0.01 or absf(wrapf(FeelMath.damp_angle(3.0, -3.0, 1000.0, 1.0), -PI, PI) + 3.0) < 0.01, "damp_angle takes the short way across ±π")


func _test_tuning() -> void:
	print("MotoTuning")
	var t := MotoTuning.new()
	var prev := 0.0
	var mono := true
	for g in range(1, t.gear_count + 1):
		var v := t.gear_top_speed(g)
		mono = mono and v > prev
		prev = v
	check(mono, "gear ratios are monotonic")
	check(is_equal_approx(t.gear_top_speed(t.gear_count), t.top_speed), "top gear reaches top speed")


func _test_weapons() -> void:
	print("Weapons")
	var p := WeaponData.pistol()
	var c := WeaponData.carbine()
	var s := WeaponData.shotgun()
	check(p.fire_interval < s.fire_interval and c.fire_interval < p.fire_interval, "fire rate order carbine > pistol > shotgun")
	check(s.damage * s.pellets >= 100.0, "point-blank shotgun can drop a walker (≥100)")
	check(p.damage * p.head_mult >= 80.0, "pistol headshot is decisive")
	check(c.automatic and not p.automatic, "only the carbine is automatic")
	check(s.kick_pitch > p.kick_pitch and s.shake > c.shake, "shotgun kicks hardest")
	check(Player.IFRAME_START < Player.IFRAME_END and Player.IFRAME_END < Player.DODGE_CANCEL and Player.DODGE_CANCEL < Player.DODGE_TIME, "dodge windows are ordered")


func _test_attack_slots() -> void:
	print("AttackSlots")
	var dummies: Array = []
	for i in 5:
		var d := _SlotDummy.new()
		add_child(d)
		dummies.append(d)
	var granted := 0
	for d in dummies:
		if AttackSlots.request(d):
			granted += 1
	check(granted == AttackSlots.MAX_ATTACKERS, "only %d attackers at once" % AttackSlots.MAX_ATTACKERS)
	AttackSlots.release(dummies[0])
	check(AttackSlots.request(dummies[4]), "released slot is reusable")
	for d in dummies:
		AttackSlots.release(d)
		d.queue_free()


class _SlotDummy extends Node:
	func is_alive() -> bool:
		return true


func _make_floor(size := 800.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(size, 1, size)
	cs.shape = sh
	cs.position.y = -0.5
	body.add_child(cs)
	add_child(body)
	return body


func _test_bike_physics() -> void:
	print("Motorcycle physics")
	var world := Node3D.new()
	add_child(world)
	var floor_body := _make_floor()
	floor_body.reparent(world)
	var bike: Moto = load("res://src/vehicle/moto.tscn").instantiate()
	world.add_child(bike)
	bike.global_position = Vector3(0, 0.2, 300)
	await get_tree().physics_frame
	bike.set_ridden(true)
	PlayerInput.override_enabled = true
	PlayerInput.override_throttle = 1.0
	PlayerInput.override_brake = 0.0
	PlayerInput.override_move = Vector2(0, 1)
	var t := 0.0
	var t60 := -1.0
	while t < 10.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if t60 < 0.0 and bike.speed_kmh() >= 60.0:
			t60 = t
	check(t60 > 2.9 and t60 < 3.6, "0→60 km/h in %.2f s (target 3.0–3.5)" % t60)
	check(bike.speed_kmh() > 85.0 and bike.speed_kmh() < 97.0, "top speed %.1f km/h near 94" % bike.speed_kmh())
	var start := bike.global_position
	var v0 := bike.speed_kmh()
	PlayerInput.override_throttle = 0.0
	PlayerInput.override_brake = 1.0
	while bike.v > 0.3:
		await get_tree().physics_frame
	var dist := start.distance_to(bike.global_position)
	check(dist < 40.0, "brakes from %.0f km/h in %.1f m" % [v0, dist])
	check(bike.yaw_rate_limit(5.0) > bike.yaw_rate_limit(25.0), "turning tightens at low speed")
	check(bike.yaw_rate_limit(0.5) < bike.yaw_rate_limit(4.0), "no pivoting on the spot")
	# lean must stay within limits during a hard carve
	PlayerInput.override_brake = 0.0
	PlayerInput.override_throttle = 1.0
	PlayerInput.override_move = Vector2(-1, 1)
	var max_lean := 0.0
	for i in 240:
		await get_tree().physics_frame
		max_lean = maxf(max_lean, absf(bike.visual.lean))
	check(rad_to_deg(max_lean) <= bike.tuning.max_lean_deg + 6.0, "lean %.1f° stays near the limit (%.0f°)" % [rad_to_deg(max_lean), bike.tuning.max_lean_deg])
	check(rad_to_deg(max_lean) > 15.0, "bike visibly leans in a carve")
	PlayerInput.override_enabled = false
	world.queue_free()
	await get_tree().physics_frame


func _test_zombie_reactions() -> void:
	print("Zombie")
	var world := Node3D.new()
	add_child(world)
	var floor_body := _make_floor(60.0)
	floor_body.reparent(world)
	var z := Zombie.new()
	z.data = ZombieData.walker()
	world.add_child(z)
	await get_tree().physics_frame
	var r := z.take_hit({"damage": 10.0, "zone": &"torso", "dir": Vector3.FORWARD, "power": 0.3})
	check(not r.killed and z.state != Zombie.S.STAGGER, "weak hit only flinches")
	z.take_hit({"damage": 10.0, "zone": &"torso", "dir": Vector3.FORWARD, "power": 1.0})
	check(z.state == Zombie.S.STAGGER, "strong hit staggers")
	var k := z.take_hit({"damage": 200.0, "zone": &"head", "dir": Vector3.FORWARD, "power": 1.0})
	check(k.killed and not z.is_alive(), "lethal hit kills")
	var b := Zombie.new()
	b.data = ZombieData.brute()
	world.add_child(b)
	await get_tree().physics_frame
	b.take_hit({"damage": 34.0, "zone": &"torso", "dir": Vector3.FORWARD, "power": WeaponData.pistol().stagger_power})
	check(b.state != Zombie.S.STAGGER, "brute ignores pistol stagger")
	b.take_hit({"damage": 50.0, "zone": &"torso", "dir": Vector3.FORWARD, "power": WeaponData.shotgun().stagger_power})
	check(b.state == Zombie.S.STAGGER, "brute staggers from the shotgun")
	world.queue_free()
	await get_tree().physics_frame


func _test_inventory() -> void:
	print("Inventory")
	var inv := Inventory.new()
	var r := inv.add(&"medkit", 5)
	check(r.kept == 3 and r.bagged == 2 and inv.count(&"medkit") == 3, "medkits over the pocket cap overflow to the bike bag")
	r = inv.add(&"medkit", 3)
	check(r.kept == 0 and r.bagged == 1 and r.lost == 2, "bag cap respected, excess reported as lost")
	check(inv.take(&"medkit", 2) == 2 and inv.count(&"medkit") == 1, "take removes from pockets")
	var moved := inv.restock_from_bag()
	check(moved.get(&"medkit", 0) == 2 and inv.count(&"medkit") == 3 and inv.bag_count(&"medkit") == 1, "restock tops pockets up from the bag")
	check(inv.add(&"bogus", 3).kept == 0, "unknown item rejected")
	var ammo := {&"pistol": [12, 80]}
	inv.ammo = ammo
	r = inv.add(&"ammo_pistol", 20)
	check(ammo[&"pistol"][1] == 90 and r.bagged == 10, "ammo fills the weapon reserve up to its pocket cap")
	var inv2 := Inventory.new()
	inv2.from_dict({"items": {"medkit": 99, "nope": 4, "scrap": "x"}, "bag": {"scrap": 7}})
	check(inv2.count(&"medkit") == 3 and inv2.count(&"scrap") == 0 and inv2.bag_count(&"scrap") == 7 and not inv2.items.has(&"nope"), "from_dict clamps and drops bad data")


func _test_loot_table() -> void:
	print("LootTable")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var ok := true
	for i in 50:
		var got := LootTable.roll(&"ammo_cache", rng, 2)
		for id in got:
			ok = ok and Inventory.is_valid(id) and got[id] > 0
	check(ok, "rolls only produce valid items")
	check(LootTable.roll(&"nowhere", rng).is_empty(), "unknown table yields nothing")


func _test_save() -> void:
	print("SaveSystem")
	var path := "user://test_save.json"
	SaveSystem.delete_save(path)
	var d := {"level": "gas_run", "step": 1, "player": {"pos": [1.0, 0.0, -5.0]}}
	check(SaveSystem.save_data(d, path), "atomic save writes")
	var back := SaveSystem.load_data(path)
	check(back.get("step") == 1.0 and back.get("version") == SaveSystem.VERSION, "round trip keeps data + version")
	d["step"] = 2
	SaveSystem.save_data(d, path)
	check(FileAccess.file_exists(path + ".bak"), "previous save kept as .bak")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{broken")
	f.close()
	check(SaveSystem.load_data(path).get("step") == 1.0, "corrupt file falls back to .bak")
	check(SaveSystem.migrate({"version": 99, "level": "gas_run"}).is_empty(), "future schema rejected")
	check(SaveSystem.migrate({"version": 1, "level": "../../evil"}).is_empty(), "unknown level rejected")
	check(SaveSystem.read_vec([1, "a", 3], Vector3.ONE) == Vector3.ONE and SaveSystem.read_vec([1e9, 0, 0], Vector3.ZERO) == Vector3.ZERO, "vector reader rejects junk")
	SaveSystem.delete_save(path)


func _test_screamer() -> void:
	print("Screamer")
	var world := Node3D.new()
	add_child(world)
	_make_floor(60.0).reparent(world)
	var heard := {"alarm": false}
	var cb := func(_p, r, pr, _s): if pr == NoiseBus.Priority.ALARM and r >= Zombie.SCREAM_RADIUS: heard.alarm = true
	NoiseBus.noise_emitted.connect(cb)
	var z := Zombie.new()
	z.data = ZombieData.screamer()
	world.add_child(z)
	await get_tree().physics_frame
	z._enter(Zombie.S.SCREAM)
	for i in 150:
		await get_tree().physics_frame
	check(heard.alarm, "scream broadcasts a 60 m alarm")
	check(z.state != Zombie.S.SCREAM and z._scream_cd > 0.0, "scream ends with a cooldown")
	NoiseBus.noise_emitted.disconnect(cb)
	world.queue_free()
	await get_tree().physics_frame


func _test_raider() -> void:
	print("Raider")
	var world := Node3D.new()
	add_child(world)
	_make_floor(80.0).reparent(world)
	var r := Raider.new()
	world.add_child(r)
	var z := Zombie.new()
	z.data = ZombieData.walker()
	z.position = Vector3(0, 0, -7)
	world.add_child(z)
	await get_tree().physics_frame
	var hp := z.health
	for i in 240:
		await get_tree().physics_frame
	check(r.state == Raider.R.COMBAT or r.state == Raider.R.FLEE or not z.is_alive(), "raider engages a nearby zombie")
	check(not z.is_alive() or z.health < hp, "raider damages the zombie")
	check(not z.is_alive() or z.target == r, "zombie retargets the raider that shot it")
	var r2 := Raider.new()
	r2.position = Vector3(20, 0, 20)
	world.add_child(r2)
	await get_tree().physics_frame
	r2.take_hit({"damage": 100.0, "zone": &"torso", "dir": Vector3.FORWARD})
	check(r2.state == Raider.R.FLEE, "badly wounded raider flees")
	r2.take_hit({"damage": 50.0, "zone": &"torso", "dir": Vector3.FORWARD})
	check(not r2.is_alive() and not r2.is_in_group(&"enemy"), "raider dies and leaves the enemy group")
	world.queue_free()
	await get_tree().physics_frame
