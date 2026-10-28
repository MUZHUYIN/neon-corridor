class_name Projectile
extends Node2D
## 通用弹丸：穿透 / 追踪 / 回旋 / 轨道 / AOE 全部由配置驱动。

var vel := Vector2.ZERO
var speed := 300.0
var dmg := 5.0
var pierce := 0
var life := 1.0
var radius := 4.0
var from_player := true
var crit := false
var aoe := 0.0
var knock := 0.0
var homing := 0.0
var boomerang := false
var orbit := false
var split_on_death := 0
var weapon_id := ""
var element := ""
var hit_ids := {}
var dead := false
var t := 0.0
var dir := Vector2.RIGHT
var sprite: AnimatedSprite2D
var glow: Sprite2D = null
var spin := 0.0
var _orbit_c := Vector2.ZERO
var _orbit_r := 0.0
var _orbit_a := 0.0
var _orbit_w := 0.0
var _target = null
var _owner_player = null

## 弹丸配色（用于光晕染色）
const TINTS := {
	"proj_pistol": Color("ffe460"), "proj_shotgun": Color("ff9a30"),
	"proj_laser": Color("34f0ff"), "proj_boomerang": Color("58f08e"),
	"proj_orb": Color("a25eff"), "proj_rocket": Color("ff7a30"),
	"eproj_shard": Color("ff3e82"), "eproj_ball": Color("ff9a30"),
	"proj_nail": Color("cffcff"), "glow_soft": Color.WHITE,
}


static func spawn(parent: Node, cfg: Dictionary) -> Projectile:
	var p := Projectile.new()
	var sc: float = float(cfg.get("scale", 1.0))
	for k in cfg.keys():
		# "scale" 和 "sprite" 不是节点属性：Node2D.scale 是 Vector2，
		# 用 float 去 set 会把缩放写成 0，整个弹丸（含子节点）直接消失。
		if k == "scale" or k == "sprite":
			continue
		p.set(k, cfg[k])
	# 柔光叠加层：让弹丸在任何背景下都显眼
	var glow := Sprite2D.new()
	glow.texture = Art.tex("glow_soft")
	glow.scale = Vector2(sc * 1.5, sc * 1.5)
	var tint: Color = TINTS.get(String(cfg["sprite"]), Color.WHITE)
	glow.modulate = Color(tint.r, tint.g, tint.b, 0.55)
	glow.z_index = -1
	p.add_child(glow)
	var a := AnimatedSprite2D.new()
	a.sprite_frames = Art.frames(cfg["sprite"], 14.0, true)
	a.animation = "anim"
	a.play("anim")
	a.scale = Vector2(sc, sc)
	p.glow = glow
	p.sprite = a
	p.add_child(a)
	parent.add_child(p)
	return p


func _enter_tree() -> void:
	if _orbit_c == Vector2.ZERO:
		_orbit_c = global_position


func setup_orbit(center: Vector2, radius_: float, ang: float, w_: float) -> void:
	orbit = true
	_orbit_c = center
	_orbit_r = radius_
	_orbit_a = ang
	_orbit_w = w_


func step(delta: float) -> void:
	t += delta
	if t >= life:
		die()
		return
	if orbit:
		var pl = Game.world.player if Game.world != null else null
		if pl != null and is_instance_valid(pl):
			_orbit_c = pl.global_position
		_orbit_a += _orbit_w * delta
		global_position = _orbit_c + Vector2(cos(_orbit_a), sin(_orbit_a)) * _orbit_r
		dir = Vector2(cos(_orbit_a + PI * 0.5), sin(_orbit_a + PI * 0.5))
		rotation = _orbit_a
		spin += delta * 12.0
		if sprite != null:
			sprite.rotation = spin
		return
	if homing > 0.0:
		if _target == null or not is_instance_valid(_target) or _target.dead:
			_target = _find_target()
		if _target != null:
			var want := (Vector2(_target.global_position) - global_position).normalized()
			vel = vel.lerp(want * speed, clampf(homing * delta, 0.0, 1.0))
	if boomerang:
		# 前半程飞出，后半程折返
		var half := life * 0.5
		if t > half:
			var back: Vector2 = Game.world.player.global_position - global_position
			vel = vel.lerp(back.normalized() * speed * 1.25, 2.4 * delta)
	spin += delta * (8.0 if not boomerang else 16.0)
	if sprite != null:
		sprite.rotation = spin if boomerang else atan2(vel.y, vel.x)
	global_position += vel * delta
	if not from_player:
		_check_wall()


func _check_wall() -> void:
	var wd = Game.world
	if wd == null:
		return
	if not wd.arena_rect().grow(24.0).has_point(global_position):
		die()


func _find_target():
	var wd = Game.world
	if wd == null:
		return null
	var arr: Array = wd.query_circle(global_position, 220.0)
	var best = null
	var bd := 1e20
	for e in arr:
		if e.dead:
			continue
		var d: float = global_position.distance_squared_to(e.global_position)
		if d < bd:
			bd = d
			best = e
	return best


func die() -> void:
	if dead:
		return
	dead = true
	queue_free()
