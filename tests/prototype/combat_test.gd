extends SceneTree

var checks: int = 0
var failures: int = 0

func check(value: bool, message: String) -> void:
	if not value:
		push_error(message)
		failures += 1
		return
	checks += 1

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var game = load("res://src/prototype/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.paused = false
	check(game.hp == 100 and game.alive_count() == 3, "initial state")
	game.player_position = Vector2(200, 200)
	game.enemies[0].position = Vector2(224, 200)
	game.enemies[1].position = Vector2(500, 200)
	game.enemies[2].position = Vector2(180, 200)
	game.attack_direction = Vector2.RIGHT
	game.apply_sword_hits()
	game.apply_sword_hits()
	check(game.enemies[0].hp == 40, "one hit per swing")
	check(game.enemies[1].hp == 60, "range miss")
	check(game.enemies[2].hp == 60, "back miss")
	game.hit_ids.clear()
	game.apply_sword_hits()
	game.hit_ids.clear()
	game.apply_sword_hits()
	check(game.enemies[0].hp == 0, "three hit kill")
	game.damage_player(12)
	game.damage_player(12)
	check(game.hp == 88, "hit invulnerability prevents multiple hits")
	game.reset_run()
	game.set_physics_process(false)
	var before: Vector2 = game.player_position
	game.tick_player(0.01, Vector2.RIGHT, true, false)
	game.damage_player(12)
	check(game.hp == 100, "dash immunity")
	for i in range(15):
		game.tick_player(0.01, Vector2.RIGHT, false, false)
	check(absf(game.player_position.x - before.x - 72) < 0.1, "dash distance")
	game.damage_player(12)
	check(game.hp == 88, "immunity expires before dash cooldown")
	check(game.dash_wait > 0, "dash cooldown persists")
	game.player_position = Vector2(605, 200)
	game.dash_wait = 0
	game.tick_player(0.16, Vector2.RIGHT, true, false)
	check(game.player_position.x <= 606, "arena blocks dash")
	game.reset_run()
	game.set_physics_process(false)
	game.player_position = Vector2(200, 200)
	game.enemies[0].position = Vector2(220, 200)
	game.tick_enemy(game.enemies[0], 0.01)
	check(game.enemies[0].state == "windup" and game.hp == 100, "attack telegraph")
	game.tick_enemy(game.enemies[0], 0.41)
	check(game.hp == 88 and game.enemies[0].state == "recover", "enemy attack and recovery")
	game.reset_run()
	game.set_physics_process(false)
	game.player_position = Vector2(200, 200)
	game.enemies[0].position = Vector2(220, 200)
	game.tick_enemy(game.enemies[0], 0.01)
	game.player_position = Vector2(100, 200)
	game.tick_enemy(game.enemies[0], 0.41)
	check(game.hp == 100, "telegraphed attack can miss")
	game.paused = true
	var at: Vector2 = game.player_position
	game._physics_process(1)
	check(game.player_position == at, "paused simulation")
	game.paused = false
	game.hp = 0
	game._physics_process(0.01)
	check(not game.result.is_empty(), "death result")
	game.reset_run()
	game.set_physics_process(false)
	for enemy: Dictionary in game.enemies:
		enemy.hp = 0
	game._physics_process(0.01)
	check(game.result.contains("완료"), "victory result")
	game.reset_run()
	check(game.result.is_empty() and game.hp == 100 and game.alive_count() == 3, "restart restores run")
	print("RESULT: %d passed, %d failed" % [checks, failures])
	game.queue_free()
	quit(1 if failures else 0)
