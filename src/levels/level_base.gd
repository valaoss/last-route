class_name LevelBase
extends Node3D

## Shared level bootstrap: atmosphere, sun, camera rig, player, bike, FX pool,
## HUD and (optionally) a runtime-baked navmesh. Subclasses build geometry.

const PlayerScene := preload("res://src/player/player.tscn")
const MotoScene := preload("res://src/vehicle/moto.tscn")
const HudScene := preload("res://src/ui/hud.tscn")
const ZombieScript := preload("res://src/ai/zombie.gd")

var geo: Node3D               ## static world geometry root (navmesh source)
var nav_region: NavigationRegion3D
var rig: CamRig
var player: Player
var bike: Moto
var hud: Hud
var use_navmesh := false
var nav_bake_aabb := AABB()      ## limits navmesh baking on large levels; empty = whole level
var nav_chunk := 0.0             ## > 0: bake nav_bake_aabb as separate tiles of this size (large maps)
var nav_pending := 0             ## tiles still baking
var player_spawn := Transform3D(Basis.IDENTITY, Vector3(2, 0.1, 2))
var bike_spawn := Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0))


func _ready() -> void:
	_setup_environment()
	if use_navmesh:
		nav_region = NavigationRegion3D.new()
		nav_region.name = "Nav"
		var nm := NavigationMesh.new()
		nm.agent_radius = 0.4
		nm.agent_height = 1.8
		nm.agent_max_climb = 0.3
		nm.cell_size = 0.2
		nm.cell_height = 0.1
		nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		nm.geometry_collision_mask = 1
		if nav_bake_aabb.has_volume():
			nm.filter_baking_aabb = nav_bake_aabb
		nav_region.navigation_mesh = nm
		add_child(nav_region)
		geo = Node3D.new()
		geo.name = "Geometry"
		nav_region.add_child(geo)
	else:
		geo = Node3D.new()
		geo.name = "Geometry"
		add_child(geo)
	build_world()
	var fx := Fx.new()
	fx.name = "Fx"
	add_child(fx)
	_spawn_actors()
	if use_navmesh:
		_ensure_map_cell_size()
		if nav_chunk > 0.0 and nav_bake_aabb.has_volume():
			_bake_chunked()
		else:
			nav_region.bake_navigation_mesh(true)
	after_spawn()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autotest="):
			var at := AutoTest.new()
			at.level = self
			add_child(at)


## Override in subclasses.
func build_world() -> void:
	pass


func after_spawn() -> void:
	pass


func _ensure_map_cell_size() -> void:
	var map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, 0.2)
	NavigationServer3D.map_set_cell_height(map, 0.1)


## Parses the static geometry once, then bakes square tiles in the background.
## Each tile bakes 1 m past its edges and trims that border, so neighbours meet
## exactly and the regions stitch together.
func _bake_chunked() -> void:
	NavigationServer3D.map_set_edge_connection_margin(get_world_3d().navigation_map, 0.5)
	var src := _parse_nav_source()
	var box := nav_bake_aabb
	for ix in ceili(box.size.x / nav_chunk):
		for iz in ceili(box.size.z / nav_chunk):
			var r := NavigationRegion3D.new()
			r.name = "NavTile_%d_%d" % [ix, iz]
			add_child(r)
			_nav_tiles[Vector2i(ix, iz)] = r
			_bake_tile(Vector2i(ix, iz), src)


## Re-bakes the tile under `pos` after the static geometry there changed.
func rebake_nav_at(pos: Vector3) -> void:
	var c := Vector2i(floori((pos.x - nav_bake_aabb.position.x) / nav_chunk), floori((pos.z - nav_bake_aabb.position.z) / nav_chunk))
	if _nav_tiles.has(c):
		_bake_tile(c, _parse_nav_source())


var _nav_tiles := {}        ## Vector2i -> NavigationRegion3D
var _nav_tokens := {}       ## Vector2i -> latest bake id (older results are dropped)


func _parse_nav_source() -> NavigationMeshSourceGeometryData3D:
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav_region.navigation_mesh, src, geo)
	return src


func _bake_tile(c: Vector2i, src: NavigationMeshSourceGeometryData3D) -> void:
	var nm: NavigationMesh = nav_region.navigation_mesh.duplicate()
	var tile := AABB(nav_bake_aabb.position + Vector3(c.x * nav_chunk, 0, c.y * nav_chunk), Vector3(nav_chunk, nav_bake_aabb.size.y, nav_chunk))
	nm.filter_baking_aabb = tile.grow(1.0)
	nm.border_size = 1.0
	var token: int = _nav_tokens.get(c, 0) + 1
	_nav_tokens[c] = token
	nav_pending += 1
	NavigationServer3D.bake_from_source_geometry_data_async(nm, src, _on_tile_baked.bind(c, token, nm))


func _on_tile_baked(c: Vector2i, token: int, nm: NavigationMesh) -> void:
	nav_pending -= 1
	var r: NavigationRegion3D = _nav_tiles.get(c)
	if is_instance_valid(r) and _nav_tokens.get(c) == token:
		r.set_deferred(&"navigation_mesh", nm)


func _setup_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("5d6d76")
	sm.sky_horizon_color = Color("a7afad")
	sm.sky_curve = 0.12
	sm.ground_bottom_color = Color("2e302b")
	sm.ground_horizon_color = Color("8e938c")
	sm.sun_angle_max = 18.0
	sm.sun_curve = 0.08
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color("a3aba8")
	env.fog_density = 0.0065
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.35
	env.fog_height = 6.0
	env.fog_height_density = 0.02
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.86
	env.adjustment_contrast = 1.06
	env.adjustment_brightness = 0.98
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color("ffe6c7")
	sun.light_energy = 1.55
	sun.rotation_degrees = Vector3(-38.0, -132.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_blur = 1.5
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	add_child(sun)


func _spawn_actors() -> void:
	rig = CamRig.new()
	rig.name = "CamRig"
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	rig.add_child(cam)
	add_child(rig)
	cam.current = true
	bike = MotoScene.instantiate()
	bike.name = "Moto"
	add_child(bike)
	bike.global_transform = bike_spawn
	_load_tuning()
	player = PlayerScene.instantiate()
	player.name = "Player"
	player.rig_path = NodePath("../CamRig")
	player.bike_path = NodePath("../Moto")
	add_child(player)
	player.global_transform = player_spawn
	hud = HudScene.instantiate()
	add_child(hud)
	hud.bind(player, bike, rig)


func _load_tuning() -> void:
	for path in ["user://moto_tuning.tres", "res://config/moto_tuning.tres"]:
		if ResourceLoader.exists(path):
			var t := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if t is MotoTuning:
				bike.tuning = t
				return


func spawn_zombie(kind: int, pos: Vector3, yaw := 0.0) -> Zombie:
	var z := Zombie.new()
	match kind:
		ZombieData.Archetype.RUNNER: z.data = ZombieData.runner()
		ZombieData.Archetype.BRUTE: z.data = ZombieData.brute()
		ZombieData.Archetype.SCREAMER: z.data = ZombieData.screamer()
		_: z.data = ZombieData.walker()
	z.rotation.y = yaw
	z.position = pos
	add_child(z)
	return z


func spawn_raider(pos: Vector3, route: PackedVector3Array, yaw := 0.0) -> Raider:
	var r := Raider.new()
	r.patrol = route
	r.rotation.y = yaw
	r.position = pos
	add_child(r)
	return r


## Invisible marker raiders evaluate as cover (stand behind it relative to the threat).
func cover_point(pos: Vector3) -> void:
	var m := Marker3D.new()
	m.position = pos
	m.add_to_group(&"cover_point")
	add_child(m)
