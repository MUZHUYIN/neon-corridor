extends SceneTree
## 批量语法检查：加载 src/ 下所有脚本，统计真正加载失败的脚本。

func _walk(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		var p := dir_path.path_join(n)
		if d.current_is_dir():
			if not n.begins_with("."):
				_walk(p, out)
		elif n.ends_with(".gd"):
			out.append(p)
		n = d.get_next()
	d.list_dir_end()


func _initialize() -> void:
	var files: Array = []
	_walk("res://src", files)
	files.sort()
	var bad := 0
	for f in files:
		var r: Variant = load(f)
		var ok := r != null
		if ok and r is GDScript and not (r as GDScript).can_instantiate():
			ok = false
		if not ok:
			bad += 1
			print("FAIL  ", f)
	print("checked ", files.size(), " scripts, failures=", bad)
	quit(1 if bad > 0 else 0)
