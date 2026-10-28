class_name Fx
extends AnimatedSprite2D
## 一次性特效：播完自动销毁。

var _scale := 1.0
var _follow: Node2D = null
var _fade := false


static func spawn(parent: Node, name: String, pos: Vector2, scale: float = 1.0,
		fps: float = 18.0, mod: Color = Color.WHITE, follow: Node2D = null) -> Fx:
	var f := Fx.new()
	f.sprite_frames = Art.frames(name, fps, false)
	f.animation = "anim"
	f.position = pos
	f.scale = Vector2(scale, scale)
	f.modulate = mod
	f.z_index = 40
	f._scale = scale
	f._follow = follow
	parent.add_child(f)
	f.play("anim")
	f.animation_finished.connect(f.queue_free)
	return f


func _process(_d: float) -> void:
	if _follow != null and is_instance_valid(_follow):
		global_position = _follow.global_position
