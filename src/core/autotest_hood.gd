class_name AutoTestHood
extends RefCounted

## Scripted pass over the P2 neighbourhood: bakes the tiled navmesh, walks the
## M01–M05 chain (teleporting between places), checks stairs, the checkpoint
## clear, the gate, the saddlebag upgrade, the save, and measures frame time.

var at: AutoTest
var lv: Node
var p: Player
var b: Moto
## The night reload frees this run; the morning half continues in the new scene.
static var phase := 0
static var carried := PackedStringArray()


func run(t: AutoTest) -> void:
	at = t
	lv = t.level
	p = lv.player
	b = lv.bike
	if phase == 1:
		at.log_lines = carried
		await _morning()
		return
	var t0 := Time.get_ticks_msec()
	while lv.nav_pending > 0 and Time.get_ticks_msec() - t0 < 60000:
		await at._frames(5)
	at._log("nav tiles pending=%d after %d ms; enemies %d, loot %d, targets %d" % [lv.nav_pending, Time.get_ticks_msec() - t0,
		at.get_tree().get_nodes_in_group(&"enemy").size(), lv.loot.size(), lv.targets.size()])
	_census()
	at._log("mesh merge %s" % lv.merge_stats)
	await at._frames(10)
	var polys := 0
	var tiles := 0
	for r in lv.get_children():
		if r is NavigationRegion3D and r.navigation_mesh:
			tiles += 1
			if r.name == "NavTile_2_5":
				var vs: PackedVector3Array = r.navigation_mesh.get_vertices()
				var lo := Vector3.INF
				var hi := -Vector3.INF
				for v in vs:
					lo = lo.min(v)
					hi = hi.max(v)
				at._log("tile 2_5 aabb %s  verts %s..%s  cell %.2f border %.2f" % [r.navigation_mesh.filter_baking_aabb, lo, hi, r.navigation_mesh.cell_size, r.navigation_mesh.border_size])
			polys += r.navigation_mesh.get_polygon_count()
	var map: RID = lv.get_world_3d().navigation_map
	for pair in [[Vector3(0, 0, 150), Vector3(0, 0, 140)], [Vector3(0, 0, 150), Vector3(0, 0, 100)], [Vector3(0, 0, 100), Vector3(0, 0, 90)], [Vector3(0, 0, 50), Vector3(60, 0, 50)]]:
		var pp := NavigationServer3D.map_get_path(map, pair[0], pair[1], true)
		at._log("nav probe %s -> %s: %d pts, end off %.1f  margin %.2f" % [pair[0], pair[1], pp.size(), pp[pp.size() - 1].distance_to(pair[1]) if pp.size() > 0 else -1.0, NavigationServer3D.map_get_edge_connection_margin(map)])
	var path := NavigationServer3D.map_get_path(map, NbPlaces.GARAGE, NbPlaces.STATION, true)
	_checkpoint_path("before M04")
	var tp := Time.get_ticks_usec()
	lv._parse_nav_source()
	at._log("nav source parse (main-thread hitch on re-bake): %.1f ms" % ((Time.get_ticks_usec() - tp) / 1000.0))
	at._log("navmesh: %d tiles, %d polygons; garage→station path %d points, ends %.1f m from target" % [tiles, polys, path.size(),
		path[path.size() - 1].distance_to(NbPlaces.STATION) if path.size() > 0 else -1.0])
	_look(p.global_position + Vector3(1.5, 0.6, -10))
	await at._frames(40)
	await at._shot("h00_garage")
	_step()
	# ---- M01
	await _goto(NbPlaces.STATION + Vector3(-8, 0.2, 16))
	_step()
	_look(NbPlaces.STATION + Vector3(-4, 2, 0))
	await at._frames(30)
	await at._shot("h01_station")
	await _loot("st_part")
	await _loot("st_fuel")
	_step()
	await _goto(NbPlaces.GARAGE + Vector3(0, 0.2, 0))
	_step()
	await _use("generator")
	await at._frames(10)
	_step()
	p.global_position = NbPlaces.GARAGE + Vector3(2.5, 0.2, -5)
	_look(NbPlaces.GARAGE + Vector3(-2, 1.0, 6))
	await at._frames(30)
	await at._shot("h02_garage_power")
	# ---- M02
	await _use("radio")
	await _goto(NbPlaces.TOWER + Vector3(6, 0.2, 10))
	_step()
	await _loot("tw_part")
	await _use("tower_panel")
	_step()
	p.global_position = NbPlaces.HILL + Vector3(4, 0.2, 13)
	_look(NbPlaces.TOWER + Vector3(0, 9, 0))
	await at._frames(60)
	await at._shot("h03_tower")
	# ---- M03
	await _goto(lv.runner.places.pharmacy + Vector3(0, 0.2, 0))
	_step()
	p.global_position = NbPlaces.PHARMACY + Vector3(-5.5, 0.2, 3.5)
	_look(NbPlaces.PHARMACY + Vector3(-2.0, 1.0, -3.0))
	await at._frames(30)
	await at._shot("h04_pharmacy")
	await _loot("ph_meds")
	await _goto(Vector3(-7, 0.2, -61))
	_step()
	# stairs: walk up from the foot of the ramp
	p.global_position = Vector3(-21.6, 0.2, -53.4)
	at.level.rig.yaw = 0.0
	await at._frames(5)
	PlayerInput.override_enabled = true
	PlayerInput.override_move = Vector2(0, 1)
	for i in 4:
		await at._frames(60)
		at._log("stairs t=%ds: y %.2f z %.1f" % [i + 1, p.global_position.y, p.global_position.z])
	PlayerInput.override_move = Vector2.ZERO
	at._log("stairs: player y %.2f at z %.1f (upper floor = 3.2)" % [p.global_position.y, p.global_position.z])
	await at._frames(10)
	await _use("apt_door")
	_step()
	_look(p.global_position + Vector3(4, 0.5, 2))
	await at._frames(20)
	await at._shot("h05_apartment_up")
	PlayerInput.override_enabled = false
	# ---- M04
	await _goto(Vector3(0, 0.2, 4))
	_step()
	_look(NbPlaces.CHECKPOINT + Vector3(0, 1, -6))
	p.global_position = Vector3(-2, 0.2, -6)
	await at._frames(120)
	await at._shot("h06_checkpoint")
	for r in at.get_tree().get_nodes_in_group(&"raider"):
		at._log("raider %s hp %d" % [Raider.R.keys()[r.state], r.health])
		r.take_damage(999.0, p)
	p.health = p.max_health
	await at._frames(40)
	_step()
	await _use("gate")
	await at._frames(90)
	while lv.nav_pending > 0:
		await at._frames(5)
	await at._frames(5)
	_checkpoint_path("gate open")
	p.global_position = Vector3(3, 0.2, -4)
	_look(NbPlaces.CHECKPOINT + Vector3(0, 1, -10))
	await at._frames(10)
	await at._shot("h07_shortcut")
	_step()
	# ---- M05
	await _goto(lv.runner.places.workshop + Vector3(0, 0.2, 0))
	p.global_position = NbPlaces.WORKSHOP + Vector3(-2, 0.2, -4)
	_look(NbPlaces.WORKSHOP + Vector3(4, 1.0, 5))
	await at._frames(30)
	await at._shot("h08_workshop")
	await _loot("ws_tools")
	await _goto(NbPlaces.GARAGE + Vector3(0, 0.2, 0))
	await _use("workbench")
	_step()
	# ---- P3 workbench: two upgrades, two recipes (materials partly in the bike bag)
	p.inventory.add(&"scrap", 24)
	p.inventory.add(&"cloth", 8)
	p.inventory.add(&"alcohol", 2)
	p.inventory.add(&"powder", 3)
	var quiet := b.noise_radius()
	var bench: WorkbenchPanel = lv.open_bench()
	await at._frames(5)
	bench._upgrade("saddlebags")
	bench._upgrade("muffler")
	bench._craft("lure")
	bench._craft("ammo_pistol")
	await at._frames(5)
	b.global_transform = Transform3D(Basis.IDENTITY, NbPlaces.GARAGE + Vector3(0.6, 0.2, -1.5))
	await at._shot("h09b_bench")
	bench.close()
	await at._frames(3)
	at._log("bench: paused while open; flags %s  noise %.1f → %.1f m  lures %d  scrap left %d  silencer %s" % [lv.runner.flags.keys(),
		quiet, b.noise_radius(), p.inventory.count(&"lure"), p.inventory.total(&"scrap"), b.visual.silencer.visible])
	at._log("flags %s  bag_mult %.1f  saddlebags %s  done %s" % [lv.runner.flags.keys(), p.inventory.bag_mult, b.visual.saddlebags.visible, lv.runner.done()])
	b.global_transform = Transform3D(Basis.IDENTITY, NbPlaces.GARAGE + Vector3(0.6, 0.2, -1.5))
	p.global_position = NbPlaces.GARAGE + Vector3(3.5, 0.2, -6)
	_look(NbPlaces.GARAGE + Vector3(-1, 0.8, 3))
	await at._frames(40)
	await at._shot("h09_garage_final")
	var sv := SaveSystem.load_data()
	at._log("autosave: level=%s missions=%s" % [sv.get("level"), sv.get("missions")])
	# ---- frame time on the main street with the town around
	p.global_position = Vector3(2, 0.2, 58)
	_look(Vector3(0, 2, 0))
	await at._frames(60)
	var wall := 0.0
	var draws := 0.0
	var last := Time.get_ticks_usec()
	for i in 240:
		await at.get_tree().process_frame
		var now := Time.get_ticks_usec()
		wall += (now - last) / 1000.0
		last = now
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	await at._shot("h10_main_street")
	await _breakdown()
	at._log("main street: wall frame avg %.2f ms  draw calls avg %d  prims %d  enemies %d" % [wall / 240.0, int(draws / 240.0),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), at.get_tree().get_nodes_in_group(&"enemy").size()])
	p.global_position = NbPlaces.HILL + Vector3(10, 0.2, 14)
	_look(Vector3(40, 0, -60))
	await at._frames(40)
	await at._shot("h11_panorama")
	var m := await _measure()
	at._log("panorama from the hill: draws %d prims %d" % [m[0], m[1]])
	await _p3_day_one()
	return


## Lure, region board, then a night at the garage (reloads the level).
func _p3_day_one() -> void:
	var lure_at := Vector3(-34, 0.0, 64)
	var near := []
	for z in at.get_tree().get_nodes_in_group(&"enemy"):
		if z is Zombie and z.global_position.distance_to(lure_at) < 30.0:
			near.append(z)
	var before := _mean_dist(near, lure_at)
	p.global_position = NbPlaces.GARAGE + Vector3(0, 0.2, 0)
	NoiseLure.throw(lv, lure_at + Vector3(-3, 1.5, 0), Vector3.RIGHT, null)
	await at._frames(60 * 9)
	at._log("lure: %d zombies within 30 m, mean distance %.1f → %.1f m after 9 s" % [near.size(), before, _mean_dist(near, lure_at)])
	for z in near:
		if is_instance_valid(z) and z.is_alive():
			z._die(Vector3.FORWARD, 1.0)
	at._log("region day %d %s  decor %s  town %s" % [lv.region.day, lv.region.to_dict(), lv.decor.built.keys(), lv.town_fx.built.keys()])
	p.global_position = NbPlaces.GARAGE + Vector3(2.5, 0.2, -4.0)
	_look(NbPlaces.GARAGE + Vector3(-1, 1.2, 6))
	var board: RegionPanel = lv.open_board()
	await at._frames(5)
	await at._shot("h12_board")
	board.close()
	for e in at.get_tree().get_nodes_in_group(&"enemy"):
		if e.is_alive() and e.global_position.distance_to(NbPlaces.GARAGE) < 45.0:
			if e is Raider:
				e.take_damage(999.0, p)
			else:
				e._die(Vector3.FORWARD, 1.0)
	await at._frames(5)
	at._log("night: dead %d  looted %d  enemies %d" % [lv.dead.size(), lv.runner.looted.size(), at.get_tree().get_nodes_in_group(&"enemy").size()])
	phase = 1
	carried = at.log_lines
	at._write_log()
	if not lv.rest():
		at._log("REST REFUSED")
		phase = 0
		return
	await at._frames(100000)


func _morning() -> void:
	var t0 := Time.get_ticks_msec()
	while lv.nav_pending > 0 and Time.get_ticks_msec() - t0 < 60000:
		await at._frames(5)
	phase = 0
	var raiders := at.get_tree().get_nodes_in_group(&"raider").filter(func(r): return r.get_meta(&"mission_tag", "") == "patrol")
	at._log("morning: day %d %s" % [lv.region.day, lv.region.to_dict()])
	at._log("morning: report %s  dead %d  looted %d  enemies %d  patrol raiders %d" % [lv.last_report, lv.dead.size(), lv.runner.looted.size(),
		at.get_tree().get_nodes_in_group(&"enemy").size(), raiders.size()])
	at._log("morning: flags %s  saddlebags %s  silencer %s  decor %s  town %s" % [lv.runner.flags.keys(), b.visual.saddlebags.visible,
		b.visual.silencer.visible, lv.decor.built.keys(), lv.town_fx.built.keys()])
	for k in lv.decor.built:
		var n: Node3D = lv.decor.built[k]
		var rm := n.get_node_or_null("RigidMerged") as MeshInstance3D
		at._log("decor %s at %s merged %s" % [k, n.global_position, rm.global_transform * rm.get_aabb() if rm else "-"])
	_look(p.global_position + Vector3(0, 1, -6))
	await at._frames(20)
	await at._shot("h13_morning")
	await at._frames(60 * 7)
	p.global_position = NbPlaces.GARAGE + Vector3(-7, 0.2, -16)
	_look(NbPlaces.GARAGE + Vector3(0, 2.5, -6))
	await at._frames(30)
	await at._shot("h14_garage_outside")
	p.global_position = NbPlaces.GARAGE + Vector3(3.5, 0.2, -5.5)
	_look(NbPlaces.GARAGE + Vector3(-4, 0.8, -5))
	await at._frames(30)
	await at._shot("h15_garage_camp")
	p.global_position = Vector3(-8, 0.2, 52)
	_look(Vector3(-12, 3, 42))
	await at._frames(30)
	await at._shot("h16_pharmacy_sign")
	var sv := SaveSystem.load_data()
	at._log("save after morning: region %s  dead %d  report kept %s" % [sv.get("region"), (sv.get("dead", []) as Array).size(), sv.has("rest_report")])


func _mean_dist(nodes: Array, to: Vector3) -> float:
	if nodes.is_empty():
		return -1.0
	var s := 0.0
	for n in nodes:
		s += n.global_position.distance_to(to) if is_instance_valid(n) else 0.0
	return s / nodes.size()


func _census() -> void:
	var cats := {}
	for n in at.get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var key := "mesh"
		var tris := 0
		var inst := 1
		if n is MultiMeshInstance3D:
			key = "mm:" + n.name.trim_prefix("MM_").get_slice("@", 0)
			var mm: MultiMesh = n.multimesh
			if mm and mm.mesh:
				inst = mm.instance_count
				tris = mm.mesh.get_faces().size() / 3 * inst
		elif n is MeshInstance3D and n.mesh:
			tris = n.mesh.get_faces().size() / 3
			key = "skinned" if n.skeleton != NodePath() and n.get_parent() is Skeleton3D else "mesh"
		else:
			continue
		if not cats.has(key):
			cats[key] = [0, 0]
		cats[key][0] += 1 if not n is MultiMeshInstance3D else inst
		cats[key][1] += tris
	var keys := cats.keys()
	keys.sort_custom(func(a, b): return cats[a][1] > cats[b][1])
	for k in keys.slice(0, 14):
		at._log("census %-14s nodes/instances %6d  tris %8d" % [k, cats[k][0], cats[k][1]])


## Frame cost split: hide one category at a time and re-read the render monitors.
func _breakdown() -> void:
	var cats := {"skinned": [], "multimesh": [], "merged": [], "other": []}
	for n in at.get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		if not n.visible:
			continue
		if n is MultiMeshInstance3D:
			cats.multimesh.append(n)
		elif n is MeshInstance3D and n.skin != null:
			cats.skinned.append(n)
		elif n.name.begins_with("Merged_"):
			cats.merged.append(n)
		else:
			cats.other.append(n)
	var owners := {}
	for n in cats.other:
		var top: Node = n
		while top.get_parent() != lv and top.get_parent() != null:
			top = top.get_parent()
		var k := String(top.name).rstrip("0123456789@_")
		owners[k] = owners.get(k, 0) + 1
	at._log("other by owner %s" % owners)
	var base := await _measure()
	at._log("breakdown all: draws %d prims %d objects %d" % base)
	for k in cats:
		for n in cats[k]:
			n.visible = false
		var m := await _measure()
		at._log("breakdown -%s (%d nodes): draws -%d prims -%d" % [k, cats[k].size(), base[0] - m[0], base[1] - m[1]])
		for n in cats[k]:
			n.visible = true


func _measure() -> Array:
	await at._frames(3)
	var d := 0.0
	var p := 0.0
	var o := 0.0
	for i in 10:
		await at.get_tree().process_frame
		d += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		p += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		o += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	return [int(d / 10), int(p / 10), int(o / 10)]


## Path length through the checkpoint: long detour while closed, straight once open.
func _checkpoint_path(label: String) -> void:
	var pts := NavigationServer3D.map_get_path(lv.get_world_3d().navigation_map, Vector3(0, 0, 10), Vector3(0, 0, -50), true)
	var len := 0.0
	for i in range(1, pts.size()):
		len += pts[i - 1].distance_to(pts[i])
	at._log("checkpoint path %s: %.0f m (straight line 60 m), ends %.1f m off" % [label, len, pts[pts.size() - 1].distance_to(Vector3(0, 0, -50)) if pts.size() > 0 else -1.0])


func _step() -> void:
	var r: MissionRunner = lv.runner
	var s := r.current()
	at._log("  mission %d step %d %s  flags %s  hp %d" % [r.index, r.step, s.get("type", "-") + ":" + str(s.get("text", "")), r.flags.keys(), p.health])


func _goto(pos: Vector3) -> void:
	p.health = p.max_health
	p.global_position = pos
	await at._frames(4)


func _loot(id: String) -> void:
	var lp: LootPoint = lv.loot[id]
	lp.interact(p)
	await at._frames(3)


func _use(id: String) -> void:
	var t: MissionTarget = lv.targets[id]
	at._log("  use %s active=%s missing=%s" % [id, t.active, t.missing(p.inventory)])
	t.interact(p)
	await at._frames(3)


func _look(target: Vector3) -> void:
	var d := target - p.global_position
	at.level.rig.yaw = atan2(-d.x, -d.z)
	at.level.rig.pitch = clampf(atan2(d.y - 1.5, Vector2(d.x, d.z).length()), -0.6, 0.5)
