class_name Raider
extends CharacterBody3D

## Hostile human: Patrol → Alert → Combat (cover, peek, burst fire) → Flee.
## Shoots the player and any zombie that gets close, makes combat noise that
## draws more zombies — the three-way conflict comes from these rules alone.

signal died(r: Raider)

enum R { PATROL, ALERT, COMBAT, FLEE, DEAD }
enum Phase { MOVE, HIDE, PEEK, OPEN }

const GRAVITY := 20.0
const SIGHT := 30.0
const FOV_DEG := 120.0
const ZOMBIE_SIGHT := 20.0
const MAG := 20
const SHOT_GAP := 0.32
const DAMAGE_PLAYER := 9.0
const DAMAGE_ZOMBIE := 32.0
const NOISE := 55.0

@export var patrol: PackedVector3Array = []
@export var max_health := 120.0

var state: int = R.PATROL
var health := 120.0
var model: CharacterModel
var agent: NavigationAgent3D
var hitboxes: HitboxSet
var target: Node3D
var player: Player

var _t := 0.0
var _think_t := 0.0
var _facing := 0.0
var _speed := 0.0
var _cur_speed := 0.0
var _move_target := Vector3.ZERO
var _push := Vector3.ZERO
var _wp := 0
var _wait := 0.0
var _suspicion := 0.0
var _last_known := Vector3.ZERO
var _sees_target := false
var _unseen_t := 0.0
var _phase := Phase.OPEN
var _phase_t := 0.0
var _cover := Vector3.ZERO
var _has_cover := false
var _cover_t := 0.0
var _burst := 0
var _shot_t := 0.0
var _mag := MAG
var _reload_t := 0.0
var _crouch := 0.0
var _muzzle: Node3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	health = max_health
	add_to_group(&"raider")
	add_to_group(&"enemy")
	collision_layer = 8
	collision_mask = 1 | 2 | 4 | 8
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	add_child(cs)
	_build_model()
	hitboxes = HitboxSet.new(self, model)
	hitboxes.build_humanoid(1.0)
	agent = NavigationAgent3D.new()
	agent.radius = 0.4
	agent.height = 1.8
	agent.path_desired_distance = 0.6
	agent.target_desired_distance = 0.5
	add_child(agent)
	_facing = rotation.y
	rotation.y = 0.0
	_think_t = _rng.randf() * 0.15
	NoiseBus.noise_emitted.connect(_on_noise)
	_enter(R.PATROL)


func _build_model() -> void:
	model = CharacterModel.new()
	model.name = "Model"
	add_child(model)
	model.setup({
		"skin_color": [Color("9c7a62"), Color("7d5a45"), Color("b08d74")][_rng.randi() % 3],
		"top_color": [Color("5a2620"), Color("3b3a2c"), Color("4a2d24")][_rng.randi() % 3],
		"bottom_color": Color("26282a"),
		"boot_color": Color("1a1715"),
		"sleeves": 1.0,
		"grime": 0.6,
		"decay": 0.0,
		"seed": _rng.randf() * 50.0,
	})
	var M := CharacterModel
	var bt := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace1D.new()
	loco.add_blend_point(M.anim(&"Idle"), 0.0, -1, &"Idle")
	loco.add_blend_point(M.anim(&"Walk"), 1.6, -1, &"Walk")
	loco.add_blend_point(M.anim(&"Jog_Fwd"), 4.0, -1, &"Jog_Fwd")
	loco.add_blend_point(M.anim(&"Sprint"), 6.0, -1, &"Sprint")
	loco.max_space = 6.5
	loco.sync = true
	bt.add_node(&"loco", loco)
	bt.add_node(&"crouch_anim", M.anim(&"Crouch_Idle"))
	bt.add_node(&"crouch", AnimationNodeBlend2.new())
	bt.connect_node(&"crouch", 0, &"loco")
	bt.connect_node(&"crouch", 1, &"crouch_anim")
	bt.add_node(&"gun_idle", M.anim(&"Pistol_Idle"))
	bt.add_node(&"gun_aim_anim", M.anim(&"Pistol_Aim_Neutral"))
	bt.add_node(&"gun_aim", AnimationNodeBlend2.new())
	bt.connect_node(&"gun_aim", 0, &"gun_idle")
	bt.connect_node(&"gun_aim", 1, &"gun_aim_anim")
	var upper := AnimationNodeBlend2.new()
	model.upper_filter(upper)
	bt.add_node(&"upper", upper)
	bt.connect_node(&"upper", 0, &"crouch")
	bt.connect_node(&"upper", 1, &"gun_aim")
	var prev := &"upper"
	for s in [[&"shoot", &"Pistol_Shoot"], [&"reload", &"Pistol_Reload"], [&"hit", &"Hit_Chest"]]:
		var o := M.one_shot(0.04, 0.12)
		model.upper_filter(o)
		bt.add_node(s[0], o)
		bt.add_node(StringName(String(s[0]) + "_anim"), M.anim(s[1]))
		bt.connect_node(s[0], 0, prev)
		bt.connect_node(s[0], 1, StringName(String(s[0]) + "_anim"))
		prev = s[0]
	var life := AnimationNodeTransition.new()
	life.add_input("alive")
	life.add_input("dead")
	life.xfade_time = 0.2
	bt.add_node(&"life", life)
	bt.add_node(&"death", M.anim(&"Death01"))
	bt.connect_node(&"life", 0, prev)
	bt.connect_node(&"life", 1, &"death")
	bt.connect_node(&"output", 0, &"life")
	model.make_tree(bt)
	model.set_param("upper/blend_amount", 1.0)
	model.set_param("life/transition_request", "alive")
	# bandana + carbine: reads "human, armed" at distance
	var head := model.bone_rest_origin("DEF-head")
	var cloth := Node3D.new()
	MeshKit.box(cloth, Vector3(0.24, 0.1, 0.26), Vector3.ZERO, Palette.pbr(Color("7a2a20"), 0.9, 0.0))
	model.attach_rigid("DEF-head", cloth, Transform3D(Basis.IDENTITY, head + Vector3(0, 0.03, 0.0)))
	var hand := model.bone_rest_origin("DEF-hand.R")
	var socket := Node3D.new()
	model.attach_rigid("DEF-hand.R", socket, Transform3D(Basis(Vector3.UP, PI * 0.5), hand + Vector3(-0.075, -0.025, 0.0)))
	var gun := WeaponModels.build(WeaponData.carbine())
	socket.add_child(gun)
	_muzzle = gun.get_node_or_null("Muzzle")
	model.rotation.y = _facing


# ------------------------------------------------------------------ interface shared with Player (zombie prey)

func is_alive() -> bool:
	return state != R.DEAD


func is_targetable() -> bool:
	return state != R.DEAD


func is_riding() -> bool:
	return false


func target_point() -> Vector3:
	return global_position + Vector3.UP * lerpf(1.4, 0.9, _crouch)


func planar_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func push(v: Vector3) -> void:
	_push += v


# ------------------------------------------------------------------ loop

func _physics_process(dt: float) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group(&"player") as Player
	_t += dt
	if state == R.DEAD:
		velocity = Vector3(0, velocity.y - GRAVITY * dt, 0)
		move_and_slide()
		return
	_think_t -= dt
	if _think_t <= 0.0:
		_think_t = 0.15
		_think(0.15)
	var desired := _act(dt)
	_cur_speed = FeelMath.damp(_cur_speed, desired.length(), 8.0, dt)
	var v := desired + _push
	_push = _push.move_toward(Vector3.ZERO, 10.0 * dt)
	velocity.x = v.x
	velocity.z = v.z
	velocity.y = velocity.y - GRAVITY * dt if not is_on_floor() else -1.0
	move_and_slide()
	_animate(dt)


func _think(dt: float) -> void:
	_perceive(dt)
	match state:
		R.PATROL:
			if _suspicion >= 1.0:
				_enter(R.COMBAT)
			elif _suspicion > 0.35:
				_enter(R.ALERT)
		R.ALERT:
			if _sees_target and _suspicion >= 1.0:
				_enter(R.COMBAT)
			elif global_position.distance_to(_last_known) < 2.0 and _t > 3.0 or _t > 14.0:
				_enter(R.PATROL)
		R.COMBAT:
			if _should_flee():
				_enter(R.FLEE)
				return
			_unseen_t = 0.0 if _sees_target else _unseen_t + dt
			if _unseen_t > 5.0:
				_enter(R.ALERT)
				return
			_cover_t -= dt
			if _cover_t <= 0.0 or (_has_cover and target and target.global_position.distance_to(_cover) < 4.0):
				_pick_cover()
		R.FLEE:
			if _t > 9.0 or global_position.distance_to(_move_target) < 2.0:
				_enter(R.ALERT if _threat_count(14.0) > 0 else R.PATROL)


## Zombies within 20 m are always hostile; the player builds suspicion first.
func _perceive(dt: float) -> void:
	_sees_target = false
	var best: Node3D = null
	var best_d := INF
	for z in get_tree().get_nodes_in_group(&"enemy"):
		if not z is Zombie or not z.is_alive():
			continue
		var d := global_position.distance_to(z.global_position)
		if d < ZOMBIE_SIGHT and d < best_d and _los(z.global_position + Vector3.UP * 1.3):
			best_d = d
			best = z
	var sees_player := false
	if player and player.is_targetable():
		var to := player.target_point() - (global_position + Vector3.UP * 1.6)
		var d := to.length()
		var fwd := Vector3(-sin(_facing), 0, -cos(_facing))
		var in_cone := rad_to_deg(fwd.angle_to(Vector3(to.x, 0, to.z).normalized())) < FOV_DEG * 0.5 or d < 3.0
		if d < SIGHT and (in_cone or state == R.COMBAT) and _los(player.target_point()):
			sees_player = true
			_suspicion += dt * (1.0 + 3.0 * (1.0 - d / SIGHT)) * (1.6 if player.is_riding() else 1.0)
			# a close zombie is the more urgent target
			if best == null or best_d > 9.0:
				best = player
				best_d = d
	if not sees_player:
		_suspicion = maxf(_suspicion - dt * 0.15, 0.0)
	if best is Zombie:
		_suspicion = maxf(_suspicion, 1.0)
	_suspicion = minf(_suspicion, 1.5)
	if best and (best is Zombie or _suspicion >= 1.0 or state == R.COMBAT):
		target = best
		_sees_target = true
		_last_known = best.global_position
	elif best != null and best == player:
		_last_known = player.global_position


func _los(p: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.5, p, 1)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _on_noise(pos: Vector3, radius: float, priority: int, source: Node) -> void:
	if state == R.DEAD or source is Raider or global_position.distance_to(pos) > radius:
		return
	if state == R.PATROL or (state == R.ALERT and priority >= NoiseBus.Priority.COMBAT):
		_last_known = pos
		_suspicion = maxf(_suspicion, 0.5)
		_enter(R.ALERT)


func _should_flee() -> bool:
	return health < max_health * 0.25 or _threat_count(8.0) >= 4


func _threat_count(r: float) -> int:
	var n := 0
	for z in get_tree().get_nodes_in_group(&"enemy"):
		if z is Zombie and z.is_alive() and global_position.distance_to(z.global_position) < r:
			n += 1
	return n


## Best cover: close to me, blocks a crouched line to the target, open when standing.
func _pick_cover() -> void:
	_cover_t = 5.0
	_has_cover = false
	if target == null:
		return
	var aim := target.global_position + Vector3.UP * 1.3
	var space := get_world_3d().direct_space_state
	var best_score := INF
	var pts := get_tree().get_nodes_in_group(&"cover_point")
	for c in pts:
		var p: Vector3 = c.global_position
		var d := global_position.distance_to(p)
		var td := p.distance_to(target.global_position)
		if d > 18.0 or td < 5.0 or td > 35.0:
			continue
		var low := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.8, aim, 1)
		if space.intersect_ray(low).is_empty():
			continue
		var score := d + absf(td - 14.0) * 0.4
		if score < best_score:
			best_score = score
			_cover = p
			_has_cover = true
	_phase = Phase.MOVE if _has_cover else Phase.OPEN
	_phase_t = 0.0


# ------------------------------------------------------------------ states

func _enter(s: int) -> void:
	if state == R.DEAD:
		return
	state = s
	_t = 0.0
	match s:
		R.PATROL:
			_speed = 1.5
			_suspicion = minf(_suspicion, 0.3)
			_next_waypoint()
		R.ALERT:
			_speed = 2.6
			_set_nav(_last_known)
		R.COMBAT:
			_speed = 4.0
			_unseen_t = 0.0
			_pick_cover()
		R.FLEE:
			_speed = 5.6
			var away := global_position - _threat_center()
			away.y = 0.0
			_set_nav(global_position + away.normalized() * 30.0)


func _act(dt: float) -> Vector3:
	_shot_t -= dt
	if _reload_t > 0.0:
		_reload_t -= dt
		if _reload_t <= 0.0:
			_mag = MAG
	match state:
		R.PATROL:
			_crouch = FeelMath.damp(_crouch, 0.0, 6.0, dt)
			if _wait > 0.0:
				_wait -= dt
				return Vector3.ZERO
			if global_position.distance_to(_move_target) < 1.0:
				_wait = _rng.randf_range(1.5, 3.5)
				_next_waypoint()
			return _steer(_speed, dt)
		R.ALERT:
			_face_toward(_last_known, 4.0, dt)
			return _steer(_speed, dt) if global_position.distance_to(_last_known) > 2.0 else Vector3.ZERO
		R.COMBAT:
			return _combat(dt)
		R.FLEE:
			_crouch = 0.0
			return _steer(_speed, dt)
	return Vector3.ZERO


func _combat(dt: float) -> Vector3:
	_phase_t += dt
	var aim_at := target.global_position if target and is_instance_valid(target) else _last_known
	var close := target != null and is_instance_valid(target) and global_position.distance_to(target.global_position) < 3.0
	if close:
		_phase = Phase.OPEN
	match _phase:
		Phase.MOVE:
			_crouch = FeelMath.damp(_crouch, 0.0, 8.0, dt)
			_set_nav(_cover)
			if global_position.distance_to(_cover) < 0.8:
				_phase = Phase.HIDE
				_phase_t = 0.0
			else:
				return _steer(_speed, dt)
		Phase.HIDE:
			_crouch = FeelMath.damp(_crouch, 1.0, 8.0, dt)
			_face_toward(aim_at, 5.0, dt)
			if _phase_t > _rng.randf_range(1.2, 2.2) and _reload_t <= 0.0:
				_phase = Phase.PEEK
				_phase_t = 0.0
				_burst = _rng.randi_range(3, 5)
			return Vector3.ZERO
		Phase.PEEK:
			_crouch = FeelMath.damp(_crouch, 0.0, 10.0, dt)
			_face_toward(aim_at, 8.0, dt)
			if _phase_t > 0.35:
				_try_fire()
			if _burst <= 0 or _phase_t > 3.0:
				_phase = Phase.HIDE
				_phase_t = 0.0
			return Vector3.ZERO
		Phase.OPEN:
			_crouch = FeelMath.damp(_crouch, 0.0, 8.0, dt)
			_face_toward(aim_at, 8.0, dt)
			if _sees_target:
				if _burst <= 0:
					_burst = _rng.randi_range(3, 5) if _phase_t > 1.0 else 0
					if _burst > 0:
						_phase_t = 0.0
				_try_fire()
			# back off from anything in arm's reach, otherwise hold position
			if close:
				var away := (global_position - aim_at) * Vector3(1, 0, 1)
				return away.normalized() * 2.4
			if not _sees_target:
				_set_nav(_last_known)
				return _steer(2.6, dt)
	return Vector3.ZERO


func _try_fire() -> void:
	if _shot_t > 0.0 or _reload_t > 0.0 or target == null or not is_instance_valid(target) or not _sees_target:
		return
	if _mag <= 0:
		_reload_t = 2.2
		model.fire(&"reload")
		return
	_shot_t = SHOT_GAP * _rng.randf_range(0.9, 1.3)
	_mag -= 1
	_burst -= 1
	_fire_at(target)


func _fire_at(t: Node3D) -> void:
	var from := _muzzle.global_position if _muzzle else global_position + Vector3.UP * 1.4
	var aim: Vector3 = t.target_point() if t.has_method("target_point") else t.global_position + Vector3.UP * 1.3
	var d := from.distance_to(aim)
	var spd := Vector2(t.velocity.x, t.velocity.z).length() if t is CharacterBody3D else 0.0
	var chance := clampf(0.78 - d / 45.0 - spd * 0.05, 0.12, 0.85)
	if t is Player and t.is_riding():
		chance *= 0.6
	var hit := _rng.randf() < chance
	var dir := (aim - from).normalized()
	var end := aim
	if not hit:
		var miss := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.4, 0.8), _rng.randf_range(-1, 1)).normalized() * _rng.randf_range(0.6, 1.6)
		var q := PhysicsRayQueryParameters3D.create(from, from + (aim + miss - from).normalized() * 60.0, 1)
		q.exclude = [get_rid()]
		var r := get_world_3d().direct_space_state.intersect_ray(q)
		end = r.position if not r.is_empty() else from + (aim + miss - from).normalized() * 60.0
		if not r.is_empty() and Fx.instance:
			Fx.instance.impact(end, r.normal, false)
	elif t is Zombie:
		t.take_hit({"damage": DAMAGE_ZOMBIE, "zone": &"torso", "dir": dir, "point": aim, "power": 0.8, "knockback": 0.5, "source": self})
		if Fx.instance:
			Fx.instance.impact(aim, -dir, true)
	else:
		t.take_damage(DAMAGE_PLAYER, self, dir)
	if Fx.instance:
		Fx.instance.tracer(from, end)
	if _muzzle and Fx.instance:
		Fx.instance.muzzle_flash(_muzzle.global_transform, 0.9)
	model.fire(&"shoot")
	Sfx.play_at(&"carbine", from, -1.0, 0.08)
	NoiseBus.emit_noise(global_position, NOISE, NoiseBus.Priority.COMBAT, self)


# ------------------------------------------------------------------ damage

## Zombie claws and brute charges.
func take_damage(amount: float, source: Node, _dir := Vector3.ZERO, _ignore := false) -> bool:
	if state == R.DEAD:
		return false
	health -= amount
	model.fire(&"hit")
	if source is Node3D:
		target = source
		_last_known = source.global_position
	if health <= 0.0:
		_die()
	elif state != R.FLEE:
		_enter(R.FLEE if _should_flee() else R.COMBAT)
	return true


## Player bullets / melee / bike.
func take_hit(info: Dictionary) -> Dictionary:
	if state == R.DEAD:
		return {}
	health -= float(info.damage)
	Sfx.play_at(&"flesh_hit", global_position + Vector3.UP * 1.2, -6.0, 0.15)
	model.fire(&"hit")
	_push += Vector3(info.get("dir", Vector3.ZERO)).normalized() * float(info.get("knockback", 0.3))
	var src: Variant = info.get("source")
	if src is Node3D:
		target = src
		_last_known = src.global_position
		_suspicion = 1.5
	if health <= 0.0:
		_die()
		return {"killed": true}
	if state != R.FLEE and _should_flee():
		_enter(R.FLEE)
	elif state in [R.PATROL, R.ALERT]:
		_enter(R.COMBAT)
	return {"killed": false}


func receive_vehicle_hit(_bike: Node, vel: Vector3, speed: float) -> void:
	take_hit({"damage": speed * 6.0, "zone": &"torso", "dir": vel, "knockback": 2.0, "source": player})


func _die() -> void:
	state = R.DEAD
	_t = 0.0
	remove_from_group(&"raider")
	remove_from_group(&"enemy")
	collision_layer = 0
	collision_mask = 1
	hitboxes.disable()
	model.set_param("life/transition_request", "dead")
	var drop := LootPoint.new()
	drop.kind = &"cache"
	drop.table = &"raider"
	drop.label = "Haydut çantası"
	drop.position = global_position + Vector3(0.4, 0.05, 0.3)
	get_parent().add_child.call_deferred(drop)
	died.emit(self)
	EventBus.enemy_killed.emit(self, &"")


# ------------------------------------------------------------------ helpers

func _next_waypoint() -> void:
	if patrol.is_empty():
		_set_nav(global_position)
		return
	_wp = (_wp + 1) % patrol.size()
	_set_nav(patrol[_wp])


func _threat_center() -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for z in get_tree().get_nodes_in_group(&"enemy"):
		if z is Zombie and z.is_alive() and global_position.distance_to(z.global_position) < 20.0:
			sum += z.global_position
			n += 1
	if target and is_instance_valid(target):
		sum += target.global_position
		n += 1
	return sum / n if n > 0 else global_position + Vector3.FORWARD


func _set_nav(p: Vector3) -> void:
	_move_target = p
	agent.target_position = p


func _steer(speed: float, dt: float) -> Vector3:
	var next := _move_target
	if not agent.is_navigation_finished():
		var p := agent.get_next_path_position()
		if agent.get_current_navigation_path().size() > 1 and p.distance_to(global_position) > 0.05:
			next = p
	var d := next - global_position
	d.y = 0.0
	if d.length() < 0.2:
		return Vector3.ZERO
	if state != R.COMBAT or not _sees_target:
		_face_toward(global_position + d, 7.0, dt)
	return d.normalized() * speed


func _face_toward(p: Vector3, rate: float, dt: float) -> void:
	var d := p - global_position
	d.y = 0.0
	if d.length() > 0.05:
		_facing = FeelMath.damp_angle(_facing, atan2(-d.x, -d.z), rate, dt)


func _animate(dt: float) -> void:
	model.rotation.y = _facing
	model.set_param("loco/blend_position", _cur_speed)
	model.set_param("crouch/blend_amount", _crouch)
	var aiming := state == R.COMBAT and _phase in [Phase.PEEK, Phase.OPEN]
	var cur: float = model.tree.get("parameters/gun_aim/blend_amount")
	model.set_param("gun_aim/blend_amount", FeelMath.damp(cur if cur != null else 0.0, 1.0 if aiming else 0.0, 10.0, dt))
	hitboxes.sync()
