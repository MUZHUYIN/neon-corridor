class_name Player
extends Node2D


class GroundRing:
	extends Node2D

	func _draw() -> void:
		draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 36, Color(0.0, 0.0, 0.0, 0.45), 4.0, true)
		draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 36, Color(0.30, 0.95, 1.0, 0.75), 1.5, true)
		draw_arc(Vector2.ZERO, 16.0, PI * 0.15, PI * 0.85, 18, Color(0.30, 0.95, 1.0, 0.28), 1.0, true)
## 玩家：WASD 移动 / 鼠标瞄准 / 自动开火 / 冲刺无敌 / 升级成长。

const RADIUS := 10.0

var hp := 100.0
var max_hp := 100.0
var level := 1
var xp := 0
var xp_need := 5
var weapons: Array = []
var passives: Dictionary = {}
var dead := false
var aim := Vector2.RIGHT
var iframe := 0.0
var hit_flash := 0.0
var dash_t := 0.0
var dash_cd := 0.0
var dash_dir := Vector2.RIGHT
var revives := 0
var kills := 0
var anim: AnimatedSprite2D
var gun: Sprite2D
var _vel := Vector2.ZERO
var _bob := 0.0
var _muzzle := 0.0
var _recoil := 0.0
var _rng := RandomNumberGenerator.new()
var bot := false
var bot_dir := Vector2.ZERO
var slow_v := 1.0
var slow_t := 0.0
# ---- 主动技能与护盾 ----
var skills: Array = []          # [{id, cd_left}]
var shield_hp := 0.0
var shield_t := 0.0             # >0 会倒计时归零；=0 表示破盾前永久
var phase_t := 0.0
var rage_t := 0.0


func _ready() -> void:
	z_index = 12
	_rng.randomize()
	var ring := GroundRing.new()
	ring.z_index = -2
	add_child(ring)
	anim = AnimatedSprite2D.new()
	anim.sprite_frames = Art.frames("player", 7.0, true)
	anim.animation = "anim"
	anim.play("anim")
	add_child(anim)
	gun = Sprite2D.new()
	gun.texture = Art.tex("gun", 1)
	gun.offset = Vector2(-1, 0)
	gun.position = Vector2(3, 0)
	gun.z_index = 1
	add_child(gun)
	recompute(true)


func reset() -> void:
	weapons.clear()
	passives.clear()
	level = 1
	xp = 0
	xp_need = 5
	dead = false
	iframe = 1.0
	revives = Game.workshop_bonus()["revives"]
	skills.clear()
	shield_hp = 0.0
	shield_t = 0.0
	phase_t = 0.0
	rage_t = 0.0
	# 开局技能：按难度决定（困难自带保命技，简单/普通靠升级获得）
	var d: Dictionary = DB.difficulty(int(Save.setting("difficulty", 1)))
	var si := int(DB.SKILL_START_DIFFICULTY.get(String(d["id"]), -1))
	if si >= 0 and si < DB.SKILLS.size():
		add_skill(String(DB.SKILLS[si]["id"]))
	recompute(true)
	hp = max_hp
	Bus.player_hp_changed.emit(hp, max_hp)
	Bus.level_changed.emit(level, xp, xp_need)


# ---------------------------------------------------------------- 数值
func p_lv(id: String) -> int:
	return int(passives.get(id, 0))


func _mod(key: String) -> float:
	var wd = Game.world
	if wd == null or not is_instance_valid(wd):
		return 0.0
	return float(wd.mod_total(key))


func apply_slow(v: float, dur: float) -> void:
	if v < slow_v or slow_t <= 0.0:
		slow_v = v
	slow_t = maxf(slow_t, dur)


func bonus() -> Dictionary:
	return Game.workshop_bonus()


func recompute(full: bool = false) -> void:
	var b := bonus()
	var old_max := max_hp
	max_hp = (DB.BASE_HP + float(b["hp_add"]) + p_lv("shield") * float(DB.passive("shield")["per"])) 		* (1.0 + _mod("hp"))
	if full or old_max <= 0.0:
		hp = max_hp
	else:
		hp = minf(max_hp, hp + maxf(0.0, max_hp - old_max))
	Bus.player_hp_changed.emit(hp, max_hp)


func speed_mul() -> float:
	var ph := 1.3 if phase_t > 0.0 else 1.0
	return (1.0 + p_lv("speed") * 0.08 + float(bonus()["speed"])) * ph


func dmg_mul() -> float:
	var rg := 1.5 if rage_t > 0.0 else 1.0
	return (1.0 + p_lv("damage") * 0.11 + float(bonus()["dmg"])) * (1.0 + _mod("dmg")) * rg


func fire_mul() -> float:
	var rg := 1.3 if rage_t > 0.0 else 1.0
	return (1.0 + p_lv("firerate") * float(DB.passive("firerate")["per"])) * rg


func crit_chance() -> float:
	return clampf(0.05 + p_lv("crit") * 0.06 + _mod("crit"), 0.0, 0.95)


func crit_mul() -> float:
	return 1.85 + p_lv("crit") * 0.10


func pickup_radius() -> float:
	return DB.PICKUP_RADIUS * (1.0 + p_lv("magnet") * 0.22 + float(bonus()["magnet"]))


func xp_mul() -> float:
	return 1.0 + p_lv("xp") * 0.10 + float(bonus()["xp"])


func gear_mul() -> float:
	return (1.0 + float(bonus()["luck"])) * (1.0 + _mod("gears"))


func armor_mul() -> float:
	var dm := 1.0
	var wd = Game.world
	if wd != null and is_instance_valid(wd):
		dm = float(wd.diff.get("taken", 1.0))
	var rg := 1.2 if rage_t > 0.0 else 1.0
	return (1.0 - float(bonus()["armor"])) * (1.0 + _mod("taken")) * dm * rg


func combat_scale() -> float:
	# 用于动态难度的战力评估
	var dps := 0.0
	for wp in weapons:
		var d: Dictionary = DB.weapon(wp["id"])
		var lv: int = wp["lv"]
		dps += DB.weapon_dmg(d, lv) * DB.weapon_count(d, lv) / maxf(0.05, DB.weapon_cd(d, lv))
	return dps * dmg_mul()


# ---------------------------------------------------------------- 每帧
func _physics_process(delta: float) -> void:
	if dead:
		return
	var world = Game.world
	if world == null:
		return
	dash_cd = maxf(0.0, dash_cd - delta)
	iframe = maxf(0.0, iframe - delta)
	hit_flash = maxf(0.0, hit_flash - delta)
	_muzzle = maxf(0.0, _muzzle - delta)
	_recoil = maxf(0.0, _recoil - delta * 30.0)

	# 移动
	var input := Vector2.ZERO
	if bot:
		input = bot_dir
	elif Game.state == Game.ST_PLAYING:
		input = Input.get_vector("mv_left", "mv_right", "mv_up", "mv_down")
	if input.length() > 1.0:
		input = input.normalized()
	if slow_t > 0.0:
		slow_t -= delta
		if slow_t <= 0.0:
			slow_v = 1.0
	if phase_t > 0.0:
		phase_t -= delta
	if rage_t > 0.0:
		rage_t -= delta
	if shield_t > 0.0:
		shield_t -= delta
		if shield_t <= 0.0:
			shield_hp = 0.0
			Bus.player_shield_changed.emit(0.0, 1.0)
	for s in skills:
		s["cd_left"] = maxf(0.0, float(s["cd_left"]) - delta)
	var slow_mul: float = slow_v if slow_t > 0.0 else 1.0
	if dash_t > 0.0:
		dash_t -= delta
		_vel = dash_dir * DB.DASH_SPEED * (0.55 + 0.45 * slow_mul)
		if _rng.randf() < 0.7:
			Fx.spawn(world.fx_layer, "vfx_trail", global_position + _rng.randf_range(-4, 4) * Vector2.RIGHT,
				1.0, 20.0, Color(1, 1, 1, 0.7))
	else:
		var target := input * DB.BASE_SPEED * speed_mul() * slow_mul
		_vel = _vel.lerp(target, clampf(14.0 * delta, 0.0, 1.0))
	global_position += _vel * delta
	global_position = world.arena.resolve(global_position, RADIUS)

	# 瞄准
	if bot:
		pass
	elif Game.state == Game.ST_PLAYING:
		var m := get_viewport().get_camera_2d().get_global_mouse_position() if get_viewport().get_camera_2d() != null else get_global_mouse_position()
		var d := m - global_position
		if d.length_squared() > 4.0:
			aim = d.normalized()
	var ga := aim.angle()
	gun.rotation = ga
	gun.position = Vector2(3, 0).rotated(ga) - Vector2(2, 0).rotated(ga) * (_recoil / 6.0)
	anim.rotation = 0.0
	anim.position = Vector2.ZERO
	# 冲刺时整体压低
	if hit_flash > 0.0:
		anim.modulate = Color(1.6, 1.6, 1.6)
	elif slow_mul < 0.999:
		anim.modulate = Color(0.72, 0.86, 1.35)
	else:
		anim.modulate = Color.WHITE

	# 回复
	var regen := p_lv("regen") * float(DB.passive("regen")["per"])
	if regen > 0.0 and hp < max_hp:
		hp = minf(max_hp, hp + regen * delta)
		Bus.player_hp_changed.emit(hp, max_hp)

	# 开火
	var want_fire := true
	if not bool(Save.setting("autofire", true)):
		want_fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if not want_fire:
		return
	for wp in weapons:
		wp["cd_left"] = float(wp["cd_left"]) - delta
		if wp["cd_left"] <= 0.0:
			_fire(wp, world)



func _fire(wp: Dictionary, world) -> void:
	var base: Dictionary = DB.weapon(wp["id"])
	var def := base
	if bool(wp.get("evolved", false)):
		def = base.duplicate(true)
		for k in base["evo"].keys():
			def[k] = base["evo"][k]
	var lv: int = int(wp["lv"])
	var dmg: float = float(def["dmg"]) * (1.0 + 0.30 * (lv - 1)) * dmg_mul()
	var cd: float = float(def["cd"]) * (1.0 - 0.055 * (lv - 1)) / fire_mul()
	wp["cd_left"] = maxf(0.06, cd)
	var count: int = int(def["count"])
	var spread: float = float(def["spread"])
	var spd: float = float(def["speed"])
	var is_crit := _rng.randf() < crit_chance() or bool(def.get("always_crit", false))
	if is_crit:
		dmg *= crit_mul()

	Audio.play(String(def["sfx"]), 1.0, 0.05, 0.55)
	_muzzle = 0.06
	_recoil = float(def.get("recoil", 1.0))
	var a0 := aim.angle()
	var muzzle: Vector2 = global_position + aim * 13.0

	# ---- 光束类武器：瞬时机检，不再发射弹丸 ----
	if bool(def.get("beam", false)):
		var bw: float = float(def.get("beam_width", 15.0))
		var blen: float = float(def.get("beam_len", 780.0))
		for i in count:
			var ba := a0
			if count > 1:
				ba += (float(i) - (count - 1) * 0.5) * spread
			var bdir := Vector2(cos(ba), sin(ba))
			var bstart: Vector2 = global_position + bdir * 13.0
			var bend: Vector2 = world.beam_endpoint(bstart, bdir, blen)
			Beam.spawn(world.bullet_layer, bstart, bend, Color("34f0ff"), bw,
				0.18 if not is_crit else 0.24)
			world.beam_damage(bstart, bend, bw * 0.5, dmg, is_crit, float(def.get("knock", 0.0)))
		world.shake(1.6 if count < 2 else 3.0, 0.09)
		return

	for i in count:
		var a := a0
		if count > 1:
			if bool(def.get("spread_fan", false)):
				a += (float(i) - (count - 1) * 0.5) * spread
			else:
				a += lerpf(-spread * 0.5, spread * 0.5, float(i) / maxf(1.0, count - 1.0))
		var dir := Vector2(cos(a), sin(a))
		muzzle = global_position + dir * 13.0
		var cfg := {
			"sprite": def["proj"], "dmg": dmg, "crit": is_crit,
			"pierce": int(def["pierce"]), "life": float(def["life"]),
			"speed": spd, "radius": 7.0, "knock": float(def.get("knock", 0.0)),
			"aoe": float(def.get("aoe", 0.0)), "homing": float(def.get("homing", 0.0)),
			"boomerang": bool(def.get("boomerang", false)), "from_player": true,
			"split_on_death": int(def.get("aoe_split", 0)), "weapon_id": wp["id"],
			"scale": 1.0,
		}
		var p := Projectile.spawn(world.bullet_layer, cfg)
		p.global_position = muzzle
		p.vel = dir * spd
		p.dir = dir
		if bool(def.get("orbit", false)):
			p.setup_orbit(global_position, 46.0, a, 2.6)
	# 每种武器用各自的枪口特效
	var mname := "vfx_muzzle_" + String(wp["id"])
	if not Art.has(mname):
		mname = "vfx_muzzle_pistol"
	var mscale: float = 1.25 if String(wp["id"]) == "shotgun" else 1.0
	Fx.spawn(world.fx_layer, mname, muzzle, mscale, 24.0, Color(1.35, 1.35, 1.35), null)
	if count >= 4:
		world.shake(2.0, 0.08)


# ---------------------------------------------------------------- 受伤/复活
func take_damage(amount: float, from: Vector2 = Vector2.ZERO) -> void:
	if dead or iframe > 0.0:
		return
	var real := amount * armor_mul()
	# 护盾优先吸收
	if shield_hp > 0.0:
		var used := minf(shield_hp, real)
		shield_hp -= used
		real -= used
		Bus.player_shield_changed.emit(shield_hp, 1.0)
		if real <= 0.0:
			iframe = 0.28
			var wd0 = Game.world
			if wd0 != null:
				Fx.spawn(wd0.fx_layer, "vfx_shock", global_position, 0.5, 22.0, Color(0.5, 0.9, 1.5))
				FloatText.spawn(wd0.text_layer, "护盾", global_position + Vector2(0, -16),
					Color("6ec8ff"), 10)
			Audio.play("sfx_hit_enemy", 0.8, 0.05, 0.6)
			return
	hp -= real
	iframe = 0.62
	hit_flash = 0.22
	Bus.player_hp_changed.emit(maxf(0.0, hp), max_hp)
	Bus.player_damaged.emit(real)
	var world = Game.world
	if world != null:
		world.shake(5.0, 0.25)
		Fx.spawn(world.fx_layer, "vfx_hit", global_position, 1.4, 20.0, Color(1.6, 0.8, 0.8))
		FloatText.spawn(world.text_layer, "-%d" % int(round(real)), global_position + Vector2(0, -14),
			Color("ff6a5a"), 10)
	Audio.play("sfx_hit_player", 1.0, 0.05, 0.9)
	Audio.duck(0.45, 0.7)
	if hp <= 0.0:
		if revives > 0:
			revives -= 1
			hp = max_hp * 0.6
			iframe = 2.4
			Bus.player_hp_changed.emit(hp, max_hp)
			if world != null:
				world.shake(9.0, 0.5)
				Fx.spawn(world.fx_layer, "vfx_levelup", global_position, 1.0, 18.0, Color("58f08e"))
				FloatText.spawn(world.text_layer, "备用机体启动！", global_position + Vector2(0, -22),
					Color("58f08e"), 12, Vector2(0, -18), 1.4)
			Audio.play("sfx_evolve", 1.0, 0.0, 0.9)
		else:
			die()


func heal(amount: float) -> void:
	if dead:
		return
	var before := hp
	hp = minf(max_hp, hp + amount)
	Bus.player_hp_changed.emit(hp, max_hp)
	if hp > before:
		Bus.player_healed.emit(hp - before)


func die() -> void:
	if dead:
		return
	dead = true
	var world = Game.world
	if world != null:
		Fx.spawn(world.fx_layer, "vfx_bigboom", global_position, 1.2, 16.0)
		world.shake(10.0, 0.7)
	Audio.play("sfx_death", 1.0, 0.0, 1.0)
	Bus.player_died.emit()


# ---------------------------------------------------------------- 冲刺
## 绝境冲刺：被围住时冲刺更远、无敌更久，作为最后的脱身手段
func try_dash() -> void:
	if dead or dash_cd > 0.0 or dash_t > 0.0:
		return
	var input := Input.get_vector("mv_left", "mv_right", "mv_up", "mv_down")
	dash_dir = input.normalized() if input.length() > 0.2 else aim
	var wd = Game.world
	var cornered := false
	if wd != null:
		cornered = wd.query_circle(global_position, 60.0).size() >= 8
	if cornered:
		dash_t = DB.DASH_TIME * 1.45
		iframe = maxf(iframe, DB.DASH_TIME * 1.45 + 0.22)
	else:
		dash_t = DB.DASH_TIME
		iframe = maxf(iframe, DB.DASH_TIME + 0.12)
	dash_cd = DB.DASH_CD
	Audio.play("sfx_dash", 1.0, 0.08, 0.6)
	var world = Game.world
	if world != null:
		Fx.spawn(world.fx_layer, "vfx_shock", global_position, 0.5, 24.0, Color(0.6, 1.4, 1.6))


# ---------------------------------------------------------------- 经验
func add_xp(n: int) -> void:
	if dead:
		return
	xp += int(round(n * xp_mul()))
	var leveled := false
	var gained := 0
	while xp >= xp_need:
		xp -= xp_need
		level += 1
		xp_need = int(round(5.0 + level * 3.6 + pow(level, 1.55)))
		leveled = true
		gained += 1
	Bus.level_changed.emit(level, xp, xp_need)
	if leveled and Game.world != null:
		for i in gained:
			Game.world.add_levelup()


# ---------------------------------------------------------------- 武器/被动
# ---------------------------------------------------------------- 技能 / 护盾
func has_skill(id: String) -> bool:
	for s in skills:
		if String(s["id"]) == id:
			return true
	return false


func add_skill(id: String) -> bool:
	if has_skill(id) or skills.size() >= DB.MAX_SKILLS:
		return false
	skills.append({"id": id, "cd_left": 0.0})
	return true


func add_shield(amount: float, duration: float) -> void:
	shield_hp = minf(120.0, shield_hp + amount)
	if duration > 0.0:
		shield_t = maxf(shield_t, duration)
	Bus.player_shield_changed.emit(shield_hp, 1.0)


func use_skill(idx: int) -> void:
	if dead or idx < 0 or idx >= skills.size():
		return
	var s: Dictionary = skills[idx]
	if float(s["cd_left"]) > 0.0:
		return
	var def := DB.skill(String(s["id"]))
	if def.is_empty():
		return
	s["cd_left"] = float(def["cd"])
	_activate(String(s["id"]), def)


func _activate(id: String, def: Dictionary) -> void:
	var wd = Game.world
	match id:
		"shockwave":
			iframe = maxf(iframe, float(def["iframe"]))
			if wd != null:
				wd.shockwave(global_position, float(def["radius"]), float(def["dmg"]), float(def["knock"]))
				wd.clear_enemy_bullets(global_position, 99999.0)
			Audio.play("sfx_explode_big", 1.0, 0.0, 0.9)
		"shieldfield":
			add_shield(float(def["amount"]), float(def["duration"]))
			if wd != null:
				Fx.spawn(wd.fx_layer, "vfx_shock", global_position, 1.1, 14.0, Color(0.5, 0.9, 1.5))
			Audio.play("sfx_pickup_hp", 0.8, 0.0, 0.9)
		"phase":
			phase_t = float(def["duration"])
			iframe = maxf(iframe, float(def["duration"]))
			if wd != null:
				Fx.spawn(wd.fx_layer, "vfx_levelup", global_position, 0.9, 16.0, Color(0.85, 0.6, 1.5))
			Audio.play("sfx_dash", 0.8, 0.0, 0.9)
		"slowfield":
			if wd != null:
				wd.slow_all_enemies(float(def["slow"]), float(def["duration"]))
				Fx.spawn(wd.fx_layer, "vfx_shock", global_position, 2.2, 12.0, Color(0.7, 0.7, 1.6))
			Audio.play("sfx_elite_spawn", 1.1, 0.0, 0.8)
	Audio.duck(0.30, 0.5)


func add_weapon(id: String) -> bool:
	for wp in weapons:
		if wp["id"] == id:
			return false
	if weapons.size() >= DB.MAX_WEAPONS:
		return false
	weapons.append({"id": id, "lv": 1, "cd_left": 0.0, "evolved": false})
	return true


func upgrade_weapon(id: String) -> void:
	for wp in weapons:
		if wp["id"] == id:
			wp["lv"] = mini(5, int(wp["lv"]) + 1)
			return


func add_passive(id: String) -> void:
	passives[id] = mini(5, p_lv(id) + 1)
	recompute()


func evolve(id: String) -> void:
	for wp in weapons:
		if wp["id"] == id:
			wp["evolved"] = true
			wp["lv"] = 5
			return
