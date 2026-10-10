class_name AutoTest
extends Node

## Scripted playthroughs for verification: drives the player/bike through
## PlayerInput overrides, records telemetry and screenshots, then quits.
## Usage: godot -- --autotest=<scenario> [--out=<dir>]

var level: LevelBase
var out_dir := "user://autotest"
var scenario := ""
var log_lines: PackedStringArray = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autotest="):
			scenario = a.get_slice("=", 1)
		elif a.begins_with("--out="):
			out_dir = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	await _frames(30)
	match scenario:
		"ride": await _ride()
		"arena": await _arena()
		"look": await _look()
		"perf": await _perf()
		"gasrun": await _gasrun()
		"hood": await AutoTestHood.new().run(self)
	_write_log()
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	log_lines.append("shot " + name)


func _log(s: String) -> void:
	log_lines.append(s)
	print("[autotest] ", s)


func _write_log() -> void:
	var f := FileAccess.open(out_dir.path_join(scenario + "_log.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(log_lines))


func _input_drive(throttle: float, brake: float, steer: float, hb := false) -> void:
	PlayerInput.override_enabled = true
	PlayerInput.override_throttle = throttle
	PlayerInput.override_brake = brake
	PlayerInput.override_move = Vector2(steer, throttle - brake)
	PlayerInput.override_handbrake = hb


func _press(action: StringName) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)


# ------------------------------------------------------------------ scenarios

func _look() -> void:
	var p := level.player
	await _shot("00_spawn")
	level.rig.yaw += PI * 0.5
	await _frames(20)
	await _shot("01_side")
	level.rig.yaw += PI * 0.5
	await _frames(20)
	await _shot("02_front")


func _ride() -> void:
	var p := level.player
	var b := level.bike
	await _shot("r00_start")
	# walk to the bike and mount
	p.global_position = b.global_position + b.global_basis.x * -1.0
	await _frames(5)
	var t0 := Time.get_ticks_msec()
	await _press(&"interact")
	await _frames(12)
	await _shot("r01_mounting")
	await _frames(30)
	_log("mounted state=%s after %d ms" % [Player.State.keys()[p.state], Time.get_ticks_msec() - t0])
	await _shot("r02_on_bike")
	# launch: measure 0→60 km/h
	var t := 0.0
	var t60 := -1.0
	_input_drive(1.0, 0.0, 0.0)
	var floor_frames := 0
	var frames := 0
	while t < 8.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		frames += 1
		if b.is_on_floor():
			floor_frames += 1
		if t60 < 0.0 and b.speed_kmh() >= 60.0:
			t60 = t
			await _shot("r03_60kmh")
		if absf(t - 6.0) < 0.009:
			await _shot("r04_fast")
	_log("0-60 km/h: %.2f s  speed after 8 s: %.1f km/h  gear %d  on-floor %d%%" % [t60, b.speed_kmh(), b.gear, 100 * floor_frames / maxi(frames, 1)])
	# braking distance from current speed
	var start_pos := b.global_position
	var v0 := b.speed_kmh()
	_input_drive(0.0, 1.0, 0.0)
	await _frames(8)
	await _shot("r05_brake_dive")
	while b.v > 0.3:
		await get_tree().physics_frame
	_log("brake from %.1f km/h: %.1f m" % [v0, start_pos.distance_to(b.global_position)])
	# carve: accelerate and steer for lean shots
	_input_drive(1.0, 0.0, 0.0)
	await _frames(150)
	_input_drive(0.7, 0.0, -1.0)
	await _frames(40)
	await _shot("r06_lean_left")
	_log("lean at %.1f km/h: %.1f deg, yaw %.2f, slide %.2f" % [b.speed_kmh(), rad_to_deg(b.visual.lean), b.yaw_rate, b.slide_amount])
	_input_drive(0.7, 0.0, 1.0)
	await _frames(70)
	await _shot("r07_lean_right")
	_input_drive(0.9, 0.0, 1.0, true)
	await _frames(30)
	await _shot("r08_handbrake_slide")
	_log("handbrake slide: slip %.1f deg, slide %.2f" % [rad_to_deg(b.slip), b.slide_amount])
	# stop and foot down
	_input_drive(0.0, 1.0, 0.0)
	while b.v > 0.2:
		await get_tree().physics_frame
	await _frames(40)
	await _shot("r09_stopped_foot_down")
	PlayerInput.override_enabled = false
	await _press(&"interact")
	await _frames(40)
	_log("dismounted state=%s" % Player.State.keys()[p.state])
	await _shot("r10_dismounted")
	_log("camera never lost target: rig->player distance %.2f" % level.rig.global_position.distance_to(p.global_position))
	# crash test: re-mount facing a building at speed
	await _press(&"interact")
	await _frames(40)
	b.global_position = Vector3(-14, 0.2, -401)
	b.heading = 0.0
	b.vel_heading = b.heading
	b.v = 14.0
	_input_drive(1.0, 0.0, 0.0)
	var crashed := false
	var ct := 0.0
	while ct < 3.0 and not crashed:
		await get_tree().physics_frame
		ct += get_physics_process_delta_time()
		crashed = b.state == Moto.State.CRASHED
	await _frames(10)
	await _shot("r11_crash")
	PlayerInput.override_enabled = false
	_log("crash into wall: crashed=%s player=%s hp=%d" % [crashed, Player.State.keys()[p.state], p.health])
	await _frames(100)
	_log("after crash: player=%s" % Player.State.keys()[p.state])


func _arena() -> void:
	var p := level.player
	var arena := level as Node
	await _shot("a00_start")
	for i in 5:
		level.spawn_zombie(ZombieData.Archetype.WALKER, p.global_position + Vector3(-3 + i * 1.6, 0.1, -9 - (i % 2) * 2.0), PI)
	level.spawn_zombie(ZombieData.Archetype.BRUTE, p.global_position + Vector3(4, 0.1, -13), PI)
	level.spawn_zombie(ZombieData.Archetype.RUNNER, p.global_position + Vector3(-5, 0.1, -15), PI)
	level.rig.yaw = 0.0
	level.rig.pitch = deg_to_rad(-6.0)
	await _frames(40)
	await _shot("a01_group")
	Input.action_press(&"aim")
	await _frames(20)
	await _shot("a02_aim")
	var stats := {"kills": 0, "hits": 0}
	EventBus.enemy_killed.connect(func(_e, _w): stats.kills += 1)
	EventBus.hit_confirmed.connect(func(_k, _h): stats.hits += 1)
	for i in 6:
		_aim_at_nearest()
		await _press(&"fire")
		await _frames(10)
	await _shot("a03_after_fire")
	Input.action_release(&"aim")
	await _press(&"weapon_3")
	await _frames(25)
	for i in 3:
		_aim_at_nearest()
		Input.action_press(&"aim")
		await _frames(5)
		await _press(&"fire")
		await _frames(30)
	await _shot("a04_shotgun")
	Input.action_release(&"aim")
	await _press(&"melee")
	await _frames(8)
	await _shot("a05_melee")
	await _frames(90)
	await _shot("a06_close")
	_log("hits %d  kills %d  player hp %d  zombies alive %d" % [stats.hits, stats.kills, p.health, get_tree().get_nodes_in_group(&"enemy").size()])
	await _press(&"dodge")
	await _frames(10)
	await _shot("a07_dodge")


## P0c flow: arrive, loot both items, alarm spawns the horde, ride home.
func _gasrun() -> void:
	var lv: Node = level
	var p := level.player
	var b := level.bike
	await _shot("g00_start")
	var station: Vector3 = lv.STATION
	# raider patrol: stand in their path and let them spot us
	b.global_transform = Transform3D(Basis.IDENTITY, Vector3(6, 0.15, -236))
	p.global_position = Vector3(4.0, 0.15, -238)
	level.rig.yaw = PI
	level.rig.pitch = deg_to_rad(-3.0)
	var hp0 := p.health
	await _frames(300)
	await _shot("g00b_raiders")
	var states := []
	for r in get_tree().get_nodes_in_group(&"raider"):
		states.append(Raider.R.keys()[r.state])
	_log("raiders %s  player hp %d -> %d" % [states, hp0, p.health])
	p.health = p.max_health
	b.global_transform = Transform3D(Basis.IDENTITY, Vector3(4, 0.15, -268))
	p.global_position = Vector3(2.6, 0.15, -268)
	await _frames(20)
	_log("near station step=%d (LOOT=1)" % lv.step)
	var before := get_tree().get_nodes_in_group(&"enemy").size()
	for lp in get_tree().get_nodes_in_group(&"interactable"):
		p.global_position = lp.global_position + Vector3(0.8, 0.1, 0)
		await _frames(4)
		_log("prompt '%s'" % p._prompt)
		await _press(&"interact")
		await _frames(6)
	_log("have %s  step=%d (ESCAPE=2)  enemies %d -> %d" % [lv.have, lv.step, before, get_tree().get_nodes_in_group(&"enemy").size()])
	_log("inventory %s  bag %s  ammo %s" % [p.inventory.items, p.inventory.bag, p.combat.ammo])
	var sv := SaveSystem.load_data()
	_log("autosave: step=%s have=%s looted=%s" % [sv.get("step"), sv.get("have"), sv.get("looted")])
	p.inventory.from_dict({})
	lv.have.clear()
	lv._restore(sv)
	_log("restored: step=%d have=%s medkits=%d fuel=%.2f" % [lv.step, lv.have, p.inventory.count(&"medkit"), b.fuel])
	p.global_position = Vector3(-1.5, 0.15, -262)
	await _frames(2)
	level.rig.yaw = atan2(-(station.x - p.global_position.x), -(station.z - p.global_position.z))
	level.rig.pitch = deg_to_rad(-4.0)
	await _frames(240)
	await _shot("g01_alarm")
	await _frames(420)
	await _shot("g01b_threeway")
	var rs := []
	for r in get_tree().get_nodes_in_group(&"raider"):
		rs.append("%s hp%d" % [Raider.R.keys()[r.state], r.health])
	_log("after alarm: raiders %s  kills so far %d" % [rs, lv.kills])
	b.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(1.5, 0.15, -262))
	b.heading = PI
	b.vel_heading = PI
	p.global_position = b.global_position + b.global_basis.x * -1.0
	await _frames(5)
	await _press(&"interact")
	await _frames(40)
	_input_drive(1.0, 0.0, 0.0)
	for i in 300:
		await get_tree().physics_frame
		if i == 200:
			await _shot("g02_escape")
	_log("escape ride: state=%s  z=%.0f  speed %.0f km/h  hp %d" % [Player.State.keys()[p.state], b.global_position.z, b.speed_kmh(), p.health])
	_input_drive(0.0, 0.0, 0.0)
	PlayerInput.override_enabled = false
	b.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(1.5, 0.15, 4))
	await _frames(20)
	_log("home step=%d (DONE=3)  kills %d  time %s" % [lv.step, lv.kills, lv._clock()])
	await _shot("g03_done")


## 30 zombies converging on the player; measures frame/physics time and draw calls.
func _perf() -> void:
	var p := level.player
	for i in 30:
		var a := TAU * i / 30.0
		var kind := ZombieData.Archetype.RUNNER if i % 8 == 0 else (ZombieData.Archetype.BRUTE if i == 5 else ZombieData.Archetype.WALKER)
		var z := level.spawn_zombie(kind, p.global_position + Vector3(cos(a), 0, sin(a)) * (10.0 + (i % 3) * 6.0) + Vector3(0, 0.1, 0), a)
		z._last_known = p.global_position
		z._enter(Zombie.S.INVESTIGATE)
	await _frames(60)
	var proc := 0.0
	var phys := 0.0
	var worst := 0.0
	var draws := 0.0
	var n := 0
	var wall := 0.0
	var last := Time.get_ticks_usec()
	for i in 300:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		wall += (now - last) / 1000.0
		last = now
		var pm := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var ph := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		proc += pm
		phys += ph
		worst = maxf(worst, pm + ph)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		n += 1
		if i == 150:
			await _shot("p00_crowd")
	_log("30 zombies: process avg %.2f ms  physics avg %.2f ms  worst %.2f ms  wall frame avg %.2f ms  draw calls avg %d  fps %d  slots %d" % [proc / n, phys / n, worst, wall / n, int(draws / n), Engine.get_frames_per_second(), AttackSlots.count()])


func _aim_at_nearest() -> void:
	var p := level.player
	var best: Node3D
	var bd := INF
	for e in get_tree().get_nodes_in_group(&"enemy"):
		var d: float = e.global_position.distance_to(p.global_position)
		if d < bd:
			bd = d
			best = e
	if best:
		var to := best.global_position + Vector3.UP * 1.3 - level.rig.camera.global_position
		level.rig.yaw = atan2(-to.x, -to.z)
		level.rig.pitch = atan2(to.y, Vector2(to.x, to.z).length())
