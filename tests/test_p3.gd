extends RefCounted

## P3 checks: region gauges, workbench economy (pockets + bag), bike upgrades,
## noise lure, safehouse growth, render-budget helpers (rigid merge, LODs, far trees).

var t: Node


func run(runner_node: Node) -> void:
	t = runner_node
	_test_region()
	_test_workbench()
	await _test_bike_upgrades()
	await _test_lure()
	await _test_shelter()
	_test_render_helpers()


func check(cond: bool, label: String) -> void:
	t.check(cond, label)


func _test_region() -> void:
	print("RegionState")
	var r := RegionState.new()
	check(r.get_value("threat") == 70.0 and r.day == 1, "starts at the design values")
	r.on_flag("power")
	r.on_flag("shortcut")
	check(r.get_value("infrastructure") == 35.0 and r.get_value("route") == 40.0 and r.get_value("hostility") == 50.0, "mission flags move their gauges")
	for i in 10:
		r.on_zombie_killed(ZombieData.Archetype.WALKER)
	r.on_zombie_killed(ZombieData.Archetype.BRUTE)
	check(is_equal_approx(r.get_value("threat"), 60.0), "kills lower the threat (brute counts more)")
	var d := r.rest()
	check(r.day == 2 and d.get("threat", 0.0) > 0.0 and d.get("resources", 0.0) > 0.0, "a night: day +1, horde drifts back, town restocks")
	for i in 500:
		r.on_raider_killed()
	check(r.get_value("hostility") == 0.0 and r.get_value("route") == 100.0, "gauges clamp to 0..100")
	check(r.revive_share() >= 0.05 and r.revive_share() <= 0.95 and r.refill_chance() <= 0.7, "derived rates stay bounded")
	r.from_dict({"threat": "x", "hostility": 1e9, "day": -4, "evil": 3})
	check(r.get_value("threat") == 70.0 and r.get_value("hostility") == 100.0 and r.day == 1, "junk save values fall back / clamp")
	var r2 := RegionState.new()
	r2.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	check(r2.to_dict() == r.to_dict(), "JSON round trip")


func _test_workbench() -> void:
	print("Workbench economy")
	var inv := Inventory.new()
	inv.add(&"scrap", 14)
	check(inv.count(&"scrap") == 10 and inv.total(&"scrap") == 14, "overflow sits in the bag, total sees both")
	check(not UpgradeDB.pay(inv, UpgradeDB.cost_of("suspension")), "missing powder: nothing paid")
	check(inv.total(&"scrap") == 14, "failed payment takes nothing")
	inv.add(&"powder", 1)
	check(UpgradeDB.pay(inv, UpgradeDB.cost_of("suspension")) and inv.total(&"scrap") == 0 and inv.total(&"powder") == 0, "pays from pockets then bag")
	inv.add(&"cloth", 3)
	inv.add(&"alcohol", 1)
	check(UpgradeDB.missing(inv, UpgradeDB.cost_of("medkit")).is_empty(), "medkit recipe affordable")
	check(UpgradeDB.RECIPES.size() == 4 and UpgradeDB.UPGRADES.size() == 3, "4 recipes, 3 upgrades")
	check(UpgradeDB.UPGRADES.keys().all(func(k): return k in MissionDB.FLAGS), "upgrades persist as whitelisted flags")
	var all_known := true
	for id in UpgradeDB.RECIPES:
		for item in UpgradeDB.RECIPES[id].cost.keys() + UpgradeDB.RECIPES[id].out.keys():
			all_known = all_known and Inventory.is_valid(item)
	for id in UpgradeDB.UPGRADES:
		for item in UpgradeDB.UPGRADES[id].cost:
			all_known = all_known and Inventory.is_valid(item)
	check(all_known, "every cost/output item exists")
	var found := {}
	for tb in LootTable.TABLES.values():
		for e in tb:
			found[e[0]] = true
	check(found.has(&"powder") and found.has(&"alcohol"), "new materials can be found as loot")


func _test_bike_upgrades() -> void:
	print("Bike upgrades")
	var bike: Moto = load("res://src/vehicle/moto.tscn").instantiate()
	t.add_child(bike)
	await t.get_tree().process_frame
	var base_noise := bike.noise_radius()
	bike.set_upgrade("muffler", true)
	check(is_equal_approx(bike.noise_radius(), base_noise * UpgradeDB.MUFFLER_NOISE) and bike.visual.silencer.visible, "muffler: −35% noise, silencer visible")
	bike.set_upgrade("suspension", true)
	var dirt := SurfaceData.get_surface(&"dirt")
	var dirt_up := SurfaceData.offroad(&"dirt")
	check(dirt_up.grip > dirt.grip and dirt_up.drag < dirt.drag and SurfaceData.offroad(&"asphalt") == SurfaceData.get_surface(&"asphalt"), "suspension: loose ground improved, asphalt unchanged")
	check(bike.offroad_kit and bike.visual.springs.visible, "suspension parts visible")
	var meshes := bike.visual.find_children("*", "MeshInstance3D", true, false).size()
	check(meshes <= 20, "bike parts merged per moving group (%d mesh nodes)" % meshes)
	bike.queue_free()
	await t.get_tree().process_frame


func _test_lure() -> void:
	print("Noise lure")
	var heard := []
	var cb := func(_p, r, pr, src): if src is NoiseLure: heard.append([r, pr])
	NoiseBus.noise_emitted.connect(cb)
	var holder := Node3D.new()
	t.add_child(holder)
	MeshKit.static_box(holder, Vector3(20, 0.2, 20), Vector3(200, -0.1, 200), Palette.mat(&"concrete"))
	var l := NoiseLure.throw(holder, Vector3(200, 1.5, 200), Vector3.FORWARD, null)
	for i in 70:
		await t.get_tree().physics_frame
	check(not heard.is_empty() and heard[0][0] == NoiseLure.RADIUS and heard[0][1] == NoiseBus.Priority.ALARM, "lure beeps an alarm-priority noise after landing")
	check(l.global_position.distance_to(Vector3(200, 0, 200)) > 2.0, "lure flies away from the thrower")
	NoiseBus.noise_emitted.disconnect(cb)
	holder.queue_free()
	await t.get_tree().process_frame


func _test_shelter() -> void:
	print("Safehouse growth")
	var r := RegionState.new()
	var flags := {}
	var has := func(f): return flags.has(f)
	check(ShelterDecor.wanted(has, r).is_empty(), "fresh run: bare garage")
	flags["radio"] = true
	flags["workbench"] = true
	r.on_flag("power")
	r.on_flag("radio")
	check(ShelterDecor.wanted(has, r) == ["antenna", "tools", "lights"], "flags + infrastructure unlock sets")
	var a := Node3D.new()
	t.add_child(a)
	var sd := ShelterDecor.new(a)
	var fresh := sd.update(has, r)
	check(fresh.size() == 3 and sd.update(has, r).is_empty(), "each set is built once")
	check(a.get_node("Decor_tools").get_child_count() <= 3, "set meshes merged")
	r.on_flag("survivor")
	r.on_flag("shortcut")
	r.day = 3
	r.add("survivors", 20.0)
	check(sd.update(has, r) == ["camp", "defense", "garden"] and sd.level() == 6, "region growth unlocks camp, defense, garden")
	a.queue_free()
	await t.get_tree().process_frame


func _test_render_helpers() -> void:
	print("Render budget helpers")
	var cm := CharacterModel.new()
	cm.setup({})
	var d := RenderingServer.mesh_get_surface(cm.mesh_instance.mesh.get_rid(), 0)
	check(d.get("lods", []).size() >= 3, "character keeps its import LODs after the region bake")
	cm.free()
	var img: Image = TreeImpostor._paint()
	var filled := [0, 0]
	for y in range(0, TreeImpostor.H, 4):
		for x in range(0, TreeImpostor.W * 2, 4):
			if img.get_pixel(x, y).a > 0.5:
				filled[x / TreeImpostor.W] += 1
	var cell := TreeImpostor.W * TreeImpostor.H / 16.0
	check(filled.all(func(n): return n / cell > 0.12 and n / cell < 0.7) and img.get_pixel(0, 0).a < 0.5, "far-tree atlas: both cells painted (%.0f%% / %.0f%%), background clear" % [filled[0] / cell * 100.0, filled[1] / cell * 100.0])
