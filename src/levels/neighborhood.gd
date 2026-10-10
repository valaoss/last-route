extends LevelBase

## "Karaçam", the first neighbourhood (~300 × 400 m): walled city blocks
## around a main road, walk-in buildings, radio hill, gas station, a raider
## checkpoint that cuts the shortest route north, and the M01–M05 chain (P2).
## P3: region gauges, persistent dead, nights at the safehouse, workbench
## upgrades and crafting, a garage that grows and a town that shows it.

const LEVEL_ID := "neighborhood"
const SERVICES := ["refuel", "bench", "rest", "board"]
const REWARDS := {"m02": {&"ammo_pistol": 24}, "m03": {&"medkit": 2, &"cloth": 3}, "m04": {&"ammo_carbine": 40, &"scrap": 4}}
const UPGRADE_FLAGS := ["saddlebags", "muffler", "suspension"]
const REST_CLEAR_RADIUS := 35.0
const MAX_DEAD := 200
const CHATTER := [
	["Telsiz · ???", "…kuzey otoyolu… konvoy… tekrar ediyorum, kuzey otoyolu…"],
	["Telsiz · Nilay", "Kardeşimin ateşi düştü. Pencereden sokak lambalarını sayıyorum, hiçbiri yanmıyor."],
	["Telsiz · ???", "…köprü tutuldu… sürü dere boyunca güneye iniyor…"],
	["Telsiz · Nilay", "Gece Çarşı'dan bir çığlık geldi. Çığlıkçılara dikkat et, sürüyü çağırıyorlar."],
	["Telsiz · ???", "…burası Kuzey Kampı, frekansı açık tutun…"],
]

var kit: WorldKit
var town: NbTown
var places: NbPlaces
var runner: MissionRunner
var region := RegionState.new()
var decor: ShelterDecor
var town_fx: NbRegionFx
var targets := {}          ## id -> MissionTarget
var loot := {}             ## id -> LootPoint
var dead := {}             ## zombie spawn id -> true (stays dead until a night revives it)
var elapsed := 0.0
var kills := 0
var last_report := {}      ## region deltas of the last night (board arrows)
var _nilay: CharacterModel
var _chatter_t := 0.0
var _chatter_i := 0
var _beacon_on := false
var _dead_t := -1.0
var _banner_t := 0.0
var _world_dirty := false
var _rest_report := {}     ## written into the save right before the night reload
var _rng := RandomNumberGenerator.new()
var merge_stats := {}


func _init() -> void:
	use_navmesh = true
	nav_bake_aabb = AABB(Vector3(-160, -2, -224), Vector3(320, 16, 416))
	nav_chunk = 64.0


func build_world() -> void:
	_rng.seed = 2026
	kit = WorldKit.new(geo, 41)
	town = NbTown.new(kit)
	town.build()
	places = NbPlaces.new(kit)
	places.build()
	town.nature(places.refs.avoid)
	kit.flush()
	places.refs.beacon.set_meta(&"no_merge", true)
	if _saved_flags().has("shortcut"):
		places.refs.gate.transform = places.refs.gate_open
	merge_stats = MeshMerger.merge(geo, 96.0)
	bike_spawn = places.refs.bike_spawn
	player_spawn = places.refs.player_spawn


func after_spawn() -> void:
	for l in places.refs.loot:
		var lp := LootPoint.new()
		lp.kind = l.kind
		lp.position = l.pos
		lp.point_id = l.id
		lp.label = l.label
		lp.item = l.item
		if l.table != &"":
			lp.table = l.table
		add_child(lp)
		loot[l.id] = lp
		lp.looted.connect(_on_looted)
	for t in places.refs.targets:
		var mt := MissionTarget.new()
		mt.target_id = t.id
		mt.prompt = t.prompt
		mt.requires = t.requires
		mt.noise_radius = t.noise
		mt.position = t.pos
		mt.show_glint = not t.id in ["rest", "board"]
		add_child(mt)
		targets[t.id] = mt
		mt.used.connect(_on_target_used)
	for c in places.refs.cover:
		cover_point(c)
	var restoring: bool = SaveSystem.pending.get("level") == LEVEL_ID
	if restoring:
		_read_world_state(SaveSystem.pending)
	_spawn_zombies()
	runner = MissionRunner.new()
	runner.name = "Missions"
	add_child(runner)
	runner.places = {"garage": NbPlaces.GARAGE, "station": NbPlaces.STATION, "tower": NbPlaces.TOWER,
		"pharmacy": NbPlaces.PHARMACY + Vector3(-3, 0, 8), "apartment": Vector3(-7, 0, -61),
		"checkpoint": NbPlaces.CHECKPOINT + Vector3(0, 0, 8), "workshop": NbPlaces.WORKSHOP + Vector3(-2, 0, -9)}
	runner.tag_alive = tag_alive
	runner.step_started.connect(_on_step)
	runner.mission_completed.connect(_on_mission_done)
	runner.flag_set.connect(_apply_flag.bind(false))
	runner.chain_completed.connect(_on_chain_done)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.player_died.connect(_on_died)
	region.changed.connect(func(_k, _v): _world_dirty = true)
	decor = ShelterDecor.new(places.refs.garage)
	town_fx = NbRegionFx.new(self)
	targets.rest.active = true
	targets.board.active = true
	hud.set_help("Karaçam mahallesi · Esc menü (kaydeder)")
	SaveSystem.provider = snapshot
	if restoring:
		_restore(SaveSystem.pending)
		SaveSystem.pending = {}
	else:
		_spawn_checkpoint()
		runner.start()
	_spawn_patrol()
	_refresh_world(true)


func _exit_tree() -> void:
	if SaveSystem.provider == Callable(self, &"snapshot"):
		SaveSystem.provider = Callable()


## Flags in the save being loaded (read before the world is built, so static
## changes like the opened checkpoint are already in the navmesh bake).
func _saved_flags() -> Array:
	var d: Dictionary = SaveSystem.pending
	if d.get("level") != LEVEL_ID or not d.get("missions") is Dictionary:
		return []
	var f: Variant = d.missions.get("flags", [])
	return f.filter(func(x): return str(x) in MissionDB.FLAGS) if f is Array else []


# ------------------------------------------------------------------ population

## Fixed spawn list; each zombie has a stable id so the dead stay dead in saves.
func _spawn_zombies() -> void:
	var W := ZombieData.Archetype.WALKER
	var R := ZombieData.Archetype.RUNNER
	var B := ZombieData.Archetype.BRUTE
	var groups := [
		[W, [Vector3(-50, 0.1, 50), Vector3(-46, 0.1, 52), Vector3(40, 0.1, 49), Vector3(60, 0.1, 51), Vector3(64, 0.1, 47)]],
		[W, [Vector3(20, 0.1, 32), Vector3(28, 0.1, 36), Vector3(-14, 0.1, 33), Vector3(-20, 0.1, 39)]],
		[R, [Vector3(16, 0.1, 38)]],
		[W, [Vector3(95, 0.1, 20), Vector3(93, 0.1, -10), Vector3(97, 0.1, -40), Vector3(90, 0.1, -70)]],
		[W, [Vector3(60, 0.1, -110), Vector3(20, 0.1, -112), Vector3(-40, 0.1, -108), Vector3(-80, 0.1, -111)]],
		[W, [Vector3(122, 0.1, -155), Vector3(136, 0.1, -166), Vector3(140, 0.1, -150), Vector3(128, 0.1, -170)]],
		[B, [Vector3(116, 0.1, -168)]],
		[W, [Vector3(-128, 0.1, -150), Vector3(-120, 5.1, -184), Vector3(-132, 5.1, -197), Vector3(-114, 5.1, -200)]],
		[R, [Vector3(-112, 5.1, -180)]],
		[W, [Vector3(36, 0.1, -94), Vector3(44, 0.1, -97), Vector3(-14, 0.1, -58), Vector3(-18, 0.1, -66)]],
		[W, [Vector3(20, 0.1, 100), Vector3(-25, 0.1, 120), Vector3(12, 0.1, 76)]],
		[ZombieData.Archetype.SCREAMER, [Vector3(-36, 0.1, 58)]],
	]
	var i := 0
	for g in groups:
		for p in g[1]:
			var id := "z%d" % i
			i += 1
			var yaw := _rng.randf() * TAU
			if dead.has(id):
				continue
			spawn_zombie(g[0], p, yaw).set_meta(&"spawn_id", id)


func _spawn_checkpoint() -> void:
	if runner.has_flag("shortcut"):
		return
	var z := NbPlaces.CHECKPOINT.z
	var routes := [
		[Vector3(-3, 0.1, z - 4), PackedVector3Array([Vector3(-5, 0.1, z - 4), Vector3(2, 0.1, z - 5)])],
		[Vector3(3, 0.1, z - 6), PackedVector3Array([Vector3(5, 0.1, z - 6), Vector3(-1, 0.1, z - 9)])],
		[Vector3(0, 0.1, z - 18), PackedVector3Array([Vector3(0, 0.1, z - 18), Vector3(0, 0.1, z - 30), Vector3(4, 0.1, z - 22)])],
	]
	for r in routes:
		var rd := spawn_raider(r[0], r[1], 0.0)
		rd.set_meta(&"mission_tag", "checkpoint")


## Raiders regroup on the Kuzey yolu after the checkpoint falls while hostility stays high.
func _spawn_patrol() -> void:
	if not runner.has_flag("shortcut") or not region.raiders_patrol():
		return
	var route := PackedVector3Array([Vector3(-70, 0.1, -112), Vector3(-20, 0.1, -108), Vector3(30, 0.1, -112), Vector3(70, 0.1, -108)])
	for k in 2:
		var rd := spawn_raider(Vector3(-40 + k * 3.0, 0.1, -110), route, 0.0)
		rd.set_meta(&"mission_tag", "patrol")


## Enemies still fighting under a mission tag (dead or fleeing don't count).
func tag_alive(tag: String) -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group(&"raider"):
		if e.get_meta(&"mission_tag", "") == tag and e.is_alive() and e.state != Raider.R.FLEE:
			n += 1
	return n


func _on_enemy_killed(e: Node, _w: StringName) -> void:
	kills += 1
	if e is Zombie:
		region.on_zombie_killed(e.data.archetype)
		if e.has_meta(&"spawn_id") and dead.size() < MAX_DEAD:
			dead[e.get_meta(&"spawn_id")] = true
	elif e is Raider:
		region.on_raider_killed()


# ------------------------------------------------------------------ missions

func _on_step(m: Dictionary, s: Dictionary) -> void:
	for id in targets:
		if not id in SERVICES:
			targets[id].active = s.type == "interact" and s.target == id
	hud.set_objective("%s  ·  %s" % [m.title, s.text], _step_pos(s))
	SaveSystem.autosave.call_deferred()


func _step_pos(s: Dictionary) -> Variant:
	match s.type:
		"goto": return runner.places.get(s.place)
		"interact": return targets[s.target].global_position if targets.has(s.target) else null
		"clear": return NbPlaces.CHECKPOINT
		"loot":
			for id in s.ids:
				if loot.has(id) and not loot[id].taken:
					return loot[id].global_position
	return null


func _on_looted(lp: LootPoint) -> void:
	region.on_searched()
	runner.on_looted(lp.point_id)
	if not runner.done() and runner.current().type == "loot":
		_on_step(runner.mission(), runner.current())
	else:
		SaveSystem.autosave()


func _on_target_used(t: MissionTarget) -> void:
	match t.target_id:
		"refuel":
			if bike.global_position.distance_to(t.global_position) < 10.0:
				bike.fuel = 1.0
				EventBus.toast.emit("Depo dolu")
			else:
				EventBus.toast.emit("Motoru garaja getir")
		"bench":
			open_bench()
		"board":
			open_board()
		"rest":
			rest()
		_:
			return
	t.set_active.call_deferred(true)


func _on_mission_done(m: Dictionary) -> void:
	var lines := PackedStringArray([m.title + " tamamlandı"])
	var rw: Dictionary = REWARDS.get(m.id, {})
	for id in rw:
		player.inventory.add(id, rw[id])
		lines.append("+%d %s" % [rw[id], Inventory.display_name(id)])
	player.combat._emit_ammo()
	EventBus.toast.emit("\n".join(lines))


func _on_chain_done() -> void:
	hud.set_objective("Serbest dolaşım · tezgâhta motoru donat, panodan bölgeyi izle, yatakta günü bitir")
	if elapsed > 1.0:
		hud.show_banner("MAHALLE AÇILDI", "M01–M05 tamamlandı · süre %s · öldürülen %d" % [_clock(), kills], Palette.LOOT_AMBER)
		_banner_t = 6.0


## Permanent world changes. `instant` = applied from a save (no fanfare, and the
## region gauges already contain the effect).
func _apply_flag(f: String, instant: bool) -> void:
	if not instant:
		region.on_flag(f)
	var L: Dictionary = places.refs.lights
	match f:
		"power":
			L.garage.light_energy = 1.7
			L.garage2.light_energy = 1.1
			L.gen.light_energy = 0.7
			L.radio.light_energy = 0.5
			targets.refuel.active = true
		"radio":
			_beacon_on = true
			places.refs.beacon.visible = true
			_chatter_t = 150.0
		"survivor":
			L.nilay.light_energy = 1.2
			_update_nilay()
		"shortcut":
			if not instant:
				var tw := create_tween()
				tw.tween_property(places.refs.gate, "transform", places.refs.gate_open, 1.2).set_trans(Tween.TRANS_QUAD)
				tw.tween_callback(rebake_nav_at.bind(NbPlaces.CHECKPOINT))
			for p in places.refs.lanterns:
				var l := OmniLight3D.new()
				l.light_color = Color("ffc070")
				l.light_energy = 1.2
				l.omni_range = 7.0
				l.position = p
				add_child(l)
				MeshKit.box(l, Vector3(0.2, 0.3, 0.2), Vector3.ZERO, Palette.mat(&"loot_glint"), Vector3.ZERO, false)
			kit.graffiti(NbPlaces.CHECKPOINT + Vector3(-6.8, 0.6, 0.33), 0.0, "AÇIK", Color("4f6b3a"), 80)
			_update_nilay()
		"workbench":
			var tb := MeshKit.box(places.refs.tools_parent, Vector3(0.6, 0.25, 0.3), Vector3(3.6, 0.97, 6.9), Palette.mat(&"hazard"))
			tb.name = "Toolbox"
			targets.bench.active = true
		"saddlebags", "muffler", "suspension":
			bike.set_upgrade(f, true)
			if f == "saddlebags":
				player.inventory.bag_mult = 2.0
			if not instant:
				EventBus.toast.emit("%s takıldı · %s" % [UpgradeDB.UPGRADES[f].name, UpgradeDB.UPGRADES[f].desc])


## Nilay moves into the garage once she can reach it (she's safe and the road is open).
func _update_nilay() -> void:
	if _nilay != null or not (runner.has_flag("survivor") and runner.has_flag("shortcut")):
		return
	_nilay = CharacterModel.new()
	_nilay.name = "Nilay"
	add_child(_nilay)
	_nilay.setup({"skin_color": Color("b08d74"), "top_color": Color("3d4a5a"), "bottom_color": Color("2b2a28"), "grime": 0.15})
	_nilay.global_position = places.refs.nilay_spot
	_nilay.rotation.y = deg_to_rad(-140.0)
	_nilay.anim_player.play(&"Idle")


## Grows the garage and the town to match flags + region gauges.
func _refresh_world(quiet: bool) -> void:
	var fresh := decor.update(runner.has_flag, region)
	town_fx.update(region)
	if not quiet and not fresh.is_empty():
		EventBus.toast.emit("Sığınak gelişti: " + ", ".join(fresh.map(func(s): return ShelterDecor.SETS[s])))


# ------------------------------------------------------------------ safehouse services

func open_bench() -> WorkbenchPanel:
	var p := WorkbenchPanel.new()
	p.inv = player.inventory
	p.installed = runner.has_flag
	p.on_upgrade = func(id: String): runner.set_flag(id); SaveSystem.autosave()
	p.on_craft = craft
	hud.open_panel(p)
	return p


func craft(id: String) -> void:
	var out: Dictionary = UpgradeDB.RECIPES[id].out
	var lines := PackedStringArray()
	for item in out:
		var r: Dictionary = player.inventory.add(item, out[item])
		lines.append("+%d %s%s" % [out[item], Inventory.display_name(item), "  (%d çantaya)" % r.bagged if r.bagged > 0 else ""])
	player.combat._emit_ammo()
	EventBus.toast.emit("\n".join(lines))
	SaveSystem.autosave()


func open_board() -> RegionPanel:
	var p := RegionPanel.new()
	p.region = region
	p.report = last_report
	hud.open_panel(p)
	return p


## Ends the day: the region drifts, some of the dead get back up, some searched
## spots refill, and the level reloads from the save in the morning.
func rest() -> bool:
	for e in get_tree().get_nodes_in_group(&"enemy"):
		if e.is_alive() and e.global_position.distance_to(NbPlaces.GARAGE) < REST_CLEAR_RADIUS:
			EventBus.toast.emit("Dinlenemezsin · garajın yakınında düşman var")
			return false
	var delta := region.rest()
	var ids := dead.keys()
	ids.shuffle()
	var revived := roundi(ids.size() * region.revive_share())
	for i in revived:
		dead.erase(ids[i])
	var refilled := 0
	for id in runner.looted.keys():
		var lp: LootPoint = loot.get(id)
		if lp and lp.kind in [&"cache", &"ammo", &"med"] and _rng.randf() < region.refill_chance():
			runner.looted.erase(id)
			refilled += 1
	player.health = player.max_health
	player.global_position = places.refs.rest_spot
	_rest_report = {"delta": delta, "revived": revived, "refilled": refilled}
	SaveSystem.autosave()
	_rest_report = {}
	hud.show_banner("…", "Dinleniyorsun", Hud.DIM)
	SaveSystem.pending = SaveSystem.load_data()
	get_tree().reload_current_scene.call_deferred()
	return true


func _show_morning(r: Dictionary) -> void:
	var parts := PackedStringArray()
	var d: Variant = r.get("delta", {})
	if d is Dictionary:
		for k in RegionState.KEYS:
			var x := SaveSystem.read_num(d, k, 0.0, -100.0, 100.0)
			if absf(x) >= 0.5:
				parts.append("%s %+d" % [RegionState.NAMES[k], roundi(x)])
				last_report[k] = x
	var rv := int(SaveSystem.read_num(r, "revived", 0, 0, MAX_DEAD))
	var rf := int(SaveSystem.read_num(r, "refilled", 0, 0, 256))
	if rv > 0:
		parts.append("%d zombi geri döndü" % rv)
	if rf > 0:
		parts.append("%d yer yeniden doldu" % rf)
	hud.show_banner("GÜN %d" % region.day, "  ·  ".join(parts), Palette.LOOT_AMBER)
	_banner_t = 7.0


# ------------------------------------------------------------------ save / load

func snapshot() -> Dictionary:
	if player.state == Player.State.DEAD:
		return {}
	var d := SaveSystem.snapshot_actors(player, bike)
	d.merge({"level": LEVEL_ID, "missions": runner.to_dict(), "elapsed": elapsed, "kills": kills,
		"region": region.to_dict(), "dead": dead.keys()})
	if not _rest_report.is_empty():
		d["rest_report"] = _rest_report
	return d


## Region + dead list are needed before the population spawns.
func _read_world_state(d: Dictionary) -> void:
	var r: Variant = d.get("region")
	if r is Dictionary:
		region.from_dict(r)
	else:
		for f in _saved_flags():
			region.on_flag(str(f))
	dead.clear()
	var dl: Variant = d.get("dead", [])
	if dl is Array:
		for x in dl.slice(0, MAX_DEAD):
			if x is String and x.length() <= 6 and x.begins_with("z") and x.substr(1).is_valid_int():
				dead[x] = true


func _restore(d: Dictionary) -> void:
	var m: Variant = d.get("missions", {})
	if m is Dictionary:
		runner.from_dict(m)
	for f in runner.flags:
		_apply_flag(f, true)
	SaveSystem.apply_actors(d, player, bike)
	elapsed = SaveSystem.read_num(d, "elapsed", 0.0, 0.0, 3600000.0)
	kills = int(SaveSystem.read_num(d, "kills", 0, 0, 1000000))
	for id in runner.looted:
		if loot.has(id):
			loot[id]._mark_taken()
	_spawn_checkpoint()
	runner.start(false)
	if d.get("rest_report") is Dictionary:
		_show_morning(d.rest_report)
		SaveSystem.autosave.call_deferred()
	else:
		EventBus.toast.emit("Kayıt yüklendi")


# ------------------------------------------------------------------ loop

func _physics_process(dt: float) -> void:
	elapsed += dt
	if runner:
		runner.update(player.global_position, dt)
	if _world_dirty:
		_world_dirty = false
		_refresh_world(false)
	if _beacon_on:
		var on := fmod(elapsed, 1.6) < 0.25
		places.refs.lights.beacon.light_energy = 3.0 if on else 0.0
		places.refs.beacon.visible = on
	if runner and runner.has_flag("radio"):
		_chatter_t -= dt
		if _chatter_t <= 0.0 and not hud.is_radio_busy():
			_chatter_t = _rng.randf_range(100.0, 160.0)
			var c: Array = CHATTER[_chatter_i % CHATTER.size()]
			_chatter_i += 1
			EventBus.radio.emit(c[0], c[1])
	if _banner_t > 0.0:
		_banner_t -= dt
		if _banner_t <= 0.0:
			hud.show_banner("", "")
	if _dead_t >= 0.0:
		_dead_t += dt
		if _dead_t > 3.0:
			SaveSystem.pending = SaveSystem.load_data()
			get_tree().reload_current_scene()


func _on_died() -> void:
	hud.set_objective("")
	hud.show_banner("ÖLDÜN", "Son kayıttan devam ediliyor…" if SaveSystem.has_save() else "Yeniden başlatılıyor…", Color("b8322a"))
	_dead_t = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		SaveSystem.autosave()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://src/levels/main_menu.tscn")


func _clock() -> String:
	return "%d:%02d" % [int(elapsed) / 60, int(elapsed) % 60]
