extends SceneTree
const Combat = preload("res://src/game/combat.gd")
func _initialize() -> void:
	seed(20261121)
	var victories: int = 0
	for base: String in ["warrior", "archer", "mage"]:
		var c = Combat.new()
		c.reset(base)
		var finished: int = 0
		for room: int in range(1, 6):
			if room > 1:
				c.start_room(room)
			if room == 5: print("BOSS START %s hp=%.1f meter=%.1f" % [base, c.hp, c.meter])
			var steps: int = 0
			while not c.completed and not c.defeated and steps < 36000:
				steps += 1
				var target: Dictionary = {}
				var best: float = INF
				for e: Dictionary in c.enemies:
					if float(e.hp) > 0 and c.p.distance_to(Vector2(e.pos)) < best:
						target = e
						best = c.p.distance_to(Vector2(e.pos))
				var move := Vector2.ZERO
				var mouse: Vector2 = c.p + Vector2.RIGHT * 100
				var dodge: bool = false
				var use_skill: bool = false
				if not target.is_empty():
					mouse = target.pos
					var toward: Vector2 = (mouse - c.p).normalized()
					var ranged: bool = c.job not in ["warrior", "berserker"]
					var desired: float = 150.0 if ranged else 29.0
					move = toward if best > desired + 20 else -toward if best < desired - 20 else toward.rotated(PI / 2)
					if ranged:
						move = (move + toward.rotated(PI / 2) * 0.8).normalized()
					use_skill = (best < 55 if c.job in ["mage", "hunter"] else best < 180)
					for e: Dictionary in c.enemies:
						if float(e.hp) <= 0: continue
						var near: float = c.p.distance_to(Vector2(e.pos))
						if (e.state == "windup" and near < (105 if e.kind == "boss" else 48)) or (e.state == "charge" and near < 70):
							var away: Vector2 = (c.p - Vector2(e.pos)).normalized()
							move = away
							dodge = float(e.timer) < 0.15 or e.state == "charge"
					for bullet: Dictionary in c.projectiles:
						if bool(bullet.friendly): continue
						var delta_pos: Vector2 = c.p - Vector2(bullet.pos)
						var along: float = delta_pos.dot(Vector2(bullet.dir))
						var side: Vector2 = Vector2(bullet.dir).rotated(PI / 2)
						if along > 0 and along < 95 and absf(delta_pos.dot(side)) < 22:
							move = side if delta_pos.dot(side) >= 0 else -side
							dodge = along < 38
					if target.kind == "boss":
						var bd: Vector2 = target.dir
						var side: Vector2 = bd.rotated(PI / 2)
						var plus: Vector2 = c.clamp_position(c.p + side * 110)
						var minus: Vector2 = c.clamp_position(c.p - side * 110)
						if minus.distance_to(c.p) > plus.distance_to(c.p): side = -side
						var pattern: int = int(target.pattern_used)
						use_skill = target.state == "recover" if not ranged else true
						if target.state == "windup":
							if pattern == 1:
								move = side
								var relative: Vector2 = c.p - Vector2(target.pos)
								var on_lane: bool = relative.dot(bd) > -30 and relative.dot(bd) < 260 and absf(relative.dot(side)) < 38
								dodge = on_lane and float(target.timer) < 0.15
							else:
								move = -toward if best < 115 else toward.rotated(PI / 2)
								dodge = best < (85 if pattern == 0 else 102) and float(target.timer) < 0.13
						elif target.state == "charge":
							move = side
							dodge = best < 55
						else:
							var boss_desired: float = 170 if ranged else 38
							move = toward if best > boss_desired + 6 else -toward if best < boss_desired - 6 else Vector2.ZERO
							if ranged: move = (move + toward.rotated(PI / 2) * 0.5).normalized()
					if c.p.x < 55: move.x = absf(move.x)
					if c.p.x > 585: move.x = -absf(move.x)
					if c.p.y < 85: move.y = absf(move.y)
					if c.p.y > 310: move.y = -absf(move.y)
				c.tick(1.0 / 60.0, move.normalized(), mouse, true, dodge, use_skill, not target.is_empty())
			if c.defeated or not c.completed:
				if room == 5 and not c.enemies.is_empty(): print("BOSS END hp=%.1f player=%.1f" % [c.enemies[0].hp,c.hp])
				break
			finished = room
			if room < 5:
				c.upgrade(2 if room % 2 else 0)
			if room == 2: c.promote()
			if room == 4: c.heal()
		if finished == 5 and not c.defeated:
			victories += 1
		print("BOT %s rooms=%d hp=%.1f time=%.1f kills=%d" % [base, finished, c.hp, c.clock, c.kills])
	print("AUTOPLAY: %d/3 normal-rule full victories" % victories)
	quit(0 if victories == 3 else 1)
