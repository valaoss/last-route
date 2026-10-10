extends LevelBase

## P0c mini scenario: ride from the safehouse to a gas station 300 m north,
## search it for fuel + a carburettor part, the car alarm pulls a horde,
## ride back through the road group to the safehouse.

enum Step { RIDE_OUT, LOOT, ESCAPE, DONE, FAILED }

const SAFE := Vector3(0, 0, 6)
const SAFE_RADIUS := 7.0
const STATION := Vector3(22, 0, -290)
const ALARM_POS := Vector3(12, 0, -280)
const NEEDED: Array[StringName] = [&"fuel", &"part"]

var kit: WorldKit
var step := Step.RIDE_OUT
var have: Array[StringName] = []
var elapsed := 0.0
var kills := 0
var _alarm_t := 0.0
var _alarm_snd_t := 0.0
var _siren_t := 0.0
var _alarm_lights: Array[OmniLight3D] = []
var _end_t := 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	use_navmesh = true
	nav_bake_aabb = AABB(Vector3(-30, -2, -350), Vector3(100, 12, 170))
	bike_spawn = Transform3D(Basis.IDENTITY, Vector3(0, 0.15, 2))
	player_spawn = Transform3D(Basis.IDENTITY, Vector3(-1.6, 0.15, 4.0))


func build_world() -> void:
	_rng.seed = 77
	kit = WorldKit.new(geo, 23)
	kit.ground(1400.0)
	_safehouse()
	_road()
	_station()
	_nature()
	kit.flush()


func _safehouse() -> void:
	kit.building(Vector3(-13, 0, 6), Vector3(14, 6, 10), 90.0, &"brick", "GARAJ", 0.7)
	MeshKit.static_box(geo, Vector3(18, 0.3, 16), Vector3(-2, -0.13, 6), Palette.mat(&"concrete"), &"concrete")
	for p in [Vector3(6.5, 0.02, 0), Vector3(6.5, 0.02, 12), Vector3(-2, 0.02, 14.5)]:
		kit.barrier(p, 90.0 if p.z != 14.5 else 0.0)
	kit.crate(Vector3(-5, 0.02, 12), 1.0, 12.0)
	kit.crate(Vector3(-4.2, 0.02, 13), 0.8, 40.0)
	kit.barrel(Vector3(-6, 0.02, 0))
	kit.graffiti(Vector3(-7.95, 2.0, 2.5), 90.0, "GÜVENLİ", Color("4f6b3a"), 110)
	kit.lamp_post(Vector3(5.5, 0, -2), 90.0)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("ffd59a")
	lamp.light_energy = 1.4
	lamp.omni_range = 9.0
	lamp.position = Vector3(-5.5, 3.2, 6)
	add_child(lamp)


func _road() -> void:
	kit.road(Vector2(0, 14), Vector2(0, -320), 8.0, &"asphalt_worn")
	kit.dashed_line(Vector2(0, 8), Vector2(0, -316))
	for z in range(-20, -300, -45):
		kit.lamp_post(Vector3(-5.6, 0, z), 180.0)
	for i in 5:
		kit.car_wreck(Vector3(-6.8, 0.0, -70 - i * 8.0), _rng.randf_range(-10, 10))
	kit.car_wreck(Vector3(2.0, 0.0, -150), 70.0, &"rust_metal", 3.0)
	kit.barrier(Vector3(-2.2, 0.02, -205), 15.0)
	kit.barrier(Vector3(2.6, 0.02, -212), -20.0)
	kit.graffiti(Vector3(-9.5, 1.6, -118), 90.0, "BENZİN →", Color("9a2f22"), 100)
	MeshKit.static_box(geo, Vector3(0.3, 2.6, 6.0), Vector3(-9.7, 1.3, -118), Palette.mat(&"concrete"), &"concrete")


func _station() -> void:
	MeshKit.static_box(geo, Vector3(32, 0.3, 26), Vector3(20, -0.13, -290), Palette.mat(&"asphalt"), &"asphalt")
	# canopy
	for x in [14.0, 26.0]:
		for z in [-285.0, -295.0]:
			MeshKit.static_box(geo, Vector3(0.4, 5.0, 0.4), Vector3(x, 2.5, z), Palette.mat(&"painted_metal"), &"concrete")
	MeshKit.box(geo, Vector3(16, 0.7, 14), Vector3(20, 5.3, -290), Palette.mat(&"painted_metal"))
	MeshKit.box(geo, Vector3(16.1, 0.35, 14.1), Vector3(20, 5.0, -290), Palette.mat(&"hazard"))
	# pump islands, one pump knocked over
	for z in [-287.0, -293.0]:
		MeshKit.static_box(geo, Vector3(6.0, 0.18, 1.4), Vector3(20, 0.09, z), Palette.mat(&"curb"), &"concrete")
	MeshKit.static_box(geo, Vector3(0.9, 1.7, 0.6), Vector3(18, 1.0, -287), Palette.mat(&"car_paint_b"), &"concrete")
	MeshKit.static_box(geo, Vector3(0.9, 1.7, 0.6), Vector3(22, 1.0, -293), Palette.mat(&"car_paint_b"), &"concrete")
	MeshKit.static_box(geo, Vector3(0.9, 0.6, 1.7), Vector3(22.6, 0.32, -288.2), Palette.mat(&"car_paint_b"), &"concrete", Vector3(0, 30, 0))
	# shop + workshop yard
	kit.building(Vector3(37, 0, -290), Vector3(14, 4.5, 10), 90.0, &"plaster", "KOVAC YAKIT", 0.5)
	kit.crate(Vector3(30.6, 0.02, -299.5), 0.9, 8.0)
	kit.crate(Vector3(29.4, 0.02, -300.2), 0.7, 30.0)
	kit.barrel(Vector3(31, 0.02, -281))
	kit.barrel(Vector3(31.7, 0.02, -280.4), true)
	kit.car_wreck(ALARM_POS, 20.0, &"car_paint_c")
	kit.car_wreck(Vector3(10, 0.0, -303), -60.0, &"rust_metal", 4.0)
	kit.container(Vector3(24, 0.0, -308), 90.0)
	kit.graffiti(Vector3(31.95, 2.2, -285.5), -90.0, "SESSİZ OL", Color("2b2b2b"), 80)
	for side in [-1.0, 1.0]:
		var l := OmniLight3D.new()
		l.light_color = Color("ff9a3a")
		l.light_energy = 0.0
		l.omni_range = 5.0
		l.position = ALARM_POS + Vector3(side * 0.9, 0.9, -2.0)
		add_child(l)
		_alarm_lights.append(l)


func _nature() -> void:
	for n in 520:
		var p := Vector3(_rng.randf_range(-120, 120), 0, _rng.randf_range(-380, 110))
		if absf(p.x) < 12.0 or (p.x > 0 and p.x < 50 and p.z < -270 and p.z > -315) or p.distance_to(SAFE) < 22.0:
			continue
		kit.tree(p, -1.0, false)
	for n in 2600:
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		kit.grass_tuft(Vector3(side * _rng.randf_range(4.3, 16.0), 0.0, _rng.randf_range(-320, -10)))


func after_spawn() -> void:
	var loot := [[&"fuel", Vector3(19.0, 0.2, -287.0)], [&"part", Vector3(30.6, 0.92, -299.5)],
			[&"ammo", Vector3(10.6, 0.02, -300.5)], [&"med", Vector3(31.2, 0.02, -292.5)],
			[&"cache", Vector3(30.8, 0.02, -287.5), &"gas_station", "Dükkân tezgâhı"],
			[&"cache", Vector3(-6.0, 0.02, -86.0), &"car", "Araç bagajı"],
			[&"cache", Vector3(3.2, 0.02, -147.5), &"car", "Araç bagajı"]]
	for i in loot.size():
		var l: Array = loot[i]
		var lp := LootPoint.new()
		lp.kind = l[0]
		lp.position = l[1]
		lp.point_id = "lp%d" % i
		if l.size() > 2:
			lp.table = l[2]
			lp.label = l[3]
		add_child(lp)
		lp.looted.connect(_on_looted)
	for p in [Vector3(16, 0.1, -296), Vector3(27, 0.1, -283), Vector3(34, 0.1, -302), Vector3(8, 0.1, -282)]:
		spawn_zombie(ZombieData.Archetype.WALKER, p, _rng.randf() * TAU)
	for p in [Vector3(-2, 0.1, -95), Vector3(3, 0.1, -180), Vector3(-1, 0.1, -240)]:
		spawn_zombie(ZombieData.Archetype.WALKER, p, _rng.randf() * TAU)
	spawn_zombie(ZombieData.Archetype.SCREAMER, Vector3(40, 0.1, -306), PI * 0.5)
	# raider patrol working the road south of the station
	var route := PackedVector3Array([Vector3(-3, 0.1, -200), Vector3(3, 0.1, -232), Vector3(-2, 0.1, -262), Vector3(4, 0.1, -232)])
	spawn_raider(Vector3(-3, 0.1, -205), route, 0.0)
	spawn_raider(Vector3(-4.5, 0.1, -208), route, 0.0)
	for c in [Vector3(-1.8, 0, -206.2), Vector3(2.8, 0, -213.2), Vector3(1.0, 0, -151.8), Vector3(18, 0, -288.6),
			Vector3(22, 0, -294.6), Vector3(12, 0, -282.6), Vector3(10, 0, -305), Vector3(29.5, 0, -298.8),
			Vector3(24, 0, -306.2), Vector3(-6.8, 0, -98), Vector3(-6.8, 0, -76)]:
		cover_point(c)
	EventBus.enemy_killed.connect(func(_e, _w): kills += 1)
	EventBus.player_died.connect(_on_died)
	hud.set_help("Benzinlik kaçışı · Esc menü (kaydeder)")
	SaveSystem.provider = snapshot
	if SaveSystem.pending.get("level") == "gas_run":
		_restore(SaveSystem.pending)
		SaveSystem.pending = {}
	else:
		_set_step(Step.RIDE_OUT)


func _exit_tree() -> void:
	if SaveSystem.provider == Callable(self, &"snapshot"):
		SaveSystem.provider = Callable()


func _set_step(s: int) -> void:
	step = s
	match s:
		Step.RIDE_OUT:
			hud.set_objective("Motora bin, kuzeydeki benzinliğe git", STATION)
		Step.LOOT:
			hud.set_objective(_loot_text(), STATION)
		Step.ESCAPE:
			hud.set_objective("Alarm sürüyü çekiyor! Motora bin, sığınağa dön", SAFE)
		Step.DONE:
			hud.set_objective("")
			hud.show_banner("SIĞINAĞA ULAŞTIN", "Süre %s · Öldürülen %d · Can %d
Enter tekrar · Esc menü" % [_clock(), kills, roundi(player.health)], Palette.LOOT_AMBER)
			SaveSystem.delete_save()
		Step.FAILED:
			hud.set_objective("")
			hud.show_banner("ÖLDÜN", "Son kayıttan devam ediliyor…" if SaveSystem.has_save() else "Yeniden başlatılıyor…", Color("b8322a"))
	if s in [Step.LOOT, Step.ESCAPE]:
		SaveSystem.autosave()


# ------------------------------------------------------------------ save / load

func snapshot() -> Dictionary:
	if step >= Step.DONE or player.state == Player.State.DEAD:
		return {}
	var d := SaveSystem.snapshot_actors(player, bike)
	var looted := []
	for lp in get_children():
		if lp is LootPoint and lp.taken and lp.point_id != "":
			looted.append(lp.point_id)
	d.merge({"level": "gas_run", "step": step, "have": have.map(func(k): return String(k)),
		"elapsed": elapsed, "kills": kills, "looted": looted})
	return d


func _restore(d: Dictionary) -> void:
	SaveSystem.apply_actors(d, player, bike)
	elapsed = SaveSystem.read_num(d, "elapsed", 0.0, 0.0, 360000.0)
	kills = int(SaveSystem.read_num(d, "kills", 0, 0, 100000))
	have.clear()
	var h: Variant = d.get("have", [])
	if h is Array:
		for k in h:
			var id := StringName(str(k))
			if id in NEEDED and not id in have:
				have.append(id)
	var looted: Variant = d.get("looted", [])
	if looted is Array:
		for lp in get_children():
			if lp is LootPoint and lp.point_id in looted:
				lp._mark_taken()
	var st := int(SaveSystem.read_num(d, "step", Step.RIDE_OUT, Step.RIDE_OUT, Step.ESCAPE))
	if st == Step.ESCAPE:
		_spawn_horde()
	step = st
	_set_step(st)
	EventBus.toast.emit("Kayıt yüklendi")


func _loot_text() -> String:
	var parts := PackedStringArray()
	for k in NEEDED:
		parts.append(("✓ " if k in have else "· ") + LootPoint.LABELS[k])
	return "Benzinliği ara:  " + "   ".join(parts)


func _on_looted(lp: LootPoint) -> void:
	if lp.kind in NEEDED and not lp.kind in have:
		have.append(lp.kind)
	if (step == Step.LOOT or step == Step.RIDE_OUT) and lp.kind in NEEDED:
		if have.size() == NEEDED.size():
			_trigger_alarm()
		else:
			_set_step(Step.LOOT)
	elif step < Step.DONE:
		SaveSystem.autosave()


## The part was wired to the wreck's alarm: pulling it sets it off.
func _trigger_alarm() -> void:
	_alarm_t = 14.0
	_alarm_snd_t = 0.0
	_siren_t = 0.0
	_spawn_horde()
	_set_step(Step.ESCAPE)


func _spawn_horde() -> void:
	var groups := [[Vector3(70, 0.1, -330), 9, 14.0], [Vector3(-35, 0.1, -300), 7, 12.0], [Vector3(0, 0.1, -150), 7, 4.5]]
	for g in groups:
		for i in g[1]:
			var off := Vector3(_rng.randf_range(-g[2], g[2]), 0, _rng.randf_range(-g[2], g[2]) * (3.0 if g[2] < 6.0 else 1.0))
			var kind := ZombieData.Archetype.RUNNER if i % 4 == 3 else ZombieData.Archetype.WALKER
			var z := spawn_zombie(kind, g[0] + off, _rng.randf() * TAU)
			z._last_known = ALARM_POS
			z._enter(Zombie.S.INVESTIGATE)


func _physics_process(dt: float) -> void:
	if step < Step.DONE:
		elapsed += dt
	if step == Step.RIDE_OUT and player.global_position.distance_to(STATION) < 32.0:
		_set_step(Step.LOOT)
	if step == Step.ESCAPE and player.global_position.distance_to(SAFE) < SAFE_RADIUS:
		_set_step(Step.DONE)
	if _alarm_t > 0.0:
		_alarm_t -= dt
		_alarm_snd_t -= dt
		if _alarm_snd_t <= 0.0:
			_alarm_snd_t = 1.0
			NoiseBus.emit_noise(ALARM_POS, 160.0, NoiseBus.Priority.ALARM, null)
		_siren_t -= dt
		if _siren_t <= 0.0 and _alarm_t > 1.0:
			_siren_t = 3.2
			Sfx.play_at(&"car_alarm", ALARM_POS + Vector3.UP, 4.0, 0.0)
		var on := _alarm_t > 0.0 and fmod(_alarm_t, 0.7) < 0.35
		for l in _alarm_lights:
			l.light_energy = 2.5 if on else 0.0
	if step == Step.FAILED:
		_end_t += dt
		if _end_t > 3.0:
			SaveSystem.pending = SaveSystem.load_data()
			get_tree().reload_current_scene()


func _on_died() -> void:
	if step != Step.DONE:
		_set_step(Step.FAILED)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_ESCAPE:
		if step < Step.DONE:
			SaveSystem.autosave()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://src/levels/main_menu.tscn")
	elif event.physical_keycode == KEY_ENTER and step == Step.DONE:
		get_tree().reload_current_scene()


func _clock() -> String:
	return "%d:%02d" % [int(elapsed) / 60, int(elapsed) % 60]
