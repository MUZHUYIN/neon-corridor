extends Node2D
## 游戏根节点：状态机、场景切换、输入分发。

var world: World = null
var ui_layer: CanvasLayer
var menu: MenuRoot
var hud: Hud
var levelup: LevelUpPanel
var pause: PausePanel
var result: ResultPanel
var _dying := false

# ---- 自测钩子（仅命令行参数触发，正常游玩不受影响）----
var _autoquit := 0
var _frames := 0
var _autostart := -99
var _autodash := false
var _bot := false
var _bot_choice: Dictionary = {}
var _bot_has_choice := false
var _maxt := 0.0
var _skip := 0.0
var _testload := false
var _swarm := 0
var _workshop := 0
var _audiotest := false
var _nomods := false
var _shots := false
var _path_flag := false
var _save_flag := false
var _shot_want_levelup := false
var _shot_dir := "res://tests/shots/"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			_autoquit = int(a.split("=")[1])
		elif a.begins_with("--autostart="):
			_autostart = int(a.split("=")[1])
		elif a == "--autodash":
			_autodash = true
		elif a == "--bot":
			_bot = true
		elif a.begins_with("--maxt="):
			_maxt = float(a.split("=")[1])
		elif a.begins_with("--skip="):
			_skip = float(a.split("=")[1])
		elif a == "--testload":
			_testload = true
		elif a == "--nosave":
			Save.readonly = true
		elif a.begins_with("--workshop="):
			_workshop = int(a.split("=")[1])
		elif a.begins_with("--swarm="):
			_swarm = int(a.split("=")[1])
		elif a == "--nomods":
			_nomods = true
		elif a.begins_with("--difficulty="):
			Save.data["settings"]["difficulty"] = int(a.split("=")[1])
		elif a == "--pathtest":
			_path_flag = true
		elif a == "--savetest":
			_save_flag = true
		elif a == "--audiotest":
			_audiotest = true
		elif a == "--shots":
			_shots = true
			_bot = true
			Save.readonly = true
	if _autoquit > 0:
		print("[SMOKE] main ready, autostart=", _autostart,
			" window=", DisplayServer.window_get_size() if DisplayServer.get_name() != "headless" else Vector2i.ZERO,
			" screen=", DisplayServer.screen_get_size() if DisplayServer.get_name() != "headless" else Vector2i.ZERO,
			" content_scale=", get_window().content_scale_size,
			" dpi=", DisplayServer.screen_get_scale() if DisplayServer.get_name() != "headless" else 1.0)
	UI.install(get_window())
	_register_inputs()
	Game.apply_settings()
	process_mode = Node.PROCESS_MODE_ALWAYS

	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui_layer)

	menu = MenuRoot.new()
	ui_layer.add_child(menu)
	menu.start_run.connect(_start_run)

	hud = Hud.new()
	hud.visible = false
	ui_layer.add_child(hud)

	levelup = LevelUpPanel.new()
	levelup.chosen.connect(_on_choice)
	ui_layer.add_child(levelup)

	pause = PausePanel.new()
	pause.resume_pressed.connect(_resume)
	pause.restart_pressed.connect(_restart)
	pause.menu_pressed.connect(_to_menu)
	ui_layer.add_child(pause)

	result = ResultPanel.new()
	result.retry_pressed.connect(_restart)
	result.next_pressed.connect(_next_stage)
	result.menu_pressed.connect(_to_menu)
	ui_layer.add_child(result)

	Bus.level_up.connect(_on_level_up)
	Bus.player_died.connect(_on_player_died)
	Bus.run_finished.connect(_on_run_finished)

	Audio.bgm("bgm_menu")
	Game.change_state(Game.ST_MENU)
	if _audiotest:
		_audio_audit()
		return
	if _save_flag:
		_save_test()
		return
	if _path_flag:
		_path_test()
	if _shots:
		_shots_run()
		return
	if _workshop > 0:
		for item in DB.WORKSHOP:
			Save.data["workshop"][String(item["id"])] = _workshop
	if _autostart >= 0:
		_start_run(_autostart, false)
		if _bot and world != null:
			world.player.bot = true
		if _testload and world != null:
			_stress_load(world)
		if _skip > 0.0 and world != null:
			world.elapsed = _skip


func _register_inputs() -> void:
	var map := {
		"mv_left": [KEY_A, KEY_LEFT],
		"mv_right": [KEY_D, KEY_RIGHT],
		"mv_up": [KEY_W, KEY_UP],
		"mv_down": [KEY_S, KEY_DOWN],
		"dash": [KEY_SPACE],
		"skill1": [KEY_E],
		"skill2": [KEY_Q],
		"pause": [KEY_ESCAPE],
		"fullscreen": [KEY_F11],
	}
	for a in map.keys():
		if InputMap.has_action(a):
			InputMap.erase_action(a)
		InputMap.add_action(a)
		for k in map[a]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(a, ev)


# ---------------------------------------------------------------- 关卡流程
func _start_run(stage_idx: int, endless: bool) -> void:
	if world != null and is_instance_valid(world):
		world.queue_free()
		world = null
	Game.world = null
	Game.stage_idx = stage_idx
	Game.endless = endless
	_dying = false
	levelup.visible = false
	pause.visible = false
	result.visible = false
	menu.visible = false
	hud.visible = true

	var w := World.new()
	add_child(w)
	w.setup(stage_idx, endless)
	world = w
	Game.world = w
	hud.bind(w)
	_set_world_active(true)
	Game.change_state(Game.ST_PLAYING)
	UI.set_crosshair(true)


func _set_world_active(on: bool) -> void:
	if world != null and is_instance_valid(world):
		world.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


func _to_menu() -> void:
	if world != null and is_instance_valid(world):
		world.queue_free()
		world = null
	Game.world = null
	hud.visible = false
	levelup.visible = false
	pause.visible = false
	result.visible = false
	UI.set_crosshair(false)
	menu.visible = true
	menu.page = "main"
	menu._rebuild()
	Game.change_state(Game.ST_MENU)
	Audio.bgm("bgm_menu")


func _restart() -> void:
	_start_run(Game.stage_idx, Game.endless)


func _next_stage() -> void:
	_start_run(mini(Game.stage_idx + 1, DB.STAGES.size() - 1), false)


func _resume() -> void:
	UI.set_crosshair(true)
	pause.visible = false
	_set_world_active(true)
	Game.change_state(Game.ST_PLAYING)


func _toggle_pause() -> void:
	if Game.state == Game.ST_PLAYING:
		UI.set_crosshair(false)
		pause.visible = true
		pause.tip.text = "难度：%s　关卡：%s　%s" % [
			DB.difficulty(int(Save.setting("difficulty", 1)))["name"],
			DB.stage(Game.stage_idx)["name"],
			("修正：" + world.mod_text()) if world != null and not world.run_mods.is_empty() else ""]
		_set_world_active(false)
		Game.change_state(Game.ST_PAUSED)
	elif Game.state == Game.ST_PAUSED:
		_resume()


# ---------------------------------------------------------------- 事件
func _on_level_up(choices: Array) -> void:
	if world == null or not is_instance_valid(world):
		return
	if choices.is_empty():
		world.take_levelup()
		return
	if _bot and not _shots:
		# 让机器人像真人一样按价值挑，而不是瞎选第一个
		var best: Dictionary = choices[0]
		var best_score := -999.0
		var wcount: int = world.player.weapons.size()
		for c in choices:
			var s := 0.0
			match String(c["type"]):
				"evolve":
					s = 100.0
				"weapon_new":
					s = 46.0 if wcount < 3 else 6.0
				"weapon_up":
					s = 26.0
				"passive":
					s = 20.0
				"skill":
					s = 30.0 if world.player.skills.size() < DB.MAX_SKILLS else 2.0
				"bonus":
					s = 4.0
			var cid := String(c.get("id", ""))
			if cid == "shield" or cid == "regen":
				s += 9.0
			elif cid == "damage" or cid == "crit" or cid == "firerate":
				s += 7.0
			elif cid == "xp" or cid == "magnet":
				s += 4.0
			if s > best_score:
				best_score = s
				best = c
		_bot_choice = best
		_bot_has_choice = true
		return
	if _shots and not _shot_want_levelup:
		world.pending_levels = 0
		return
	levelup.show_choices(choices, world.player)
	_set_world_active(false)
	Game.change_state(Game.ST_LEVELUP)


func _on_choice(c: Dictionary) -> void:
	if world == null or not is_instance_valid(world):
		return
	levelup.visible = false
	world.apply_choice(c)
	world.take_levelup()
	if world.pending_levels > 0:
		return
	_set_world_active(true)
	Game.change_state(Game.ST_PLAYING)


func _on_player_died() -> void:
	if _dying:
		return
	_dying = true
	await get_tree().create_timer(1.15).timeout
	if world != null and is_instance_valid(world):
		world.finish(false)


func _on_run_finished(entry: Dictionary) -> void:
	_set_world_active(false)
	result.show_result(entry, Game.stage_idx, Game.endless,
		Game.stage_idx + 1 < DB.STAGES.size())
	Game.change_state(Game.ST_RESULT)


# ---------------------------------------------------------------- 输入
func _audio_audit() -> void:
	await _wait(0.7)
	print("[AUD] ok=", Audio._ok, " voices=", Audio._pool.size(),
		" master=", Save.setting("vol_master"), " bgm=", Save.setting("vol_bgm"),
		" sfx=", Save.setting("vol_sfx"))
	for n in ["sfx_shoot_pistol", "sfx_hit_enemy", "sfx_explode", "sfx_levelup", "bgm_menu"]:
		var s: AudioStream = Audio._stream(n)
		if s == null:
			print("[AUD] ", n, " -> STREAM NULL")
			continue
		var lm := -1
		var le := -1
		if s is AudioStreamWAV:
			lm = (s as AudioStreamWAV).loop_mode
			le = (s as AudioStreamWAV).loop_end
		print("[AUD] ", n, " len=%.2f loop_mode=%d loop_end=%d" % [s.get_length(), lm, le])
	# 实际播一发，看播放器状态
	Audio.play("sfx_shoot_pistol", 1.0, 0.0, 0.8)
	await _wait(0.12)
	for i in mini(4, Audio._pool.size()):
		var pl: AudioStreamPlayer = Audio._pool[i]
		print("[AUD] voice", i, " playing=", pl.playing, " vol_db=%.1f" % pl.volume_db,
			" stream=", "yes" if pl.stream != null else "no")
	var cross := UI.make_crosshair()
	print("[AUD] crosshair tex=", cross != null, " size=", cross.get_size() if cross != null else Vector2.ZERO)
	UI.set_crosshair(true)
	UI.set_crosshair(false)
	print("[AUD] cursor set/reset ok")
	print("[AUD] bgm active=", Audio._active_bgm, " A=", Audio._bgm_a.playing, " B=", Audio._bgm_b.playing)
	Audio.bgm_layered("bgm_stage1_base", "bgm_stage1_drive")
	await _wait(1.6)
	print("[AUD] after switch: active=", Audio._active_bgm,
		" A playing=", Audio._bgm_a.playing, " A vol=%.1f" % Audio._bgm_a.volume_db,
		" B playing=", Audio._bgm_b.playing, " B vol=%.1f" % Audio._bgm_b.volume_db)
	# 分层联动：同一对音轨必须都在播（同步），且驱动层音量随战斗强度变化
	print("[AUD] layered=", Audio._bgm_layered,
		" base_playing=", Audio._bgm_a.playing,
		" drive_playing=", Audio._bgm_drive.playing,
		" drive_stream=", Audio._bgm_drive.stream != null)
	var base_len: float = Audio._bgm_a.stream.get_length()
	var drv_len: float = Audio._bgm_drive.stream.get_length()
	print("[AUD] stem lengths equal=", absf(base_len - drv_len) < 0.001,
		" base=%.3f drive=%.3f" % [base_len, drv_len])
	Audio.set_intensity(0.0)
	await _wait(1.5)
	var v0: float = Audio._bgm_drive.volume_db
	Audio.set_intensity(1.0)
	await _wait(1.5)
	var v1: float = Audio._bgm_drive.volume_db
	print("[AUD] intensity 0 -> drive vol=%.1f dB ; intensity 1 -> %.1f dB ; delta=%.1f dB" % [
		v0, v1, v1 - v0])
	get_tree().quit(0)


# ---------------------------------------------------------------- 截图自检
func _settle(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shot_dir + name + ".png")
	print("[SHOT] ", name, " ", img.get_size(), " fps=", Engine.get_frames_per_second(),
		" enemies=", world.enemies.size() if (world != null and is_instance_valid(world)) else -1)


func _populate(kinds: Array, n: int, elite_chance: float = 0.0, rmin: float = 70.0,
		rmax: float = 200.0) -> void:
	if world == null or not is_instance_valid(world):
		return
	var pl = world.player
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in n:
		var a := TAU * float(i) / float(n) + rng.randf() * 0.4
		var d := rng.randf_range(rmin, rmax)
		var p: Vector2 = pl.global_position + Vector2(cos(a), sin(a)) * d
		p = world.arena.resolve(p, 14.0)
		var kind := String(kinds[i % kinds.size()])
		var eid := ""
		if rng.randf() < elite_chance:
			eid = String(DB.ELITES[i % DB.ELITES.size()]["id"])
		world._spawn_at(kind, eid, p, false)


func _give_player(weapons: Array, passives: Dictionary) -> void:
	var pl = world.player
	pl.weapons.clear()
	for w in weapons:
		pl.weapons.append({"id": String(w), "lv": 3, "cd_left": 0.0, "evolved": false})
	for k in passives.keys():
		pl.passives[String(k)] = int(passives[k])
	pl.recompute(true)
	pl.hp = pl.max_hp * 0.62


## 存档槽验证：迁移、切换、槽间独立、重置后设置保留
func _save_test() -> void:
	print("[SAVE] active_slot=", Save.active_slot, " slots=", Save.SLOT_COUNT)
	for i in Save.SLOT_COUNT:
		var s: Dictionary = Save.slot_summary(i)
		print("[SAVE]  slot%d used=%s gears=%d stages=%d runs=%d kills=%d ws=%d active=%s" % [
			i, str(s["used"]), int(s["gears"]), int(s["stages"]),
			int(s["runs"]), int(s["kills"]), int(s["workshop_total"]), str(s["active"])])
	print("[SAVE] settings vol_bgm=", Save.setting("vol_bgm"), " diff=", Save.setting("difficulty"))
	# 回归：解锁列表必须是 int，否则选关界面会全部显示"未解锁"
	var ul: Array = Save.data["unlocked"]
	var all_int := true
	for v in ul:
		if typeof(v) != TYPE_INT:
			all_int = false
	print("[SAVE] unlocked=", ul, " all_int=", all_int,
		" is_unlocked(0)=", Save.is_unlocked(0), " is_unlocked(2)=", Save.is_unlocked(2),
		" (expect true/true/true)")
	Save.switch_slot(1)
	print("[SAVE] -> slot1: gears=", Save.gears(), " unlocked=", Save.data["unlocked"])
	Save.add_gears(500)
	Save.set_workshop_level("w_dmg", 3)
	Save.switch_slot(0)
	print("[SAVE] -> slot0: gears=", Save.gears(), " w_dmg=", Save.workshop_level("w_dmg"))
	Save.switch_slot(1)
	print("[SAVE] slot1 preserved: gears=", Save.gears(), " w_dmg=", Save.workshop_level("w_dmg"))
	Save.reset_slot(1)
	print("[SAVE] reset slot1: gears=", Save.gears(),
		" w_dmg=", Save.workshop_level("w_dmg"), " vol_bgm kept=", Save.setting("vol_bgm"))
	# 回归：清空后槽位必须变回"空"，界面才能给出「开始新游戏」
	var s1: Dictionary = Save.slot_summary(1)
	print("[SAVE] slot1 after reset: used=", s1["used"], " (expect false)")
	Save.start_new_game(1)
	var s1b: Dictionary = Save.slot_summary(1)
	print("[SAVE] start_new_game(1): used=", s1b["used"], " gears=", s1b["gears"],
		" active=", s1b["active"], " (expect true/0/true)")
	print("[SAVE] active slot now=", Save.active_slot, " vol_bgm kept=", Save.setting("vol_bgm"))
	Save.switch_slot(0)
	print("[SAVE] final active=", Save.active_slot, " gears=", Save.gears())
	get_tree().quit(0)


## A/B 测试：把敌人放在立柱正后方，量有多少能绕过来到达玩家
func _path_trial(use_pathing: bool) -> void:
	_start_run(0, false)
	world.player.bot = false
	var pl = world.player
	# 取长墙中段的一根柱子，把玩家和敌人放在墙的两侧 —— 复现"有路也不绕"
	var pil: Dictionary = world.arena.pillars[world.arena.pillars.size() / 4]
	var c: Vector2 = pil["pos"]
	var rr: float = float(pil["r"])
	pl.global_position = c + Vector2(0.0, -(rr + 120.0))
	pl.max_hp = 999999.0
	pl.hp = 999999.0
	world.arena.flow_enabled = use_pathing
	world.arena.update_flow(pl.global_position, true)
	var spawned: Array = []
	for i in 12:
		var e := Enemy.spawn(world.enemy_layer, "grunt", "", Vector2.ZERO, 1.0, 1.0)
		# 沿墙一字排开，全部在墙的另一侧
		e.global_position = c + Vector2(-140.0 + float(i) * 25.0, rr + 120.0)
		e.speed = 62.0
		world.enemies.append(e)
		spawned.append(e)
	# 用固定帧数推进，不依赖 delta 累加（headless 下更可靠）。
	# 给足 22 秒：绕行本来就走更长的路，固定短窗口会误判成"更差"。
	# 进度采样：确认"还在远处"的敌人是在移动还是卡死
	for stage_i in 5:
		for i in 600:
			await get_tree().physics_frame
		var sum_d := 0.0
		var cnt := 0
		var unreach := 0
		for e in spawned:
			if not is_instance_valid(e) or e.dead:
				continue
			sum_d += e.global_position.distance_to(pl.global_position)
			cnt += 1
			if not world.arena.flow_reaches(e.global_position):
				unreach += 1
		if cnt > 0:
			print("[PATH]   t=%ds mean_dist=%.0f alive=%d flow_unreachable=%d" % [
				(stage_i + 1) * 10, sum_d / float(cnt), cnt, unreach])
	var arrived := 0
	var far := 0
	for e in spawned:
		if not is_instance_valid(e) or e.dead:
			arrived += 1
			continue
		var d: float = e.global_position.distance_to(pl.global_position)
		if d < 90.0:
			arrived += 1
		elif d > 240.0:
			far += 1
	print("[PATH] deflect=", use_pathing, " -> ", arrived, "/", spawned.size(),
		" reached player, ", far, " still stuck far away")


func _path_test() -> void:
	await _path_trial(false)
	await _path_trial(true)
	get_tree().quit(0)


func _shots_run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/shots"))
	await _settle(30)
	await _shot("01_menu")
	menu.page = "stages"
	menu._rebuild()
	await _settle(8)
	await _shot("02_stages")
	# 功能测试：点"返回"应该回到主菜单
	for c in menu.content.get_children():
		if c is HBoxContainer:
			for cc in c.get_children():
				if cc is Button:
					(cc as Button).emit_signal("pressed")
					break
			break
	await _settle(4)
	print("[SHOT] back-button -> page=", menu.page, " (expect main)")
	menu.page = "stages"
	menu._rebuild()
	await _settle(4)
	Save.data["gears"] = 1500
	for item in DB.WORKSHOP:
		Save.set_workshop_level(String(item["id"]), 3)
	menu.page = "workshop"
	menu._rebuild()
	await _settle(8)
	await _shot("03_workshop")
	menu.page = "settings"
	menu._rebuild()
	await _settle(8)
	await _shot("04_settings")
	menu.page = "save"
	menu._rebuild()
	await _settle(10)
	await _shot("20_save")
	menu._ask_confirm("重开槽位 2？",
		"该槽位的进度会被清空（齿轮 / 工坊 / 解锁 / 记录 / 统计），设置保留。此操作不可撤销。",
		true, func() -> void: pass)
	await _settle(10)
	await _shot("21_save_confirm")
	# 关掉弹窗
	for ch in menu.get_children():
		if ch is ColorRect:
			ch.queue_free()
	menu.page = "main"
	menu._rebuild()
	await _settle(8)

	_start_run(0, false)
	if world != null:
		world.player.bot = true
	await _settle(40)
	_give_player(["pistol", "shotgun"], {"damage": 2, "firerate": 1})
	_populate(["grunt", "darter", "flyer"], 16, 0.12)
	await _settle(50)
	await _shot("05_play_start")

	world.elapsed = 118.0
	_give_player(["pistol", "shotgun", "laser"], {"damage": 3, "firerate": 3, "speed": 2, "crit": 3, "magnet": 2})
	_populate(["grunt", "darter", "lancer", "bomber", "splitter", "flyer", "tank"], 34, 0.18)
	await _settle(70)
	await _shot("06_play_mid")

	world.elapsed = 190.0
	_populate(["splitter", "tank", "summoner", "bomber", "darter"], 46, 0.4, 60.0, 240.0)
	await _settle(60)
	await _shot("07_elite_wave")

	_shot_want_levelup = true
	Bus.level_up.emit(world.roll_choices(4))
	await _settle(12)
	await _shot("08_levelup")
	_shot_want_levelup = false
	levelup.visible = false
	_set_world_active(true)
	Game.change_state(Game.ST_PLAYING)

	world.elapsed = 239.4
	await _settle(150)
	_populate(["grunt", "darter"], 14, 0.0, 90.0, 220.0)
	await _settle(60)
	await _shot("09_boss")

	# 先拍低血画面：临时屏蔽保底回血，否则会立刻被治愈
	world._mercy_used = true
	world.player.hp = world.player.max_hp * 0.2
	Bus.player_hp_changed.emit(world.player.hp, world.player.max_hp)
	await _settle(12)
	await _shot("10_lowhp")
	# 再验证保底回血：让它真正触发一次，看血量是否被拉回
	world._mercy_used = false
	world.player.hp = world.player.max_hp * 0.18
	var before_hp := world.player.hp
	await _settle(26)
	print("[SHOT] mercy-triggered=", world._mercy_used,
		" hp ", int(before_hp), " -> ", int(world.player.hp),
		" / ", int(world.player.max_hp), " (expect true and hp rising)")

	world.player.hp = world.player.max_hp * 0.8
	world.finish(true)
	await _settle(20)
	await _shot("11_result")
	result.visible = false

	# ---------------- 各关专属机制 ----------------
	# 第 1 关：巡逻激光门
	_start_run(0, false)
	world.player.bot = true
	_give_player(["pistol", "shotgun", "laser"], {"damage": 2, "firerate": 2})
	_populate(["grunt", "darter", "lancer", "bomber"], 22, 0.1, 60.0, 220.0)
	world._spawn_hazard("laser_gate")
	world._spawn_hazard("laser_gate")
	await _wait(1.7)
	await _shot("12_hazard_laser")

	# 第 2 关：数据风暴区 + 腐蚀区 + 传送
	_start_run(1, false)
	world.player.bot = true
	_give_player(["pistol", "laser", "boomerang"], {"damage": 3, "speed": 2, "crit": 2})
	_populate(["grunt", "darter", "flyer", "splitter"], 26, 0.15, 60.0, 240.0)
	for i in 3:
		world._spawn_hazard("storm_zone")
	for i in 5:
		Hazard.spawn(world.hazard_layer(), "corro",
			world.player.global_position + Vector2(randf_range(-160, 160), randf_range(-120, 120)), {})
	await _wait(1.9)
	await _shot("13_hazard_storm")

	# 第 3 关：熔岩喷口 + 旋转激光臂 + 敌人护盾
	_start_run(2, false)
	world.player.bot = true
	_give_player(["pistol", "shotgun", "orb"], {"damage": 3, "firerate": 3, "shield": 3})
	_populate(["tank", "splitter", "summoner", "bomber"], 24, 0.45, 60.0, 240.0)
	world._spawn_hazard("laser_arm")
	for i in 3:
		world._spawn_hazard("lava_vent")
	await _wait(2.0)
	await _shot("14_hazard_lava")

	# Boss 大招
	world.elapsed = 239.3
	await _wait(2.2)
	_populate(["grunt", "darter"], 10, 0.0, 90.0, 200.0)
	await _wait(1.4)
	if world.boss != null and is_instance_valid(world.boss):
		world.boss.hp = world.boss.max_hp * 0.70
		world.boss.take_damage(1.0, false, world.player.global_position, 0.0)
	await _wait(0.9)
	await _shot("15_boss_ult")

	# 掉落物展示：确认医疗包在战场上一眼可辨
	_start_run(0, false)
	world.player.bot = true
	_give_player(["pistol", "shotgun", "laser"], {"damage": 2, "firerate": 2})
	var kinds := ["hp", "shield", "pulse", "timechip", "rage", "gear", "xp", "chest"]
	_populate(["splitter", "bomber", "tank", "grunt"], 12, 0.0, 150.0, 240.0)
	for i in kinds.size():
		var px: Vector2 = world.player.global_position + Vector2(-150.0 + float(i) * 43.0, -60.0)
		var pk := Pickup.spawn(world.pickup_layer, String(kinds[i]), 1, world.arena.resolve(px, 10.0))
		pk.vel = Vector2.ZERO
	await _wait(0.5)
	await _shot("16_pickups")

	# 全武器弹道 / 枪口特效对比
	_start_run(0, false)
	world.player.bot = true
	await _wait(0.8)   # 等摄像机平滑跟随归位，否则玩家不在画面中心
	var pnames := ["proj_pistol", "proj_shotgun", "proj_laser", "proj_boomerang", "proj_orb", "proj_rocket"]
	var mnames := ["vfx_muzzle_pistol", "vfx_muzzle_shotgun", "vfx_muzzle_laser",
		"vfx_muzzle_boomerang", "vfx_muzzle_orb", "vfx_muzzle_rocket"]
	var pl2 = world.player
	for i in pnames.size():
		var at: Vector2 = pl2.global_position + Vector2(-90.0 + float(i) * 36.0, -40.0)
		var pr := Projectile.spawn(world.bullet_layer, {
			"sprite": String(pnames[i]), "dmg": 1.0, "crit": false, "pierce": 0, "life": 9.0,
			"speed": 0.0, "radius": 6.0, "knock": 0.0, "aoe": 0.0, "homing": 0.0,
			"from_player": true, "scale": 1.0,
		})
		pr.global_position = at
		pr.vel = Vector2.ZERO
		pr.speed = 0.0
		pr.boomerang = false
		if i == 0:
			Fx.spawn(world.fx_layer, "vfx_muzzle_pistol",
				pl2.global_position + Vector2(-160.0, -150.0), 1.0, 1.0, Color.WHITE)
	await _wait(0.06)
	await _shot("17_weapons")

	# 激光束实测：给玩家激光武器，朝一列敌人开火
	_start_run(0, false)
	world.player.bot = false
	await _wait(0.8)
	_give_player(["laser", "pistol"], {"crit": 3, "damage": 2})
	var pl3 = world.player
	pl3.aim = Vector2.RIGHT
	for i in 9:
		var e := Enemy.spawn(world.enemy_layer, "grunt", "", Vector2.ZERO, 1.0, 1.0)
		e.global_position = pl3.global_position + Vector2(90.0 + float(i) * 62.0, -18.0 + float(i % 3) * 18.0)
		world.enemies.append(e)
	pl3.weapons.clear()
	pl3.weapons.append({"id": "laser", "lv": 5, "cd_left": 0.0, "evolved": true})
	pl3._fire(pl3.weapons[0], world)
	await _wait(0.05)
	await _shot("18_laser")

	# 主动技能与战术道具实测
	_start_run(0, false)
	world.player.bot = false
	await _wait(0.8)
	_give_player(["pistol"], {"damage": 2})
	var pl4 = world.player
	pl4.add_skill("shockwave")
	pl4.add_skill("shieldfield")
	_populate(["grunt", "darter", "bomber", "splitter"], 28, 0.18, 42.0, 165.0)
	pl4.use_skill(0)
	pl4.use_skill(1)
	await _wait(0.10)
	await _shot("19_skills")

	# 回归：地上掉落物 >300 时打死 Boss，必须仍然通关
	_start_run(0, false)
	world.player.bot = true
	await _wait(0.4)
	for i in 320:
		var off := Vector2(randf_range(-320.0, 320.0), randf_range(-320.0, 320.0))
		Pickup.spawn(world.pickup_layer, "gear", 1,
			world.arena.resolve(world.player.global_position + off, 10.0))
	world.boss_spawned = true
	world._spawn_boss()
	await _wait(0.15)
	var pk_before := world.pickup_layer.get_child_count()
	world.boss.take_damage(999999.0, false, Vector2.ZERO, 0.0)
	await _wait(0.25)
	print("[SHOT] boss-kill-with-", pk_before, "-pickups -> finished=", world.finished,
		" won=", world.won, " (expect true true)")

	print("[SHOT] done")
	get_tree().quit(0)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _stress_load(w) -> void:
	## 仅自测用：直接给满配，用于压测 Boss/弹幕/性能
	w.player.weapons.clear()
	for d in DB.WEAPONS:
		w.player.weapons.append({"id": String(d["id"]), "lv": 5, "cd_left": 0.0, "evolved": true})
	for d in DB.PASSIVES:
		w.player.passives[String(d["id"])] = 5
	w.player.recompute(true)
	w.player.hp = w.player.max_hp


func _bot_step() -> void:
	if world == null or not is_instance_valid(world):
		return
	var pl = world.player
	if pl == null or not is_instance_valid(pl) or pl.dead:
		return
	var arr: Array = world.query_circle(pl.global_position, 320.0)
	var flee := Vector2.ZERO
	var n := 0.0
	var nearest = null
	var bd := 1e20
	for e in arr:
		var d: float = pl.global_position.distance_squared_to(e.global_position)
		if d < bd:
			bd = d
			nearest = e
		if d < 6400.0:
			flee += (pl.global_position - e.global_position).normalized() / maxf(sqrt(d), 8.0)
			n += 1.0
	if nearest != null:
		pl.aim = (nearest.global_position - pl.global_position).normalized()
	# 安全时去捡最近的掉落
	var best_loot = null
	var bld := 200.0
	for pk in world.pickup_layer.get_children():
		if not is_instance_valid(pk):
			continue
		var d2: float = pl.global_position.distance_squared_to(pk.global_position)
		if pk.kind != "chest" and d2 < bld * bld:
			bld = sqrt(d2)
			best_loot = pk
	# 机器人技能策略：血少或被围住就交技能（贴近真人用法）
	for si in pl.skills.size():
		if float(pl.skills[si]["cd_left"]) > 0.0:
			continue
		if pl.hp < pl.max_hp * 0.62 or arr.size() >= 6:
			pl.use_skill(si)
	if n > 0.0:
		flee = flee.normalized()
	var inner: Rect2 = world.arena.inner_rect().grow(-70.0)
	var center: Vector2 = world.arena.arena_size * 0.5
	var to_center: Vector2 = center - pl.global_position
	var seek := Vector2.ZERO
	if best_loot != null:
		seek = (best_loot.global_position - pl.global_position).normalized() * 0.55
	pl.bot_dir = (flee * 1.4 + seek + to_center.normalized() * clampf(to_center.length() / 700.0, 0.0, 1.0)).normalized()
	if pl.bot_dir.length() < 0.1:
		pl.bot_dir = Vector2(1, 0)
	if not inner.has_point(pl.global_position):
		pl.bot_dir = to_center.normalized()


func _process(_d: float) -> void:
	if _bot and _bot_has_choice:
		_bot_has_choice = false
		_on_choice(_bot_choice)
	if _swarm > 0 and world != null and is_instance_valid(world) and world.enemies.size() < _swarm:
		var kinds := ["grunt", "darter", "lancer", "bomber", "splitter", "flyer", "tank", "summoner"]
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var pl = world.player
		for i in mini(12, _swarm - world.enemies.size()):
			var ang := rng.randf() * TAU
			var p: Vector2 = pl.global_position + Vector2(cos(ang), sin(ang)) * rng.randf_range(220.0, 420.0)
			p = world.arena.resolve(p, 14.0)
			world._spawn_at(String(kinds[rng.randi_range(0, kinds.size() - 1)]), "", p, false)
	if _bot and Game.state == Game.ST_PLAYING:
		_bot_step()
		if _autodash and world != null and is_instance_valid(world) and world.player != null:
			world.player.try_dash()
	if _autoquit > 0:
		_frames += 1
		if _autodash and world != null and is_instance_valid(world) and world.player != null:
			world.player.try_dash()
		if world != null and is_instance_valid(world) and _frames % 300 == 0:
			print("[PERF] t=", "%.0f" % world.elapsed, " fps=", Engine.get_frames_per_second(),
				" enemies=", world.enemies.size(), " proj=", world.bullet_layer.get_child_count(),
				" pickups=", world.pickup_layer.get_child_count())
		var done := _frames >= _autoquit
		if not done and _maxt > 0.0 and world != null and is_instance_valid(world):
			done = world.elapsed >= _maxt or (world.finished and world.elapsed > 2.0)
		if done:
			if world != null and is_instance_valid(world):
				print("[SMOKE] t=", "%.1f" % world.elapsed, " kills=", world.kills,
					" enemies=", world.enemies.size(), " lv=", world.player.level,
					" hp=", "%.0f" % world.player.hp, " pending=", world.pending_levels,
					" boss=", world.boss_spawned, " finished=", world.finished,
					" gears=", world.gears_earned,
					" weapons=", world.player.weapons.size(),
					" flow_us=%d builds=%d" % [world.arena._flow_usec, world.arena._flow_builds],
					" bgm_intensity=%.2f drive_db=%.1f" % [Audio._intensity,
						Audio._bgm_drive.volume_db])
			print("[SMOKE] clean exit after ", _frames, " frames")
			get_tree().quit(0)
	if Game.state == Game.ST_PLAYING and world != null and is_instance_valid(world) and world.player != null:
		if Input.is_action_just_pressed("dash"):
			world.player.try_dash()
		if Input.is_action_just_pressed("skill1"):
			world.player.use_skill(0)
		if Input.is_action_just_pressed("skill2"):
			world.player.use_skill(1)


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	var k: int = (e as InputEventKey).physical_keycode
	if k == KEY_ESCAPE:
		if Game.state == Game.ST_PLAYING or Game.state == Game.ST_PAUSED:
			_toggle_pause()
	elif k == KEY_F11:
		Save.set_setting("fullscreen", not bool(Save.setting("fullscreen", false)))
		Game.apply_settings()
	elif k == KEY_R and Game.state == Game.ST_RESULT:
		_restart()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Save.save_game()
