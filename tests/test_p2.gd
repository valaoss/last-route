extends RefCounted

## P2 checks: mission runner flow + save validation, mission data integrity
## against the neighbourhood, interior shells, mesh merging, bag upgrade.

var t: Node


func run(runner_node: Node) -> void:
	t = runner_node
	await _test_missions()
	await _test_mission_data()
	await _test_interior()
	await _test_merger()
	_test_bag_upgrade()


func check(cond: bool, label: String) -> void:
	t.check(cond, label)


func _test_missions() -> void:
	print("MissionRunner")
	check(MissionDB.step_types_valid(), "every step type is known")
	var r := MissionRunner.new()
	t.add_child(r)
	r.places = {"station": Vector3(100, 0, 0), "garage": Vector3.ZERO, "tower": Vector3(0, 5, -200), "checkpoint": Vector3(0, 0, -20)}
	r.start(false)
	check(r.current().type == "goto", "chain starts with a goto")
	r.update(Vector3(50, 0, 0), 0.016)
	check(r.step == 0, "far from the place: no progress")
	r.update(Vector3(95, 0, 0), 0.016)
	check(r.step == 1 and r.current().type == "loot", "reaching the place advances to loot")
	r.on_looted("st_part")
	check(r.step == 1, "one of two loot ids is not enough")
	r.on_looted("st_fuel")
	check(r.step == 2, "both searched: advance")
	r.on_interact("generator")
	check(r.step == 2, "interact for a later step is ignored")
	r.update(Vector3(1, 0, 1), 0.016)
	EventBus.mission_interact.emit("generator")
	check(r.index == 1 and r.step == 0 and r.has_flag("power"), "mission done: flag set, next mission")
	r.on_looted("tw_part")
	r.on_interact("radio")
	r.update(Vector3(0, 5, -195), 0.016)
	check(r.index == 1 and r.step == 3, "loot already searched skips its step")
	var alive := {"n": 2}
	r.tag_alive = func(_tag): return alive.n
	r.from_dict({"index": 3, "step": 0, "flags": ["power", "radio", "survivor"]})
	r.start(false)
	r.update(Vector3(0, 0, -10), 0.016)
	check(r.current().type == "clear", "checkpoint reached: clear step")
	r.update(Vector3.ZERO, 1.0)
	check(r.current().type == "clear", "raiders still fighting: stays")
	alive.n = 0
	r.update(Vector3.ZERO, 1.0)
	check(r.current().type == "interact", "all down or fled: advance")
	var saved := r.to_dict()
	r.from_dict({"index": 99, "step": -5, "flags": ["power", "evil"], "looted": [1, "x".repeat(100), "ok"]})
	check(r.done() and r.step == 0 and r.flags.keys() == ["power"] and r.looted.keys() == ["ok"], "junk save data clamped / filtered")
	r.from_dict(JSON.parse_string(JSON.stringify(saved)))
	check(r.index == 3 and r.step == 2 and r.has_flag("survivor"), "JSON round trip restores the chain position")
	r.queue_free()
	await t.get_tree().process_frame


## Every loot id / target referenced by the chain exists in the neighbourhood.
func _test_mission_data() -> void:
	print("Mission data ↔ neighbourhood")
	var root := Node3D.new()
	t.add_child(root)
	var kit := WorldKit.new(root, 1)
	var places := NbPlaces.new(kit)
	places.build()
	var loot_ids: Array = places.refs.loot.map(func(l): return l.id)
	var target_ids: Array = places.refs.targets.map(func(x): return x.id)
	var missing := []
	for m in MissionDB.CHAIN:
		for s in m.steps:
			if s.type == "loot":
				for id in s.ids:
					if not id in loot_ids:
						missing.append(id)
			elif s.type == "interact" and not s.target in target_ids:
				missing.append(s.target)
	check(missing.is_empty(), "chain references exist (missing: %s)" % [missing])
	var uniq := {}
	for id in loot_ids:
		uniq[id] = true
	check(uniq.size() == loot_ids.size(), "loot ids are unique (save keys)")
	check(MissionDB.CHAIN.all(func(m): return m.flag in MissionDB.FLAGS), "every mission flag is whitelisted")
	root.queue_free()
	await t.get_tree().process_frame


func _test_interior() -> void:
	print("InteriorKit")
	var root := Node3D.new()
	t.add_child(root)
	var ik := InteriorKit.new(WorldKit.new(root, 2))
	var a := ik.shell(Vector3(50, 0, 50), Vector3(6, 3, 5), 90.0, &"plaster", [[0, 0.0, 1.2, 2.2]])
	await t.get_tree().physics_frame
	await t.get_tree().physics_frame
	var space := root.get_world_3d().direct_space_state
	var q := PhysicsPointQueryParameters3D.new()
	q.position = a.to_global(Vector3(0, 1.0, -2.5 + InteriorKit.WALL * 0.5))
	check(space.intersect_point(q).is_empty(), "door opening is clear")
	q.position = a.to_global(Vector3(2.0, 1.0, -2.5 + InteriorKit.WALL * 0.5))
	check(not space.intersect_point(q).is_empty(), "wall beside the door is solid")
	q.position = a.to_global(Vector3(0, 2.6, -2.5 + InteriorKit.WALL * 0.5))
	check(not space.intersect_point(q).is_empty(), "lintel above the door is solid")
	q.position = a.to_global(Vector3(0, 1.0, 0))
	check(space.intersect_point(q).is_empty(), "room interior is empty")
	root.queue_free()
	await t.get_tree().process_frame


func _test_merger() -> void:
	print("MeshMerger")
	var root := Node3D.new()
	t.add_child(root)
	for i in 3:
		MeshKit.box(root, Vector3.ONE, Vector3(i * 2, 0, 0), Palette.mat(&"concrete"))
	MeshKit.box(root, Vector3.ONE, Vector3(0, 0, 3), Palette.mat(&"brick"))
	MeshKit.box(root, Vector3.ONE, Vector3(0, 0, 6), Palette.mat(&"rubber"))
	var keep := MeshKit.box(root, Vector3.ONE, Vector3(0, 3, 0), Palette.mat(&"concrete"))
	keep.set_meta(&"no_merge", true)
	var st := MeshMerger.merge(root, 96.0)
	check(st.sources == 5 and st.meshes == 2, "world-shader boxes share one mesh, other material separate")
	var merged := root.get_children().filter(func(n): return n.name.begins_with("Merged_"))
	var world: MeshInstance3D = merged.filter(func(n): return n.material_override is ShaderMaterial)[0]
	check(world.mesh.surface_get_array_len(0) == 4 * 24, "all four boxes' vertices kept")
	check(world.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_CUSTOM0 != 0 and world.material_override.get_shader_parameter(&"vertex_params"), "per-vertex surface params on")
	check(is_instance_valid(keep) and keep.get_parent() == root, "no_merge node left alone")
	root.queue_free()
	await t.get_tree().process_frame


func _test_bag_upgrade() -> void:
	print("Saddlebags")
	var inv := Inventory.new()
	inv.add(&"scrap", 50)
	check(inv.bag_count(&"scrap") == 30, "stock bag holds 30 scrap")
	inv.bag_mult = 2.0
	inv.add(&"scrap", 50)
	check(inv.bag_count(&"scrap") == 60, "saddlebags double the bike bag")
	inv.from_dict({"bag": {"scrap": 999}})
	check(inv.bag_count(&"scrap") == 60, "loaded bag clamped to the upgraded cap")
	var lp := LootPoint.new()
	lp.kind = &"quest"
	lp.item = &"antibiotics"
	lp.table = &"pharmacy"
	var got := lp.contents()
	check(got.get(&"antibiotics") == 1 and got.size() >= 2, "quest loot gives its item plus a table roll")
	lp.free()
