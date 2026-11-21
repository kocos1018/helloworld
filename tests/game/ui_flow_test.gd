extends SceneTree
## 콜백/상태 검증이며 플레이로 적을 쓰러뜨렸다는 증거가 아니다.
var passed: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, description: String) -> void:
	if condition:
		passed += 1
	else:
		failures.append(description)
		push_error(description)

func run_checks() -> void:
	var scene = load("res://src/game/main.tscn")
	if scene == null:
		push_error("main scene could not load")
		quit(1)
		return
	var game = scene.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	check(game.state == "title", "launch title")
	game.show_selection()
	check(game.state == "select", "all jobs selectable")
	for base: String in ["warrior", "archer", "mage"]:
		game.start_run(base)
		check(game.state == "playing" and game.room == 1 and game.combat.job == base, base + " starts first room")
		for room: int in range(1, 5):
			game.combat.completed = true
			game._physics_process(0.01)
			check(game.state == "reward", base + " room %d reward" % room)
			check(game.offered.size() == 3 and game.offered[0] != game.offered[1] and game.offered[1] != game.offered[2] and game.offered[0] != game.offered[2], base + " distinct reward options")
			var choice: int = game.offered[0]
			var previous_stack: int = game.combat.stacks[choice]
			game.choose_upgrade(choice)
			check(game.combat.stacks[choice] == previous_stack + 1, base + " choice applies once")
			game.choose_upgrade(choice)
			check(game.combat.stacks[choice] == previous_stack + 1, base + " stale reward callback cannot duplicate choice")
			if room == 2:
				check(game.state == "promotion", base + " reward precedes promotion")
				game.combat.hp = 37
				game.combat.meter = 56
				game.confirm_promotion()
				game.confirm_promotion()
				check(game.room == 3 and game.combat.job != base, base + " promotion enters room three")
				check(game.combat.hp == 37 and game.combat.meter == 56, base + " promotion preserves run values")
			elif room == 4:
				check(game.state == "camp", base + " fourth reward precedes optional camp")
				game.combat.hp = game.combat.max_hp
				game.use_fountain()
				check(not game.fountain_used, base + " full HP does not consume fountain")
				game.combat.hp = 10
				var maximum: float = game.combat.max_hp
				if base != "archer":
					game.use_fountain()
					game.use_fountain()
					check(game.state == "camp" and game.fountain_used, base + " fountain stays safe and single use")
					check(absf(game.combat.hp - (10 + maximum * 0.3)) < 0.001, base + " camp thirty percent heal")
				else:
					check(game.combat.hp == 10, "hunter can skip heal")
				game.advance_room()
				game.advance_room()
				check(game.room == 5 and game.state == "playing", base + " camp advances boss")
			else:
				check(game.state == "playing" and game.room == room + 1, base + " ordinary room advances")
		game.combat.completed = true
		game._physics_process(0.01)
		check(game.state == "ending", base + " boss victory reaches rescue ending")
		game.show_selection()
		game.start_run(base)
		check(game.combat.stacks == [0, 0, 0, 0] and game.combat.meter == 0 and game.combat.hp == 100, base + " new run clears prior rewards")
	game.start_run("warrior")
	game.combat.hp = 43
	game.combat.meter = 51
	game.combat.upgrade(0)
	game.show_pause()
	var old_clock: float = game.combat.clock
	game._physics_process(1)
	check(game.state == "paused" and game.combat.clock == old_clock, "pause halts combat")
	game.show_settings("paused")
	check(game.state == "settings" and game.combat.hp == 43 and game.combat.meter == 51, "settings preserves run")
	game.resume_pause_menu()
	check(game.state == "paused", "settings returns to pause menu")
	game.resume_game()
	check(game.combat.hp == 43 and game.combat.stacks[0] == 1, "resume preserves health and upgrades")
	game.combat.hp = 0
	game.combat.defeated = true
	game._physics_process(0.01)
	check(game.state == "dead", "death opens death menu")
	game.show_selection()
	game.start_run("mage")
	check(game.combat.hp == 100 and game.combat.stacks == [0, 0, 0, 0], "death retry resets run")
	game.show_quit_confirmation()
	check(game.state == "confirm", "abandon confirmation")
	game.show_title()
	check(game.state == "title", "abandon returns title")
	print("UI FLOW TEST: %d passed, %d failed" % [passed, failures.size()])
	game.music.stop()
	game.sfx.stop()
	game.music.stream = null
	game.sfx.stream = null
	await create_timer(0.15).timeout
	game.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
