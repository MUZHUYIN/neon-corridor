class_name Boss
extends Enemy
## Boss：按 patterns 轮转攻击，50% 血量进入狂暴。

var patterns: Array = []
var pi := 0
var atk_gap := 2.4
var enraged := false
var busy := false
var _ult_idx := 0
var charge_dir := Vector2.ZERO
var boss_name := ""


static func spawn_boss(parent: Node, idx: int, pos: Vector2, hp_mult: float) -> Boss:
	var b := Boss.new()
	var d: Dictionary = DB.BOSSES[clampi(idx, 0, DB.BOSSES.size() - 1)]
	b.kind = String(d["id"])
	b.data = d
	b.is_boss = true
	b.boss_name = String(d["name"])
	b.max_hp = float(d["hp"]) * hp_mult
	b.hp = b.max_hp
	b.speed = float(d["speed"])
	b.dmg = float(d["dmg"])
	b.radius = float(d["r"])
	b.xp_value = 120
	b.gears = int(d["gears"])
	b.patterns = d["patterns"].duplicate()
	b.global_position = pos
	b.z_index = 11
	parent.add_child(b)
	return b


func _ready() -> void:
	_rng.randomize()
	anim = AnimatedSprite2D.new()
	anim.sprite_frames = Art.frames(String(data["sprite"]), 6.0, true)
	anim.animation = "anim"
	anim.play("anim")
	add_child(anim)
	eye = Sprite2D.new()
	eye.texture = Art.tex("eye", 0)
	eye.z_index = 1
	add_child(eye)
	var halo := Fx.spawn(self, "vfx_spawn", Vector2.ZERO, 2.4, 12.0, Color(1.6, 0.8, 1.2))
	halo.z_index = -1
	Audio.play("sfx_boss_roar", 1.0, 0.0, 1.0)
	Audio.duck(0.55, 1.2)
	_attack_loop()


func _physics_process(delta: float) -> void:
	if dead:
		return
	var wd = Game.world
	if wd == null:
		return
	var pl = wd.player
	flash = maxf(0.0, flash - delta)
	if anim != null:
		anim.modulate = Color(2.4, 2.4, 2.4) if flash > 0.0 else (Color(1.6, 0.9, 0.9) if enraged else Color.WHITE)
	if knock.length_squared() > 1.0:
		global_position += knock * delta
		knock = knock.lerp(Vector2.ZERO, clampf(11.0 * delta, 0.0, 1.0))
	if pl == null or pl.dead:
		return
	var to_p: Vector2 = pl.global_position - global_position
	var dist := to_p.length()
	var dir := to_p / maxf(dist, 0.001)
	if eye != null:
		eye.position = dir * (radius * 0.42)
	if charge_dir != Vector2.ZERO:
		global_position += charge_dir * speed * 5.2 * delta
	else:
		if dist > 150.0:
			global_position += dir * speed * delta
		elif dist < 90.0:
			global_position -= dir * speed * 0.8 * delta
	global_position = wd.arena.resolve(global_position, radius)
	if dist < radius + Player.RADIUS:
		pl.take_damage(dmg * delta * 1.6, global_position)


func _ultimate(n: int) -> void:
	var wd = Game.world
	if wd == null or dead:
		return
	Audio.duck(0.5, 1.0)
	Audio.play("sfx_boss_roar", 1.2, 0.0, 1.0)
	wd.shake(9.0, 0.5)
	_wave_text_ult(n)
	match int(DB.stage(wd.stage_idx)["theme"]):
		1:
			# 数据荒原：传送 + 环形弹幕 + 召唤
			var a := _rng.randf() * TAU
			global_position = wd.arena.resolve(
				wd.player.global_position + Vector2(cos(a), sin(a)) * 260.0, radius)
			Fx.spawn(wd.fx_layer, "vfx_shock", global_position, 1.8, 16.0, Color(0.9, 0.6, 1.5))
			for i in 20:
				var ang := TAU * float(i) / 20.0
				wd.enemy_bullet(global_position, Vector2(cos(ang), sin(ang)), 210.0, dmg * 0.55, "eproj_ball")
			wd.summon_around(global_position, "flyer", 4)
		2:
			# 熔核暴君：双重激光臂 + 大范围喷发
			Hazard.spawn(wd.hazard_layer(), "laser_arm", wd.arena.arena_size * 0.5,
				{"dir": -1.0, "angle": _rng.randf() * TAU})
			for i in 5:
				var aa := _rng.randf() * TAU
				var p: Vector2 = wd.player.global_position + Vector2(cos(aa), sin(aa)) * _rng.randf_range(60.0, 240.0)
				Hazard.spawn(wd.hazard_layer(), "lava_vent", wd.arena.resolve(p, 44.0), {})
		_:
			# 霓虹走廊：横向激光网 + 弹幕环
			for i in 2:
				var hor := 0.0 if i == 0 else 1.0
				Hazard.spawn(wd.hazard_layer(), "laser_gate",
					Vector2(0, wd.player.global_position.y) if i == 1 else Vector2(wd.player.global_position.x, 0),
					{"horiz": hor})
			for i in 22:
				var ang2 := TAU * float(i) / 22.0 + 0.2
				wd.enemy_bullet(global_position, Vector2(cos(ang2), sin(ang2)), 230.0, dmg * 0.6, "eproj_shard")


func _wave_text_ult(n: int) -> void:
	var wd = Game.world
	if wd != null:
		wd.wave_text_signal("%s 释放大招！（第 %d 阶段）" % [boss_name, n + 1])


func _attack_loop() -> void:
	await get_tree().create_timer(1.6).timeout
	while is_instance_valid(self) and not dead:
		if Game.state == Game.ST_PLAYING and not busy:
			var pat := String(patterns[pi % patterns.size()])
			pi += 1
			await _pattern(pat)
		await get_tree().create_timer(atk_gap * (0.62 if enraged else 1.0)).timeout


func _pattern(pat: String) -> void:
	var wd = Game.world
	if wd == null:
		return
	var pl = wd.player
	if pl == null:
		return
	busy = true
	match pat:
		"radial":
			for wave in 2:
				if not is_instance_valid(self) or dead:
					break
				var n := 14
				var off := _rng.randf() * TAU
				for i in n:
					if dead:
						break
					wd.enemy_bullet(global_position, Vector2(cos(off + i * TAU / n), sin(off + i * TAU / n)),
						190.0, dmg * 0.6, "eproj_shard")
				Audio.play("sfx_shoot_shotgun", 0.85, 0.05, 0.7)
				await get_tree().create_timer(0.42).timeout
		"spiral":
			var off2 := _rng.randf() * TAU
			for k in 26:
				if not is_instance_valid(self) or dead:
					break
				off2 += 0.46
				for s in 2:
					var a := off2 + s * PI
					wd.enemy_bullet(global_position, Vector2(cos(a), sin(a)), 210.0, dmg * 0.5, "eproj_ball")
				if k % 6 == 0:
					Audio.play("sfx_shoot_laser", 0.8, 0.03, 0.5)
				await get_tree().create_timer(0.055).timeout
		"summon":
			wd.summon_around(global_position, "grunt", 4)
			wd.summon_around(global_position, "darter", 2)
			Audio.play("sfx_elite_spawn", 1.0, 0.0, 0.8)
			await get_tree().create_timer(0.35).timeout
		"charge":
			var target: Vector2 = pl.global_position
			for k in 7:
				if not is_instance_valid(self) or dead:
					break
				anim.modulate = Color(2.2, 0.6, 0.6) if k % 2 == 0 else Color(1.2, 0.6, 0.6)
				await get_tree().create_timer(0.09).timeout
			if not is_instance_valid(self) or dead:
				busy = false
				return
			charge_dir = (target - global_position).normalized()
			Audio.play("sfx_dash", 0.65, 0.0, 0.9)
			wd.shake(5.0, 0.3)
			await get_tree().create_timer(0.75).timeout
			charge_dir = Vector2.ZERO
			if is_instance_valid(self) and not dead:
				wd.shake(7.0, 0.3)
				wd.explode(global_position, 90.0, dmg * 0.8, false)
		"ring_wall":
			for wave in 2:
				if not is_instance_valid(self) or dead:
					break
				var n2 := 24
				var gap := _rng.randi_range(0, n2 - 1)
				var off3 := _rng.randf() * TAU
				for i in n2:
					if i == gap or i == (gap + 1) % n2 or i == (gap - 1 + n2) % n2:
						continue
					var a2 := off3 + i * TAU / n2
					wd.enemy_bullet(global_position, Vector2(cos(a2), sin(a2)), 150.0, dmg * 0.55, "eproj_ball")
				Audio.play("sfx_warn", 0.8, 0.02, 0.8)
				await get_tree().create_timer(0.6).timeout
	busy = false


func take_damage(amount: float, crit: bool, from_pos: Vector2, knock_amt: float) -> void:
	super.take_damage(amount, crit, from_pos, knock_amt * 0.12)
	if dead or hp <= 0.0:
		return
	# 每掉 25% 血放一次专属大招（与关卡环境联动）
	while _ult_idx < 3 and hp < max_hp * (0.75 - 0.25 * _ult_idx):
		_ult_idx += 1
		_ultimate(_ult_idx)
	if not enraged and hp > 0.0 and hp < max_hp * 0.5:
		enraged = true
		atk_gap = 1.9
		var wd = Game.world
		if wd != null:
			wd.shake(9.0, 0.6)
			Fx.spawn(wd.fx_layer, "vfx_shock", global_position, 1.6, 16.0, Color(1.6, 0.6, 0.6))
			FloatText.spawn(wd.text_layer, "狂暴化！", global_position + Vector2(0, -46),
				Color("ff4c3a"), 13, Vector2(0, -14), 1.6)
		Audio.play("sfx_boss_roar", 1.15, 0.0, 1.0)
