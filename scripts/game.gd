extends Node3D

## Breach — a small 3D arena shooter that runs entirely offline.
##
## Design note: the whole level is built from code instead of a .tscn file.
## Binary-ish scene files are hard to review and easy to corrupt in a headless
## pipeline, while code can be diffed, tested and regenerated.

const SPEED := 6.0
const BOT_SPEED := 2.3
const GRAVITY := 22.0
const JUMP_VELOCITY := 7.5
const LOOK_SENS := 0.0035
const BOT_RANGE := 22.0
const BOT_DAMAGE_PER_SEC := 9.0
const PLAYER_DAMAGE := 34.0
const MAGAZINE := 30
const RESPAWN_TIME := 2.0

var player: CharacterBody3D
var camera: Camera3D
var hud: Label
var state_label: Label
var fire_button: Button
var layer: CanvasLayer

var yaw := 0.0
var pitch := -0.06
var health := 100.0
var kills := 0
var ammo := MAGAZINE
var reload_timer := 0.0
var respawn_timer := 0.0
var fire_cooldown := 0.0
var firing := false

var move_touch_id := -1
var look_touch_id := -1
var move_origin := Vector2.ZERO
var move_vector := Vector2.ZERO

var bots: Array = []


func _ready() -> void:
	_build_environment()
	_build_arena()
	_build_player()
	_spawn_bots()
	_build_hud()
	if OS.get_name() != "Android":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	return mat


func _add_box(pos: Vector3, size: Vector3, color: Color, collide := true) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _material(color)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = pos
	add_child(visual)
	if not collide:
		return
	var body := StaticBody3D.new()
	body.position = pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	add_child(body)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.66, 0.70)
	env.fog_density = 0.008
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)


func _build_arena() -> void:
	const HALF = 32.0
	_add_box(Vector3(0.0, -0.5, 0.0), Vector3(HALF * 2.0, 1.0, HALF * 2.0), Color(0.36, 0.40, 0.33))
	_add_box(Vector3(0.0, 2.0, -HALF), Vector3(HALF * 2.0, 4.0, 1.0), Color(0.30, 0.32, 0.30))
	_add_box(Vector3(0.0, 2.0, HALF), Vector3(HALF * 2.0, 4.0, 1.0), Color(0.30, 0.32, 0.30))
	_add_box(Vector3(-HALF, 2.0, 0.0), Vector3(1.0, 4.0, HALF * 2.0), Color(0.30, 0.32, 0.30))
	_add_box(Vector3(HALF, 2.0, 0.0), Vector3(1.0, 4.0, HALF * 2.0), Color(0.30, 0.32, 0.30))

	var crates := [
		Vector3(-6.0, 0.6, -5.0),
		Vector3(-6.0, 1.8, -5.0),
		Vector3(6.0, 0.6, -5.0),
		Vector3(9.0, 1.0, 2.0),
		Vector3(-9.0, 1.0, 2.0),
		Vector3(0.0, 1.0, -12.0),
		Vector3(0.0, 1.0, 12.0),
		Vector3(-14.0, 1.2, 10.0),
		Vector3(14.0, 1.2, 10.0),
		Vector3(-14.0, 1.2, -10.0),
		Vector3(14.0, 1.2, -10.0),
	]
	for i in range(crates.size()):
		var size := Vector3(2.0, 2.0, 2.0) if i % 3 != 2 else Vector3(3.0, 2.4, 3.0)
		var tint := Color(0.55, 0.42, 0.26) if i % 2 == 0 else Color(0.42, 0.44, 0.46)
		_add_box(crates[i], size, tint)

	# Cover walls in the middle so the arena is not a bare box.
	_add_box(Vector3(-3.0, 1.0, 0.0), Vector3(8.0, 2.0, 0.6), Color(0.44, 0.46, 0.42))
	_add_box(Vector3(3.0, 1.0, 6.0), Vector3(8.0, 2.0, 0.6), Color(0.44, 0.46, 0.42))


func _build_player() -> void:
	player = CharacterBody3D.new()
	player.position = Vector3(0.0, 1.0, 14.0)
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	col.shape = capsule
	player.add_child(col)

	var mesh := CapsuleMesh.new()
	mesh.radius = 0.35
	mesh.height = 1.7
	mesh.material = _material(Color(0.20, 0.45, 0.90))
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	player.add_child(visual)

	camera = Camera3D.new()
	camera.position = Vector3(0.0, 0.68, 0.0)
	camera.fov = 78.0
	camera.current = true
	player.add_child(camera)
	add_child(player)


func _spawn_bot(pos: Vector3) -> void:
	var bot := CharacterBody3D.new()
	bot.position = pos
	bot.add_to_group("bots")
	bot.set_meta("hp", 100.0)

	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	col.shape = capsule
	bot.add_child(col)

	var mesh := CapsuleMesh.new()
	mesh.radius = 0.35
	mesh.height = 1.7
	mesh.material = _material(Color(0.85, 0.24, 0.20))
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	bot.add_child(visual)

	var visor := BoxMesh.new()
	visor.size = Vector3(0.5, 0.14, 0.1)
	visor.material = _material(Color(1.0, 0.85, 0.3))
	var visor_node := MeshInstance3D.new()
	visor_node.mesh = visor
	visor_node.position = Vector3(0.0, 0.45, -0.34)
	bot.add_child(visor_node)

	add_child(bot)
	bots.append(bot)


func _spawn_bots() -> void:
	_spawn_bot(Vector3(-14.0, 1.0, -14.0))
	_spawn_bot(Vector3(14.0, 1.0, -16.0))
	_spawn_bot(Vector3(0.0, 1.0, -22.0))
	_spawn_bot(Vector3(18.0, 1.0, 0.0))


func _build_hud() -> void:
	layer = CanvasLayer.new()
	add_child(layer)

	hud = Label.new()
	hud.position = Vector2(28.0, 24.0)
	hud.add_theme_font_size_override("font_size", 24)
	hud.add_theme_color_override("font_color", Color(0.92, 0.96, 0.92))
	hud.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	hud.add_theme_constant_override("shadow_offset_x", 2)
	hud.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(hud)

	state_label = Label.new()
	state_label.add_theme_font_size_override("font_size", 44)
	state_label.add_theme_color_override("font_color", Color(1.0, 0.42, 0.36))
	state_label.set_anchors_preset(Control.PRESET_CENTER)
	state_label.position = Vector2(-160.0, -140.0)
	state_label.size = Vector2(420.0, 60.0)
	state_label.visible = false
	layer.add_child(state_label)

	var cross := ColorRect.new()
	cross.color = Color(0.95, 1.0, 0.95, 0.9)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.size = Vector2(6.0, 6.0)
	cross.position = Vector2(-3.0, -3.0)
	layer.add_child(cross)

	fire_button = Button.new()
	fire_button.text = "ОГОНЬ"
	fire_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	fire_button.position = Vector2(-190.0, -150.0)
	fire_button.size = Vector2(150.0, 110.0)
	fire_button.add_theme_font_size_override("font_size", 26)
	fire_button.pressed.connect(_on_fire_pressed)
	fire_button.button_down.connect(_on_fire_down)
	fire_button.button_up.connect(_on_fire_up)
	layer.add_child(fire_button)


func _on_fire_down() -> void:
	firing = true


func _on_fire_up() -> void:
	firing = false


func _on_fire_pressed() -> void:
	_fire()


func _process(delta: float) -> void:
	fire_cooldown = maxf(0.0, fire_cooldown - delta)
	if ammo == 0:
		reload_timer += delta
		if reload_timer >= 1.4:
			ammo = MAGAZINE
			reload_timer = 0.0
	if respawn_timer > 0.0:
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			_respawn()

	if hud:
		hud.text = "HP %d\nПАТРОНЫ %d\nФРАГИ %d\nВРАГИ %d\nFPS %d" % [
			int(maxf(health, 0.0)),
			ammo,
			kills,
			bots.size(),
			Engine.get_frames_per_second(),
		]


func _physics_process(delta: float) -> void:
	if player == null:
		return

	var keys := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		keys.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		keys.y += 1.0
	if Input.is_key_pressed(KEY_A):
		keys.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		keys.x += 1.0
	var wish := (keys + move_vector).limit_length(1.0)

	if player.is_on_floor():
		if Input.is_key_pressed(KEY_SPACE):
			player.velocity.y = JUMP_VELOCITY
	else:
		player.velocity.y -= GRAVITY * delta

	var direction := Basis(Vector3.UP, yaw) * Vector3(wish.x, 0.0, wish.y)
	player.velocity.x = direction.x * SPEED
	player.velocity.z = direction.z * SPEED
	player.rotation.y = yaw
	camera.rotation.x = pitch
	player.move_and_slide()

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or firing:
		_fire()

	_update_bots(delta)


func _update_bots(delta: float) -> void:
	var alive: Array = []
	for bot in bots:
		if not is_instance_valid(bot):
			continue
		alive.append(bot)
		var to_player: Vector3 = player.global_position - bot.global_position
		to_player.y = 0.0
		var distance := to_player.length()
		if distance > 1.8 and distance < BOT_RANGE:
			var direction := to_player.normalized()
			bot.velocity.x = direction.x * BOT_SPEED
			bot.velocity.z = direction.z * BOT_SPEED
			bot.look_at(Vector3(player.global_position.x, bot.global_position.y, player.global_position.z), Vector3.UP)
		else:
			bot.velocity.x = 0.0
			bot.velocity.z = 0.0
		bot.velocity.y -= GRAVITY * delta
		bot.move_and_slide()

		if distance < BOT_RANGE and respawn_timer <= 0.0:
			var falloff := 1.0 if distance < 10.0 else 0.35
			health -= BOT_DAMAGE_PER_SEC * falloff * delta
			if health <= 0.0:
				_die()
	bots = alive


func _fire() -> void:
	if fire_cooldown > 0.0 or ammo <= 0 or respawn_timer > 0.0:
		return
	ammo -= 1
	fire_cooldown = 0.11
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * 80.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var collider = hit.get("collider")
	if collider is CharacterBody3D and collider.is_in_group("bots"):
		_damage_bot(collider, PLAYER_DAMAGE)


func _damage_bot(bot: CharacterBody3D, amount: float) -> void:
	var hp := float(bot.get_meta("hp", 100.0)) - amount
	if hp <= 0.0:
		bots.erase(bot)
		bot.queue_free()
		kills += 1
		return
	bot.set_meta("hp", hp)


func _die() -> void:
	health = 0.0
	respawn_timer = RESPAWN_TIME
	state_label.text = "ВЫ УБИТЫ"
	state_label.visible = true


func _respawn() -> void:
	health = 100.0
	ammo = MAGAZINE
	player.position = Vector3(0.0, 1.0, 14.0)
	player.velocity = Vector3.ZERO
	state_label.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var half := get_viewport().get_visible_rect().size.x * 0.5
		if touch.pressed:
			if touch.position.x < half and move_touch_id == -1:
				move_touch_id = touch.index
				move_origin = touch.position
			elif touch.position.x >= half and look_touch_id == -1:
				look_touch_id = touch.index
		else:
			if touch.index == move_touch_id:
				move_touch_id = -1
				move_vector = Vector2.ZERO
			elif touch.index == look_touch_id:
				look_touch_id = -1
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == move_touch_id:
			move_vector = ((drag.position - move_origin) / 90.0).limit_length(1.0)
		elif drag.index == look_touch_id:
			yaw -= drag.relative.x * LOOK_SENS
			pitch = clampf(pitch - drag.relative.y * LOOK_SENS, -1.3, 1.0)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		yaw -= motion.relative.x * LOOK_SENS
		pitch = clampf(pitch - motion.relative.y * LOOK_SENS, -1.3, 1.0)
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
