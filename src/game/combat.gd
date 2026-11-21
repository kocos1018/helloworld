extends RefCounted
## Pure simulation: root owns screens, pause, choices and rendering.
const ARENA := Rect2(24, 64, 592, 272)
const BASIC_INTERVAL := {"warrior": 0.5, "berserker": 0.85, "archer": 0.45, "hunter": 0.45, "mage": 0.6, "firemage": 0.7}
const BASIC_DAMAGE := {"warrior": 20.0, "berserker": 32.0, "archer": 18.0, "hunter": 18.0, "mage": 22.0, "firemage": 14.0}
const SKILL_BASE := {"warrior": 6.0, "berserker": 8.0, "archer": 6.0, "hunter": 6.0, "mage": 6.0, "firemage": 7.0}
var p := Vector2(100, 200)
var aim := Vector2.RIGHT
var hp: float = 100.0
var max_hp: float = 100.0
var meter: float = 0.0
var job: String = "warrior"
var stacks: Array[int] = [0, 0, 0, 0]
var enemies: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var zones: Array[Dictionary] = []
var traps: Array[Dictionary] = []
var events: Array[Dictionary] = []
var dash_cd: float = 0.0
var dash_left: float = 0.0
var skill_cd: float = 0.0
var charges: int = 3
var charge_time: float = 0.0
var clock: float = 0.0
var defeated: bool = false
var completed: bool = false
var kills: int = 0
var room: int = 1
var spawn_variant: int = 0
var invuln: float = 0.0
var rage: float = 0.0
var attack_flash: float = 0.0
var attack_dir := Vector2.RIGHT
var attack_cd: float = 0.0
var ultimate_lock: float = 0.0
var cast_left: float = 0.0
var cast_action: String = ""
var cast_target := Vector2.ZERO
var cast_direction := Vector2.RIGHT
var swing: Dictionary = {}
var dash_direction := Vector2.RIGHT
var move_left: float = 0.0
var move_direction := Vector2.RIGHT
var move_speed: float = 0.0
var landing: bool = false
var _life_budget: float = 2.0
var _meter_budget: float = 10.0
var _serial: int = 0
var _wave: int = 0
var _waves: Array = []
var _spawn_wait: float = 1.0
var _mouse := Vector2.ZERO
var _room_kills: int = 0
var _channeling: bool = false

func reset(base_job: String) -> void:
	job = base_job if base_job in ["warrior", "archer", "mage"] else "warrior"
	stacks = [0, 0, 0, 0]
	max_hp = 100.0
	hp = max_hp
	meter = 0.0
	clock = 0.0
	kills = 0
	attack_cd = 0.0
	_serial = 0
	dash_cd = 0.0
	skill_cd = 0.0
	charges = 3
	charge_time = 0.0
	_life_budget = 2.0
	_meter_budget = 10.0
	start_room(1)

func start_room(number: int) -> void:
	room = clampi(number, 1, 5)
	spawn_variant = randi_range(0, 2) if room < 5 else 0
	p = Vector2(100, 200)
	aim = Vector2.RIGHT
	enemies.clear()
	projectiles.clear()
	zones.clear()
	traps.clear()
	events.clear()
	swing.clear()
	cast_left = 0.0
	cast_action = ""
	move_left = 0.0
	landing = false
	dash_left = 0.0
	attack_flash = 0.0
	invuln = 0.0
	rage = 0.0
	ultimate_lock = 0.0
	completed = false
	defeated = hp <= 0.0
	_wave = 0
	_room_kills = 0
	_spawn_wait = 1.0
	match room:
		1: _waves = [["melee", "melee", "melee", "melee"], ["melee", "melee", "melee", "melee", "ranged", "ranged", "ranged", "ranged"]]
		2: _waves = [["melee", "melee", "melee", "ranged", "ranged"], ["melee", "melee", "melee", "ranged", "ranged", "charger", "charger"]]
		3: _waves = [["elite", "melee", "melee", "ranged"], ["melee", "melee", "ranged"]]
		4: _waves = [["melee", "melee", "melee", "melee", "ranged", "ranged", "charger", "charger"], ["melee", "melee", "melee", "melee", "ranged", "ranged", "charger", "charger"]]
		5: _waves = [["boss"]]

func promote() -> void:
	job = {"warrior": "berserker", "archer": "hunter", "mage": "firemage"}.get(job, job)
	skill_cd = 0.0
	charges = 3
	charge_time = 0.0
	cast_action = ""
	cast_left = 0.0
	projectiles.clear()
	zones.clear()
	traps.clear()
	rage = 0.0
	ultimate_lock = 0.0

func upgrade(index: int) -> void:
	if index < 0 or index > 3:
		return
	var old_cdr: float = cdr_factor()
	var old_speed: float = speed_factor()
	stacks[index] += 1
	if index == 2:
		max_hp += 20.0
		hp = minf(max_hp, hp + 20.0)
	if index == 3:
		skill_cd *= cdr_factor() / old_cdr
		charge_time *= cdr_factor() / old_cdr
	if index == 1:
		attack_cd *= old_speed / speed_factor()

func heal() -> void:
	hp = minf(max_hp, hp + max_hp * 0.3)

func remaining() -> int:
	var alive: int = 0
	for e: Dictionary in enemies:
		if float(e.hp) > 0.0:
			alive += 1
	return alive

func low_health() -> float:
	if job != "berserker":
		return 0.0
	return 1.0 if rage > 0.0 else clampf((0.6 - hp / max_hp) / 0.4, 0.0, 1.0)

func power() -> float:
	return 1.0 + 0.15 * stacks[0] + 0.5 * low_health()

func speed_factor() -> float:
	return 1.0 + 0.1 * stacks[1] + 0.35 * low_health()

func cdr_factor() -> float:
	return maxf(0.5, 1.0 - 0.08 * stacks[3])

func get_status() -> String:
	if _spawn_wait > 0.0:
		return "다음 적 등장 준비"
	if rage > 0.0:
		return "피의 격노 %.1f초" % rage
	return ""

func tick(delta: float, movement: Vector2, mouse: Vector2, attack: bool, dodge: bool, skill: bool, ultimate: bool) -> void:
	if completed or defeated:
		return
	clock += delta
	_mouse = mouse
	var offset: Vector2 = mouse - p
	if offset.length_squared() > 1.0:
		aim = offset.normalized()
	for key: String in ["dash_cd", "skill_cd", "invuln", "rage", "attack_flash", "attack_cd", "ultimate_lock"]:
		set(key, maxf(0.0, float(get(key)) - delta))
	_life_budget = minf(2.0, _life_budget + 2.0 * delta)
	_meter_budget = minf(10.0, _meter_budget + 10.0 * delta)
	_tick_charges(delta)
	var moving: Vector2 = movement.limit_length(1.0)
	if dodge and dash_cd <= 0.0 and dash_left <= 0.0:
		dash_direction = moving.normalized() if moving.length_squared() > 0.01 else aim
		dash_left = 0.16
		dash_cd = 1.0
		invuln = maxf(invuln, 0.12)
		cast_action = ""
		cast_left = 0.0
		swing.clear()
		move_left = 0.0
		landing = false
		for z: Dictionary in zones:
			if z.get("channel", false):
				z.left = 0.0
	_channeling = false
	for z: Dictionary in zones:
		if z.get("channel", false) and float(z.left) > 0.0:
			_channeling = true
	if dash_left > 0.0:
		var step: float = minf(delta, dash_left)
		p = clamp_position(p + dash_direction * 450.0 * step, 8.0)
		dash_left = maxf(0.0, dash_left - delta)
	elif move_left > 0.0:
		var step: float = minf(delta, move_left)
		p = clamp_position(p + move_direction * move_speed * step, 8.0)
		move_left = maxf(0.0, move_left - delta)
		if move_left <= 0.0 and landing:
			area_hit(p, 48.0, 65.0 * power())
			flash_zone(p, 48.0, "slam", Color("#fbc394"))
			landing = false
	else:
		var channeling: bool = false
		for z: Dictionary in zones:
			if z.get("channel", false) and float(z.left) > 0.0:
				channeling = true
		if not channeling:
			p = clamp_position(p + moving * 110.0 * delta, 8.0)
	if cast_left > 0.0:
		cast_left = maxf(0.0, cast_left - delta)
		if cast_left <= 0.0:
			_execute_cast()
	if dash_left <= 0.0 and move_left <= 0.0 and cast_left <= 0.0 and not _channeling:
		if ultimate and meter >= 100.0 and ultimate_lock <= 0.0:
			_cast_ultimate()
		elif skill and (charges > 0 if job == "hunter" else skill_cd <= 0.0):
			_cast_skill()
		elif attack and attack_cd <= 0.0:
			_basic_attack()
	_tick_swing(delta)
	_tick_traps(delta)
	_tick_projectiles(delta)
	_tick_zones(delta)
	for e: Dictionary in enemies:
		if float(e.hp) > 0.0:
			_tick_burn(e, delta)
		if float(e.hp) > 0.0:
			_tick_enemy(e, delta)
		if hp <= 0.0:
			break
	if hp <= 0.0:
		hp = 0.0
		defeated = true
		return
	if remaining() == 0:
		if _wave < _waves.size():
			if _spawn_wait < 0.0:
				_spawn_wait = 1.0
			_spawn_wait -= delta
			if _spawn_wait <= 0.0:
				_spawn_wave()
		else:
			completed = true
			projectiles.clear()
			zones.clear()
			traps.clear()

func _tick_charges(delta: float) -> void:
	if job != "hunter" or charges >= 3:
		return
	charge_time += delta
	var duration: float = 6.0 * cdr_factor()
	while charge_time >= duration and charges < 3:
		charge_time -= duration
		charges += 1
	if charges >= 3:
		charge_time = 0.0

func _basic_attack() -> void:
	attack_cd = float(BASIC_INTERVAL[job]) / speed_factor()
	attack_dir = aim
	attack_flash = 0.2
	if job in ["warrior", "berserker"]:
		swing = {"age": 0.0, "delay": 0.1 / speed_factor(), "end": 0.2 / speed_factor(), "ids": [], "dir": aim, "damage": float(BASIC_DAMAGE[job]) * power(), "reach": 44.0 if job == "berserker" else 32.0, "angle": 70.0 if job == "berserker" else 50.0}
	else:
		var color: Color = Color("#f6dd8a") if job in ["archer", "hunter"] else Color("#9bbdfd")
		if job == "firemage":
			color = Color("#ff904d")
		var speed: float = 360.0 if job in ["archer", "hunter"] else (260.0 if job == "firemage" else 280.0)
		var reach: float = 320.0 if job in ["archer", "hunter"] else 300.0
		_spawn_projectile(p, aim, float(BASIC_DAMAGE[job]) * power(), speed, reach, true, "basic", color)

func _tick_swing(delta: float) -> void:
	if swing.is_empty():
		return
	var previous: float = float(swing.age)
	swing.age = previous + delta
	if float(swing.age) >= float(swing.delay) and previous < float(swing.end):
		for e: Dictionary in enemies:
			if float(e.hp) <= 0.0 or int(e.id) in swing.ids:
				continue
			var offset: Vector2 = e.pos - p
			if offset.length() <= float(swing.reach) + float(e.radius) * 0.35 and absf(Vector2(swing.dir).angle_to(offset)) <= deg_to_rad(float(swing.angle)):
				_hit(e, float(swing.damage), false, true)
				swing.ids.append(int(e.id))
	if float(swing.age) >= float(swing.end):
		swing.clear()

func _cast_skill() -> void:
	cast_target = _aim_target(96.0 if job == "hunter" else 240.0)
	cast_direction = aim
	if job == "hunter":
		charges -= 1
	else:
		skill_cd = float(SKILL_BASE[job]) * cdr_factor()
	cast_action = "skill"
	cast_left = 0.1
	attack_cd = maxf(attack_cd, 0.2)

func _cast_ultimate() -> void:
	meter = 0.0
	cast_target = _aim_target(240.0)
	cast_direction = aim
	cast_action = "ultimate"
	cast_left = 0.15 if job == "berserker" else 0.2
	ultimate_lock = 6.15 if job == "berserker" else 0.35
	attack_cd = maxf(attack_cd, 0.35)

func _execute_cast() -> void:
	var action: String = cast_action
	cast_action = ""
	if action == "skill":
		match job:
			"warrior":
				line_hit(p, cast_direction, 80.0, 24.0, 50.0 * power())
				move_direction = cast_direction
				move_speed = 400.0
				move_left = 0.2
				flash_zone(p + cast_direction * 40.0, 36.0, "slash", Color("#e6e7b1"))
			"berserker":
				var offset: Vector2 = cast_target - p
				move_direction = offset.normalized()
				move_speed = minf(128.0, offset.length()) / 0.35
				move_left = 0.35
				landing = true
			"archer":
				_spawn_projectile(p, cast_direction, 30.0 * power(), 400.0, 280.0, true, "push", Color("#c3f9da"))
			"hunter":
				if traps.size() >= 3:
					traps.remove_at(0)
				traps.append({"pos": cast_target, "left": 30.0, "arm": 0.25})
			"mage":
				area_hit(p, 48.0, 24.0 * power(), false, false, 32.0)
				flash_zone(p, 48.0, "shock", Color("#a2c7ff"))
			"firemage":
				_spawn_projectile(p, cast_direction, 45.0 * power(), 240.0, 240.0, true, "fireball", Color("#ffb46a"))
	elif action == "ultimate":
		match job:
			"warrior":
				area_hit(p, 72.0, 100.0 * power(), true)
				flash_zone(p, 72.0, "whirl", Color("#fff2bf"))
			"berserker": rage = 6.0
			"archer":
				line_hit(p, cast_direction, 360.0, 20.0, 140.0 * power(), true)
				zones.append({"pos": p, "dir": cast_direction, "radius": 360.0, "left": 0.25, "total": 0.25, "kind": "arrowbeam", "color": Color("#f9e8a0"), "visual": true})
			"hunter":
				_make_zone(cast_target, 64.0, 22.0 * power(), 0.4, 5, 0.2, "rain", false)
				ultimate_lock = 2.0
			"mage":
				_make_zone(p, 320.0, 35.0 * power(), 0.25, 4, 0.25, "beam", false)
				ultimate_lock = 1.0
			"firemage":
				_make_zone(cast_target, 72.0, 18.0 * power(), 0.5, 6, 0.25, "storm", true)
				ultimate_lock = 3.0

func _make_zone(point: Vector2, radius: float, damage: float, interval: float, count: int, delay: float, kind: String, burns: bool) -> void:
	zones.append({"pos": point, "dir": cast_direction, "radius": radius, "left": delay + (count - 1) * interval + 0.1, "total": delay + (count - 1) * interval + 0.1, "kind": kind, "color": Color("#ff884c") if burns else Color("#8cbbfb"), "damage": damage, "interval": interval, "ticks": count, "timer": delay, "burns": burns, "channel": kind == "beam", "visual": false})

func flash_zone(point: Vector2, radius: float, kind: String, color: Color) -> void:
	zones.append({"pos": point, "radius": radius, "left": 0.25, "total": 0.25, "kind": kind, "color": color, "visual": true})

func _tick_zones(delta: float) -> void:
	for z: Dictionary in zones:
		if float(z.left) <= 0.0:
			continue
		z.left = float(z.left) - delta
		if not z.get("visual", false) and float(z.left) > -0.1:
			z.timer = float(z.timer) - delta
			while float(z.timer) <= 0.0 and int(z.ticks) > 0 and float(z.left) > -0.1:
				z.timer = float(z.timer) + float(z.interval)
				z.ticks = int(z.ticks) - 1
				if z.kind == "beam":
					line_hit(Vector2(z.pos), Vector2(z.dir), 320.0, 20.0, float(z.damage), true)
				else:
					area_hit(Vector2(z.pos), float(z.radius), float(z.damage), true, bool(z.burns))
	for i: int in range(zones.size() - 1, -1, -1):
		if float(zones[i].left) <= 0.0:
			zones.remove_at(i)

func _tick_traps(delta: float) -> void:
	for trap: Dictionary in traps:
		trap.left = float(trap.left) - delta
		trap.arm = float(trap.arm) - delta
		if float(trap.arm) > 0.0:
			continue
		var closest: Dictionary = {}
		var distance: float = INF
		for e: Dictionary in enemies:
			var d: float = Vector2(e.pos).distance_to(Vector2(trap.pos))
			if float(e.hp) > 0.0 and d <= 12.0 + float(e.radius) and d < distance:
				closest = e
				distance = d
		if not closest.is_empty():
			if closest.kind == "boss":
				closest.slow = 2.0
			else:
				closest.root = 1.0 if closest.kind == "elite" else 2.0
				if closest.state == "charge":
					closest.state = "recover"
					closest.timer = 0.5
			_hit(closest, 10.0 * power())
			trap.left = 0.0
	for i: int in range(traps.size() - 1, -1, -1):
		if float(traps[i].left) <= 0.0:
			traps.remove_at(i)

func _spawn_projectile(point: Vector2, direction: Vector2, damage: float, speed: float, reach: float, friendly: bool, kind: String, color: Color, target: int = -1) -> void:
	projectiles.append({"pos": point, "dir": direction.normalized(), "damage": damage, "speed": speed, "travel": reach, "friendly": friendly, "kind": kind, "radius": 4.0, "color": color, "target": target})

func _tick_projectiles(delta: float) -> void:
	var original_count: int = projectiles.size()
	for i: int in range(original_count):
		var bullet: Dictionary = projectiles[i]
		if float(bullet.travel) <= 0.0:
			continue
		var previous: Vector2 = bullet.pos
		var step: float = minf(float(bullet.travel), float(bullet.speed) * delta)
		bullet.pos = previous + Vector2(bullet.dir) * step
		bullet.travel = float(bullet.travel) - step
		if not ARENA.has_point(Vector2(bullet.pos)):
			bullet.travel = 0.0
		if bool(bullet.friendly):
			for e: Dictionary in enemies:
				if float(e.hp) <= 0.0 or (int(bullet.target) >= 0 and int(e.id) != int(bullet.target)):
					continue
				var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2(e.pos), previous, Vector2(bullet.pos))
				if nearest.distance_to(Vector2(e.pos)) <= float(e.radius) + float(bullet.radius):
					var marked: bool = float(e.root) > 0.0 or float(e.slow) > 0.0
					if bullet.kind == "fireball":
						bullet.hit = true
						_explode(Vector2(bullet.pos), 56.0, float(bullet.damage), false)
					else:
						_hit(e, float(bullet.damage), false, bullet.kind == "basic")
						if job == "firemage" and bullet.kind == "basic":
							_explode(Vector2(bullet.pos), 24.0, 8.0 * power(), false)
						if bullet.kind == "push":
							_knock(e, Vector2(bullet.dir), 48.0)
						if job == "hunter" and bullet.kind == "basic" and marked:
							var offset: Vector2 = e.pos - p
							_spawn_projectile(p, offset if offset.length_squared() > 0.0 else aim, 9.0 * power(), 420.0, 400.0, true, "extra", Color("#fff3b9"), int(e.id))
					bullet.travel = 0.0
					break
		else:
			var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(p, previous, Vector2(bullet.pos))
			if nearest.distance_to(p) <= 10.0:
				_damage_player(float(bullet.damage))
				bullet.travel = 0.0
		if float(bullet.travel) <= 0.0 and bullet.kind == "fireball" and not bullet.get("exploded", false):
			# End-of-range detonation; collision branch marks itself below via one explosion guard.
			if not bullet.get("hit", false):
				_explode(clamp_position(Vector2(bullet.pos), 1.0), 56.0, float(bullet.damage), false)
			bullet.exploded = true
	for i: int in range(projectiles.size() - 1, -1, -1):
		if float(projectiles[i].travel) <= 0.0:
			projectiles.remove_at(i)

func _explode(point: Vector2, radius: float, damage: float, ultimate: bool) -> void:
	area_hit(point, radius, damage, ultimate, true)
	flash_zone(point, radius, "explosion", Color("#ff9c55"))

func area_hit(point: Vector2, radius: float, damage: float, ultimate: bool = false, burns: bool = false, knockback: float = 0.0) -> void:
	for e: Dictionary in enemies:
		if float(e.hp) <= 0.0 or Vector2(e.pos).distance_to(point) > radius + float(e.radius) * 0.35:
			continue
		_hit(e, damage, ultimate)
		if burns and float(e.hp) > 0.0:
			_burn(e, ultimate)
		if knockback > 0.0:
			_knock(e, Vector2(e.pos) - point, knockback)

func line_hit(point: Vector2, direction: Vector2, distance: float, width: float, damage: float, ultimate: bool = false) -> void:
	var end: Vector2 = clamp_position(point + direction * distance, 1.0)
	for e: Dictionary in enemies:
		if float(e.hp) <= 0.0:
			continue
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2(e.pos), point, end)
		if closest.distance_to(Vector2(e.pos)) <= width * 0.5 + float(e.radius):
			_hit(e, damage, ultimate)

func _knock(e: Dictionary, direction: Vector2, strength: float) -> void:
	if e.kind == "boss":
		return
	var distance: float = strength / 3.0 if e.kind == "elite" else strength
	e.pos = clamp_position(Vector2(e.pos) + direction.normalized() * distance, float(e.radius))

func _hit(e: Dictionary, amount: float, ultimate: bool = false, basic: bool = false) -> float:
	if float(e.hp) <= 0.0:
		return 0.0
	var actual: float = minf(float(e.hp), maxf(0.0, amount))
	e.hp = maxf(0.0, float(e.hp) - actual)
	e.flash = 0.12
	if not ultimate:
		_gain_meter(actual * 0.05)
	if job == "berserker" and basic:
		var healing: float = minf(minf(actual * 0.03, _life_budget), max_hp - hp)
		hp += healing
		_life_budget -= healing
	if float(e.hp) <= 0.0:
		kills += 1
		_room_kills += 1
		if not ultimate:
			_gain_meter(3.0)
	return actual

func _gain_meter(value: float) -> void:
	if ultimate_lock > 0.0:
		return
	var earned: float = minf(minf(value, _meter_budget), 100.0 - meter)
	meter += earned
	_meter_budget -= earned

func _burn(e: Dictionary, ultimate: bool) -> void:
	var strength: float = 1.5 * power()
	if float(e.burn) <= 0.0:
		e.burn_tick = 0.5
		e.burn_damage = strength
		e.burn_ultimate = ultimate
	elif strength > float(e.burn_damage):
		e.burn_damage = strength
		e.burn_ultimate = ultimate
	e.burn = 3.0

func _tick_burn(e: Dictionary, delta: float) -> void:
	if float(e.burn) <= 0.0:
		return
	var elapsed: float = minf(delta, float(e.burn))
	e.burn = maxf(0.0, float(e.burn) - delta)
	e.burn_tick = float(e.burn_tick) - elapsed
	while float(e.burn_tick) <= 0.00001 and float(e.hp) > 0.0:
		e.burn_tick = float(e.burn_tick) + 0.5
		_hit(e, float(e.burn_damage), bool(e.burn_ultimate))

func _damage_player(amount: float) -> void:
	if hp <= 0.0 or invuln > 0.0:
		return
	hp = maxf(0.0, hp - amount)
	invuln = 0.5

func _spawn_wave() -> void:
	var entries: Array = _waves[_wave]
	_wave += 1
	_spawn_wait = -1.0
	for i: int in range(entries.size()):
		var kind: String = str(entries[i])
		var point := Vector2(330 + (i % 4) * 70, 105 + (i / 4) * 75)
		if spawn_variant == 1:
			point.y = 400.0 - point.y
		elif spawn_variant == 2:
			point += Vector2(-28 if i % 2 == 0 else 14, 28)
		if kind == "boss":
			point = Vector2(455, 200)
		if point.distance_to(p) < 72.0:
			point = Vector2(100.0 if p.x > 320.0 else 540.0, 110.0 + (i % 3) * 75.0)
		_spawn_enemy(kind, clamp_position(point, 20.0))

func _spawn_enemy(kind: String, point: Vector2) -> Dictionary:
	_serial += 1
	var health: float = {"melee": 60.0, "ranged": 50.0, "charger": 90.0, "elite": 240.0, "boss": 2400.0}.get(kind, 60.0)
	var enemy: Dictionary = {"id": _serial, "pos": point, "hp": health, "max_hp": health, "kind": kind, "state": "chase", "timer": 0.0, "dir": Vector2.LEFT, "burn": 0.0, "burn_tick": 0.5, "burn_damage": 0.0, "burn_ultimate": false, "root": 0.0, "slow": 0.0, "radius": 21.0 if kind == "boss" else (14.0 if kind == "elite" else 9.0), "cooldown": 0.5 + fmod(float(_serial) * 0.2, 0.8), "flash": 0.0, "pattern": 0, "pattern_used": 0, "windup_total": 0.4, "hit_player": false}
	enemies.append(enemy)
	return enemy

func _tick_enemy(e: Dictionary, delta: float) -> void:
	e.root = maxf(0.0, float(e.root) - delta)
	e.slow = maxf(0.0, float(e.slow) - delta)
	e.flash = maxf(0.0, float(e.flash) - delta)
	e.cooldown = maxf(0.0, float(e.cooldown) - delta)
	var offset: Vector2 = p - Vector2(e.pos)
	var distance: float = offset.length()
	var direction: Vector2 = offset.normalized() if distance > 0.01 else Vector2.LEFT
	var speed: float = 65.0 if e.kind == "melee" else (50.0 if e.kind == "ranged" else 40.0)
	if e.kind == "boss":
		speed = 45.0
	if float(e.slow) > 0.0:
		speed *= 0.7
	if e.state == "chase":
		var can_start: bool = false
		if e.kind == "melee":
			can_start = distance <= 25.0
		elif e.kind == "ranged":
			can_start = distance <= 240.0
		elif e.kind == "boss":
			can_start = true
		else:
			can_start = distance <= (240.0 if e.kind == "elite" else 192.0)
		if can_start and float(e.cooldown) <= 0.0:
			e.state = "windup"
			e.dir = direction
			e.pattern_used = int(e.pattern)
			e.hit_player = false
			e.timer = {"melee": 0.4, "ranged": 0.6, "charger": 0.8, "elite": 1.0, "boss": 1.0}.get(str(e.kind), 0.4)
			if e.kind == "boss" and int(e.pattern_used) == 0:
				e.timer = 0.8
			e.windup_total = float(e.timer)
		elif float(e.root) <= 0.0:
			if e.kind == "ranged" and distance < 144.0:
				e.pos = Vector2(e.pos) - direction * speed * delta
			elif distance > (180.0 if e.kind == "ranged" else 22.0):
				e.pos = Vector2(e.pos) + direction * minf(speed * delta, maxf(0.0, distance - 20.0))
	elif e.state == "windup":
		if float(e.timer) > 0.2:
			e.dir = direction
		e.timer = float(e.timer) - delta
		if float(e.timer) <= 0.0:
			_execute_enemy(e)
	elif e.state == "charge":
		var hit_wall: bool = false
		var multiplier: float = 0.7 if float(e.slow) > 0.0 else 1.0
		if float(e.root) <= 0.0:
			var old: Vector2 = e.pos
			var requested: Vector2 = old + Vector2(e.dir) * float(e.charge_speed) * minf(delta, float(e.timer)) * multiplier
			e.pos = clamp_position(requested, float(e.radius))
			hit_wall = not Vector2(e.pos).is_equal_approx(requested)
			var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(p, old, Vector2(e.pos))
			if not bool(e.hit_player) and nearest.distance_to(p) <= float(e.radius) + 8.0:
				_damage_player(float(e.charge_damage))
				e.hit_player = true
		e.timer = float(e.timer) - delta
		if float(e.timer) <= 0.0 or hit_wall:
			_recover(e)
	elif e.state == "recover":
		e.timer = float(e.timer) - delta
		if float(e.timer) <= 0.0:
			e.state = "chase"
	e.pos = clamp_position(Vector2(e.pos), float(e.radius))
	# Small separation keeps telegraphs readable without a navigation dependency.
	if e.state == "chase" and float(e.root) <= 0.0:
		for other: Dictionary in enemies:
			if int(other.id) == int(e.id) or float(other.hp) <= 0.0:
				continue
			var gap: Vector2 = Vector2(e.pos) - Vector2(other.pos)
			var minimum: float = float(e.radius) + float(other.radius) + 2.0
			if gap.length_squared() > 0.01 and gap.length() < minimum:
				e.pos = clamp_position(Vector2(e.pos) + gap.normalized() * 22.0 * delta, float(e.radius))

func _execute_enemy(e: Dictionary) -> void:
	var direction: Vector2 = e.dir
	var offset: Vector2 = p - Vector2(e.pos)
	if e.kind == "ranged":
		_spawn_projectile(Vector2(e.pos), direction, 10.0, 140.0, 320.0, false, "enemy", Color("#fb8d91"))
		_recover(e)
	elif e.kind in ["charger", "elite"] or (e.kind == "boss" and int(e.pattern_used) == 1):
		e.state = "charge"
		e.timer = 0.7 if e.kind == "boss" else (0.5 if e.kind == "elite" else 0.4)
		e.charge_speed = 320.0 if e.kind == "boss" else (416.0 if e.kind == "elite" else 360.0)
		e.charge_damage = 28.0 if e.kind == "boss" else (22.0 if e.kind == "elite" else 18.0)
	else:
		var reach: float = 26.0
		var damage: float = 12.0
		var half_angle: float = 60.0
		if e.kind == "boss":
			reach = 88.0 if int(e.pattern_used) == 2 else 72.0
			damage = 30.0 if int(e.pattern_used) == 2 else 24.0
			half_angle = 180.0 if int(e.pattern_used) == 2 else 80.0
		if offset.length() <= reach + 5.0 and absf(direction.angle_to(offset)) <= deg_to_rad(half_angle):
			_damage_player(damage)
		_recover(e)

func _recover(e: Dictionary) -> void:
	e.state = "recover"
	e.timer = {"melee": 0.4, "ranged": 0.3, "charger": 0.8, "elite": 1.0, "boss": 1.2}.get(str(e.kind), 0.4)
	e.cooldown = {"melee": 0.8, "ranged": 1.2, "charger": 1.8, "elite": 2.0, "boss": 1.5}.get(str(e.kind), 0.8)
	if e.kind == "boss":
		e.pattern = (int(e.pattern) + 1) % 3

func _aim_target(reach: float) -> Vector2:
	var offset: Vector2 = _mouse - p
	return clamp_position(p + offset.limit_length(reach), 12.0)

func clamp_position(point: Vector2, radius: float = 8.0) -> Vector2:
	return Vector2(clampf(point.x, ARENA.position.x + radius, ARENA.end.x - radius), clampf(point.y, ARENA.position.y + radius, ARENA.end.y - radius))
