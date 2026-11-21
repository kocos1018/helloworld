extends RefCounted
## 원본 도형으로 그리는 픽셀풍 성채. 외부 이미지·폰트·소리를 요구하지 않는다.

const FIELD := Rect2(24, 64, 592, 272)
const INK := Color("#111923")
const PALE := Color("#f4e6bb")
const GOLD := Color("#e8ba65")
const JOB_COLORS := {
	"warrior": Color("#65bad5"), "berserker": Color("#d7676f"),
	"archer": Color("#92c282"), "hunter": Color("#dec078"),
	"mage": Color("#a89ce3"), "firemage": Color("#ee9564")}

var label_font: SystemFont = SystemFont.new()

func _init() -> void:
	label_font.font_names = PackedStringArray(["Malgun Gothic", "Noto Sans CJK KR", "Noto Sans"])

func paint(canvas: Node2D, combat, room: int, elapsed: float) -> void:
	_environment(canvas, room + int(combat.get("spawn_variant")) if room < 5 else room, elapsed)
	for zone: Dictionary in combat.zones:
		_zone(canvas, zone, elapsed)
	for trap: Dictionary in combat.traps:
		_trap(canvas, trap)
	for actor: Dictionary in combat.enemies:
		if float(actor.get("hp", 0)) > 0:
			_warning(canvas, actor, elapsed)
	for projectile: Dictionary in combat.projectiles:
		_projectile(canvas, projectile)
	var actors: Array[Dictionary] = []
	for actor: Dictionary in combat.enemies:
		if float(actor.get("hp", 0)) > 0:
			actors.append(actor)
	actors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return Vector2(a.get("pos", Vector2.ZERO)).y < Vector2(b.get("pos", Vector2.ZERO)).y)
	var player_painted: bool = false
	for actor: Dictionary in actors:
		if not player_painted and Vector2(actor.get("pos", Vector2.ZERO)).y > Vector2(combat.p).y:
			_player(canvas, combat, elapsed)
			player_painted = true
		_enemy(canvas, actor, elapsed)
	if not player_painted:
		_player(canvas, combat, elapsed)
	if room == 5:
		_boss_bar(canvas, combat.enemies)

func _environment(c: Node2D, room: int, elapsed: float) -> void:
	c.draw_rect(Rect2(0, 0, 640, 360), Color("#101722"))
	var floor_color := Color("#29313c") if room < 5 else Color("#342d36")
	var brick_color := Color("#303a46") if room < 5 else Color("#3d3440")
	c.draw_rect(FIELD, floor_color)
	for row: int in range(17):
		for col: int in range(36):
			var p := Vector2(32 + col * 16, 72 + row * 16)
			if (col * 7 + row * 11 + room) % 9 < 3:
				c.draw_rect(Rect2(p, Vector2(14, 14)), brick_color)
			if (col * 13 + row * 5) % 31 == 0:
				c.draw_line(p + Vector2(2, 9), p + Vector2(9, 10), Color("#202933"), 1)
	# 두꺼운 외벽과 이음새로 화면 경계를 읽기 쉽게 만든다.
	for y: int in [64, 324]:
		c.draw_rect(Rect2(24, y, 592, 12), Color("#475565"))
		for x: int in range(24, 616, 32):
			c.draw_rect(Rect2(x, y, 30, 9), Color("#3c4959"))
			c.draw_line(Vector2(x, y + 1), Vector2(x + 29, y + 1), Color("#617183"), 1)
	for x: int in [24, 604]:
		c.draw_rect(Rect2(x, 76, 12, 248), Color("#3c4959"))
		for y: int in range(76, 324, 24):
			c.draw_line(Vector2(x, y), Vector2(x + 11, y), Color("#26313f"), 1)
	# 바닥의 희미한 문장. 충돌 오브젝트처럼 보이는 큰 기둥은 배치하지 않는다.
	var motif_color := Color(0.56, 0.62, 0.68, 0.10)
	c.draw_rect(Rect2(274, 163, 92, 72), motif_color, false, 2)
	c.draw_line(Vector2(292, 199), Vector2(348, 199), motif_color, 2)
	c.draw_line(Vector2(320, 177), Vector2(320, 221), motif_color, 2)
	for torch: Vector2 in [Vector2(48, 88), Vector2(592, 88), Vector2(48, 312), Vector2(592, 312)]:
		_torch(c, torch, elapsed)
	# 입구와 목적지가 색과 문양 양쪽으로 구분된다.
	c.draw_rect(Rect2(26, 181, 10, 38), Color("#18232f"))
	c.draw_line(Vector2(29, 184), Vector2(29, 216), Color("#75b3b8"), 2)
	c.draw_rect(Rect2(604, 181, 10, 38), Color("#18232f"))
	c.draw_line(Vector2(610, 184), Vector2(610, 216), GOLD, 2)
	for mark: int in range(4):
		c.draw_rect(Rect2(264 + mark * 30, 341, 22, 3), GOLD if mark < mini(room, 4) else Color("#364453"))

func _torch(c: Node2D, p: Vector2, elapsed: float) -> void:
	c.draw_rect(Rect2(p + Vector2(-3, -2), Vector2(6, 9)), Color("#161e29"))
	c.draw_rect(Rect2(p + Vector2(-1, -4), Vector2(2, 8)), Color("#7d6556"))
	var lean: float = 1 if int(elapsed * 5 + p.x) % 2 == 0 else -1
	c.draw_rect(Rect2(p + Vector2(-3 + lean, -10), Vector2(6, 7)), Color("#d3824a"))
	c.draw_rect(Rect2(p + Vector2(-1, -8), Vector2(3, 5)), Color("#f3d686"))

func _player(c: Node2D, combat, elapsed: float) -> void:
	var p: Vector2 = Vector2(combat.p).round()
	var job: String = String(combat.job)
	var color: Color = JOB_COLORS.get(job, JOB_COLORS.warrior)
	var direction: Vector2 = Vector2(combat.aim)
	var invuln: float = float(combat.invuln)
	if invuln > 0 and int(elapsed * 20) % 2 == 0:
		color = Color("#fff2d2")
	if float(combat.dash_left) > 0:
		c.draw_line(p - direction * 20, p, Color(0.59, 0.83, 0.88, 0.45), 6)
	_shadow(c, p, 10)
	if float(combat.rage) > 0:
		c.draw_arc(p, 16, elapsed * 2, elapsed * 2 + PI * 1.6, 20, Color("#f4a07e"), 2)
	# 공통 몸체와 직업별 모자·옷·무기. 도형은 논리 픽셀에 정렬한다.
	c.draw_rect(Rect2(p + Vector2(-6, -8), Vector2(12, 16)), INK)
	c.draw_rect(Rect2(p + Vector2(-5, -6), Vector2(10, 10)), color.darkened(0.20))
	c.draw_rect(Rect2(p + Vector2(-3, -13), Vector2(7, 7)), INK)
	c.draw_rect(Rect2(p + Vector2(-2, -12), Vector2(5, 5)), Color("#e6c6a0"))
	c.draw_rect(Rect2(p + Vector2(-5, 4), Vector2(4, 5)), Color("#202837"))
	c.draw_rect(Rect2(p + Vector2(2, 4), Vector2(4, 5)), Color("#202837"))
	c.draw_rect(Rect2(p + Vector2(-4, -6), Vector2(8, 2)), color.lightened(0.28))
	match job:
		"warrior":
			c.draw_rect(Rect2(p + Vector2(-4, -14), Vector2(10, 4)), Color("#9fc6d0"))
			c.draw_rect(Rect2(p + Vector2(-9, -5), Vector2(4, 8)), Color("#7196a4"))
		"berserker":
			c.draw_rect(Rect2(p + Vector2(-4, -14), Vector2(9, 3)), Color("#ab5a58"))
			c.draw_line(p + Vector2(-4, -12), p + Vector2(-8, -17), Color("#e7c5a0"), 2)
			c.draw_line(p + Vector2(4, -12), p + Vector2(8, -17), Color("#e7c5a0"), 2)
		"archer", "hunter":
			c.draw_rect(Rect2(p + Vector2(-4, -15), Vector2(10, 4)), color)
			c.draw_rect(Rect2(p + Vector2(4, -13), Vector2(5, 2)), color)
			if job == "hunter":
				c.draw_line(p + Vector2(-2, -14), p + Vector2(-6, -20), Color("#dfc783"), 2)
		"mage", "firemage":
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(-7, -11), p + Vector2(0, -24), p + Vector2(7, -11)]), color.darkened(0.12))
			c.draw_rect(Rect2(p + Vector2(-8, -12), Vector2(17, 3)), color.lightened(0.12))
	_weapon(c, p, direction, job, color)
	if float(combat.attack_flash) > 0:
		var angle: float = Vector2(combat.attack_dir).angle()
		var reach: float = 44 if job == "berserker" else 32
		if job in ["warrior", "berserker"]:
			c.draw_arc(p, reach, angle - 0.85, angle + 0.85, 18, Color("#f9e4a5"), 3)
	# 작은 조준점. 커서 전체를 덮지 않고 진행 방향만 보여준다.
	var tip: Vector2 = (p + direction * 28).round()
	c.draw_rect(Rect2(tip - Vector2.ONE, Vector2(3, 3)), PALE)

func _weapon(c: Node2D, p: Vector2, direction: Vector2, job: String, color: Color) -> void:
	var side := Vector2(-direction.y, direction.x)
	var hand: Vector2 = p + direction * 7 + side * 3
	match job:
		"warrior":
			c.draw_line(hand, hand + direction * 16, Color("#b7d5db"), 3)
			c.draw_line(hand - side * 4, hand + side * 4, GOLD, 2)
		"berserker":
			c.draw_line(hand, hand + direction * 20, Color("#987c67"), 3)
			c.draw_line(hand + direction * 15 - side * 7, hand + direction * 15 + side * 7, Color("#d4bcc1"), 6)
		"archer", "hunter":
			var middle: Vector2 = p + direction * 11
			c.draw_line(middle - side * 10, middle + direction * 5, Color("#b99461"), 2)
			c.draw_line(middle + side * 10, middle + direction * 5, Color("#b99461"), 2)
			c.draw_line(middle - side * 10, middle + side * 10, Color("#d6d2b5"), 1)
		"mage", "firemage":
			c.draw_line(hand - side * 5, hand + direction * 13, Color("#b99d80"), 3)
			c.draw_rect(Rect2(hand + direction * 13 - Vector2(3, 3), Vector2(6, 6)), color.lightened(0.35))

func _enemy(c: Node2D, actor: Dictionary, elapsed: float) -> void:
	var p: Vector2 = Vector2(actor.get("pos", Vector2.ZERO)).round()
	var kind: String = String(actor.get("kind", "melee"))
	var large: bool = kind in ["elite", "boss"]
	var scale: float = 1.6 if large else 1.0
	_shadow(c, p, 12 if large else 9)
	var color := Color("#bd776f")
	if kind == "ranged":
		color = Color("#ad98ba")
	elif kind == "charger":
		color = Color("#b99b79")
	elif kind == "elite":
		color = Color("#b4ac8c")
	elif kind == "boss":
		color = Color("#a3899d")
	if float(actor.get("flash", 0)) > 0:
		color = PALE
	c.draw_rect(Rect2(p + Vector2(-7, -14) * scale, Vector2(14, 20) * scale), INK)
	c.draw_rect(Rect2(p + Vector2(-6, -8) * scale, Vector2(12, 12) * scale), color.darkened(0.20))
	c.draw_rect(Rect2(p + Vector2(-5, -15) * scale, Vector2(10, 9) * scale), color)
	c.draw_rect(Rect2(p + Vector2(-4, -12) * scale, Vector2(8, 2) * scale), INK)
	c.draw_rect(Rect2(p + Vector2(-3, -12) * scale, Vector2(2, 1) * scale), Color("#f7ca8c"))
	c.draw_rect(Rect2(p + Vector2(2, -12) * scale, Vector2(2, 1) * scale), Color("#f7ca8c"))
	c.draw_rect(Rect2(p + Vector2(-6, 4) * scale, Vector2(4, 4) * scale), Color("#252333"))
	c.draw_rect(Rect2(p + Vector2(2, 4) * scale, Vector2(4, 4) * scale), Color("#252333"))
	match kind:
		"melee":
			c.draw_line(p + Vector2(7, -3), p + Vector2(15, -12), Color("#b7c3c5"), 3)
		"ranged":
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(-8, -13), p + Vector2(0, -22), p + Vector2(8, -13)]), color.darkened(0.18))
			c.draw_line(p + Vector2(9, -2), p + Vector2(13, -18), Color("#a5876f"), 3)
		"charger", "elite":
			c.draw_rect(Rect2(p + Vector2(-10, -7) * scale, Vector2(5, 13) * scale), color.lightened(0.2))
			c.draw_line(p + Vector2(7, 2) * scale, p + Vector2(13, -15) * scale, Color("#c1b6a0"), 3)
			if kind == "elite":
				c.draw_arc(p, 18, 0, TAU, 24, GOLD, 1)
				c.draw_rect(Rect2(p + Vector2(-4, -28), Vector2(8, 3)), GOLD)
		"boss":
			c.draw_rect(Rect2(p + Vector2(-16, -13), Vector2(8, 12)), Color("#c5acb7"))
			c.draw_rect(Rect2(p + Vector2(10, -13), Vector2(8, 12)), Color("#c5acb7"))
			c.draw_line(p + Vector2(12, -1), p + Vector2(27, -26), Color("#c4a581"), 4)
			c.draw_line(p + Vector2(17, -28), p + Vector2(34, -18), Color("#e1c8c5"), 9)
	if float(actor.get("burn", 0)) > 0:
		c.draw_rect(Rect2(p + Vector2(-7, -21), Vector2(3, 5)), Color("#f5b46e"))
		c.draw_rect(Rect2(p + Vector2(4, -24), Vector2(3, 7)), Color("#e77c55"))
	if float(actor.get("root", 0)) > 0:
		c.draw_line(p + Vector2(-12, 1), p + Vector2(12, 1), Color("#b8c58c"), 2)
		c.draw_line(p + Vector2(-8, -3), p + Vector2(8, 5), Color("#b8c58c"), 2)
	if float(actor.get("slow", 0)) > 0:
		c.draw_arc(p, 17, elapsed, elapsed + PI * 1.5, 14, Color("#89b7c4"), 1)
	if kind != "boss":
		var width: float = 28 if large else 20
		var hp_fraction: float = clampf(float(actor.get("hp", 0)) / maxf(1, float(actor.get("max_hp", 60))), 0, 1)
		var bar_p: Vector2 = p + Vector2(-width / 2, -32 if large else -26)
		c.draw_rect(Rect2(bar_p, Vector2(width, 3)), Color("#111822"))
		c.draw_rect(Rect2(bar_p, Vector2(width * hp_fraction, 3)), GOLD if large else Color("#c88e86"))

func _warning(c: Node2D, actor: Dictionary, elapsed: float) -> void:
	if String(actor.get("state", "")) not in ["windup", "prepare", "telegraph"]:
		return
	var p: Vector2 = actor.get("pos", Vector2.ZERO)
	var direction: Vector2 = actor.get("dir", Vector2.RIGHT)
	var kind: String = String(actor.get("kind", "melee"))
	var pattern: String = str(actor.get("pattern", ""))
	var outline := Color("#f2c46d")
	var fill := Color(0.93, 0.45, 0.22, 0.16)
	if kind in ["charger", "elite"] or (kind == "boss" and pattern in ["charge", "dash", "1"]):
		var distance: float = 224 if kind == "boss" else (208 if kind == "elite" else 144)
		var side := Vector2(-direction.y, direction.x) * (14 if kind == "boss" else 9)
		var points := PackedVector2Array([p - side, p + side, p + direction * distance + side, p + direction * distance - side])
		c.draw_colored_polygon(points, fill)
		c.draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), outline, 1)
		c.draw_line(p, p + direction * distance, outline, 1)
	elif kind == "boss" and pattern in ["slam", "smash", "2"]:
		c.draw_circle(p, 88, fill)
		c.draw_arc(p, 88, 0, TAU, 40, outline, 2)
		c.draw_line(p + Vector2(-9, 0), p + Vector2(9, 0), outline, 2)
		c.draw_line(p + Vector2(0, -9), p + Vector2(0, 9), outline, 2)
	else:
		var radius: float = 72 if kind == "boss" else 26
		var half: float = deg_to_rad(80 if kind == "boss" else 60)
		var angle: float = direction.angle()
		var sector := PackedVector2Array([p])
		for index: int in range(13):
			sector.append(p + Vector2.from_angle(angle - half + half * 2 * index / 12) * radius)
		c.draw_colored_polygon(sector, fill)
		c.draw_arc(p, radius, angle - half, angle + half, 18, outline, 2)
		c.draw_line(p, sector[1], outline, 1)
		c.draw_line(p, sector[sector.size() - 1], outline, 1)
	# 시간 정보가 없어도 경고는 항상 같은 모양이며 흔들리지 않는다.
	if int(elapsed * 6) % 2 == 0:
		c.draw_rect(Rect2(p + Vector2(-1, -34), Vector2(3, 6)), outline)

func _projectile(c: Node2D, projectile: Dictionary) -> void:
	var p: Vector2 = Vector2(projectile.get("pos", Vector2.ZERO)).round()
	var direction: Vector2 = projectile.get("dir", Vector2.RIGHT)
	var friendly: bool = bool(projectile.get("friendly", false))
	var color: Color = projectile.get("color", PALE if friendly else Color("#f49a90"))
	var radius: float = float(projectile.get("radius", 3))
	c.draw_line(p - direction * (8 if friendly else 5), p, color.darkened(0.25), maxf(1, radius))
	c.draw_rect(Rect2(p - Vector2(radius, radius), Vector2(radius * 2, radius * 2)), color)
	if friendly:
		c.draw_rect(Rect2(p - Vector2.ONE, Vector2(2, 2)), PALE)

func _zone(c: Node2D, zone: Dictionary, elapsed: float) -> void:
	var p: Vector2 = zone.get("pos", Vector2.ZERO)
	var radius: float = float(zone.get("radius", 32))
	var kind: String = String(zone.get("kind", ""))
	var color: Color = zone.get("color", Color("#d99c69"))
	var transparent: Color = color
	transparent.a = 0.16
	c.draw_circle(p, radius, transparent)
	c.draw_arc(p, radius, 0, TAU, 28, color, 1)
	for index: int in range(7):
		var angle: float = index * TAU / 7 + elapsed * 0.35
		var location: Vector2 = p + Vector2.from_angle(angle) * radius * 0.60
		if kind.contains("rain"):
			c.draw_line(location + Vector2(3, -9), location + Vector2(-2, 3), color, 2)
		else:
			c.draw_rect(Rect2(location.round() - Vector2(2, 4), Vector2(4, 7)), color)

func _trap(c: Node2D, trap: Dictionary) -> void:
	var p: Vector2 = Vector2(trap.get("pos", Vector2.ZERO)).round()
	c.draw_rect(Rect2(p - Vector2(9, 7), Vector2(18, 14)), Color("#303725"))
	c.draw_line(p + Vector2(-8, -6), p + Vector2(-8, 6), Color("#c7bd8e"), 2)
	c.draw_line(p + Vector2(8, -6), p + Vector2(8, 6), Color("#c7bd8e"), 2)
	for tooth: int in range(-1, 2):
		c.draw_rect(Rect2(p + Vector2(tooth * 5 - 1, -5), Vector2(2, 3)), GOLD)
		c.draw_rect(Rect2(p + Vector2(tooth * 5 - 1, 3), Vector2(2, 3)), GOLD)
	c.draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), Color("#a59e74"))

func _boss_bar(c: Node2D, enemies: Array[Dictionary]) -> void:
	for actor: Dictionary in enemies:
		if String(actor.get("kind", "")) != "boss" or float(actor.get("hp", 0)) <= 0:
			continue
		var fraction: float = clampf(float(actor.get("hp", 0)) / maxf(1, float(actor.get("max_hp", 2400))), 0, 1)
		c.draw_rect(Rect2(168, 78, 304, 10), INK)
		c.draw_rect(Rect2(170, 80, 300 * fraction, 6), Color("#ba6b73"))
		for index: int in range(1, 4):
			c.draw_line(Vector2(170 + index * 75, 80), Vector2(170 + index * 75, 86), Color("#503a49"), 1)
		c.draw_string(label_font, Vector2(282, 102), "성문 수문장", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, PALE)
		break

func _shadow(c: Node2D, p: Vector2, radius: float) -> void:
	c.draw_rect(Rect2(p + Vector2(-radius, 5), Vector2(radius * 2, 5)), Color(0.03, 0.05, 0.08, 0.5))

func paint_ending(c: Node2D) -> void:
	# 구출 이미지를 외부 파일 대신 원본 픽셀풍 삽화로 제공한다.
	c.draw_rect(Rect2(152, 94, 336, 164), Color("#222d3e"))
	for x: int in range(168, 480, 24):
		c.draw_rect(Rect2(x, 108, 20, 40), Color("#526172"))
		c.draw_rect(Rect2(x, 108, 12, 8), Color("#728496"))
	c.draw_rect(Rect2(296, 114, 48, 100), Color("#101c2a"))
	c.draw_rect(Rect2(300, 118, 40, 96), Color("#bcaa84"))
	for y: int in range(214, 250, 8):
		c.draw_rect(Rect2(200 - (y - 214) / 2, y, 240 + y - 214, 7), Color("#526172"))
	var p := Vector2(344, 198)
	c.draw_rect(Rect2(p + Vector2(-8, -14), Vector2(16, 22)), Color("#d9a1b5"))
	c.draw_rect(Rect2(p + Vector2(-5, -25), Vector2(10, 12)), Color("#edceaa"))
	c.draw_rect(Rect2(p + Vector2(-6, -27), Vector2(12, 4)), GOLD)
	for x: int in [-4, 0, 4]:
		c.draw_rect(Rect2(p + Vector2(x - 1, -30), Vector2(3, 5)), GOLD)
	var h := Vector2(288, 201)
	c.draw_rect(Rect2(h + Vector2(-7, -13), Vector2(14, 20)), Color("#6eb4ca"))
	c.draw_rect(Rect2(h + Vector2(-4, -22), Vector2(8, 9)), Color("#e9c8a4"))
	c.draw_rect(Rect2(h + Vector2(-6, -25), Vector2(12, 5)), Color("#a9c6cc"))
	c.draw_line(h + Vector2(-10, -4), h + Vector2(-14, 12), Color("#d7d6bc"), 3)
	c.draw_line(h + Vector2(7, -5), p + Vector2(-8, -5), GOLD, 2)
