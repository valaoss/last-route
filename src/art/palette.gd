class_name Palette
extends RefCounted

## Art-bible palette and the shared material library. Everything in the world pulls
## its materials from here so assets from different sources read as one game.

const CONCRETE := Color("6e6b66")
const CONCRETE_DARK := Color("4f4d49")
const ASPHALT := Color("3a3b3d")
const ASPHALT_WORN := Color("47484a")
const MOSS := Color("4f5b3a")
const FOREST := Color("2f3a2a")
const RUST := Color("a4532a")
const RUST_DARK := Color("6b3a22")
const SIGN_YELLOW := Color("c9a646")
const HAZE := Color("a9b3b5")
const LOOT_AMBER := Color("e8b04a")
const DIRT := Color("6a5a45")
const MUD := Color("3d3328")
const GRASS := Color("56603d")
const OLIVE := Color("55593a")
const LEATHER := Color("2b2420")
const STEEL := Color("5d6165")
const CHROME := Color("8d9195")
const RUBBER := Color("1c1c1d")
const BRICK := Color("7a4b3a")
const PLASTER := Color("8c857a")

static var _cache: Dictionary = {}
static var _world_shader: Shader
static var _noise: NoiseTexture2D

static func mat(key: StringName) -> Material:
	if _cache.has(key):
		return _cache[key]
	var m: Material
	match key:
		&"asphalt": m = world(ASPHALT, 0.92, 0.0, 0.55, 0.35)
		&"asphalt_worn": m = world(ASPHALT_WORN, 0.9, 0.0, 0.6, 0.45)
		&"concrete": m = world(CONCRETE, 0.95, 0.0, 0.5, 0.6)
		&"concrete_dark": m = world(CONCRETE_DARK, 0.95, 0.0, 0.45, 0.65)
		&"curb": m = world(Color("7d7a73"), 0.9, 0.0, 0.5, 0.55)
		&"dirt": m = world(DIRT, 1.0, 0.0, 0.25, 0.2)
		&"mud": m = world(MUD, 0.55, 0.0, 0.25, 0.1)
		&"gravel": m = world(Color("6f685d"), 1.0, 0.0, 0.6, 0.3)
		&"grass": m = world(GRASS, 1.0, 0.0, 0.3, 0.15)
		&"brick": m = world(BRICK, 0.95, 0.0, 0.45, 0.7)
		&"plaster": m = world(PLASTER, 0.95, 0.0, 0.5, 0.75)
		&"rust_metal": m = world(RUST_DARK, 0.8, 0.35, 0.7, 0.4)
		&"painted_metal": m = world(Color("5b6b6a"), 0.7, 0.3, 0.55, 0.6)
		&"car_paint_a": m = world(Color("6b6f5a"), 0.65, 0.25, 0.6, 0.55)
		&"car_paint_b": m = world(Color("7a4a38"), 0.65, 0.25, 0.65, 0.5)
		&"car_paint_c": m = world(Color("4a5560"), 0.65, 0.25, 0.6, 0.55)
		&"wood": m = world(Color("5e4a36"), 0.95, 0.0, 0.5, 0.4)
		&"barrier": m = world(Color("b8b2a4"), 0.9, 0.0, 0.6, 0.65)
		&"hazard": m = world(SIGN_YELLOW, 0.8, 0.0, 0.6, 0.5)
		&"foliage": m = world(MOSS, 1.0, 0.0, 0.2, 0.1)
		&"foliage_dark": m = world(FOREST, 1.0, 0.0, 0.2, 0.1)
		&"bark": m = world(Color("3f3529"), 1.0, 0.0, 0.3, 0.2)
		# bike & props — plain PBR, tight control
		&"bike_tank": m = pbr(Color("4d5236"), 0.48, 0.35)
		&"bike_frame": m = pbr(Color("232426"), 0.55, 0.6)
		&"bike_engine": m = pbr(Color("3b3d40"), 0.5, 0.75)
		&"bike_chrome": m = pbr(CHROME, 0.25, 0.95)
		&"bike_exhaust": m = pbr(Color("4a3a30"), 0.6, 0.7)
		&"bike_seat": m = pbr(LEATHER, 0.75, 0.0)
		&"rubber": m = pbr(RUBBER, 0.9, 0.0)
		&"canvas": m = pbr(Color("5a5340"), 0.95, 0.0)
		&"gun_metal": m = pbr(Color("2a2b2d"), 0.45, 0.8)
		&"gun_polymer": m = pbr(Color("1f2021"), 0.7, 0.0)
		&"gun_wood": m = pbr(Color("5a3d28"), 0.6, 0.0)
		&"blade": m = pbr(Color("7c7f82"), 0.35, 0.9)
		&"headlight": m = emissive(Color("fff2d6"), 3.0)
		&"taillight": m = emissive(Color("ff3a20"), 1.6)
		&"loot_glint": m = emissive(LOOT_AMBER, 2.2)
		_: m = pbr(Color.MAGENTA, 0.5, 0.0)
	if m is ShaderMaterial:
		match key:
			&"asphalt", &"asphalt_worn":
				m.set_shader_parameter(&"cracks", 1.0)
				m.set_shader_parameter(&"puddles", 0.45)
			&"concrete", &"concrete_dark", &"curb":
				m.set_shader_parameter(&"cracks", 0.6)
				m.set_shader_parameter(&"moss_top", 0.5)
			&"mud":
				m.set_shader_parameter(&"puddles", 1.0)
			&"brick", &"plaster", &"barrier":
				m.set_shader_parameter(&"moss_top", 0.8)
	_cache[key] = m
	return m

static func pbr(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	m.metallic_specular = 0.45
	return m

static func emissive(c: Color, energy: float) -> StandardMaterial3D:
	var m := pbr(c, 0.4, 0.0)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m

## World surfaces use one shader: triplanar grime, top-down rain streaks, edge wear
## and per-object tint variation. `grime` and `wear` are 0..1.
static func world(c: Color, rough: float, metal: float, grime: float, streaks: float) -> ShaderMaterial:
	if _world_shader == null:
		_world_shader = load("res://src/art/world_surface.gdshader")
		_noise = NoiseTexture2D.new()
		_noise.width = 256
		_noise.height = 256
		_noise.seamless = true
		_noise.generate_mipmaps = true
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.frequency = 0.012
		fn.fractal_octaves = 4
		_noise.noise = fn
	var m := ShaderMaterial.new()
	m.shader = _world_shader
	m.set_shader_parameter(&"noise_tex", _noise)
	m.set_shader_parameter(&"base_color", c)
	m.set_shader_parameter(&"roughness_base", rough)
	m.set_shader_parameter(&"metallic_base", metal)
	m.set_shader_parameter(&"grime_amount", grime)
	m.set_shader_parameter(&"streak_amount", streaks)
	return m
