class_name CamProfile
extends Resource

## One camera behaviour (on foot / aiming / riding / horde). The rig blends between
## profiles so mode switches never cut.

@export var distance := 3.2
@export var distance_fast := 3.2        ## at speed_ref (riding)
@export var height := 1.5
@export var height_fast := 1.5
@export var fov := 60.0
@export var fov_fast := 60.0
@export var shoulder := 0.45
@export var pivot_frequency := 6.0      ## follow spring Hz (lower = more lag)
@export var pitch_default := -10.0
@export var pitch_min := -60.0
@export var pitch_max := 50.0
@export var auto_center := false
@export var auto_center_delay := 1.2
@export var auto_center_rate := 2.4
@export var look_ahead := 0.0           ## seconds of yaw-rate to lead
@export var look_ahead_max_deg := 15.0
@export var speed_ref := 26.0

static func on_foot() -> CamProfile:
	var p := CamProfile.new()
	p.distance = 3.3
	p.distance_fast = 3.6
	p.height = 1.55
	p.height_fast = 1.55
	p.fov = 62.0
	p.fov_fast = 66.0
	p.shoulder = 0.5
	p.pivot_frequency = 7.0
	p.speed_ref = 6.2
	return p

static func aiming() -> CamProfile:
	var p := CamProfile.new()
	p.distance = 1.55
	p.distance_fast = 1.55
	p.height = 1.58
	p.height_fast = 1.58
	p.fov = 50.0
	p.fov_fast = 50.0
	p.shoulder = 0.62
	p.pivot_frequency = 12.0
	return p

static func riding() -> CamProfile:
	var p := CamProfile.new()
	p.distance = 4.3
	p.distance_fast = 5.7
	p.height = 1.65
	p.height_fast = 1.95
	p.fov = 62.0
	p.fov_fast = 70.0
	p.shoulder = 0.0
	p.pivot_frequency = 4.2
	p.pitch_default = -11.0
	p.pitch_min = -45.0
	p.pitch_max = 30.0
	p.auto_center = true
	p.look_ahead = 0.28
	return p
