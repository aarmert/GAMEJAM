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
		for m in muzik:
			if m.bus != &"Music" or not is_equal_approx(m.volume_db, am.SCENE_MUSIC_NODE_DB):
				ok = false
				print("  FAIL: scene music node not routed/levelled (bus=%s db=%.1f)" % [m.bus, m.volume_db])
	ok = _check_mix(am) and ok
	ok = await _check_sfx_limits(am) and ok
	ok = await _check_checkpoint_chime(am) and ok
	print("RESULT: %s" % ("OK" if ok else "FAIL"))
	quit(0 if ok else 1)



# Bus volumes come from the constants at the top of audio_manager.gd; Master has a limiter.
func _check_mix(am: Node) -> bool:
	var ok := true
	var want := {&"Master": am.MASTER_VOLUME_DB, &"Music": am.MUSIC_VOLUME_DB, &"SFX": am.SFX_VOLUME_DB,
		&"Ambient": am.AMBIENT_VOLUME_DB}
	for bus in want:
		var got := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus))
		if not is_equal_approx(got, want[bus]):
			ok = false
			print("FAIL: bus %s volume %.1f != %.1f" % [bus, got, want[bus]])
	var has_limiter := false
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter and AudioServer.is_bus_effect_enabled(0, i):
			has_limiter = true
	if not has_limiter:
		ok = false
		print("FAIL: no HardLimiter on Master")
	# hierarchy sanity: chase music must be the loudest music (file LUFS + dB + bus)
	var chase: float = -12.4 + am.SCENE_MUSIC_NODE_DB
	for k in am.MUSIC_DB:
		if -17.0 + float(am.MUSIC_DB[k]) >= chase - 3.0:
			ok = false
			print("FAIL: music %s is not clearly below the chase music" % k)
	print("mix: buses/limiter %s" % ("OK" if ok else "FAIL"))
	return ok


func _playing_count(am: Node, file: String) -> int:
	var c := 0
	for p in am._sfx_pool:
		if p.playing and p.stream != null and p.stream.resource_path.get_file() == file:
			c += 1
	return c


func _stop_all(am: Node) -> void:
	for p in am._sfx_pool:
		p.stop()
	am._last_played.clear()


# A burst of identical play_sfx calls in one frame must produce a single voice (retrigger cooldown),
# and no sound may exceed MAX_VOICES_PER_SOUND simultaneous copies.
func _check_sfx_limits(am: Node) -> bool:
	var ok := true
	_stop_all(am)
	for i in 5:
		am.play_sfx("death", 0.0)
		am.play_sfx("pickup", 0.0)
	var d := _playing_count(am, "death.wav")
	var pk := _playing_count(am, "pickup.wav")
	if d != 1 or pk != 1:
		ok = false
		print("FAIL: burst of 5 -> death voices %d, pickup voices %d (want 1)" % [d, pk])
	_stop_all(am)
	for i in 6:  # spaced past the default cooldown, still overlapping
		am.play_sfx("whoosh", 0.0)
		am._last_played.clear()
	var w := _playing_count(am, "whoosh.wav")
	if w > am.MAX_VOICES_PER_SOUND:
		ok = false
		print("FAIL: %d simultaneous whoosh voices (max %d)" % [w, am.MAX_VOICES_PER_SOUND])
	_stop_all(am)
	print("sfx limits: %s (death=%d pickup=%d whoosh=%d)" % ["OK" if ok else "FAIL", d, pk, w])
	return ok


# The checkpoint chime plays only the first time a given heal zone is activated, also across reloads.
func _check_checkpoint_chime(am: Node) -> bool:
	CheckpointData.clear()
	change_scene_to_file("res://scenes/levels/level2.tscn")
	await _wait(1.0)
	var gd := GDScript.new()
	gd.source_code = "extends Area2D\nvar player_in_area = null\nvar checkpoint_index = 0\n"
	gd.reload()
	var zone := Area2D.new()
	zone.set_script(gd)
	zone.name = "FakeHealZone"
	current_scene.add_child(zone)
	zone.player_in_area = zone
	var results := []
	for attempt in 2:
		_stop_all(am)
		am.play_sfx("checkpoint", 0.0)
		results.append(_playing_count(am, "checkpoint.wav"))
		if attempt == 0:  # simulate death -> reload of the same scene
			reload_current_scene()
			await _wait(1.0)
			zone = Area2D.new()
			zone.set_script(gd)
			zone.name = "FakeHealZone"
			current_scene.add_child(zone)
			zone.player_in_area = zone
	_stop_all(am)
	var ok: bool = results == [1, 0]
	print("checkpoint chime first/after-respawn: %s -> %s" % [results, "OK" if ok else "FAIL"])
	return ok
