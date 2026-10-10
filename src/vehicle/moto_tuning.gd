class_name MotoTuning
extends Resource

## Every riding-feel parameter lives here so it can be tuned live (F1) and saved.

@export_group("Engine")
@export var top_speed := 26.0            ## m/s (~94 km/h)
@export var launch_accel := 7.4          ## m/s² at standstill; falls off as (1 - (v/vmax)²)
@export var coast_decel := 0.7           ## rolling + engine braking, m/s²
@export var air_drag := 0.0016           ## per v²
@export var reverse_speed := 2.2
@export var gear_count := 5
@export var shift_cut_time := 0.12       ## torque interruption on upshift
@export var idle_rpm := 1100.0
@export var redline_rpm := 9200.0

@export_group("Brakes")
@export var front_brake := 9.0           ## m/s² on asphalt
@export var rear_brake := 4.5
@export var brake_dive := 0.012          ## rad of pitch per m/s² of decel

@export_group("Steering")
@export var steer_rise_time := 0.10
@export var steer_return_time := 0.16
@export var min_turn_radius := 2.1       ## at walking pace
@export var max_yaw_rate := 2.4          ## rad/s
@export var lateral_grip := 1.55         ## multiplier on μg for the yaw-rate limit (arcade > 1)
@export var yaw_response := 9.0          ## how fast actual yaw rate follows target
@export var high_speed_steer := 0.75     ## extra steer damping at top speed (0..1)

@export_group("Slide")
@export var grip_recovery := 11.0        ## velocity heading follows body heading, 1/s
@export var slide_grip_recovery := 2.4   ## while sliding / handbraking
@export var max_slip_deg := 26.0
@export var slide_threshold := 0.85      ## fraction of grip limit before tyres let go
@export var handbrake_oversteer := 1.35
@export var slide_scrub := 3.2           ## speed loss per second at full sideways slip

@export_group("Lean & Suspension")
@export var max_lean_deg := 42.0
@export var lean_scale := 0.68         ## visual lean vs. physical (arcade grip would over-lean)
@export var lean_frequency := 3.2
@export var lean_damping := 0.72
@export var suspension_frequency := 3.4
@export var suspension_damping := 0.55
@export var suspension_travel := 0.12
@export var wheelbase := 1.42

@export_group("Collisions")
@export var crash_impact := 9.5         ## m/s into a wall, head-on → crash
@export var crash_max_angle_deg := 38.0
@export var bump_speed_keep := 0.55
@export var zombie_knock_speed := 8.3   ## ≥ 30 km/h knocks walkers down
@export var zombie_speed_loss := 0.15

@export_group("Noise")
@export var noise_idle_radius := 25.0
@export var noise_full_radius := 80.0
@export var muffler := 1.0              ## upgrade multiplier (0.65 with silencer)

@export_group("Fuel")
@export var tank_seconds := 420.0       ## full tank ≈ 7 min of full throttle
@export var reserve_power := 0.4        ## empty tank: slow, never stranded


func gear_top_speed(gear: int) -> float:
	# progressively longer gears: 0.28, 0.46, 0.63, 0.8, 1.0 of top speed for 5 gears
	var t := float(gear) / gear_count
	return top_speed * (0.1 + 0.9 * pow(t, 0.85))
