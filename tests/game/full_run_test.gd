extends SceneTree
## 시각·밸런스 검증을 대체하지 않는 상태/규칙 회귀 검사.
## 진행 검사는 적 HP를 강제로 0으로 만들어 방 전환의 막힘을 확인한다.

var passed: int = 0
var failures: Array[String] = []
var combat_script: Script

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, description: String) -> void:
	if condition:
		passed += 1
	else:
		failures.append(description)
		push_error(description)

func tick_for(c, seconds: float, attack: bool = false) -> void:
	var frames: int = int(ceil(seconds * 60.0))
	for frame: int in range(frames):
		c.tick(1.0 / 60.0, Vector2.ZERO, c.p + Vector2(120, 0), attack, false, false, false)

func press(c, skill: bool, ultimate: bool) -> void:
	c.tick(1.0 / 60.0, Vector2.ZERO, c.p + Vector2(96, 0), false, false, skill, ultimate)

func new_combat(base_job: String):
	var c = combat_script.new()
	c.reset(base_job)
	return c

func close(a: float, b: float) -> bool:
	return absf(a - b) < 0.001

func run_checks() -> void:
	combat_script = load("res://src/game/combat.gd") as Script
	if combat_script == null:
		push_error("combat module could not load")
		quit(1)
		return
	var promotions := {"warrior": "berserker", "archer": "hunter", "mage": "firemage"}
	for base_job: String in promotions:
		check_run_progression(base_job, String(promotions[base_job]))
	check_upgrade_math()
	check_all_abilities()
	check_hunter_charges()
	check_projectile_cleanup()
	check_damage_and_status_rules()
	check_cast_and_charge_regressions()
	print("FULL RUN TEST: %d passed, %d failed" % [passed, failures.size()])
	for failure: String in failures:
		print("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)

func check_run_progression(base_job: String, promoted_job: String) -> void:
	var c = new_combat(base_job)
	check(c.job == base_job and close(c.hp, 100) and close(c.meter, 0), base_job + " fresh state")
	for room: int in range(1, 6):
		c.start_room(room)
		check(not c.completed and not c.defeated, base_job + " room %d active" % room)
		tick_for(c, 1.1)
		check(c.remaining() > 0, base_job + " room %d enemies or waves" % room)
		if room == 3:
			var elite_count: int = 0
			var ordinary_count: int = 0
			for enemy: Dictionary in c.enemies:
				if enemy.kind == "elite":
					elite_count += 1
				elif enemy.hp > 0:
					ordinary_count += 1
			check(elite_count == 1 and ordinary_count > 0, base_job + " third room elite and companions")
		if room == 5:
			check(c.enemies.size() == 1 and c.enemies[0].kind == "boss", base_job + " single boss in last room")
		# 이 검사는 플레이 승리가 아니라 웨이브/완료 상태 전이만 검증한다.
		for frame: int in range(600):
			for enemy: Dictionary in c.enemies:
				enemy.hp = 0.0
			c.tick(1.0 / 60.0, Vector2.ZERO, c.p + Vector2.RIGHT * 100, false, false, false, false)
			if c.completed:
				break
		check(c.completed and c.remaining() == 0, base_job + " room %d can complete" % room)
		check(c.projectiles.is_empty(), base_job + " room %d cleanup" % room)
		if room <= 4:
			c.upgrade((room - 1) % 4)
		if room == 2:
			c.hp = 37.0
			c.meter = 56.0
			var before_stacks: Array = c.stacks.duplicate()
			var before_max: float = c.max_hp
			c.promote()
			check(c.job == promoted_job, base_job + " promotion mapping")
			check(close(c.hp, 37) and close(c.max_hp, before_max) and close(c.meter, 56), base_job + " promotion preserves HP and meter")
			check(c.stacks == before_stacks and c.skill_cd <= 0.001, base_job + " promotion preserves upgrades and readies skill")
			if promoted_job == "hunter":
				check(c.charges == 3, "hunter starts with three charges")
	# 실패·재시작은 지난 모험 자원을 남기지 않는다.
	c.reset(base_job)
	check(c.job == base_job and close(c.hp, 100) and close(c.max_hp, 100), base_job + " restart restores base stats")
	check(close(c.meter, 0) and c.stacks == [0, 0, 0, 0], base_job + " restart clears run upgrades")

func check_upgrade_math() -> void:
	var c = new_combat("warrior")
	c.hp = 40
	c.upgrade(2)
	check(close(c.hp, 60) and close(c.max_hp, 120), "max HP increases current HP by same amount")
	c.upgrade(2)
	check(close(c.hp, 80) and close(c.max_hp, 140) and c.stacks[2] == 2, "same upgrade can stack")
	var d = new_combat("warrior")
	for index: int in range(4):
		d.upgrade(3)
	check(d.stacks[3] == 4, "cooldown upgrade stacks four times")
	c.hp = 1
	c.heal()
	check(c.hp > 1 and c.hp <= c.max_hp, "heal is positive and bounded")

func check_all_abilities() -> void:
	for base_job: String in ["warrior", "archer", "mage"]:
		for advanced: bool in [false, true]:
			var c = new_combat(base_job)
			if advanced:
				c.promote()
			c.start_room(1)
			tick_for(c, 1.1)
			c.hp = 10000
			var label: String = c.job
			press(c, true, false)
			check(c.skill_cd > 0 or (label == "hunter" and c.charges == 2), label + " E consumes cooldown or charge")
			var charge_before: int = c.charges
			var cooldown_before: float = c.skill_cd
			press(c, true, false)
			if label != "hunter":
				check(c.skill_cd <= cooldown_before, label + " E cannot reset running cooldown")
			else:
				check(c.charges <= charge_before, "hunter E does not create charges")
			tick_for(c, 0.5)
			c.meter = 99
			press(c, false, true)
			check(c.meter >= 99, label + " Q needs full meter")
			c.meter = 100
			press(c, false, true)
			check(c.meter < 1, label + " Q consumes full meter")
			if label == "berserker":
				tick_for(c, 0.2)
				check(c.rage > 0, "berserker Q starts rage")
			c.meter = 0
			tick_for(c, 0.3, true)
			check(c.meter < 1, label + " active ultimate cannot refill itself")

func check_hunter_charges() -> void:
	var c = new_combat("archer")
	c.promote()
	c.start_room(1)
	c.hp = 10000
	check(c.charges == 3, "hunter fresh room retains initial full charges")
	press(c, true, false)
	tick_for(c, 0.2)
	check(c.charges == 2 and c.traps.size() == 1, "trap costs exactly one charge")
	tick_for(c, 0.5)
	press(c, true, false)
	tick_for(c, 0.5)
	press(c, true, false)
	check(c.charges == 0 and c.traps.size() <= 3, "three traps exhaust charges and ground remains capped")
	tick_for(c, 5.2)
	check(c.charges == 1, "trap recharges sequentially one at a time")
	press(c, true, false)
	check(c.traps.size() <= 3, "fourth trap cannot exceed ground limit")
	c.start_room(2)
	check(c.traps.is_empty(), "room transition removes traps")
	check(c.charges <= 1, "room transition does not grant free trap charges")

func check_projectile_cleanup() -> void:
	var c = new_combat("archer")
	c.start_room(1)
	c.hp = 10000
	tick_for(c, 1.1)
	for frame: int in range(20):
		c.tick(1.0 / 60.0, Vector2.ZERO, c.p + Vector2.RIGHT * 200, true, false, false, false)
	check(c.projectiles.size() > 0, "archer creates projectile")
	tick_for(c, 5)
	check(c.projectiles.size() < 20, "projectiles expire instead of accumulating indefinitely")
	c.start_room(2)
	check(c.projectiles.is_empty() and c.zones.is_empty() and c.traps.is_empty(), "room transition clears transient effects")

func check_damage_and_status_rules() -> void:
	var c = new_combat("warrior")
	var e: Dictionary = c._spawn_enemy("melee", c.p + Vector2(80, 0))
	e.hp = 5.0
	var actual: float = c._hit(e, 20.0)
	check(close(actual, 5) and close(c.meter, 3.25), "overkill meter uses actual HP lost plus one kill bonus")
	c._hit(e, 20.0)
	check(c.kills == 1 and close(c.meter, 3.25), "dead enemy cannot award duplicate kill or meter")
	c = new_combat("mage")
	e = c._spawn_enemy("melee", c.p + Vector2(80, 0))
	c._hit(e, 20, true)
	check(close(c.meter, 0), "ultimate direct damage does not charge meter")
	c._gain_meter(1000)
	c._gain_meter(1000)
	check(close(c.meter, 10), "damage and kill charge share finite budget")
	c = new_combat("warrior")
	c.promote()
	c.hp = 60
	check(close(c.low_health(), 0), "berserker no bonus at sixty percent")
	c.hp = 40
	check(close(c.low_health(), 0.5), "berserker continuous half bonus at forty percent")
	c.hp = 20
	check(close(c.low_health(), 1), "berserker maximum bonus at twenty percent")
	e = c._spawn_enemy("melee", c.p + Vector2(80, 0))
	c._hit(e, 1000, false, true)
	var second: Dictionary = c._spawn_enemy("melee", c.p + Vector2(80, 0))
	c._hit(second, 1000, false, true)
	check(c.hp > 20 and c.hp <= 22.001, "berserker multiple targets share lifesteal budget")
	var health_before: float = c.hp
	e = c._spawn_enemy("melee", c.p + Vector2(80, 0))
	c._hit(e, 20, false, false)
	check(close(c.hp, health_before), "berserker skills cannot lifesteal")
	c = new_combat("mage")
	c.promote()
	e = c._spawn_enemy("melee", c.p + Vector2(80, 0))
	c._burn(e, false)
	for i: int in range(6):
		c._tick_burn(e, 0.5)
	check(close(e.hp, 51) and close(e.burn, 0), "burn deals six ticks including expiry tick")
	c._burn(e, true)
	c._tick_burn(e, 0.25)
	var tick_before: float = e.burn_tick
	c._burn(e, false)
	check(close(e.burn_tick, tick_before), "refresh does not postpone next burn tick")
	check(e.burn_ultimate, "equal-power refresh cannot strip ultimate provenance")
	c = new_combat("archer")
	c.promote()
	e = c._spawn_enemy("melee", c.p + Vector2(60, 0))
	e.hp = 1000.0
	e.root = 2.0
	c._spawn_projectile(c.p, Vector2.RIGHT, 18, 360, 320, true, "basic", Color.WHITE)
	c._tick_projectiles(0.2)
	check(c.projectiles.size() == 1 and c.projectiles[0].kind == "extra", "marked basic hit creates exactly one extra arrow")
	c._tick_projectiles(0.2)
	check(c.projectiles.is_empty(), "extra arrow does not recursively generate more arrows")

func check_cast_and_charge_regressions() -> void:
	var c = new_combat("mage")
	c.promote()
	var e: Dictionary = c._spawn_enemy("melee", c.p + Vector2(60, 0))
	c._spawn_projectile(c.p, Vector2.RIGHT, 45, 240, 240, true, "fireball", Color.WHITE)
	c._tick_projectiles(0.25)
	check(close(e.hp, 15), "fireball collision explodes exactly once")
	c = new_combat("mage")
	c._make_zone(c.p, 320, 35, 0.25, 4, 0.25, "beam", false)
	var location: Vector2 = c.p
	c.tick(1.0 / 60.0, Vector2.RIGHT, c.p + Vector2.RIGHT * 96, true, false, true, false)
	check(c.projectiles.is_empty() and close(c.skill_cd, 0), "beam channel prevents basic attack and E")
	check(c.p == location, "beam channel prevents ordinary movement")
	c.tick(1.0 / 60.0, Vector2.RIGHT, c.p + Vector2.RIGHT * 96, false, true, false, false)
	check(c.zones.is_empty() and c.dash_cd > 0, "dash cancels remaining beam ticks")
	c = new_combat("warrior")
	e = c._spawn_enemy("charger", Vector2(600, 200))
	e.state = "charge"
	e.dir = Vector2.RIGHT
	e.timer = 1.0
	e.charge_speed = 360.0
	e.charge_damage = 18.0
	c._tick_enemy(e, 0.1)
	check(e.state == "recover" and e.pos.x <= 607.001, "wall ends enemy charge immediately")
	for kind: String in ["melee", "elite", "boss"]:
		c = new_combat("archer")
		c.promote()
		e = c._spawn_enemy(kind, Vector2(200, 200))
		c.traps.append({"pos": e.pos, "left": 30.0, "arm": 0.0})
		c._tick_traps(0.01)
		if kind == "boss":
			check(close(e.slow, 2) and close(e.root, 0), "boss trap slows instead of rooting")
		else:
			check(close(e.root, 1 if kind == "elite" else 2), kind + " trap root duration")
		check(c.traps.is_empty(), kind + " triggered trap removed immediately")
