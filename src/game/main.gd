extends Node2D
## 모험의 진행·메뉴·설정. 전투와 시각화는 별도 모듈이 담당한다.
const Combat = preload("res://src/game/combat.gd")
const Painter = preload("res://src/game/renderer.gd")
const NAMES: Dictionary = {"warrior":"전사", "berserker":"광전사", "archer":"궁수", "hunter":"사냥꾼", "mage":"마법사", "firemage":"불꽃마법사"}
const SKILLS: Dictionary = {"warrior":["돌진 베기", "회전 베기"], "berserker":["도약 강타", "피의 격노"], "archer":["밀쳐내는 사격", "관통 사격"], "hunter":["덫 설치", "화살비"], "mage":["충격파", "마력 광선"], "firemage":["화염구", "화염 폭풍"]}
const UPGRADE_NAMES: Array[String] = ["힘의 문장", "질풍의 문장", "생명의 문장", "집중의 문장"]
const UPGRADE_TEXT: Array[String] = ["공격력 +15%", "기본 공격속도 +10%", "최대 체력 +20\n현재 체력도 +20", "일반 스킬 대기시간 -8%\n사냥꾼 덫 충전에도 적용"]
var combat = Combat.new()
var painter = Painter.new()
var state: String = "title"
var room: int = 1
var elapsed: float = 0.0
var selection: String = "warrior"
var panel: PanelContainer
var layout: VBoxContainer
var hud: Label
var status: Label
var backdrop: ColorRect
var canvas: CanvasLayer
var offered: Array[int] = []
var elapsed_before_pause: String = "playing"
var previous_space: bool = false
var previous_e: bool = false
var previous_q: bool = false
var music: AudioStreamPlayer
var sfx: AudioStreamPlayer
var master_volume: float = 0.65
var music_volume: float = 0.32
var effects_volume: float = 0.6
var muted: bool = false
var fountain_used: bool = false

func _ready() -> void:
	get_tree().auto_accept_quit = false
	randomize()
	load_settings()
	canvas = CanvasLayer.new()
	add_child(canvas)
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Malgun Gothic", "Noto Sans CJK KR", "Noto Sans"])
	theme.default_font = font
	theme.default_font_size = 13
	var ui := Control.new()
	ui.theme = theme
	canvas.add_child(ui)
	hud = make_label("", 14)
	hud.position = Vector2(25, 7)
	ui.add_child(hud)
	status = make_label("", 11)
	status.position = Vector2(25, 31)
	status.size = Vector2(590, 30)
	ui.add_child(status)
	backdrop = ColorRect.new()
	backdrop.color = Color(0.015, 0.025, 0.045, 0.87)
	backdrop.position = Vector2.ZERO
	backdrop.size = Vector2(640, 360)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(backdrop)
	panel = PanelContainer.new()
	panel.position = Vector2(65, 42)
	panel.size = Vector2(510, 276)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#142333")
	style.border_color = Color("#bd9752")
	style.set_border_width_all(2)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	ui.add_child(panel)
	layout = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	panel.add_child(layout)
	music = AudioStreamPlayer.new()
	sfx = AudioStreamPlayer.new()
	add_child(music)
	add_child(sfx)
	music.stream = make_music()
	apply_volume()
	if DisplayServer.get_name() != "headless":
		music.play()
	combat.reset(selection)
	show_title()

func make_label(text: String, size: int = 13) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("#ece4cd"))
	return label

func clear_panel() -> void:
	panel.position = Vector2(65, 42)
	panel.size = Vector2(510, 276)
	layout.add_theme_constant_override("separation", 8)
	for child: Node in layout.get_children():
		layout.remove_child(child)
		child.queue_free()
	panel.visible = true
	backdrop.visible = true

func heading(title: String, subtitle: String) -> void:
	clear_panel()
	var title_label := make_label(title, 24)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(title_label)
	var label := make_label(subtitle, 12)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(label)

func button(text: String, callback: Callable, parent: Node = null) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size.y = 31
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.pressed.connect(callback)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#243d50")
	style.border_color = Color("#517086")
	style.set_border_width_all(1)
	node.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#456174")
	hover.border_color = Color("#f5cb75")
	node.add_theme_stylebox_override("hover", hover)
	node.add_theme_stylebox_override("focus", hover)
	(parent if parent != null else layout).add_child(node)
	return node

func show_title() -> void:
	state = "title"
	heading("전직 용사의 구출 작전", "폐성의 문을 열고, 공주를 구하세요.")
	layout.add_child(make_label("세 가지 전투 방식 · 모험 중 전직 · 성문 수문장\nWASD 이동 / 마우스 조준·공격 / Space 회피\nE 일반 스킬 / Q 필살기 / F 상호작용 / Esc 메뉴", 13))
	button("모험 시작", show_selection)
	var row := HBoxContainer.new()
	layout.add_child(row)
	button("설정", func(): show_settings("title"), row)
	button("종료", exit_game, row)
	update_hud()
	queue_redraw()

func show_selection() -> void:
	state = "select"
	heading("어떤 용사로 출발할까요?", "모든 기본 직업은 처음부터 선택할 수 있습니다.")
	button("전사 → 광전사    |    검 베기 · 저체력의 강한 한 방", func(): start_run("warrior"))
	button("궁수 → 사냥꾼    |    거리 유지 · 덫과 집중 사격", func(): start_run("archer"))
	button("마법사 → 불꽃마법사    |    마법탄 · 폭발과 화상", func(): start_run("mage"))
	button("제목으로", show_title)

func start_run(job: String) -> void:
	selection = job
	elapsed = 0
	room = 1
	combat.reset(job)
	combat.start_room(room)
	resume_game()
	play_note(440)

func resume_game() -> void:
	state = "playing"
	panel.visible = false
	backdrop.visible = false
	previous_space = Input.is_physical_key_pressed(KEY_SPACE)
	previous_e = Input.is_physical_key_pressed(KEY_E)
	previous_q = Input.is_physical_key_pressed(KEY_Q)
	update_hud()
	queue_redraw()

func _physics_process(delta: float) -> void:
	if state != "playing":
		return
	elapsed += delta
	var movement := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))).normalized()
	var space: bool = Input.is_physical_key_pressed(KEY_SPACE)
	var e: bool = Input.is_physical_key_pressed(KEY_E)
	var q: bool = Input.is_physical_key_pressed(KEY_Q)
	var old_hp: float = combat.hp
	var old_kills: int = combat.kills
	var old_dash: float = combat.dash_cd
	combat.tick(delta, movement, get_global_mouse_position(), Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), space and not previous_space, e and not previous_e, q and not previous_q)
	previous_space = space
	previous_e = e
	previous_q = q
	if combat.hp < old_hp:
		play_note(130)
	elif combat.kills > old_kills:
		play_note(660)
	elif combat.dash_cd > old_dash:
		play_note(330)
	if combat.defeated:
		show_death()
	elif combat.completed:
		if room == 5:
			show_ending()
		else:
			show_reward()
	update_hud()
	queue_redraw()

func show_reward() -> void:
	state = "reward"
	heading("전투방 %d 클리어" % room, "힘을 하나 고르세요. 이전에 고른 강화도 다시 누적됩니다.")
	var pool: Array[int] = [0, 1, 2, 3]
	pool.shuffle()
	offered = [pool[0], pool[1], pool[2]]
	for slot: int in range(3):
		var index: int = offered[slot]
		var card := button("%d. %s  [현재 %d회]\n%s" % [slot + 1, UPGRADE_NAMES[index], combat.stacks[index], UPGRADE_TEXT[index].replace("\n", " / ")], choose_upgrade.bind(index))
		card.custom_minimum_size.y = 44
	layout.add_child(make_label("숫자 1·2·3 또는 마우스로 선택", 11))
	play_note(880)

func choose_upgrade(index: int) -> void:
	if state != "reward":
		return
	combat.upgrade(index)
	if room == 2:
		show_promotion()
	elif room == 4:
		show_camp()
	else:
		advance_room()

func show_promotion() -> void:
	state = "promotion"
	var next_jobs: Dictionary = {"warrior":"berserker", "archer":"hunter", "mage":"firemage"}
	var promoted: String = next_jobs.get(combat.job, "berserker")
	heading("새로운 힘, 전직", "%s → %s" % [NAMES[combat.job], NAMES[promoted]])
	var details: Dictionary = {"berserker":"느리지만 강한 대형 무기. 낮은 체력에서 더 강해집니다.\nE 도약 강타 / Q 피의 격노 / 기본 공격 흡혈", "hunter":"덫을 놓고 효과 중인 적에게 집중 사격하세요.\nE 충전식 덫 3회 / Q 화살비 / 기본 공격 시 추가 화살", "firemage":"화염탄의 폭발과 화상으로 적 무리를 상대합니다.\nE 화염구 / Q 화염 폭풍"}
	layout.add_child(make_label(details[promoted]))
	layout.add_child(make_label("체력·필살기 게이지·강화 유지 / 새 일반 스킬 즉시 사용", 11))
	button("전직하고 세 번째 방으로", confirm_promotion)

func confirm_promotion() -> void:
	if state != "promotion":
		return
	combat.promote()
	advance_room()

func advance_room() -> void:
	if state not in ["reward", "promotion", "camp"]:
		return
	room += 1
	combat.start_room(room)
	resume_game()

func show_camp() -> void:
	state = "camp"
	fountain_used = false
	refresh_camp()

func refresh_camp() -> void:
	heading("성문 앞의 작은 샘", "다음 방에는 성문 수문장이 기다립니다.")
	layout.add_child(make_label("현재 체력 %d / %d\n샘은 최대 체력의 30%%를 무료로 한 번 회복합니다.\n광전사는 저체력을 유지하려면 건너뛰어도 됩니다." % [ceili(combat.hp), int(combat.max_hp)]))
	if fountain_used:
		layout.add_child(make_label("샘의 빛이 잦아들었습니다. 회복을 마쳤습니다."))
	else:
		var heal_button := button("F · 샘에서 회복 (무료 1회)", use_fountain)
		heal_button.disabled = combat.hp >= combat.max_hp
		if combat.hp >= combat.max_hp:
			heal_button.text = "체력이 가득합니다 — 회복 횟수 미소비"
	button("보스에게 나아가기", advance_room)
	update_hud()
	queue_redraw()

func use_fountain() -> void:
	if state != "camp" or fountain_used or combat.hp >= combat.max_hp:
		return
	combat.heal()
	fountain_used = true
	refresh_camp()
	play_note(660)

func show_death() -> void:
	state = "dead"
	heading("용사는 잠시 쓰러졌습니다", "이번 모험의 강화는 초기화됩니다.")
	layout.add_child(make_label("%s · %d번 방 · %d처치 · %s\n다른 직업으로 새로운 싸움을 시도해 보세요." % [NAMES[combat.job], room, combat.kills, time_text()]))
	button("직업을 다시 선택", show_selection)
	button("제목으로", show_title)
	play_note(110)

func show_ending() -> void:
	state = "ending"
	clear_panel()
	layout.add_theme_constant_override("separation", 4)
	var title_label := make_label("공주를 구했습니다!", 22)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(title_label)
	var picture := Control.new()
	picture.custom_minimum_size.y = 88
	picture.clip_contents = true
	layout.add_child(picture)
	var art := Node2D.new()
	art.set_script(preload("res://src/game/rescue_art.gd"))
	art.scale = Vector2(0.53, 0.53)
	art.position = Vector2(68, -49)
	picture.add_child(art)
	layout.add_child(make_label("용사는 공주의 손을 잡고, 아침이 밝은 성 밖으로 나섰습니다.", 11))
	layout.add_child(make_label("%s · %d처치 · %s" % [NAMES[combat.job], combat.kills, time_text()], 12))
	button("다른 직업으로 다시 모험", show_selection)
	button("제목으로", show_title)
	play_note(1046)
	queue_redraw()

func time_text() -> String:
	return "%02d:%02d" % [int(elapsed) / 60, int(elapsed) % 60]

func update_hud() -> void:
	if not is_instance_valid(hud):
		return
	hud.text = "%s  |  HP %d/%d  |  필살기 %d%%  |  %s  %s" % [NAMES.get(combat.job, "전사"), ceili(combat.hp), int(combat.max_hp), int(combat.meter), "보스" if room == 5 else "전투방 %d/4" % room, time_text()]
	var skill_text: String = "충전 %d/3 (다음 %.1f초)" % [combat.charges, maxf(0, 6.0 * combat.cdr_factor() - combat.charge_time) if combat.charges < 3 else 0.0] if combat.job == "hunter" else ("준비" if combat.skill_cd <= 0 else "%.1f초" % combat.skill_cd)
	status.text = "E %s: %s  ·  Q %s  ·  회피 %.1f초  ·  적 %d\nWASD 이동 / 마우스 공격 / Space 회피 / Esc 메뉴" % [SKILLS[combat.job][0], skill_text, SKILLS[combat.job][1], combat.dash_cd, combat.remaining()]

func show_pause() -> void:
	if state != "playing":
		return
	state = "paused"
	heading("잠시 쉬어가기", "일시정지 중에는 전투와 모든 시간이 멈춥니다.")
	button("계속하기", resume_game)
	button("설정·조작 안내", func(): show_settings("paused"))
	button("모험을 포기하고 제목으로", show_quit_confirmation)

func show_quit_confirmation() -> void:
	state = "confirm"
	heading("이번 모험을 마칠까요?", "모험 중간 저장은 없습니다. 직업·강화는 초기화됩니다.")
	button("모험을 포기하고 제목으로", show_title)
	button("돌아가기", func(): state = "playing"; show_pause())

func show_settings(return_state: String) -> void:
	state = "settings"
	heading("설정·조작", "WASD 이동 · 왼쪽 공격 · Space 회피 · E 스킬 · Q 필살기")
	add_slider("전체 음량", master_volume, func(value: float): master_volume = value; apply_volume())
	add_slider("음악", music_volume, func(value: float): music_volume = value; apply_volume())
	add_slider("효과음", effects_volume, func(value: float): effects_volume = value; apply_volume())
	var row := HBoxContainer.new()
	layout.add_child(row)
	button("창 / 전체 화면", toggle_fullscreen, row)
	button("돌아가기", func(): save_settings(); show_title() if return_state == "title" else resume_pause_menu(), row)

func resume_pause_menu() -> void:
	state = "playing"
	show_pause()

func add_slider(label: String, value: float, callback: Callable) -> void:
	var row := HBoxContainer.new()
	var name_label := make_label(label, 11)
	name_label.custom_minimum_size.x = 70
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.max_value = 1
	slider.step = 0.05
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(callback)
	row.add_child(slider)
	layout.add_child(row)

func toggle_fullscreen() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if state in ["title", "select", "dead", "ending"]:
			exit_game()
		else:
			if state == "playing":
				show_pause()
			var dialog := ConfirmationDialog.new()
			dialog.title = "게임을 종료할까요?"
			dialog.dialog_text = "모험 중간 저장은 없습니다. 이번 진행은 초기화됩니다."
			dialog.confirmed.connect(exit_game)
			dialog.confirmed.connect(dialog.queue_free)
			dialog.canceled.connect(dialog.queue_free)
			add_child(dialog)
			dialog.popup_centered(Vector2i(420, 100))
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == "playing" and is_instance_valid(panel):
		show_pause()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if state == "reward" and event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_3:
			choose_upgrade(offered[event.physical_keycode - KEY_1])
		elif event.physical_keycode == KEY_ESCAPE:
			if state == "playing":
				show_pause()
			elif state == "paused":
				resume_game()
		elif event.physical_keycode == KEY_F and state == "camp":
			use_fountain()

func _draw() -> void:
	painter.paint(self, combat, room, elapsed)

func apply_volume() -> void:
	if is_instance_valid(music):
		music.volume_db = linear_to_db(maxf(0.0001, master_volume * music_volume * (0 if muted else 1)))
	if is_instance_valid(sfx):
		sfx.volume_db = linear_to_db(maxf(0.0001, master_volume * effects_volume * (0 if muted else 1)))

func play_note(hz: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not is_instance_valid(sfx):
		return
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var bytes := PackedByteArray()
	bytes.resize(2205 * 2)
	for i: int in range(2205):
		var value: float = sin(TAU * hz * float(i) / 22050.0) * 0.2 * (1.0 - float(i) / 2205.0)
		bytes.encode_s16(i * 2, int(value * 32767))
	stream.data = bytes
	sfx.stop()
	sfx.stream = stream
	sfx.play()

func make_music() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	var notes: Array[float] = [220, 261.63, 329.63, 293.66, 220, 261.63, 196, 164.81, 220, 261.63, 329.63, 392, 329.63, 293.66, 261.63, 196]
	var count: int = 176400
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i: int in range(count):
		var beat: int = i / 11025
		var local_time: float = float(i % 11025) / 22050.0
		var envelope: float = minf(local_time * 30.0, 1) * maxf(0, 1 - local_time * 2)
		var wave: float = sin(TAU * notes[beat] * float(i) / 22050.0) * 0.13 * envelope
		wave += sin(TAU * 110 * float(i) / 22050.0) * 0.025
		bytes.encode_s16(i * 2, int(wave * 32767))
	stream.data = bytes
	stream.loop_end = count
	return stream

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		master_volume = clampf(float(config.get_value("audio", "master", 0.65)), 0, 1)
		music_volume = clampf(float(config.get_value("audio", "music", 0.32)), 0, 1)
		effects_volume = clampf(float(config.get_value("audio", "effects", 0.6)), 0, 1)
		if bool(config.get_value("screen", "fullscreen", false)) and DisplayServer.get_name() != "headless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master", master_volume)
	config.set_value("audio", "music", music_volume)
	config.set_value("audio", "effects", effects_volume)
	config.set_value("screen", "fullscreen", DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	config.save("user://settings.cfg")

func exit_game() -> void:
	if is_instance_valid(music):
		music.stop()
		music.stream = null
	if is_instance_valid(sfx):
		sfx.stop()
		sfx.stream = null
	await get_tree().create_timer(0.15).timeout
	get_tree().quit()
