class_name World
extends Node2D
## 一局游戏的全部世界逻辑：关卡、刷怪、碰撞、掉落、动态难度。

const CELL := 56.0
const MAX_ALIVE_DEFAULT := 165
var max_alive := MAX_ALIVE_DEFAULT
const MAX_TEXTS := 40

var stage_idx := 0
var endless := false
var elapsed := 0.0
var duration := 240.0
var kills := 0
var gears_earned := 0
var finished := false
var won := false
var boss = null
var boss_spawned := false
var pending_levels := 0
var player: Player
var arena: Arena
var camera: Camera2D
var floor_layer: Node2D
var bullet_layer: Node2D
var enemy_layer: Node2D
var pickup_layer: Node2D
var fx_layer: Node2D
var text_layer: Node2D

var enemies: Array = []

var _grid: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _shake_amt := 0.0
var _shake_t := 0.0
var _shake_dur := 0.0
var _spawn_acc := 0.0
var _dda := 0.0
var _clear_t := -1.0
var _last_phase_text := ""
# ---- 关卡差异化 ----
var flags: Dictionary = {}
var run_mods: Array = []
var calm_t := 0.0
var bounty_target = null
var boss_hazard_mul := 1.0
var _mod_total: Dictionary = {}
var _hazard_layer: Node2D
var _hazards_cfg: Array = []
var _hazard_t: Array = []
var _hazard_spawned: Dictionary = {}
var _event_t := 58.0
var _mercy_used := false
var _spawn_ang := 0.0
var _spawn_ang_t := 7.0
var diff: Dictionary = {}
var _dmg_t := 0.0
var _last_hp := -1.0


func setup(p_stage: int, p_endless: bool) -> void:
	stage_idx = p_stage
	endless = p_endless
	_rng.randomize()
	z_index = 0
	var st: Dictionary = DB.stage(stage_idx)
	diff = DB.difficulty(int(Save.setting("difficulty", 1)))
	max_alive = int(diff["max_alive"])
	flags = (st.get("flags", {}) as Dictionary).duplicate()
	_roll_mods()
	_event_t = _rng.randf_range(50.0, 68.0)
	floor_layer = _layer(-100)
	arena = Arena.new()
	floor_layer.add_child(arena)
	arena.setup(int(st["theme"]), Vector2(2048, 1408), _rng.randi(), String(st.get("layout", "open")))
	duration = float(st["duration"])
	_hazard_layer = _layer(4)
	_hazards_cfg = (st.get("hazards", []) as Array).duplicate()
	for hc in _hazards_cfg:
		_hazard_t.append(0.0)   # 一旦到达 from 时间就立刻触发第一次

	pickup_layer = _layer(0)
	bullet_layer = _layer(16)   # 必须画在敌人(10)和玩家(12)之上，否则看不见子弹
	enemy_layer = _layer(10)
	fx_layer = _layer(30)
	text_layer = _layer(40)

	player = Player.new()
	player.z_index = 12
	add_child(player)
	player.global_position = arena.arena_size * 0.5
	player.reset()
	player.add_weapon("pistol")

	camera = Camera2D.new()
	var zf := 1.0 + mod_total("zoom")
	camera.zoom = Vector2(zf, zf)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 9.0
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(arena.arena_size.x)
	camera.limit_bottom = int(arena.arena_size.y)
	add_child(camera)
	camera.make_current()

	Bus.stage_time.emit(stage_idx, 0.0, duration)
	var mod_names: Array = []
	for m in run_mods:
		mod_names.append(String(m["name"]))
	Bus.wave_phase.emit("第 %d 关 - %s　[%s / 修正：%s]" % [stage_idx + 1, st["name"],
		diff.get("name", "普通"), " · ".join(mod_names)])
	if endless:
		Bus.stage_time.emit(stage_idx, 0.0, 0.0)
	var bn := String(DB.stage(stage_idx)["bgm"])
	Audio.bgm_layered(bn + "_base", bn + "_drive", 1.4)
	Game.world = self


func _layer(z: int) -> Node2D:
	var n := Node2D.new()
	n.z_index = z
	add_child(n)
	return n


func arena_rect() -> Rect2:
	return Rect2(Vector2.ZERO, arena.arena_size)


# ---------------------------------------------------------------- 主循环
func _physics_process(delta: float) -> void:
	if _dmg_t > 0.0:
		_dmg_t -= delta
	if player != null and is_instance_valid(player):
		if _last_hp >= 0.0 and player.hp < _last_hp - 0.01:
			_dmg_t = 2.5
		_last_hp = player.hp
	if not finished:
		Audio.set_intensity(combat_intensity())
		if arena != null and player != null and is_instance_valid(player):
			arena.update_flow(player.global_position)
	if player == null:
		return
	if not finished:
		elapsed += delta
		Bus.stage_time.emit(stage_idx, elapsed, duration)
	_rebuild_grid()
	_step_projectiles(delta)
	_separate(delta)
	_collect_pickups(delta)
	if not finished:
		_update_spawner(delta)
		_update_phase_text()
		_update_hazards(delta)
		_update_events(delta)
		calm_t = maxf(0.0, calm_t - delta)
		_spawn_ang_t -= delta
		if _spawn_ang_t <= 0.0:
			_spawn_ang_t = _rng.randf_range(7.0, 12.0)
			_spawn_ang = _rng.randf() * TAU
	_update_clear_state(delta)
	_prune()


func _process(delta: float) -> void:
	# 相机跟随 + 震屏
	if camera != null and player != null and is_instance_valid(player):
		camera.global_position = player.global_position
		if _shake_t > 0.0:
			_shake_t -= delta
			var k: float = _shake_amt * (_shake_t / maxf(_shake_dur, 0.001))
			camera.offset = Vector2(_rng.randf_range(-k, k), _rng.randf_range(-k, k))
		elif camera.offset != Vector2.ZERO:
			camera.offset = camera.offset.lerp(Vector2.ZERO, 0.35)


func shake(amount: float, dur: float) -> void:
	if not bool(Save.setting("shake", true)):
		return
	if amount >= _shake_amt or _shake_t <= 0.0:
		_shake_amt = amount
	_shake_dur = maxf(dur, 0.05)
	_shake_t = maxf(_shake_t, _shake_dur)


# ---------------------------------------------------------------- 空间网格
func _rebuild_grid() -> void:
	_grid.clear()
	for e in enemies:
		if not is_instance_valid(e) or e.dead:
			continue
		var c := Vector2i(int(floor(e.global_position.x / CELL)), int(floor(e.global_position.y / CELL)))
		if _grid.has(c):
			_grid[c].append(e)
		else:
			_grid[c] = [e]


func query_circle(center: Vector2, radius: float) -> Array:
	var out: Array = []
	var r := int(ceil(radius / CELL)) + 1
	var cx := int(floor(center.x / CELL))
	var cy := int(floor(center.y / CELL))
	var r2 := radius * radius
	for gy in range(cy - r, cy + r + 1):
		for gx in range(cx - r, cx + r + 1):
			var key := Vector2i(gx, gy)
			if not _grid.has(key):
				continue
			for e in _grid[key]:
				if is_instance_valid(e) and not e.dead and e.global_position.distance_squared_to(center) <= r2:
					out.append(e)
	return out


func query_segment(a: Vector2, b: Vector2, pad: float) -> Array:
	var lo := Vector2(minf(a.x, b.x) - pad, minf(a.y, b.y) - pad)
	var hi := Vector2(maxf(a.x, b.x) + pad, maxf(a.y, b.y) + pad)
	var out: Array = []
	var gx0 := int(floor(lo.x / CELL)); var gx1 := int(floor(hi.x / CELL))
	var gy0 := int(floor(lo.y / CELL)); var gy1 := int(floor(hi.y / CELL))
	for gy in range(gy0, gy1 + 1):
		for gx in range(gx0, gx1 + 1):
			var key := Vector2i(gx, gy)
			if not _grid.has(key):
				continue
			for e in _grid[key]:
				if is_instance_valid(e) and not e.dead:
					out.append(e)
	return out


func _separate(delta: float) -> void:
	for e in enemies:
		if not is_instance_valid(e) or e.dead:
			continue
		var c := Vector2i(int(floor(e.global_position.x / CELL)), int(floor(e.global_position.y / CELL)))
		for gy in range(c.y - 1, c.y + 2):
			for gx in range(c.x - 1, c.x + 2):
				var key := Vector2i(gx, gy)
				if not _grid.has(key):
					continue
				for o in _grid[key]:
					if o == e or not is_instance_valid(o) or o.dead:
						continue
					var d: Vector2 = o.global_position - e.global_position
					var dl := d.length()
					var want: float = e.radius + o.radius
					if dl < want and dl > 0.01:
						var push := d / dl * (want - dl) * 0.5
						if not e.is_boss:
							e.global_position -= push * clampf(6.0 * delta, 0.0, 1.0)
						if not o.is_boss:
							o.global_position += push * clampf(6.0 * delta, 0.0, 1.0)


# ---------------------------------------------------------------- 弹丸
static func seg_circle(a: Vector2, b: Vector2, c: Vector2, r: float) -> bool:
	var ab := b - a
	var den := ab.length_squared()
	var t := 0.0
	if den > 0.0001:
		t = clampf((c - a).dot(ab) / den, 0.0, 1.0)
	return (a + ab * t).distance_squared_to(c) <= r * r


func _step_projectiles(delta: float) -> void:
	for p in bullet_layer.get_children():
		# 弹丸层里还混着激光束(Beam)节点，先过滤掉
		if not is_instance_valid(p) or not (p is Projectile) or p.dead:
			continue
		var prev: Vector2 = p.global_position
		p.step(delta)
		if not is_instance_valid(p) or p.dead:
			continue
		if arena.hits_pillar(p.global_position, p.radius):
			Fx.spawn(fx_layer, "vfx_hit", p.global_position, 0.7, 20.0, Color(0.9, 0.9, 1.2))
			p.die()
			continue
		if p.from_player:
			for e in query_segment(prev, p.global_position, p.radius + 16.0):
				if p.dead or e.dead:
					continue
				var id: int = e.get_instance_id()
				if p.hit_ids.has(id):
					continue
				if seg_circle(prev, p.global_position, e.global_position, e.radius + p.radius):
					p.hit_ids[id] = true
					_hit_enemy(p, e)
					if p.dead:
						break
					if p.pierce <= 0:
						p.die()
						break
					p.pierce -= 1
		else:
			var pl := player
			if pl != null and not pl.dead and pl.iframe <= 0.0:
				if seg_circle(prev, p.global_position, pl.global_position, Player.RADIUS + p.radius):
					pl.take_damage(p.dmg, p.global_position)
					p.die()


func _hit_enemy(p: Projectile, e) -> void:
	e.take_damage(p.dmg, p.crit, p.global_position, p.knock)
	Fx.spawn(fx_layer, "vfx_hit", p.global_position, 0.62, 22.0,
		Color(1.6, 1.6, 0.9) if p.crit else Color(1.0, 1.2, 1.6))
	Audio.play("sfx_hit_enemy", 1.0 if not p.crit else 1.3, 0.08, 0.35)
	if p.aoe > 0.0:
		explode(p.global_position, p.aoe, p.dmg * 0.75, true)
		p.die()
	elif p.split_on_death > 0 and (e.hp <= 0.0 or p.pierce <= 0):
		for i in p.split_on_death:
			var a := _rng.randf() * TAU
			var np := Projectile.spawn(bullet_layer, {
				"sprite": "proj_orb", "dmg": p.dmg * 0.45, "crit": p.crit, "pierce": 1,
				"life": 1.4, "speed": 210.0, "radius": 6.0, "knock": 20.0, "aoe": 0.0,
				"homing": 4.0, "from_player": true, "scale": 0.65,
			})
			np.global_position = p.global_position
			np.vel = Vector2(cos(a), sin(a)) * 210.0
			np.speed = 210.0
		p.die()


# ---------------------------------------------------------------- 伤害/死亡回调
func on_enemy_damaged(e, real: float, crit: bool, from_pos: Vector2) -> void:
	if e.is_boss:
		Bus.boss_hp_changed.emit(maxf(0.0, e.hp), e.max_hp)
	if crit:
		_float_text("%d!" % int(round(real)), e.global_position + Vector2(0, -e.radius - 4),
			Color("ffe460"), 11, true)
	elif _rng.randf() < 0.45:
		_float_text(str(int(round(real))), e.global_position + Vector2(0, -e.radius - 4),
			Color("dfe6ff") if e.hp > 0.0 else Color("ff9a30"), 9, true)


## 敌人死亡掉落（与死亡处理分开，避免"掉落过多"影响通关判定）
func _on_enemy_drops(e, pos: Vector2) -> void:
	var g := int(round(e.gears * player.gear_mul() * float(diff["gears"])))
	gears_earned += g
	var gn := clampi(g, 1, 3)
	for i in gn:
		Pickup.spawn(pickup_layer, "gear", maxi(1, int(round(float(g) / float(gn)))), pos)
	var xp_total: int = e.xp_value
	var n := clampi(xp_total, 1, 6)
	for i in n:
		Pickup.spawn(pickup_layer, "xp", maxi(1, int(round(float(xp_total) / float(n)))), pos)
	if _rng.randf() < (0.10 + (0.15 if e.elite else 0.0)):
		Pickup.spawn(pickup_layer, "hp", 1, pos)
	# 精英与 Boss 必掉战术道具
	if e.elite or e.is_boss:
		var tactic := ["shield", "pulse", "timechip", "rage"]
		for i in (2 if e.is_boss else 1):
			Pickup.spawn(pickup_layer, String(tactic[_rng.randi_range(0, tactic.size() - 1)]), 1, pos)
	if String(e.data.get("split_into", "")) != "" and not e.is_boss:
		for i in int(e.data.get("split_n", 2)):
			var a := _rng.randf() * TAU
			summon_around(pos + Vector2(cos(a), sin(a)) * 22.0,
				String(e.data["split_into"]), 1, false)


func on_enemy_died(e, no_drop: bool) -> void:
	if not enemies.has(e):
		return
	kills += 1
	Bus.kill_count.emit(kills)
	var pos: Vector2 = e.global_position
	Fx.spawn(fx_layer, "vfx_explosion", pos, 0.8 if not e.is_boss else 1.6, 18.0)
	Fx.spawn(fx_layer, "vfx_smoke", pos, 1.0, 12.0)
	if e.elite or e.is_boss:
		shake(6.0 if not e.is_boss else 14.0, 0.4)
	Audio.play("sfx_explode_big" if e.is_boss else "sfx_explode", 1.0, 0.06, 0.55)
	if e.is_boss or e.elite:
		Audio.duck(0.35, 0.6)

	if not no_drop:
		if pickup_layer.get_child_count() > 300:
			# 掉落物过多时直接结算经验，避免刷屏。
			# 这里绝对不能 return —— 那会连下面的 Boss 死亡处理一起跳过，
			# 造成"Boss 血条清空却不通关"（已修复的 Bug）。
			player.add_xp(e.xp_value)
		else:
			_on_enemy_drops(e, pos)

	if e.bounty:
		gears_earned += 80
		_float_text("悬赏 +80 齿轮", pos + Vector2(0, -22), Color("ffe460"), 12, true)
		Audio.play("sfx_pickup_gear", 0.8, 0.0, 0.8)
		bounty_target = null
	if bool(flags.get("corrosive_death", false)) and not e.is_boss and _rng.randf() < 0.32:
		Hazard.spawn(_hazard_layer, "corro", pos, {})
	if e.is_boss:
		Bus.boss_died.emit()
		boss_hazard_mul = 1.0
		boss = null
		boss_spawned = true
		shake(18.0, 1.0)
		Fx.spawn(fx_layer, "vfx_bigboom", pos, 2.0, 14.0)
		_wave_text("BOSS 击破！")
		finish(true)
	elif e.elite:
		Audio.play("sfx_levelup", 0.9, 0.05, 0.5)


func explode(pos: Vector2, radius: float, dmg: float, from_player: bool) -> void:
	Fx.spawn(fx_layer, "vfx_explosion", pos, clampf(radius / 28.0, 0.7, 2.2), 18.0)
	shake(clampf(radius * 0.10, 2.0, 9.0), 0.25)
	Audio.play("sfx_explode", 1.0, 0.1, 0.6)
	if from_player:
		for e in query_circle(pos, radius):
			if e.dead:
				continue
			var k := 1.0 - pos.distance_to(e.global_position) / maxf(radius, 1.0)
			e.take_damage(dmg * (0.55 + 0.45 * k), false, pos, 130.0)
	else:
		if player != null and not player.dead:
			if pos.distance_to(player.global_position) < radius + Player.RADIUS:
				player.take_damage(dmg, pos)


func _float_text(text: String, pos: Vector2, col: Color, size: int, _important: bool) -> void:
	if text_layer.get_child_count() >= MAX_TEXTS:
		return
	FloatText.spawn(text_layer, text, pos, col, size)


# ---------------------------------------------------------------- 战术效果
## 环形冲击：伤害 + 强击退（技能与脉冲炸弹共用）
func shockwave(pos: Vector2, radius: float, dmg: float, knock: float) -> void:
	Fx.spawn(fx_layer, "vfx_shock", pos, clampf(radius / 44.0, 0.8, 4.0), 15.0, Color(0.6, 1.2, 1.6))
	Fx.spawn(fx_layer, "vfx_bigboom", pos, clampf(radius / 90.0, 0.8, 2.2), 18.0, Color(0.7, 1.1, 1.5))
	shake(7.0, 0.35)
	Audio.play("sfx_explode_big", 1.0, 0.05, 0.75)
	for e in query_circle(pos, radius):
		if e.dead:
			continue
		e.take_damage(dmg, false, pos, knock)


## 清空指定范围内的敌方子弹
func clear_enemy_bullets(pos: Vector2, radius: float) -> int:
	var n := 0
	for p in bullet_layer.get_children():
		if not is_instance_valid(p) or not (p is Projectile) or p.dead or p.from_player:
			continue
		if p.global_position.distance_to(pos) <= radius:
			Fx.spawn(fx_layer, "vfx_hit", p.global_position, 0.7, 20.0, Color(0.7, 1.2, 1.5))
			p.die()
			n += 1
	return n


## 全场敌人减速（走 enemies 数组，不用空间网格，避免超大半径）
func slow_all_enemies(mul: float, dur: float) -> void:
	for e in enemies:
		if is_instance_valid(e) and not e.dead:
			e.apply_slow(mul, dur)


# ---------------------------------------------------------------- 激光束
## 从 from 沿 dir 推进，遇到立柱或竞技场边界就停下
## 战斗强度 0~1：驱动 BGM 的战斗层。敌人密度 / 濒危 / Boss / 刚受伤
func combat_intensity() -> float:
	if player == null or not is_instance_valid(player):
		return 0.0
	# 阈值要贴着实际战场密度定：之前用 /18 导致常规交战时只有 0.17，
	# 战斗层几乎推不进来，"战斗时激昂"就成了空话。
	var near := float(query_circle(player.global_position, 380.0).size())
	var v: float = clampf(near / 8.0, 0.0, 1.0)
	if boss != null and is_instance_valid(boss):
		v = maxf(v, 0.80)
	if player.hp < player.max_hp * 0.45:
		v = maxf(v, 0.55)
	if _dmg_t > 0.0:
		v = maxf(v, 0.72)
	return clampf(v, 0.0, 1.0)


func beam_endpoint(from: Vector2, dir: Vector2, max_len: float) -> Vector2:
	var inner := arena.inner_rect()
	var step := 12.0
	var d := step
	while d < max_len:
		var p: Vector2 = from + dir * d
		if not inner.has_point(p) or arena.hits_pillar(p, 2.0):
			return from + dir * maxf(0.0, d - step * 0.6)
		d += step
	return from + dir * max_len


## 沿光束一次性伤害所有命中的敌人（真正的贯穿）
func beam_damage(from: Vector2, to: Vector2, half_w: float, dmg: float,
		crit: bool, knock: float) -> int:
	var hits := 0
	for e in query_segment(from, to, half_w + 26.0):
		if e == null or e.dead:
			continue
		if seg_circle(from, to, e.global_position, e.radius + half_w):
			e.take_damage(dmg, crit, from, knock)
			Fx.spawn(fx_layer, "vfx_hit", e.global_position, 0.75, 22.0, Color(1.5, 1.7, 1.9))
			hits += 1
	return hits


# ---------------------------------------------------------------- 敌人弹幕
func enemy_bullet(pos: Vector2, dir: Vector2, spd: float, dmg: float, sprite: String) -> void:
	var p := Projectile.spawn(bullet_layer, {
		"sprite": sprite, "dmg": dmg, "crit": false, "pierce": 0, "life": 3.4,
		"speed": spd, "radius": 6.0, "knock": 0.0, "aoe": 0.0, "from_player": false,
		"homing": 0.0, "scale": 1.0,
	})
	p.global_position = pos
	p.vel = dir * spd
	p.speed = spd


func enemy_shoot(pos: Vector2, dir: Vector2, data: Dictionary, _shooter) -> void:
	var spr := String(data.get("eproj", "eproj_shard"))
	var spd := float(data.get("eproj_speed", 180.0))
	enemy_bullet(pos, dir, spd, 7.0, spr)
	Audio.play("sfx_shoot_orb", 0.9, 0.08, 0.3)


func summon_around(pos: Vector2, kind: String, n: int, telegraph: bool = true) -> void:
	for i in n:
		var a := _rng.randf() * TAU
		var p := pos + Vector2(cos(a), sin(a)) * _rng.randf_range(26.0, 54.0)
		p = arena.resolve(p, 12.0)
		if enemies.size() >= max_alive:
			return
		_spawn_at(kind, "", p, telegraph)


# ---------------------------------------------------------------- 刷怪
func _update_spawner(delta: float) -> void:
	if elapsed >= duration:
		if not boss_spawned:
			boss_spawned = true
			_spawn_boss()
		return
	var st := DB.stage(stage_idx)
	var ph := DB.phase_at(stage_idx, elapsed)
	if calm_t > 0.0:
		return
	var rate := float(ph["rate"]) * float(st["rate_mult"]) * (1.0 + _dda) 		* maxf(0.05, 1.0 + mod_total("erate")) * float(diff["erate"])
	# 拥堵保护：同屏敌人远超玩家的清怪能力时降低刷新速度，
	# 避免"清不过来 → 越堆越多 → 被压死"的死亡螺旋（强玩家不受影响）
	var kill_rate: float = maxf(0.5, player.combat_scale() / 60.0)
	var congestion: float = float(enemies.size()) / maxf(1.0, kill_rate * 8.0)
	rate *= clampf(1.0 - maxf(0.0, congestion - 2.0) * 0.25, 0.55, 1.0)
	_spawn_acc += rate * delta
	var guard := 0
	while _spawn_acc >= 1.0 and guard < 24:
		guard += 1
		_spawn_acc -= 1.0
		if enemies.size() >= max_alive:
			_spawn_acc = 0.0
			break
		var pool: Array = ph["pool"]
		var kind := String(pool[_rng.randi_range(0, pool.size() - 1)])
		var ec := maxf(DB.elite_chance(stage_idx, elapsed), float(ph.get("elite", 0.0))) 			* (1.0 + maxf(mod_total("elite"), 0.0)) * float(diff["elite"])
		var eid := ""
		if _rng.randf() < ec:
			eid = String(DB.ELITES[_rng.randi_range(0, DB.ELITES.size() - 1)]["id"])
		_spawn_at(kind, eid, _spawn_pos(), true)


func _spawn_pos() -> Vector2:
	## 敌人集中在一个扇形里出现，永远留出可以撤退的一侧；
	## 距离也拉远，让玩家有反应时间。之前是 360 度围着玩家生成，确实无从躲避。
	var inner := arena.inner_rect().grow(-24.0)
	for i in 40:
		var a: float = _spawn_ang + _rng.randf_range(-1.05, 1.05)
		if _rng.randf() < 0.2:
			a = _rng.randf() * TAU
		var dir := Vector2(cos(a), sin(a))
		for d in [660.0, 580.0, 500.0, 430.0, 380.0]:
			var p: Vector2 = player.global_position + dir * d
			if inner.has_point(p) and not arena.hits_pillar(p, 18.0):
				return p
	var far := Vector2(inner.position.x, inner.position.y)
	for c in [Vector2(inner.end.x, inner.position.y), Vector2(inner.position.x, inner.end.y), inner.end]:
		if c.distance_to(player.global_position) > far.distance_to(player.global_position):
			far = c
	return far


func _hp_mult() -> float:
	var st := DB.stage(stage_idx)
	var ramp := 1.0 + 0.75 * clampf(elapsed / maxf(duration, 1.0), 0.0, 1.4)
	return float(st["hp_mult"]) * ramp * (1.0 + 0.12 * _dda) 		* maxf(0.2, 1.0 + mod_total("ehp")) * float(diff["ehp"])


func _speed_mult() -> float:
	var st := DB.stage(stage_idx)
	return (1.0 + 0.03 * stage_idx + 0.07 * clampf(elapsed / maxf(duration, 1.0), 0.0, 1.0)) 		* maxf(0.3, 1.0 + mod_total("espeed"))


func _spawn_at(kind: String, elite_id: String, pos: Vector2, telegraph: bool):
	var e := Enemy.spawn(enemy_layer, kind, elite_id, pos, _hp_mult(), _speed_mult())
	enemies.append(e)
	if telegraph:
		Fx.spawn(fx_layer, "vfx_spawn", pos, 1.1, 16.0,
			Color(1.6, 0.8, 1.0) if elite_id != "" else Color.WHITE)
	return e


func _spawn_boss() -> void:
	_wave_text("警告：%s 出现！" % DB.BOSSES[stage_idx]["name"])
	# Boss 登场冲击：清掉大部分小怪（照给经验），让 Boss 战能聚焦
	var trash: Array = []
	for e in enemies:
		if is_instance_valid(e) and not e.dead and not e.is_boss:
			trash.append(e)
	for i in range(int(float(trash.size()) * 0.45), trash.size()):
		trash[i].take_damage(999999.0, false, arena.arena_size * 0.5, 0.0)
	Fx.spawn(fx_layer, "vfx_bigboom", arena.arena_size * 0.5, 5.0, 10.0, Color(1.1, 0.85, 1.3))
	var pos := _spawn_pos()
	var hp_m := (1.0 + 0.45 * float(stage_idx) + 0.30 * maxf(_dda, 0.0)) * float(diff["ehp"])
	boss = Boss.spawn_boss(enemy_layer, stage_idx, pos, hp_m)
	enemies.append(boss)
	boss_hazard_mul = 2.0
	Bus.boss_spawned.emit(boss)
	Bus.boss_hp_changed.emit(boss.hp, boss.max_hp)
	shake(10.0, 0.8)


func _update_phase_text() -> void:
	var ph := DB.phase_at(stage_idx, elapsed)
	var txt := String(ph.get("phase", ""))
	if txt != "" and txt != _last_phase_text:
		_last_phase_text = txt
		_wave_text(txt)


func _wave_text(t: String) -> void:
	Bus.wave_phase.emit(t)


func wave_text_signal(t: String) -> void:
	Bus.wave_phase.emit(t)


func hazard_layer() -> Node2D:
	return _hazard_layer


# ---------------------------------------------------------------- 每局随机修正
func mod_total(key: String) -> float:
	return float(_mod_total.get(key, 0.0))


func _roll_mods() -> void:
	run_mods.clear()
	_mod_total.clear()
	if OS.get_cmdline_user_args().has("--nomods"):
		return
	var pool: Array = DB.RUN_MODS.duplicate()
	for i in range(pool.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var n := 1
	if stage_idx >= 1:
		n = 2
	if stage_idx >= 1 and _rng.randf() < 0.45:
		n = 3
	for i in mini(n, pool.size()):
		run_mods.append(pool[i])
	for m in run_mods:
		for k in m.keys():
			var ks := String(k)
			if ks == "id" or ks == "name" or ks == "desc":
				continue
			_mod_total[ks] = float(_mod_total.get(ks, 0.0)) + float(m[k])


func mod_text() -> String:
	var parts: Array = []
	for m in run_mods:
		parts.append(String(m["name"]))
	return " · ".join(parts)


# ---------------------------------------------------------------- 环境危害
func _update_hazards(delta: float) -> void:
	if _hazards_cfg.is_empty() or player == null:
		return
	for i in _hazards_cfg.size():
		var hc: Dictionary = _hazards_cfg[i]
		var start := float(hc.get("from", 30.0))
		if elapsed < start:
			continue
		var every := float(hc.get("every", 0.0))
		if every <= 0.0:
			if not _hazard_spawned.has(i):
				_hazard_spawned[i] = true
				_spawn_hazard(String(hc["kind"]))
			continue
		_hazard_t[i] -= delta * boss_hazard_mul * float(diff["hazard"])
		if _hazard_t[i] <= 0.0:
			_hazard_t[i] = every * _rng.randf_range(0.8, 1.25) / maxf(boss_hazard_mul, 0.01)
			_spawn_hazard(String(hc["kind"]))


func _spawn_hazard(kind: String) -> void:
	match kind:
		"laser_gate":
			var horiz := _rng.randf() < 0.5
			var inner := arena.inner_rect()
			if horiz:
				Hazard.spawn(_hazard_layer, kind,
					Vector2(0, _rng.randf_range(inner.position.y + 90.0, inner.end.y - 90.0)),
					{"horiz": 1.0})
			else:
				Hazard.spawn(_hazard_layer, kind,
					Vector2(_rng.randf_range(inner.position.x + 90.0, inner.end.x - 90.0), 0),
					{"horiz": 0.0})
		"storm_zone", "lava_vent":
			var a := _rng.randf() * TAU
			var p: Vector2 = player.global_position + Vector2(cos(a), sin(a)) * _rng.randf_range(80.0, 250.0)
			p = arena.resolve(p, 44.0)
			Hazard.spawn(_hazard_layer, kind, p, {})
		"laser_arm":
			Hazard.spawn(_hazard_layer, kind, arena.arena_size * 0.5,
				{"dir": 1.0 if _rng.randf() < 0.6 else -1.0, "angle": _rng.randf() * TAU})


# ---------------------------------------------------------------- 局内事件
func _update_events(delta: float) -> void:
	if finished or elapsed < 26.0:
		return
	_event_t -= delta
	if _event_t > 0.0:
		return
	_event_t = _rng.randf_range(48.0, 72.0)
	_do_event()


func _pick_kind() -> String:
	var ph := DB.phase_at(stage_idx, elapsed)
	var pool: Array = ph["pool"]
	return String(pool[_rng.randi_range(0, pool.size() - 1)])


func _do_event() -> void:
	var ev: Dictionary = DB.EVENTS[_rng.randi_range(0, DB.EVENTS.size() - 1)]
	var pl := player
	match String(ev["id"]):
		"airdrop":
			for i in 3:
				var a := TAU * float(i) / 3.0
				var p: Vector2 = pl.global_position + Vector2(cos(a), sin(a)) * 48.0
				p = arena.resolve(p, 12.0)
				Pickup.spawn(pickup_layer, "hp", 1, p)
			var pc: Vector2 = arena.resolve(pl.global_position + Vector2(0, 62), 14.0)
			Pickup.spawn(pickup_layer, "chest", 1, pc)
			Fx.spawn(fx_layer, "vfx_levelup", pl.global_position, 1.0, 13.0)
			Audio.play("sfx_chest", 1.0, 0.0, 0.7)
		"elite_squad":
			for i in 6:
				var a2 := TAU * float(i) / 6.0
				var p2: Vector2 = pl.global_position + Vector2(cos(a2), sin(a2)) * _rng.randf_range(230.0, 360.0)
				p2 = arena.resolve(p2, 16.0)
				var eid := String(DB.ELITES[_rng.randi_range(0, DB.ELITES.size() - 1)]["id"])
				_spawn_at(_pick_kind(), eid, p2, true)
			Audio.play("sfx_elite_spawn", 1.0, 0.0, 0.8)
		"bounty":
			var cand: Array = []
			for e in enemies:
				if is_instance_valid(e) and not e.dead and not e.is_boss:
					cand.append(e)
			var target = null
			if cand.is_empty():
				target = _spawn_at("tank", "rage", _spawn_pos(), true)
			else:
				target = cand[_rng.randi_range(0, cand.size() - 1)]
			if target != null and is_instance_valid(target):
				target.set_bounty(true)
				bounty_target = target
		"calm":
			calm_t = 10.0
		"surge":
			for i in 10:
				_spawn_at(_pick_kind(), "", _spawn_pos(), true)
			Audio.play("sfx_elite_spawn", 0.9, 0.0, 0.7)
	_wave_text("%s：%s" % [ev["name"], ev["desc"]])
	Audio.play("sfx_warn", 1.0, 0.02, 0.55)


# ---------------------------------------------------------------- 动态难度
func _update_director(delta: float) -> void:
	var dps := player.combat_scale()
	var expected := 20.0 + elapsed * 0.30
	var err := (expected - dps) / maxf(expected, 1.0)
	_dda = clampf(_dda + err * delta * 0.12, -0.35, 0.40)
	# 血量告急时明显降低压力
	var hp_ratio := player.hp / maxf(1.0, player.max_hp)
	if hp_ratio < 0.35:
		_dda = maxf(_dda - delta * 0.35, -0.35)


# ---------------------------------------------------------------- 掉落拾取
func _collect_pickups(delta: float) -> void:
	if player == null or player.dead:
		return
	_check_mercy()
	var pr := player.pickup_radius()
	for p in pickup_layer.get_children():
		if not is_instance_valid(p):
			continue
		if p.kind == "chest":
			if p.global_position.distance_to(player.global_position) < 22.0:
				_open_chest(p)
			continue
		if p.global_position.distance_to(player.global_position) < Player.RADIUS + 8.0:
			_apply_pickup(p)
			p.queue_free()
	_update_director(delta)


## 保底回血：本局第一次跌破 25% 生命时，必定在附近掉一个医疗包。
## 避免"被慢慢耗死、无计可施"的挫败感。
func _check_mercy() -> void:
	if _mercy_used or finished:
		return
	if player.hp > player.max_hp * 0.25:
		return
	_mercy_used = true
	for i in 3:
		var a := TAU * float(i) / 3.0 + _rng.randf()
		var p: Vector2 = player.global_position + Vector2(cos(a), sin(a)) * 46.0
		p = arena.resolve(p, 12.0)
		Pickup.spawn(pickup_layer, "hp", 1, p)
	_wave_text("生命危急 - 紧急医疗包已投放")
	Audio.play("sfx_pickup_hp", 0.85, 0.0, 0.8)


func _apply_pickup(p) -> void:
	match p.kind:
		"xp":
			player.add_xp(p.value)
			Audio.play("sfx_pickup_xp", 1.0 + _rng.randf_range(-0.1, 0.18), 0.05, 0.35)
		"gear":
			gears_earned += p.value
			Audio.play("sfx_pickup_gear", 1.0, 0.08, 0.4)
		"shield":
			player.add_shield(60.0, 0.0)
			Audio.play("sfx_pickup_hp", 0.9, 0.05, 0.8)
			_float_text("护盾 +60", player.global_position + Vector2(0, -18), Color("6ec8ff"), 11, false)
		"pulse":
			shockwave(player.global_position, 260.0, 60.0, 480.0)
			clear_enemy_bullets(player.global_position, 99999.0)
			_float_text("脉冲爆发！", player.global_position + Vector2(0, -22), Color("a25eff"), 12, false)
		"timechip":
			slow_all_enemies(0.5, 5.0)
			Audio.play("sfx_elite_spawn", 1.2, 0.0, 0.7)
			_float_text("时间迟滞", player.global_position + Vector2(0, -18), Color("34f0ff"), 11, false)
		"rage":
			player.rage_t = 8.0
			Audio.play("sfx_evolve", 1.3, 0.0, 0.7)
			_float_text("狂暴！", player.global_position + Vector2(0, -18), Color("ff4c3a"), 12, false)
		"hp":
			# 固定 22 点在后期（150+ 最大生命）几乎无感，改成按最大生命百分比
			var amount: float = maxf(22.0, player.max_hp * 0.12)
			player.heal(amount)
			Audio.play("sfx_pickup_hp", 1.0, 0.05, 0.6)
			_float_text("+%d" % int(round(amount)), player.global_position + Vector2(0, -16),
				Color("58f08e"), 11, false)


func _open_chest(p) -> void:
	Audio.play("sfx_chest", 1.0, 0.0, 0.8)
	shake(5.0, 0.3)
	Fx.spawn(fx_layer, "vfx_levelup", p.global_position, 1.0, 16.0)
	player.heal(player.max_hp * 0.25)
	var g := int(round(_rng.randf_range(18.0, 34.0) * player.gear_mul()))
	gears_earned += g
	_float_text("+%d 齿轮" % g, p.global_position + Vector2(0, -20), Color("ffe460"), 11, false)
	p.queue_free()
	pending_levels = 0
	Bus.level_up.emit(roll_choices(4))


# ---------------------------------------------------------------- 升级选项
func roll_choices(count: int = 3) -> Array:
	var pool: Array = []
	var evo: Array = []
	for wp in player.weapons:
		var id: String = wp["id"]
		var lv: int = int(wp["lv"])
		var d: Dictionary = DB.weapon(id)
		if not bool(wp.get("evolved", false)) and lv >= 5 				and player.p_lv(String(d["evo_with"])) >= 3:
			evo.append({"type": "evolve", "id": id, "weight": 100.0})
		elif lv < 5:
			pool.append({"type": "weapon_up", "id": id, "weight": 10.0})
	for d in DB.WEAPONS:
		var wid := String(d["id"])
		if player.weapons.size() < DB.MAX_WEAPONS and not _has_weapon(wid) 				and DB.weapon_ok(wid, stage_idx):
			pool.append({"type": "weapon_new", "id": wid, "weight": 9.0})
	for d in DB.PASSIVES:
		var pid := String(d["id"])
		if player.p_lv(pid) < 5 and DB.passive_ok(pid, stage_idx):
			pool.append({"type": "passive", "id": pid, "weight": 8.0 - player.p_lv(pid)})
	# 主动技能：槽位没满时**每次只抽 1 个候选**参与竞争。
	# 之前把 4 个技能各自设成高权重，结果挤占了武器/被动的选项，
	# 玩家会变成"一堆技能但没有武器"。
	if player.skills.size() < DB.MAX_SKILLS:
		var avail: Array = []
		for sk in DB.SKILLS:
			var sid := String(sk["id"])
			if not player.has_skill(sid):
				avail.append(sid)
		if not avail.is_empty():
			var spick := String(avail[_rng.randi_range(0, avail.size() - 1)])
			pool.append({"type": "skill", "id": spick,
				"weight": 30.0 if player.level <= 3 else 13.0})

	var chosen: Array = []
	if not evo.is_empty():
		chosen.append(evo[_rng.randi_range(0, evo.size() - 1)])
	# 保底：连续拿武器类
	var picks := count - chosen.size()
	var tries := 0
	while chosen.size() < count and tries < 200:
		tries += 1
		if pool.is_empty():
			break
		var total := 0.0
		for o in pool:
			total += float(o["weight"])
		var r := _rng.randf() * total
		var acc := 0.0
		var idx := 0
		for i in pool.size():
			acc += float(pool[i]["weight"])
			if r <= acc:
				idx = i
				break
		var pick: Dictionary = pool[idx]
		pool.remove_at(idx)
		chosen.append(pick)
	if chosen.is_empty():
		chosen.append({"type": "bonus", "id": "supply"})
	return chosen


func _has_weapon(id: String) -> bool:
	for wp in player.weapons:
		if wp["id"] == id:
			return true
	return false


func apply_choice(c: Dictionary) -> void:
	var t := String(c["type"])
	var id := String(c["id"])
	match t:
		"skill":
			player.add_skill(id)
			_wave_text("习得技能：%s" % DB.skill(id)["name"])
			Audio.play("sfx_evolve", 1.0, 0.0, 0.9)
			Audio.duck(0.35, 0.6)
			return
		"bonus":
			player.heal(player.max_hp * 0.35)
			var bg := 20 + int(player.gear_mul() * 10.0)
			gears_earned += bg
			_wave_text("补给：+35%% 生命，+%d 齿轮" % bg)
			Audio.play("sfx_pickup_hp", 1.0, 0.0, 0.8)
			return
		"weapon_new":
			player.add_weapon(id)
		"weapon_up":
			player.upgrade_weapon(id)
		"passive":
			player.add_passive(id)
		"evolve":
			player.evolve(id)
			Audio.play("sfx_evolve", 1.0, 0.0, 1.0)
			shake(6.0, 0.4)
			var d: Dictionary = DB.weapon(id)
			_wave_text("%s 进化：%s！" % [d["name"], d["evo_name"]])
			return
	Audio.play("sfx_levelup", 1.0, 0.05, 0.7)
	Audio.duck(0.30, 0.5)
	Bus.upgrade_taken.emit(id)


func take_levelup() -> void:
	pending_levels = maxi(0, pending_levels - 1)
	if pending_levels > 0:
		Bus.level_up.emit(roll_choices())


func add_levelup() -> void:
	pending_levels += 1
	if pending_levels == 1:
		Bus.level_up.emit(roll_choices())


# ---------------------------------------------------------------- 结束
func _update_clear_state(delta: float) -> void:
	if finished and won:
		_clear_t -= delta


func finish(win: bool) -> void:
	if finished:
		return
	finished = true
	won = win
	if win and not endless:
		Save.unlock_stage(stage_idx + 1)
	var entry := {
		"time": elapsed, "kills": kills, "gears": gears_earned,
		"level": player.level, "score": kills * 10 + int(gears_earned) + int(elapsed),
		"win": win,
	}
	Save.record_best(-1 if endless else stage_idx, entry)
	# 通关/阵亡都要把本局齿轮结算进永久存档（之前漏了，导致工坊永远是 0 齿轮）
	if gears_earned > 0:
		Save.add_gears(gears_earned)
	Save.data["stats"]["kills"] = int(Save.data["stats"]["kills"]) + kills
	Save.data["stats"]["runs"] = int(Save.data["stats"]["runs"]) + 1
	if win and not endless:
		Save.data["stats"]["bosses"] = int(Save.data["stats"]["bosses"]) + 1
	Save.save_game()
	Game.last_result = entry
	Bus.run_finished.emit(entry)


func _prune() -> void:
	if enemies.size() > 0:
		enemies = enemies.filter(func(e): return is_instance_valid(e) and not e.dead)
