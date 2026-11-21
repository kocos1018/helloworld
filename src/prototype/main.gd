extends Node2D
## 이동·회피·근접 전투 검증용. 영구 게임 구조로 승격하기 전 물리 장면을 분리한다.

@export var move_speed: float = 110.0
@export var attack_damage: int = 20
@export var attack_interval: float = 0.5
@export var attack_range: float = 32.0
@export var dash_distance: float = 72.0
@export var dash_duration: float = 0.16
@export var dash_cooldown: float = 1.0
const ARENA := Rect2(24, 64, 592, 272)
const PLAYER_RADIUS := 10.0
var player_position := Vector2(180, 200)
var aim_direction := Vector2.RIGHT
var hp: int = 100
var enemies: Array[Dictionary] = []
var attack_age: float = -1.0
var attack_wait: float = 0.0
var attack_direction := Vector2.RIGHT
var hit_ids: Array[int] = []
var dash_left: float = 0.0
var dash_wait: float = 0.0
var dash_direction := Vector2.RIGHT
var dodge_invulnerability: float = 0.0
var hit_invulnerability: float = 0.0
var paused: bool = false
var result: String = ""
var ui: Label
var overlay: Label
var restart_button: Button

func _ready() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	ui = Label.new()
	ui.position = Vector2(24, 6)
	ui.add_theme_font_size_override("font_size", 13)
	canvas.add_child(ui)
	overlay = Label.new()
	overlay.position = Vector2(100, 130)
	overlay.size = Vector2(440, 60)
	overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.add_theme_font_size_override("font_size", 22)
	canvas.add_child(overlay)
	restart_button = Button.new()
	restart_button.text = "다시 시작 (R)"
	restart_button.position = Vector2(240, 212)
	restart_button.size = Vector2(160, 36)
	restart_button.pressed.connect(reset_run)
	canvas.add_child(restart_button)
	reset_run()

func reset_run() -> void:
	player_position = Vector2(180, 200)
	aim_direction = Vector2.RIGHT
	hp = 100
	attack_age = -1.0
	attack_wait = 0.0
	dash_left = 0.0
	dash_wait = 0.0
	dodge_invulnerability = 0.0
	hit_invulnerability = 0.0
	hit_ids.clear()
	paused = false
	result = ""
	enemies.clear()
	for point: Vector2 in [Vector2(450, 112), Vector2(500, 200), Vector2(440, 288)]:
		enemies.append({"position": point, "hp": 60, "state": "chase",
			"timer": 0.0, "cooldown": 0.0, "aim": Vector2.LEFT})
	update_ui()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		paused = true
		if is_instance_valid(ui):
			update_ui()
			queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R:
			reset_run()
		elif event.physical_keycode == KEY_ESCAPE and result.is_empty():
			paused = not paused
			update_ui()
			queue_redraw()

func _physics_process(delta: float) -> void:
	if paused or not result.is_empty():
		return
	var movement := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	movement = movement.normalized()
	var offset := get_global_mouse_position() - player_position
	if offset.length_squared() > 1:
		aim_direction = offset.normalized()
	tick_player(delta, movement, Input.is_physical_key_pressed(KEY_SPACE),
		Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	for enemy: Dictionary in enemies:
		tick_enemy(enemy, delta)
		if hp <= 0:
			break
	if hp <= 0:
		result = "쓰러졌습니다\nR로 다시 도전하세요"
	elif alive_count() == 0:
		result = "전사 전투 시험 완료!\n적 세 마리를 모두 처치했습니다"
	update_ui()
	queue_redraw()

func tick_player(delta: float, movement: Vector2, dodge: bool, attack: bool) -> void:
	attack_wait = maxf(0, attack_wait - delta)
	dash_wait = maxf(0, dash_wait - delta)
	dodge_invulnerability = maxf(0, dodge_invulnerability - delta)
	hit_invulnerability = maxf(0, hit_invulnerability - delta)
	if dodge and dash_wait <= 0 and dash_left <= 0:
		dash_direction = movement if movement.length_squared() > 0 else aim_direction
		dash_left = dash_duration
		dash_wait = dash_cooldown
		dodge_invulnerability = 0.12
		attack_age = -1.0
	if dash_left > 0:
		var step := minf(delta, dash_left)
		player_position += dash_direction * (dash_distance / dash_duration) * step
		dash_left = maxf(0, dash_left - delta)
	else:
		player_position += movement * move_speed * delta
		if attack and attack_wait <= 0:
			attack_age = 0.0
			attack_wait = attack_interval
			attack_direction = aim_direction
			hit_ids.clear()
	player_position = clamp_to_arena(player_position, PLAYER_RADIUS)
	if attack_age >= 0:
		var previous_age := attack_age
		attack_age += delta
		if attack_age >= 0.1 and previous_age < 0.2:
			apply_sword_hits()
		if attack_age >= 0.25:
			attack_age = -1.0

func apply_sword_hits() -> void:
	for index: int in range(enemies.size()):
		var enemy: Dictionary = enemies[index]
		if int(enemy.hp) <= 0 or index in hit_ids:
			continue
		var offset: Vector2 = enemy.position - player_position
		if offset.length() <= attack_range and absf(attack_direction.angle_to(offset)) <= deg_to_rad(50):
			enemy.hp = maxi(0, int(enemy.hp) - attack_damage)
			hit_ids.append(index)

func tick_enemy(enemy: Dictionary, delta: float) -> void:
	if int(enemy.hp) <= 0:
		return
	enemy.cooldown = maxf(0, float(enemy.cooldown) - delta)
	var offset: Vector2 = player_position - enemy.position
	match String(enemy.state):
		"chase":
			if offset.length() <= 24 and float(enemy.cooldown) <= 0:
				enemy.state = "windup"
				enemy.timer = 0.4
				enemy.cooldown = 1.2
				enemy.aim = offset.normalized() if offset.length_squared() > 0 else Vector2.LEFT
			elif offset.length() > 20:
				enemy.position += offset.normalized() * minf(65 * delta, offset.length() - 20)
		"windup":
			enemy.timer = float(enemy.timer) - delta
			if float(enemy.timer) <= 0:
				var direction: Vector2 = enemy.aim
				if offset.length() <= 26 and absf(direction.angle_to(offset)) <= deg_to_rad(60):
					damage_player(12)
				enemy.state = "recover"
				enemy.timer = 0.4
		"recover":
			enemy.timer = float(enemy.timer) - delta
			if float(enemy.timer) <= 0:
				enemy.state = "chase"
	enemy.position = clamp_to_arena(enemy.position, 10)

func damage_player(amount: int) -> void:
	if hp <= 0 or dodge_invulnerability > 0 or hit_invulnerability > 0:
		return
	hp = maxi(0, hp - amount)
	hit_invulnerability = 0.5

func clamp_to_arena(point: Vector2, radius: float) -> Vector2:
	return Vector2(clampf(point.x, ARENA.position.x + radius, ARENA.end.x - radius),
		clampf(point.y, ARENA.position.y + radius, ARENA.end.y - radius))

func alive_count() -> int:
	var count: int = 0
	for enemy: Dictionary in enemies:
		if int(enemy.hp) > 0:
			count += 1
	return count

func update_ui() -> void:
	ui.text = "전사 시험 | 체력 %d/100 | 남은 적 %d | 회피 %.1f초\nWASD 이동 · 마우스 조준/좌클릭 공격 · Space 회피\nR 다시 시작 · Esc 일시정지" % [hp, alive_count(), dash_wait]
	overlay.text = result if not result.is_empty() else ("일시정지\nEsc로 계속" if paused else "")
	restart_button.visible = not result.is_empty()

func _draw() -> void:
	draw_rect(Rect2(0, 0, 640, 360), Color("#171d28"))
	draw_rect(ARENA, Color("#252e3c"))
	draw_rect(ARENA, Color("#62788e"), false, 2)
	for enemy: Dictionary in enemies:
		if int(enemy.hp) <= 0:
			continue
		var point: Vector2 = enemy.position
		if String(enemy.state) == "windup":
			var angle: float = Vector2(enemy.aim).angle()
			draw_arc(point, 26, angle - PI / 3, angle + PI / 3, 18, Color("#ffcb66"), 3)
			draw_line(point, point + Vector2(enemy.aim) * 26, Color("#ffcb66"), 1)
		draw_circle(point, 10, Color("#f37d7d"))
		draw_rect(Rect2(point + Vector2(-13, -18), Vector2(26, 3)), Color("#502c36"))
		draw_rect(Rect2(point + Vector2(-13, -18), Vector2(26.0 * float(enemy.hp) / 60, 3)), Color("#94e6a8"))
	var color := Color("#70c8ff")
	if dodge_invulnerability > 0:
		color = Color.WHITE
	elif hit_invulnerability > 0:
		color = Color("#eab7ee")
	if hp <= 0:
		color = Color("#616a7c")
	draw_circle(player_position, PLAYER_RADIUS, color)
	draw_line(player_position, player_position + aim_direction * 22, Color("#ffe08a"), 2)
	if attack_age >= 0.1 and attack_age < 0.2:
		var angle := attack_direction.angle()
		draw_arc(player_position, attack_range, angle - deg_to_rad(50), angle + deg_to_rad(50), 20, Color("#fff2ba"), 4)
	if paused or not result.is_empty():
		draw_rect(ARENA, Color(0.04, 0.05, 0.08, 0.75))
