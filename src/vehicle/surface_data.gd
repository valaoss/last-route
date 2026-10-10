class_name SurfaceData
extends Resource

@export var id: StringName = &"asphalt"
@export var grip := 1.0             ## μ
@export var power := 1.0            ## engine traction multiplier
@export var drag := 0.0             ## extra rolling drag, m/s²
@export var brake := 1.0
@export var roughness := 0.1        ## camera/visual vibration
@export var slide_ease := 1.0       ## <1 lets the rear step out sooner
@export var dust_color := Color(0.45, 0.42, 0.38, 0.0)
@export var tyre_tone := 0.0        ## 0 = asphalt hiss, 1 = gravel crunch

static var _table: Dictionary = {}
static var _offroad: Dictionary = {}

static func get_surface(id: StringName) -> SurfaceData:
	if _table.is_empty():
		_build()
	return _table.get(id, _table[&"asphalt"])

## The same surface as felt with the off-road suspension upgrade: loose ground
## loses less grip and power, rolls easier and shakes less. Asphalt is unchanged.
static func offroad(id: StringName) -> SurfaceData:
	var base := get_surface(id)
	if base.id == &"asphalt":
		return base
	if not _offroad.has(base.id):
		var s: SurfaceData = base.duplicate()
		s.grip = lerpf(base.grip, 1.0, 0.35)
		s.power = lerpf(base.power, 1.0, 0.5)
		s.drag = base.drag * 0.5
		s.brake = lerpf(base.brake, 1.0, 0.3)
		s.roughness = base.roughness * 0.55
		s.slide_ease = lerpf(base.slide_ease, 1.0, 0.3)
		_offroad[base.id] = s
	return _offroad[base.id]

static func _build() -> void:
	_add(&"asphalt", 1.0, 1.0, 0.0, 1.0, 0.08, 1.0, Color(0.5, 0.5, 0.5, 0.0), 0.0)
	_add(&"concrete", 0.95, 1.0, 0.05, 1.0, 0.12, 1.0, Color(0.6, 0.6, 0.58, 0.0), 0.1)
	_add(&"dirt", 0.72, 0.88, 0.5, 0.65, 0.45, 0.7, Color(0.48, 0.4, 0.3, 0.55), 0.8)
	_add(&"gravel", 0.65, 0.85, 0.7, 0.6, 0.6, 0.65, Color(0.55, 0.52, 0.47, 0.45), 1.0)
	_add(&"grass", 0.6, 0.8, 0.8, 0.55, 0.35, 0.6, Color(0.3, 0.35, 0.2, 0.25), 0.5)
	_add(&"mud", 0.45, 0.65, 2.2, 0.45, 0.5, 0.5, Color(0.25, 0.2, 0.15, 0.7), 0.6)

static func _add(id: StringName, grip: float, power: float, drag: float, brake: float, rough: float, slide: float, dust: Color, tone: float) -> void:
	var s := SurfaceData.new()
	s.id = id
	s.grip = grip
	s.power = power
	s.drag = drag
	s.brake = brake
	s.roughness = rough
	s.slide_ease = slide
	s.dust_color = dust
	s.tyre_tone = tone
	_table[id] = s
