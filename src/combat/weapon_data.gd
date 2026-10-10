class_name WeaponData
extends Resource

## Data-driven weapon definition. Feel lives in recoil/kick/sound, not only damage.

enum Kind { PISTOL, CARBINE, SHOTGUN, MELEE }

@export var id: StringName
@export var display_name := ""
@export var kind: int = Kind.PISTOL
@export var mag_size := 12
@export var reserve_start := 48
@export var fire_interval := 0.18
@export var automatic := false
@export var damage := 34.0
@export var pellets := 1
@export var spread_deg := 0.6          ## hip spread (aimed = 35%)
@export var falloff_start := 20.0
@export var falloff_end := 45.0
@export var falloff_min := 0.5
@export var head_mult := 2.5
@export var leg_mult := 0.7
@export var range := 80.0
@export var reload_time := 1.3
@export var reload_empty_time := 1.3
@export var per_shell_reload := false
@export var noise_radius := 45.0
@export_group("Feel")
@export var recoil_pitch := 1.2        ## permanent aim climb per shot (deg)
@export var recoil_yaw := 0.25         ## random +- (deg)
@export var recoil_yaw_bias := 0.0     ## pattern drift (deg)
@export var kick_pitch := 2.0          ## camera spring kick (deg)
@export var kick_fov := 0.0
@export var shake := 0.08
@export var body_kick := 6.0           ## upper body recoil (deg)
@export var stagger_power := 1.0       ## 0 = flinch only, 1 = can stagger, 2 = knock down light
@export var knockback := 0.5
@export_group("Melee")
@export var combo_times := PackedFloat32Array()
@export var combo_damage := PackedFloat32Array()
@export var reach := 1.7
@export var arc_deg := 100.0


static func pistol() -> WeaponData:
	var w := WeaponData.new()
	w.id = &"pistol"
	w.display_name = "M-11 Pistol"
	w.kind = Kind.PISTOL
	w.mag_size = 12
	w.reserve_start = 60
	w.fire_interval = 0.18
	w.damage = 34.0
	w.spread_deg = 0.9
	w.head_mult = 2.5
	w.reload_time = 1.3
	w.reload_empty_time = 1.5
	w.noise_radius = 45.0
	w.recoil_pitch = 1.1
	w.recoil_yaw = 0.35
	w.kick_pitch = 2.2
	w.shake = 0.07
	w.body_kick = 7.0
	w.stagger_power = 0.4
	w.knockback = 0.3
	return w

static func carbine() -> WeaponData:
	var w := WeaponData.new()
	w.id = &"carbine"
	w.display_name = "Scav Carbine"
	w.kind = Kind.CARBINE
	w.mag_size = 24
	w.reserve_start = 96
	w.fire_interval = 0.11
	w.automatic = true
	w.damage = 28.0
	w.spread_deg = 1.6
	w.falloff_start = 30.0
	w.falloff_end = 70.0
	w.head_mult = 2.0
	w.range = 120.0
	w.reload_time = 2.1
	w.reload_empty_time = 2.6
	w.noise_radius = 60.0
	w.recoil_pitch = 0.75
	w.recoil_yaw = 0.3
	w.recoil_yaw_bias = 0.18
	w.kick_pitch = 1.6
	w.kick_fov = 0.4
	w.shake = 0.1
	w.body_kick = 5.0
	w.stagger_power = 0.8
	w.knockback = 0.4
	return w

static func shotgun() -> WeaponData:
	var w := WeaponData.new()
	w.id = &"shotgun"
	w.display_name = "Pump Shotgun"
	w.kind = Kind.SHOTGUN
	w.mag_size = 5
	w.reserve_start = 25
	w.fire_interval = 0.85
	w.damage = 14.0
	w.pellets = 8
	w.spread_deg = 6.5
	w.falloff_start = 6.0
	w.falloff_end = 14.0
	w.falloff_min = 0.2
	w.head_mult = 1.5
	w.range = 35.0
	w.reload_time = 0.5
	w.per_shell_reload = true
	w.noise_radius = 55.0
	w.recoil_pitch = 3.2
	w.recoil_yaw = 0.6
	w.kick_pitch = 6.0
	w.kick_fov = 2.5
	w.shake = 0.28
	w.body_kick = 16.0
	w.stagger_power = 2.0
	w.knockback = 2.2
	return w

static func pipe() -> WeaponData:
	var w := WeaponData.new()
	w.id = &"pipe"
	w.display_name = "Steel Pipe"
	w.kind = Kind.MELEE
	w.mag_size = 0
	w.combo_times = PackedFloat32Array([0.42, 0.46, 0.66])
	w.combo_damage = PackedFloat32Array([38.0, 42.0, 75.0])
	w.reach = 1.85
	w.arc_deg = 110.0
	w.noise_radius = 10.0
	w.shake = 0.12
	w.stagger_power = 1.0
	w.knockback = 1.0
	return w
