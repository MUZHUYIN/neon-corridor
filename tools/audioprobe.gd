extends SceneTree
## 检查音频资源是否按预期加载、循环点是否正确。

func _initialize() -> void:
	var names := ["bgm_menu",
		"bgm_stage1_base", "bgm_stage1_drive", "bgm_stage2_base", "bgm_stage2_drive",
		"bgm_stage3_base", "bgm_stage3_drive",
		"sfx_shoot_pistol", "sfx_hit_player", "sfx_levelup"]
	for n in names:
		var p := "res://assets/audio/%s.wav" % n
		if not ResourceLoader.exists(p):
			print("MISSING ", n)
			continue
		var s: AudioStream = load(p)
		if s is AudioStreamWAV:
			var w := s as AudioStreamWAV
			if w.loop_mode == AudioStreamWAV.LOOP_DISABLED:
				w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_end = int(w.get_length() * float(w.mix_rate))
			print("%-18s len=%.2fs rate=%d ch=%s fmt=%d loop_end=%d frames_ok=%s" % [
				n, w.get_length(), w.mix_rate, str(w.stereo), w.format, w.loop_end,
				str(abs(w.get_length() - float(w.loop_end) / float(w.mix_rate)) < 0.02)])
		else:
			print(n, " -> ", s.get_class())
	quit()
