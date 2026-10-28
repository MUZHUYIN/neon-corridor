class_name Enemy
extends Node2D
## 通用敌人：行为由数据表的 AI 字段决定，不为每种敌人写一个脚本。

var kind := "grunt"
var data: Dictionary = {}
var hp := 10.0
var max_hp := 10.0
var speed := 50.0
var dmg := 5.0
var radius := 10.0
var xp_value := 1
var gears := 1
var armor := 0.0
var elite := false
var elite_id := ""
var elite_name := ""
var is_boss := false
var dead := false
var flash := 0.0
var knock := Vector2.ZERO
var anim: AnimatedSprite2D
var eye: Sprite2D = null
var _shoot_t := 1.0
var _summon_t := 3.0
var _fuse := -1.0
var _contact_t := 0.0
var _rng := RandomNumberGenerator.new()
var _base_scale := 1.0
var shield := 0.0
var shield_max := 0.0
var shield_t := 0.0
var death_zone := false
var death_bomb := false
var bomb_armed := false
var bomb_t := 0.0
var can_teleport := false
var bounty := false
var slow_v := 1.0
var slow_t := 0.0
var shield_fx: Sprite2D = null
var bounty_fx: Sprite2D = null
var _tp_t := 4.0


static func spawn(parent: Node, kind_: String, elite_id_: String, pos: Vector2,
		hp_mult: float, speed_mult: float) -> Enemy:
	var e := Enemy.new()
	e.kind = kind_
	e.data = DB.enemy(kind_)
	e.elite_id = elite_id_
	e.elite = elite_id_ != ""
	var em := 1.0
	var sm := 1.0
	var dm := 1.0
	var xm := 1.0
	var sc := 1.0
	if e.elite:
		for m in DB.ELITES:
			if m["id"] == elite_id_:
				em = float(m["hp"]); sm = float(m["speed"]); dm = float(m["dmg"])
				xm = float(m["xp"]); sc = float(m["scale"]); e.elite_name = String(m["name"])
	e.max_hp = float(e.data["hp"]) * hp_mult * em
	e.hp = e.max_hp
	e.speed = float(e.data["speed"]) * speed_mult * sm
	e.dmg = float(e.data["dmg"]) * dm * (1.0 + 0.10 * maxf(0.0, speed_mult - 1.0))
	e.radius = float(e.data["r"]) * sc
	e.xp_value = int(round(float(e.data["xp"]) * xm))
	e.gears = int(e.data.get("gears", 1)) * (2 if e.elite else 1)
	e.armor = float(e.data.get("armor", 0.0))
	e._base_scale = sc
	e.global_position = pos
	e.z_index = 10
	parent.add_child(e)
	return e


func _ready() -> void:
	_rng.randomize()
	anim = AnimatedSprite2D.new()
	anim.sprite_frames = Art.frames(String(data["sprite"]), 8.0, true)
	anim.animation = "anim"
	anim.play("anim")
	add_child(anim)
	if bool(data.get("eye", false)) or elite:
		eye = Sprite2D.new()
		eye.texture = Art.tex("eye", 0)
		eye.position = Vector2(0, -1)
		add_child(eye)
	if elite:
		anim.scale = Vector2(_base_scale, _base_scale)
		anim.modulate = Color(1.35, 1.15, 1.5)
		var halo := Fx.spawn(self, "vfx_sparkle", Vector2.ZERO, _base_scale * 1.5, 6.0, Color(1.5, 1.0, 1.6))
		halo.z_index = -1
	_apply()
	var wd_cap = Game.world
	if wd_cap != null:
		# 难度：敌人伤害倍率
		dmg *= float(wd_cap.diff.get("edmg", 1.0))
		# 硬上限：任何敌人都不能比玩家快，否则无从躲避
		if wd_cap.player != null and is_instance_valid(wd_cap.player):
			var cap: float = DB.BASE_SPEED * wd_cap.player.speed_mul() * 0.80
			speed = minf(speed, cap)
	# 关卡专属词缀
	var wd = Game.world
	var fl: Dictionary = wd.flags if wd != null else {}
	shield_max = max_hp * 0.35 if bool(fl.get("shielded", false)) else 0.0
	shield = shield_max
	death_zone = bool(fl.get("corrosive_death", false))
	death_bomb = bool(fl.get("death_explode", false))
	can_teleport = bool(fl.get("teleport", false)) and not is_boss
	if can_teleport:
		_tp_t = _rng.randf_range(7.0, 11.0)
	# 护盾环用贴图精灵，避免每帧重绘画布（190 个敌人时这是致命的性能问题）
	if shield_max > 0.0:
		shield_fx = Sprite2D.new()
		shield_fx.texture = Art.tex("vfx_shock", 3)
		shield_fx.modulate = Color(0.45, 0.9, 1.15, 0.85)
		shield_fx.z_index = 1
		var s0 := (radius + 6.0) / 25.0
		shield_fx.scale = Vector2(s0, s0)
		add_child(shield_fx)


func _apply() -> void:
	if anim:
		anim.scale = Vector2(_base_scale, _base_scale)


func world():
	return Game.world


func player():
	var wd = Game.world
	if wd == null:
		return null
	return wd.player


func _physics_process(delta: float) -> void:
	if dead:
		return
	var wd = Game.world
	if wd == null:
		return
	var pl = wd.player
	flash = maxf(0.0, flash - delta)
	if anim != null:
		if flash > 0.0:
			anim.modulate = Color(2.2, 2.2, 2.2)
		elif slow_t > 0.0:
			anim.modulate = Color(0.65, 0.85, 1.45)
		elif elite:
			anim.modulate = Color(1.35, 1.15, 1.5)
		else:
			anim.modulate = Color.WHITE
	if knock.length_squared() > 1.0:
		global_position += knock * delta
		knock = knock.lerp(Vector2.ZERO, clampf(9.0 * delta, 0.0, 1.0))
	if bounty_fx != null:
		var bp := 1.0 + 0.16 * sin(Time.get_ticks_msec() / 190.0)
		bounty_fx.scale = Vector2(bp, bp) * ((radius + 12.0) / 20.0)
	if pl == null or pl.dead:
		return
	var to_p: Vector2 = pl.global_position - global_position
	var dist := to_p.length()
	var dir := to_p / maxf(dist, 0.001)
	var slow_mul: float = slow_v if slow_t > 0.0 else 1.0
	if slow_t > 0.0:
		slow_t -= delta
		if slow_t <= 0.0:
			slow_v = 1.0
	var sp: float = speed * slow_mul
	# 流场寻路：开阔处流场方向≈直线（走 dir），被墙隔开时自动改走绕行通路。
	# 查表是 O(1)，190 个敌人也只算一次 BFS。
	var mv: Vector2 = dir
	if wd.arena != null and wd.arena.flow_enabled:
		var f: Vector2 = wd.arena.flow_at(global_position)
		# 方向分歧超过约 20° 才采用流场，避免粗网格的细微抖动
		if f != Vector2.ZERO and f.dot(dir) < 0.94:
			mv = (f * 0.86 + dir * 0.14).normalized()
	if eye != null:
		eye.position = dir * (radius * 0.45)
	# 护盾再生
	if shield_max > 0.0 and shield_fx != null:
		shield_t = maxf(0.0, shield_t - delta)
		if shield_t <= 0.0 and shield < shield_max:
			shield = minf(shield_max, shield + shield_max * 0.30 * delta)
		var k := clampf(shield / maxf(shield_max, 0.001), 0.0, 1.0)
		shield_fx.visible = k > 0.01
		shield_fx.modulate.a = 0.30 + 0.60 * k
	# 残血自爆
	if bomb_armed:
		bomb_t -= delta
		anim.modulate = Color(2.6, 1.0, 0.5) if fmod(bomb_t, 0.14) < 0.07 else Color(1.6, 0.8, 0.4)
		if bomb_t <= 0.0:
			wd.explode(global_position, 58.0, dmg * 1.1, false)
			die(false)
			return
	# 传送
	if can_teleport:
		_tp_t -= delta
		if _tp_t <= 0.0:
			_tp_t = _rng.randf_range(8.0, 13.0)
			_teleport(wd, pl)
	match int(data["ai"]):
		DB.AI.CHASE:
			global_position += mv * sp * delta
		DB.AI.RANGED:
			var want := float(data.get("shoot_range", 200.0)) * 0.7
			if dist > want:
				global_position += mv * sp * delta
			elif dist < want * 0.6:
				global_position -= dir * sp * 0.7 * delta
			_shoot_t -= delta
			if _shoot_t <= 0.0 and dist < float(data.get("shoot_range", 200.0)) * 1.2:
				_shoot_t = float(data.get("shoot_cd", 2.0)) * _rng.randf_range(0.85, 1.2)
				wd.enemy_shoot(global_position, dir, data, self)
		DB.AI.EXPLODE:
			if _fuse < 0.0:
				global_position += mv * sp * delta
				if dist < radius + 22.0:
					_fuse = 0.75
					Audio.play("sfx_warn", 1.0, 0.05, 0.5)
			else:
				_fuse -= delta
				anim.modulate = Color(2.4, 1.2, 0.8) if fmod(_fuse, 0.16) < 0.08 else Color(1.4, 1.0, 0.6)
				if _fuse <= 0.0:
					wd.explode(global_position, float(data.get("boom_r", 44.0)), dmg, false)
					die(false)
					return
		DB.AI.SUMMON:
			var keep := float(data.get("keep_dist", 180.0))
			if dist > keep:
				global_position += mv * sp * delta
			elif dist < keep * 0.6:
				global_position -= dir * sp * 0.8 * delta
			_summon_t -= delta
			if _summon_t <= 0.0:
				_summon_t = float(data.get("summon_cd", 5.5))
				wd.summon_around(global_position, String(data.get("summon_kind", "grunt")),
					int(data.get("summon_n", 3)))
		_:
			global_position += mv * sp * delta

	global_position = wd.arena.resolve(global_position, radius)

	# 接触伤害
	_contact_t = maxf(0.0, _contact_t - delta)
	if dist < radius + Player.RADIUS and _contact_t <= 0.0 and _fuse < 0.0:
		_contact_t = 0.5
		pl.take_damage(dmg, global_position)


func apply_slow(v: float, dur: float) -> void:
	if v < slow_v or slow_t <= 0.0:
		slow_v = v
	slow_t = maxf(slow_t, dur)


func set_bounty(on: bool) -> void:
	bounty = on
	if on and bounty_fx == null:
		bounty_fx = Sprite2D.new()
		bounty_fx.texture = Art.tex("vfx_spawn", 5)
		bounty_fx.modulate = Color(1.4, 1.15, 0.3, 0.9)
		bounty_fx.z_index = 1
		var s0 := (radius + 12.0) / 20.0
		bounty_fx.scale = Vector2(s0, s0)
		add_child(bounty_fx)
	elif not on and bounty_fx != null:
		bounty_fx.queue_free()
		bounty_fx = null


func _teleport(wd, pl) -> void:
	var a := _rng.randf() * TAU
	var p: Vector2 = pl.global_position + Vector2(cos(a), sin(a)) * _rng.randf_range(230.0, 340.0)
	p = wd.arena.resolve(p, radius)
	Fx.spawn(wd.fx_layer, "vfx_spawn", global_position, 0.8, 18.0, Color(0.8, 0.6, 1.4))
	global_position = p
	Fx.spawn(wd.fx_layer, "vfx_spawn", p, 0.8, 18.0, Color(0.8, 0.6, 1.4))
	Audio.play("sfx_dash", 1.4, 0.05, 0.18)


func aim_at_player() -> Vector2:
	var pl = player()
	if pl == null:
		return Vector2.RIGHT
	return (pl.global_position - global_position).normalized()


func take_damage(amount: float, crit: bool, from_pos: Vector2, knock_amt: float) -> void:
	if dead:
		return
	var real := maxf(1.0, amount - armor)
	if shield > 0.0:
		var used := minf(shield, real)
		shield -= used
		real -= used
		shield_t = 5.0
		flash = 0.10
		if shield <= 0.0:
			Audio.play("sfx_hit_enemy", 1.4, 0.05, 0.4)
			var wd0 = Game.world
			if wd0 != null:
				Fx.spawn(wd0.fx_layer, "vfx_shock", global_position, 0.35, 20.0, Color(0.6, 0.9, 1.4))
		if real <= 0.0:
			return
	hp -= real
	flash = 0.10
	if knock_amt > 0.0:
		var dir := (global_position - from_pos).normalized()
		knock += dir * knock_amt
	var wd = Game.world
	if wd != null:
		wd.on_enemy_damaged(self, real, crit, from_pos)
	if death_bomb and not bomb_armed and hp > 0.0 and hp < max_hp * 0.30:
		bomb_armed = true
		bomb_t = 0.9
		Audio.play("sfx_warn", 1.15, 0.03, 0.55)
	if hp <= 0.0:
		die(false)


func die(no_drop: bool) -> void:
	if dead:
		return
	dead = true
	var wd = Game.world
	var pos := global_position
	if wd != null:
		wd.on_enemy_died(self, no_drop)
	queue_free()
