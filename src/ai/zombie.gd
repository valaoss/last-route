class_name Zombie
extends CharacterBody3D

## Zombie agent: hierarchical FSM with sight/hearing perception, attack-slot
## coordination, type-specific attacks, layered hit reactions and distance-based
## AI + animation LOD (manual AnimationTree advance also gives per-enemy hit-stop).

signal died(z: Zombie)

enum S { IDLE, WANDER, SUSPICIOUS, INVESTIGATE, CHASE, CIRCLE, ATTACK, CHARGE, SEARCH, STAGGER, KNOCKDOWN, SCREAM, DEAD }

const SCREAM_TIME := 2.0
const SCREAM_RADIUS := 60.0

const GRAVITY := 20.0
const TOPS := [Color("8a8478"), Color("6b3b2e"), Color("4a4f55"), Color("55707a"), Color("2c3445"), Color("7a6a4a"), Color("5c5f4a")]
const BOTTOMS := [Color("2e3644"), Color("5d5444"), Color("1f2022"), Color("3b3f35"), Color("4a3b30")]
const SKINS := [Color("8f9283"), Color("9a8f84"), Color("7f8676"), Color("a39a8c")]

@export var data: ZombieData

var state: int = S.IDLE
var health := 100.0
var is_heavy := false
var model: CharacterModel
var agent: NavigationAgent3D
var player: Player
var target: Node3D               ## current prey: the player or a raider

var _t := 0.0
var _ai_timer := 0.0
var _ai_interval := 0.1
var _anim_acc := 0.0
var _anim_div := 1
var _frame := 0
var _lod := 0
var _hitstop := 0.0
var _suspicion := 0.0
var _last_known := Vector3.ZERO
var _sees_player := false
var _home := Vector3.ZERO
var _move_target := Vector3.ZERO
var _speed := 0.0
var _cur_speed := 0.0
var _facing := 0.0
var _push := Vector3.ZERO
var _has_slot := false
var _attack_hit_done := false
var _circle_offset := 0.0
var _circle_t := 0.0
var _leg_hp := 45.0
var _crawler := false
var _groan_t := 0.0
var _react_delay := 0.0
var _pending_noise := Vector3.ZERO
var _has_pending_noise := false
var _flash := 0.0
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _posture := {}
var _flinch := FeelMath.Spring.new(5.0, 0.45)
var _flinch_axis := Vector3.RIGHT
var _walk_scale := 1.0
var _attack_shot := &"atk"
var hitboxes: HitboxSet
var _charge_dir := Vector3.ZERO
var _scream_cd := 0.0


func _ready() -> void:
	if data == null:
		data = ZombieData.walker()
	_rng.randomize()
	health = data.health
	is_heavy = data.is_heavy
	add_to_group(&"enemy")
	collision_layer = 8
	collision_mask = 1 | 2 | 4 | 8
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3 * data.model_scale
	cap.height = 1.75 * data.model_scale
	cs.shape = cap
	cs.position.y = cap.height * 0.5
	add_child(cs)
	_build_model()
	_build_hitboxes()
	agent = NavigationAgent3D.new()
	agent.radius = 0.38 * data.model_scale
	agent.height = 1.8
	agent.path_desired_distance = 0.6
	agent.target_desired_distance = 0.5
	agent.avoidance_enabled = true
	agent.max_speed = maxf(data.chase_speed, data.charge_speed) + 1.0
	agent.neighbor_distance = 4.0
	agent.max_neighbors = 6
	agent.time_horizon_agents = 0.6
	agent.velocity_computed.connect(_on_velocity_computed)
	add_child(agent)
	_home = global_position
	_facing = rotation.y
	rotation.y = 0.0
	_walk_scale = 1.0 + _rng.randf_range(-data.walk_speed_var, data.walk_speed_var)
	_ai_timer = _rng.randf() * 0.1
	_groan_t = _rng.randf_range(2.0, 9.0)
	_circle_offset = _rng.randf_range(-1.0, 1.0)
	NoiseBus.noise_emitted.connect(_on_noise)
	state = S.WANDER if _rng.randf() < 0.6 else S.IDLE
	_pick_wander()


func is_alive() -> bool:
	return state != S.DEAD


# ------------------------------------------------------------------ build

func _build_model() -> void:
	model = CharacterModel.new()
	model.name = "Model"
	add_child(model)
	var heavy := data.archetype == ZombieData.Archetype.BRUTE
	model.setup({
		"skin_color": SKINS[_rng.randi() % SKINS.size()],
		"top_color": TOPS[_rng.randi() % TOPS.size()],
		"bottom_color": BOTTOMS[_rng.randi() % BOTTOMS.size()],
		"boot_color": Color("1e1b18"),
		"sleeves": 1.0 if _rng.randf() < 0.6 else 0.0,
		"grime": _rng.randf_range(0.5, 0.9),
		"decay": _rng.randf_range(0.55, 1.0),
		"seed": _rng.randf() * 50.0,
	})
	var body := _rng.randi() % 3
	var s := data.model_scale
	var sx: float = [0.93, 1.0, 1.14][body]
	var sz: float = [0.9, 1.0, 1.18][body]
	var sy: float = [1.03, 1.0, 0.97][body]
	if data.archetype == ZombieData.Archetype.SCREAMER:
		sx = 0.84
		sz = 0.82
		sy = 1.06
	if heavy:
		sx = 1.22
		sz = 1.25
	model.scale = Vector3(s * sx, s * sy * _rng.randf_range(0.95, 1.04), s * sz)
	_build_tree()
	# posture: arms reach, hunch and head tilt vary per individual
	var reach := _rng.randf_range(0.0, 1.0) if data.archetype == ZombieData.Archetype.WALKER else 0.15
	var one_arm := _rng.randf() < 0.3
	var hunch := deg_to_rad(_rng.randf_range(8.0, 24.0)) + (deg_to_rad(14.0) if data.archetype != ZombieData.Archetype.WALKER else 0.0)
	_posture = {
		"DEF-spine.002": Quaternion(Vector3.RIGHT, hunch * 0.6),
		"DEF-spine.003": Quaternion(Vector3.RIGHT, hunch * 0.4),
		"DEF-neck": Quaternion(Vector3.BACK, deg_to_rad(_rng.randf_range(-18.0, 18.0))) * Quaternion(Vector3.RIGHT, deg_to_rad(_rng.randf_range(-12.0, 10.0))),
		"DEF-upper_arm.L": Quaternion(Vector3.RIGHT, -deg_to_rad(65.0) * reach),
		"DEF-upper_arm.R": Quaternion(Vector3.RIGHT, -deg_to_rad(65.0) * reach * (0.0 if one_arm else 1.0)),
	}
	if data.archetype == ZombieData.Archetype.SCREAMER:
		_posture["DEF-neck"] = Quaternion(Vector3.RIGHT, -deg_to_rad(22.0))
		_posture["DEF-upper_arm.L"] = Quaternion(Vector3.BACK, -deg_to_rad(30.0))
		_posture["DEF-upper_arm.R"] = Quaternion(Vector3.BACK, deg_to_rad(30.0))
	if heavy:
		_posture["DEF-upper_arm.L"] = Quaternion(Vector3.BACK, -deg_to_rad(18.0))
		_posture["DEF-upper_arm.R"] = Quaternion(Vector3.BACK, deg_to_rad(18.0))
	model.offsets.set_layer(&"posture", _posture)
	model.tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	model.rotation.y = _facing


func _build_tree() -> void:
	var M := CharacterModel
	var bt := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace1D.new()
	loco.add_blend_point(M.anim(&"Idle"), 0.0, -1, &"Idle")
	match data.archetype:
		ZombieData.Archetype.RUNNER:
			loco.add_blend_point(M.anim(&"Walk"), 1.4, -1, &"Walk")
			loco.add_blend_point(M.anim(&"Jog_Fwd"), 3.2, -1, &"Jog_Fwd")
			loco.add_blend_point(M.anim(&"Sprint"), 5.2, -1, &"Sprint")
			loco.max_space = 6.0
		_:
			loco.add_blend_point(M.anim(&"Walk"), 1.0, -1, &"Walk")
			loco.add_blend_point(M.anim(&"Jog_Fwd"), 3.0, -1, &"Jog_Fwd")
			loco.max_space = 7.5
	loco.sync = true
	bt.add_node(&"loco", loco)
	bt.add_node(&"loco_ts", AnimationNodeTimeScale.new())
	bt.connect_node(&"loco_ts", 0, &"loco")
	bt.add_node(&"crawl_anim", M.anim(&"Crouch_Fwd"))
	bt.add_node(&"crawl", AnimationNodeBlend2.new())
	bt.connect_node(&"crawl", 0, &"loco_ts")
	bt.connect_node(&"crawl", 1, &"crawl_anim")
	var prev := &"crawl"
	prev = _shot(bt, prev, &"atk", &"Punch_Cross", false)
	prev = _shot(bt, prev, &"atk2", &"Punch_Jab", false)
	prev = _shot(bt, prev, &"heavy", &"Sword_Attack", false)
	prev = _shot(bt, prev, &"hit", &"Hit_Chest", true)
	prev = _shot(bt, prev, &"hit_head", &"Hit_Head", true)
	prev = _shot(bt, prev, &"stagger", &"Hit_Chest", false)
	prev = _shot(bt, prev, &"scream", &"Spell_Simple_Shoot", false)
	var down := AnimationNodeTransition.new()
	down.add_input("up")
	down.add_input("down")
	down.xfade_time = 0.25
	bt.add_node(&"down", down)
	bt.add_node(&"fall", M.anim(&"Death01"))
	bt.connect_node(&"down", 0, prev)
	bt.connect_node(&"down", 1, &"fall")
	bt.connect_node(&"output", 0, &"down")
	model.make_tree(bt)
	model.set_param("down/transition_request", "up")


func _shot(bt: AnimationNodeBlendTree, prev: StringName, n: StringName, anim_name: StringName, upper: bool) -> StringName:
	var o := CharacterModel.one_shot(0.06, 0.2)
	if upper:
		model.upper_filter(o)
	bt.add_node(n, o)
	var ts := StringName(String(n) + "_ts")
	bt.add_node(ts, AnimationNodeTimeScale.new())
	bt.add_node(StringName(String(n) + "_anim"), CharacterModel.anim(anim_name))
	bt.connect_node(ts, 0, StringName(String(n) + "_anim"))
	bt.connect_node(n, 0, prev)
	bt.connect_node(n, 1, ts)
	return n


func _build_hitboxes() -> void:
	hitboxes = HitboxSet.new(self, model)
	hitboxes.build_humanoid(data.model_scale, (model.scale.x + model.scale.z) * 0.5)


# ------------------------------------------------------------------ loop

func _physics_process(dt: float) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group(&"player") as Player
	if target == null or not is_instance_valid(target) or not target.is_targetable():
		target = player
	_t += dt
	_frame += 1
	_hitstop = maxf(_hitstop - dt, 0.0)
	_update_lod()
	if state != S.DEAD:
		_ai_timer -= dt
		if _ai_timer <= 0.0:
			_ai_timer += _ai_interval
			_think(_ai_interval)
		_act(dt)
	else:
		velocity = Vector3(0, velocity.y - GRAVITY * dt, 0)
		move_and_slide()
	_animate(dt)


func _update_lod() -> void:
	if _frame % 15 != 0 or player == null:
		return
	var d := global_position.distance_to(player.global_position)
	var lod := 0 if d < 25.0 else (1 if d < 60.0 else 2)
	if lod == _lod:
		return
	_lod = lod
	_ai_interval = [0.1, 0.33, 1.0][lod]
	_anim_div = [1, 3, 6][lod]
	model.mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	agent.avoidance_enabled = lod == 0


# ------------------------------------------------------------------ perception & decisions (AI tick)

func _think(dt: float) -> void:
	_perceive(dt)
	if _has_pending_noise:
		_react_delay -= dt
		if _react_delay <= 0.0:
			_has_pending_noise = false
			if state in [S.IDLE, S.WANDER, S.SUSPICIOUS, S.SEARCH, S.INVESTIGATE]:
				_last_known = _pending_noise
				_enter(S.INVESTIGATE)
	match state:
		S.IDLE:
			if _t > 3.0 + _rng.randf() * 4.0:
				_enter(S.WANDER)
		S.WANDER:
			if global_position.distance_to(_move_target) < 1.0 or _t > 14.0:
				_enter(S.IDLE)
		S.SUSPICIOUS:
			if _suspicion <= 0.05 and _t > 2.0:
				_enter(S.WANDER)
		S.INVESTIGATE:
			_set_nav(_last_known)
			if global_position.distance_to(_last_known) < 1.6 or _t > 15.0:
				_enter(S.SEARCH)
		S.SEARCH:
			if _t > _rng.randf_range(6.0, 10.0):
				_home = global_position
				_enter(S.WANDER)
		S.CHASE, S.CIRCLE:
			_think_combat()
	_groan_t -= dt
	if _groan_t <= 0.0 and player and global_position.distance_to(player.global_position) < 35.0:
		_groan_t = _rng.randf_range(2.5, 6.0) if state in [S.CHASE, S.CIRCLE] else _rng.randf_range(6.0, 14.0)
		Sfx.play_at(&"groan", global_position + Vector3.UP * 1.6, -8.0 if state != S.CHASE else -4.0, 0.15)


func _perceive(dt: float) -> void:
	_sees_player = false
	_scream_cd = maxf(_scream_cd - dt, 0.0)
	var best: Node3D = null
	var best_d := INF
	for c in _prey():
		var cd := _visible_dist(c)
		if cd < best_d:
			best_d = cd
			best = c
	if best == null:
		_suspicion = maxf(_suspicion - dt * 0.3, 0.0)
		return
	target = best
	var d := best_d
	_sees_player = true
	_last_known = target.global_position
	var closeness := 1.0 - d / data.sight_range
	var motion := clampf(target.planar_speed() / 4.0, 0.3, 1.5) + (1.0 if target.is_riding() else 0.0)
	_suspicion += dt * (0.6 + closeness * 3.0) * motion
	if d < 4.0 or state in [S.CHASE, S.CIRCLE, S.ATTACK]:
		_suspicion = 1.2
	if _suspicion >= 1.0 and data.archetype == ZombieData.Archetype.SCREAMER and _scream_cd <= 0.0 and state not in [S.SCREAM, S.STAGGER, S.KNOCKDOWN]:
		_enter(S.SCREAM)
	elif _suspicion >= 1.0 and state not in [S.CHASE, S.CIRCLE, S.ATTACK, S.CHARGE, S.STAGGER, S.KNOCKDOWN, S.SCREAM]:
		_enter(S.CHASE)
	elif _suspicion >= 0.4 and state in [S.IDLE, S.WANDER]:
		_enter(S.SUSPICIOUS)
	_suspicion = minf(_suspicion, 1.5)


## Player first, then any raiders.
func _prey() -> Array:
	var out := []
	if player:
		out.append(player)
	out.append_array(get_tree().get_nodes_in_group(&"raider"))
	return out


## Distance if `c` is targetable, inside the view cone and in line of sight, else INF.
func _visible_dist(c: Node3D) -> float:
	if not c.is_targetable():
		return INF
	var eye := global_position + Vector3.UP * 1.6
	var tp: Vector3 = c.target_point()
	var to := tp - eye
	var d := to.length()
	if d > data.sight_range:
		return INF
	var fwd := Vector3(-sin(_facing), 0.0, -cos(_facing))
	var flat := Vector3(to.x, 0.0, to.z).normalized()
	if rad_to_deg(fwd.angle_to(flat)) >= data.fov_deg * 0.5 and d >= 2.2:
		return INF
	var q := PhysicsRayQueryParameters3D.create(eye, tp, 1)
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		return INF
	return d


func _on_noise(pos: Vector3, radius: float, priority: int, source: Node) -> void:
	if state == S.DEAD or source == self:
		return
	var d := global_position.distance_to(pos)
	if d > radius * data.hearing:
		return
	if state in [S.CHASE, S.CIRCLE, S.ATTACK, S.CHARGE]:
		if source == target or (source is Moto and target == player):
			_last_known = pos
		return
	if state in [S.STAGGER, S.KNOCKDOWN]:
		return
	if _has_pending_noise and priority < NoiseBus.Priority.COMBAT:
		return
	_pending_noise = pos + Vector3(_rng.randf_range(-2, 2), 0, _rng.randf_range(-2, 2)) * clampf(d / 20.0, 0.2, 1.0)
	_has_pending_noise = true
	_react_delay = _rng.randf_range(0.15, 0.6) * (0.5 if data.archetype == ZombieData.Archetype.RUNNER else 1.0)


func _think_combat() -> void:
	if target == null or not target.is_targetable():
		_release_slot()
		_enter(S.SEARCH)
		return
	var goal := target.global_position if _sees_player else _last_known
	var d := global_position.distance_to(target.global_position)
	if not _sees_player and global_position.distance_to(_last_known) < 1.5:
		_release_slot()
		_enter(S.SEARCH)
		return
	if data.archetype == ZombieData.Archetype.SCREAMER:
		_think_screamer(d)
		return
	# brute charges from mid range in the open
	if data.charge_speed > 0.0 and _sees_player and d > 4.5 and d < 11.0 and _rng.randf() < 0.08:
		_enter(S.CHARGE)
		return
	if d < 6.0 and _sees_player:
		if not _has_slot:
			_has_slot = AttackSlots.request(self) if target == player else true
		if _has_slot:
			if state != S.CHASE:
				_enter(S.CHASE)
			if d <= data.attack_range and not target.is_riding():
				_enter(S.ATTACK)
				return
			_set_nav(goal)
		else:
			if state != S.CIRCLE:
				_enter(S.CIRCLE)
	else:
		if state != S.CHASE:
			_enter(S.CHASE)
		_set_nav(goal)


## Screamer keeps 7+ m away and only scratches when cornered.
func _think_screamer(d: float) -> void:
	if d < 1.6 and _sees_player:
		_enter(S.ATTACK)
	elif d < 7.0:
		var away := (global_position - target.global_position) * Vector3(1, 0, 1)
		_set_nav(global_position + away.normalized() * 6.0)
	else:
		_set_nav(global_position)


# ------------------------------------------------------------------ state machine

func _enter(s: int) -> void:
	if state == S.DEAD:
		return
	var prev := state
	state = s
	_t = 0.0
	match s:
		S.IDLE:
			_speed = 0.0
		S.WANDER:
			_pick_wander()
			_speed = data.walk_speed * 0.7 * _walk_scale
		S.SUSPICIOUS:
			_speed = 0.0
		S.INVESTIGATE:
			_speed = data.walk_speed * _walk_scale * (1.6 if data.archetype == ZombieData.Archetype.RUNNER else 1.0)
			_set_nav(_last_known)
		S.SEARCH:
			_speed = data.walk_speed * 0.6 * _walk_scale
			_set_nav(_last_known + Vector3(_rng.randf_range(-5, 5), 0, _rng.randf_range(-5, 5)))
		S.CHASE:
			_speed = data.chase_speed * _walk_scale
			if prev not in [S.CHASE, S.CIRCLE, S.ATTACK, S.STAGGER, S.CHARGE]:
				if data.archetype == ZombieData.Archetype.RUNNER:
					Sfx.play_at(&"screech", global_position + Vector3.UP * 1.6, -2.0)
				else:
					Sfx.play_at(&"groan", global_position + Vector3.UP * 1.6, -3.0)
		S.CIRCLE:
			_speed = data.walk_speed * _walk_scale
			_circle_t = 0.0
		S.ATTACK:
			_speed = 0.0
			_attack_hit_done = false
			var heavy := data.archetype == ZombieData.Archetype.BRUTE
			_attack_shot = &"heavy" if heavy else (&"atk" if _rng.randf() < 0.6 else &"atk2")
			var anim_name: StringName = {&"heavy": &"Sword_Attack", &"atk": &"Punch_Cross", &"atk2": &"Punch_Jab"}[_attack_shot]
			var total := data.attack_windup + data.attack_recover
			model.set_param("%s_ts/scale" % _attack_shot, model.anim_length(anim_name) / total * 0.9)
			model.fire(_attack_shot)
		S.SCREAM:
			_speed = 0.0
			_release_slot()
			model.set_param("scream_ts/scale", model.anim_length(&"Spell_Simple_Shoot") / SCREAM_TIME)
			model.fire(&"scream")
			Sfx.play_at(&"screech", global_position + Vector3.UP * 1.7, 6.0, 0.1)
		S.CHARGE:
			_speed = 0.0
			_charge_dir = (target.global_position - global_position) * Vector3(1, 0, 1)
			_charge_dir = _charge_dir.normalized()
			Sfx.play_at(&"screech", global_position + Vector3.UP * 1.8, 0.0, 0.0)
		S.STAGGER, S.KNOCKDOWN:
			_speed = 0.0
			_release_slot()


func _act(dt: float) -> void:
	var desired := Vector3.ZERO
	match state:
		S.IDLE, S.SUSPICIOUS:
			if state == S.SUSPICIOUS and target:
				_face_toward(target.global_position, 3.0, dt)
		S.SCREAM:
			_scream(dt)
		S.WANDER, S.INVESTIGATE, S.SEARCH:
			desired = _nav_dir() * _speed
		S.CHASE:
			var spd := _speed * (0.35 if _crawler else 1.0)
			desired = _nav_dir() * spd
		S.CIRCLE:
			desired = _circle_velocity(dt)
		S.ATTACK:
			_attack(dt)
		S.CHARGE:
			desired = _charge(dt)
		S.STAGGER:
			if _t > 0.6 * (1.4 if is_heavy else 1.0):
				_enter(S.CHASE)
		S.KNOCKDOWN:
			if _t > 1.5:
				model.set_param("down/transition_request", "up")
			if _t > 2.2:
				_enter(S.CHASE)
	# steering / facing
	_cur_speed = FeelMath.damp(_cur_speed, desired.length(), 6.0, dt)
	if desired.length() > 0.1 and state != S.ATTACK:
		_face_toward(global_position + desired, 6.0 if data.archetype != ZombieData.Archetype.BRUTE else 3.0, dt)
	var v := desired + _push
	_push = _push.move_toward(Vector3.ZERO, 12.0 * dt)
	if agent.avoidance_enabled and state in [S.CHASE, S.CIRCLE, S.WANDER, S.INVESTIGATE, S.SEARCH]:
		agent.velocity = Vector3(v.x, 0.0, v.z)
	else:
		_apply_velocity(v, dt)
	_check_stuck(dt)


func _on_velocity_computed(safe: Vector3) -> void:
	if state == S.DEAD:
		return
	_apply_velocity(safe, get_physics_process_delta_time())


func _apply_velocity(v: Vector3, dt: float) -> void:
	velocity.x = v.x
	velocity.z = v.z
	velocity.y = velocity.y - GRAVITY * dt if not is_on_floor() else -1.0
	move_and_slide()


func _scream(dt: float) -> void:
	if target:
		_face_toward(target.global_position, 4.0, dt)
	if _t >= SCREAM_TIME * 0.45 and _t - dt < SCREAM_TIME * 0.45:
		Sfx.play_at(&"screech", global_position + Vector3.UP * 1.7, 8.0, 0.05)
		NoiseBus.emit_noise(global_position, SCREAM_RADIUS, NoiseBus.Priority.ALARM, self)
	if _t >= SCREAM_TIME:
		_scream_cd = 10.0
		_enter(S.CHASE)


func _attack(dt: float) -> void:
	if target:
		_face_toward(target.global_position, 8.0 if _t < data.attack_windup * 0.8 else 1.0, dt)
	if data.lunge_speed > 0.0 and _t > data.attack_windup * 0.5 and _t < data.attack_windup:
		_push = Vector3(-sin(_facing), 0, -cos(_facing)) * data.lunge_speed
	if not _attack_hit_done and _t >= data.attack_windup:
		_attack_hit_done = true
		if target and target.is_targetable():
			var to := target.global_position - global_position
			to.y = 0.0
			var fwd := Vector3(-sin(_facing), 0, -cos(_facing))
			if to.length() < data.attack_range + 0.45 and rad_to_deg(fwd.angle_to(to.normalized())) < 55.0:
				if target.take_damage(data.attack_damage, self, to.normalized()):
					Sfx.play_at(&"flesh_hit", target.global_position + Vector3.UP, -2.0)
	if _t >= data.attack_windup + data.attack_recover:
		_release_slot()
		_enter(S.CHASE)


func _charge(dt: float) -> Vector3:
	if _t < 0.9:
		if target:
			_charge_dir = ((target.global_position - global_position) * Vector3(1, 0, 1)).normalized()
			_face_toward(global_position + _charge_dir, 5.0, dt)
		return Vector3.ZERO
	var v := _charge_dir * data.charge_speed
	if target and target.is_targetable() and global_position.distance_to(target.global_position) < 1.6:
		if target.take_damage(data.attack_damage, self, _charge_dir) and target is CharacterBody3D:
			target.velocity += _charge_dir * 8.0 + Vector3.UP * 3.0
			Sfx.play_at(&"melee_hit", target.global_position, 2.0)
		_enter(S.CHASE)
	if _t > 3.0 or (is_on_wall() and _t > 1.1):
		if is_on_wall():
			_enter(S.STAGGER)
			model.set_param("stagger_ts/scale", 0.6)
			model.fire(&"stagger")
		else:
			_enter(S.CHASE)
	return v


func _circle_velocity(dt: float) -> Vector3:
	if target == null:
		return Vector3.ZERO
	_circle_t += dt
	var to_me := global_position - target.global_position
	to_me.y = 0.0
	var d := to_me.length()
	var radius := 3.6 + _circle_offset * 0.8
	var tangent := Vector3.UP.cross(to_me.normalized()) * signf(_circle_offset + 0.01)
	var radial := to_me.normalized() * clampf(radius - d, -1.0, 1.0)
	var drift := tangent * (0.5 + 0.3 * sin(_circle_t * 0.7 + _circle_offset * 4.0))
	_face_toward(target.global_position, 5.0, dt)
	if _rng.randf() < 0.01:
		_has_slot = AttackSlots.request(self)
		if _has_slot:
			_enter(S.CHASE)
	return (radial + drift).limit_length(1.0) * data.walk_speed * _walk_scale


func _check_stuck(dt: float) -> void:
	if state not in [S.CHASE, S.INVESTIGATE, S.WANDER, S.SEARCH] or _speed < 0.3:
		_stuck_t = 0.0
		_last_pos = global_position
		return
	_stuck_t += dt
	if _stuck_t > 1.5:
		if global_position.distance_to(_last_pos) < 0.3:
			var side := Vector3(-sin(_facing + PI * 0.5), 0, -cos(_facing + PI * 0.5)) * (1.0 if _rng.randf() < 0.5 else -1.0)
			_push = side * 1.6
			if state == S.WANDER:
				_pick_wander()
		_stuck_t = 0.0
		_last_pos = global_position


# ------------------------------------------------------------------ navigation helpers

func _pick_wander() -> void:
	var a := _rng.randf() * TAU
	var r := _rng.randf_range(3.0, 9.0)
	_move_target = _home + Vector3(cos(a) * r, 0, sin(a) * r)
	_set_nav(_move_target)


func _set_nav(p: Vector3) -> void:
	_move_target = p
	agent.target_position = p


func _nav_dir() -> Vector3:
	var next := _move_target
	if not agent.is_navigation_finished():
		var p := agent.get_next_path_position()
		if agent.get_current_navigation_path().size() > 1 and p.distance_to(global_position) > 0.05:
			next = p
	var d := next - global_position
	d.y = 0.0
	if d.length() < 0.15:
		return Vector3.ZERO
	return d.normalized()


func _face_toward(p: Vector3, rate: float, dt: float) -> void:
	var d := p - global_position
	d.y = 0.0
	if d.length() < 0.05:
		return
	_facing = FeelMath.damp_angle(_facing, atan2(-d.x, -d.z), rate, dt)


# ------------------------------------------------------------------ damage

## Returns {"killed": bool} or {} if ignored.
func take_hit(info: Dictionary) -> Dictionary:
	if state == S.DEAD:
		return {}
	var dmg: float = info.damage
	var zone: StringName = info.get("zone", &"torso")
	var power: float = info.get("power", 1.0)
	var dir: Vector3 = info.get("dir", Vector3.ZERO)
	health -= dmg
	var src: Variant = info.get("source")
	if src is Node3D and src.has_method("is_targetable"):
		target = src
	_hitstop = 0.045 if info.get("melee", false) else 0.03
	_flash = 1.0
	_suspicion = 1.5
	if target:
		_last_known = target.global_position
	Sfx.play_at(&"flesh_hit", global_position + Vector3.UP * 1.2, -6.0, 0.15)
	if health <= 0.0:
		_die(dir, power)
		return {"killed": true}
	if zone == &"legs" and data.archetype == ZombieData.Archetype.WALKER:
		_leg_hp -= dmg
		if _leg_hp <= 0.0 and not _crawler:
			_crawler = true
			model.set_param("crawl/blend_amount", 1.0)
	# reaction: knockdown > stagger > flinch
	var flat_dir := Vector3(dir.x, 0, dir.z).normalized()
	if power >= data.knock_threshold:
		_push = flat_dir * float(info.get("knockback", 1.0)) * 2.0
		_knockdown()
	elif power >= data.stagger_threshold:
		_push = flat_dir * float(info.get("knockback", 0.5)) * 2.5
		if state == S.ATTACK:
			model.abort(_attack_shot)
		_enter(S.STAGGER)
		model.set_param("stagger_ts/scale", 1.4)
		model.fire(&"stagger")
	else:
		model.set_param("%s_ts/scale" % (&"hit_head" if zone == &"head" else &"hit"), 1.6)
		model.fire(&"hit_head" if zone == &"head" else &"hit")
		_push += flat_dir * float(info.get("knockback", 0.3))
		if state in [S.IDLE, S.WANDER, S.SUSPICIOUS, S.INVESTIGATE, S.SEARCH]:
			_enter(S.CHASE)
	# directional flinch on the spine/head
	_flinch_axis = Vector3.UP.cross(flat_dir).normalized() if flat_dir.length() > 0.1 else Vector3.RIGHT
	_flinch.impulse((2.0 if zone == &"head" else 1.2) * 8.0)
	return {"killed": false}


func _knockdown() -> void:
	if state == S.ATTACK:
		model.abort(_attack_shot)
	_enter(S.KNOCKDOWN)
	model.set_param("down/transition_request", "down")


func receive_vehicle_hit(_bike: Node, vel: Vector3, speed: float) -> void:
	if state == S.DEAD:
		return
	var flat := Vector3(vel.x, 0, vel.z).normalized()
	if is_heavy:
		_push = flat * 1.5
		return
	if speed >= 8.3:
		take_hit({"damage": speed * 5.5, "zone": &"torso", "dir": flat, "power": 3.0, "knockback": 2.0})
		_push = flat * speed * 0.5 + Vector3.UP * 2.0
		velocity.y = 4.0
	else:
		take_hit({"damage": speed * 3.0, "zone": &"torso", "dir": flat, "power": 1.0, "knockback": 1.0})
		_push = flat * 3.0 + Vector3(flat.z, 0, -flat.x) * 1.5


func push(v: Vector3) -> void:
	_push += v


func _die(dir: Vector3, power: float) -> void:
	_release_slot()
	state = S.DEAD
	_t = 0.0
	remove_from_group(&"enemy")
	collision_layer = 0
	collision_mask = 1
	hitboxes.disable()
	agent.avoidance_enabled = false
	model.set_param("down/transition_request", "down")
	_push = Vector3(dir.x, 0, dir.z).normalized() * (1.0 + power)
	died.emit(self)
	EventBus.enemy_killed.emit(self, &"")
	get_tree().create_timer(25.0).timeout.connect(queue_free)


func _release_slot() -> void:
	if _has_slot:
		AttackSlots.release(self)
		_has_slot = false


# ------------------------------------------------------------------ animation (manual advance = LOD + hit-stop)

func _animate(dt: float) -> void:
	if state == S.DEAD:
		_push = _push.move_toward(Vector3.ZERO, 6.0 * dt)
		velocity.x = _push.x
		velocity.z = _push.z
	model.rotation.y = _facing
	var ref := data.anim_walk_ref
	var spd := _cur_speed
	model.set_param("loco/blend_position", spd if data.archetype == ZombieData.Archetype.RUNNER else spd * (1.45 / ref))
	model.set_param("loco_ts/scale", (0.8 if spd < 1.5 else 1.0) * (1.0 / data.model_scale))
	var fl := _flinch.step(0.0, dt)
	if absf(fl) > 0.001:
		var axis_skel := (model.global_basis.inverse() * _flinch_axis).normalized()
		model.offsets.set_layer(&"flinch", {"DEF-spine.003": Quaternion(axis_skel, fl * 0.12), "DEF-neck": Quaternion(axis_skel, fl * 0.2)})
	if _flash > 0.0:
		_flash = maxf(_flash - dt * 8.0, 0.0)
		model.mesh_instance.set_instance_shader_parameter(&"hit_flash", _flash * 0.5)
	if _hitstop > 0.0:
		return
	_anim_acc += dt
	if _frame % _anim_div == 0:
		model.tree.advance(_anim_acc)
		_anim_acc = 0.0
	if state != S.DEAD and _lod < 2:
		hitboxes.sync()
