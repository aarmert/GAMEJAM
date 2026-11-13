extends SceneTree

# Headless smoke test for AudioManager scene mapping + footstep surface detection.
#   ~/tools/godot/godot --headless --path . -s res://tools/audio/tests/audio_mapping_test.gd
# For each scene: load it, wait, print music/ambient stream, then hold "move_right" for a bit and
# print which footstep samples got played and which surface was detected under the player.

const SCENES := [
	"res://scenes/main_menu.tscn",
	"res://scenes/levels/3_part.tscn",
	"res://scenes/levels/level2.tscn",
	"res://scenes/levels/level1.tscn",
	"res://scenes/levels/level1_2.tscn",
]


func _initialize() -> void:
	_run.call_deferred()


func _wait(sec: float) -> void:
	var end := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


func _run() -> void:
	var am := root.get_node_or_null("AudioManager")
	if am == null:
		print("FAIL: AudioManager autoload missing")
		quit(1)
		return
	var ok := true
	for path in SCENES:
		CheckpointData.clear()
		change_scene_to_file(path)
		await _wait(2.5)
		var st: Dictionary = am.get_debug_state()
		print("[%s]\n  music  : %s (%s)\n  ambient: %s (%s)" % [path, st.music_stream, st.music_key, st.ambient_stream, st.ambient_key])
		var muzik := current_scene.find_children("Muzik", "", true, false)
		for m in muzik:
			print("  scene music node %s -> bus=%s playing=%s" % [m.name, m.bus, m.playing])
		var players := get_nodes_in_group("player")
		if players.size() > 0:
			var p: Node = players[0]
			var pa := p.get_node_or_null("PlayerAudio")
			print("  PlayerAudio attached: %s" % (pa != null))
			for sfx in am._sfx_pool:
				sfx.stream = null
			Input.action_press("move_right")
			await _wait(3.5)
			Input.action_release("move_right")
			var steps := {}
			for sfx in am._sfx_pool:
				if sfx.stream != null:
					var f: String = sfx.stream.resource_path.get_file()
					steps[f] = true
			var surf: String = pa._surface_under_feet() if pa != null else "?"
			print("  surface under feet: %s | on_floor=%s | sounds played: %s" % [surf, p.is_on_floor(), steps.keys()])
		if path.ends_with("level1.tscn") and st.music_stream != "":
			ok = false
			print("  FAIL: level1 should not have an extra music track")
	print("RESULT: %s" % ("OK" if ok else "FAIL"))
	quit(0 if ok else 1)

