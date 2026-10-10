class_name ZombieData
extends Resource

enum Archetype { WALKER, RUNNER, BRUTE, SCREAMER }

@export var archetype: int = Archetype.WALKER
@export var health := 100.0
@export var walk_speed := 1.1
@export var walk_speed_var := 0.25
@export var chase_speed := 1.5
@export var anim_walk_ref := 1.45       ## m/s the Walk clip covers at 1x
@export var attack_range := 1.45
@export var attack_windup := 0.45
@export var attack_recover := 0.55
@export var attack_damage := 12.0
@export var lunge_speed := 0.0
@export var sight_range := 18.0
@export var fov_deg := 110.0
@export var hearing := 1.0
@export var stagger_threshold := 0.7    ## hit power needed to interrupt
@export var knock_threshold := 1.8
@export var is_heavy := false
@export var model_scale := 1.0
@export var charge_speed := 0.0


static func walker() -> ZombieData:
	return ZombieData.new()

static func runner() -> ZombieData:
	var d := ZombieData.new()
	d.archetype = Archetype.RUNNER
	d.health = 70.0
	d.walk_speed = 1.3
	d.chase_speed = 5.0
	d.attack_range = 1.6
	d.attack_windup = 0.3
	d.attack_recover = 0.7
	d.attack_damage = 10.0
	d.lunge_speed = 4.5
	d.sight_range = 22.0
	d.hearing = 1.3
	d.stagger_threshold = 0.5
	d.knock_threshold = 1.6
	return d

static func brute() -> ZombieData:
	var d := ZombieData.new()
	d.archetype = Archetype.BRUTE
	d.health = 450.0
	d.walk_speed = 1.0
	d.walk_speed_var = 0.1
	d.chase_speed = 1.6
	d.attack_range = 1.9
	d.attack_windup = 0.9
	d.attack_recover = 1.0
	d.attack_damage = 30.0
	d.sight_range = 16.0
	d.hearing = 0.8
	d.stagger_threshold = 1.9
	d.knock_threshold = 99.0
	d.is_heavy = true
	d.model_scale = 1.32
	d.charge_speed = 7.0
	return d

## Fragile alarm: on sight it screams (60 m alarm noise), then keeps its distance.
static func screamer() -> ZombieData:
	var d := ZombieData.new()
	d.archetype = Archetype.SCREAMER
	d.health = 60.0
	d.walk_speed = 1.0
	d.chase_speed = 2.2
	d.attack_damage = 6.0
	d.sight_range = 24.0
	d.fov_deg = 150.0
	d.hearing = 1.2
	d.stagger_threshold = 0.3
	d.knock_threshold = 1.2
	d.model_scale = 0.97
	return d
