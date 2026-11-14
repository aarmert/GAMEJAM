extends SceneTree
# Trials replay harness: her oda için betikli girdiyle oynar ve raporlar (cleared / died / timeout).
#   godot --headless --path . --audio-driver Dummy --fixed-fps 60 -s tools/trials/replay.gd -- \
#       <chapter.gd> [--replay <file>] [--room <id>] [--trace N] [--shots <dir> --every N] [--visual]
# Varsayılan replay dosyası: bölüm dosyasıyla aynı ad, uzantı .replay (chapter1.gd -> chapter1.replay).
# Her oda betiği o odanın giriş doğuşunda (ölünce dönülen nokta) duran oyuncuyla başlar.

const Lib := preload("res://tools/trials/replay_lib.gd")
const GameScript := preload("res://trials/scripts/trials_game.gd")
const GAME_SCENE := "res://trials/scenes/trials_chapter1.tscn"
const ROOM_FRAME_CAP := 60 * 90
const GRACE := 150

var chapter_path := ""
var replay_path := ""
var only_room := ""
var trace := 0
var shots_dir := ""
var shot_every := 30
var visual := false

var game: Node
var drv: Node
var sections := {}        # room id -> {cmds, line}
var order: Array = []     # oda indeksleri
var oi := -1
var phase := "boot"
var wait := 0
var room_frames := 0
var grace := 0
var died_at = null
var results: Array = []
var start_coins := 0
var total_frames := 0
var parse_errors := PackedStringArray()


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		match a[i]:
			"--replay":
				i += 1; replay_path = _res(a[i])
			"--room":
				i += 1; only_room = a[i]
			"--trace":
				i += 1; trace = int(a[i])
			"--shots":
				i += 1; shots_dir = a[i]
			"--every":
				i += 1; shot_every = int(a[i])
			"--visual":
				visual = true
			_:
				chapter_path = _res(a[i])
		i += 1
	if chapter_path.is_empty():
		print("usage: replay.gd -- <chapter> [--replay file] [--room id] [--trace N] [--shots dir --every N] [--visual]")
		quit(2)
		return
	if replay_path.is_empty():
		replay_path = chapter_path.get_basename() + ".replay"
	if not shots_dir.is_empty():
		visual = true
		DirAccess.make_dir_recursive_absolute(shots_dir)
	_load_replay()
	GameScript.override_path = chapter_path
	GameScript.no_save = true
	GameScript.tool_mode = not visual
	game = load(GAME_SCENE).instantiate()
	root.add_child(game)
	current_scene = game
	drv = Lib.new()
	drv.name = "ReplayDriver"
	root.add_child(drv)
	drv.player = null


func _res(p: String) -> String:
	if p.begins_with("res://") or p.begins_with("/") or p.begins_with("user://"):
		return p
	return "res://" + p


func _load_replay() -> void:
	var f := FileAccess.open(replay_path, FileAccess.READ)
	if f == null:
		print("NOTE: no replay file %s" % replay_path)
		return
	var lines := f.get_as_text().split("\n")
	var cur := ""
	var buf := PackedStringArray()
	var buf_line := 1
	for i in lines.size() + 1:
		var l: String = lines[i] if i < lines.size() else "[room __end__]"
		var t := l.strip_edges()
		if t.begins_with("[room") and t.ends_with("]"):
			if cur != "":
				var res := Lib.parse("\n".join(buf), buf_line)
				for e in res.errors:
					parse_errors.append("%s: room %s: %s" % [replay_path.get_file(), cur, e])
				sections[cur] = {"cmds": res.cmds, "line": buf_line}
			cur = t.substr(5, t.length() - 6).strip_edges()
			buf = PackedStringArray()
			buf_line = i + 2
		elif cur != "":
			buf.append(l)


func _physics_process(_delta: float) -> bool:
	total_frames += 1
	match phase:
		"boot":
			if game.rooms.is_empty():
				if total_frames > 5:
					print("ERROR: chapter did not build:")
					for e in game.load_errors:
						print("  " + e)
					quit(1)
				return false
			for e in parse_errors:
				print("REPLAY ERROR: " + e)
			drv.player = game.player
			drv.game = game
			game.player_died.connect(_on_died)
			for idx in game.rooms.size():
				var id: String = game.rooms[idx].room.id
				if only_room.is_empty() or only_room == id:
					order.append(idx)
			if order.is_empty():
				print("ERROR: room '%s' not found" % only_room)
				quit(2)
				return false
			_next_room()
		"settle":
			wait += 1
			if paused:
				return false
			if (game.player.is_on_floor() and wait > 2) or wait > 60:
				var id: String = game.rooms[order[oi]].room.id
				drv.start(sections[id].cmds)
				phase = "run"
				room_frames = 0
				grace = 0
				died_at = null
				start_coins = game.banked.size() + game.pending.size()
		"run":
			if paused:
				return false
			room_frames += 1
			if trace > 0 and room_frames % trace == 0:
				print("    [f%d] %s" % [room_frames, drv.state_string()])
			if not shots_dir.is_empty() and room_frames % shot_every == 0:
				_shot()
			var idx: int = order[oi]
			var id: String = game.rooms[idx].room.id
			var coins: int = game.banked.size() + game.pending.size() - start_coins
			if game.complete:
				_finish("CLEARED (chapter exit) in %d frames, collectibles +%d" % [room_frames, coins], true)
			elif game.current != idx:
				_finish("CLEARED -> %s in %d frames, collectibles +%d" % [game.rooms[game.current].room.id, room_frames, coins], true)
			elif died_at != null:
				var p: Vector2 = died_at
				var r: Dictionary = game.rooms[idx].room
				_finish("DIED at (%.0f,%.0f) local cell (%d,%d) frame %d [script line ~%d]" % [p.x, p.y, int(floor(p.x / 32.0)) - r.x, int(floor((p.y - 32.0) / 32.0)) - r.y, room_frames, _cur_line()], false)
			elif drv.error != "":
				_finish("STALLED: %s at %s" % [drv.error, drv.state_string()], false)
			elif drv.finished:
				grace += 1
				if grace > GRACE:
					_finish("TIMEOUT: script ended without leaving the room; %s" % drv.state_string(), false)
			elif room_frames > ROOM_FRAME_CAP:
				_finish("TIMEOUT: frame cap; %s" % drv.state_string(), false)
		"done":
			pass
	return false


func _cur_line() -> int:
	if drv.active.is_empty():
		return 0
	return int(drv.active.get("line", 0))


func _on_died(at: Vector2) -> void:
	if phase == "run" and died_at == null:
		died_at = at


func _finish(msg: String, ok: bool) -> void:
	var id: String = game.rooms[order[oi]].room.id
	print("room %-14s %s" % [id, msg])
	results.append([id, ok])
	drv.finished = true
	drv.release_all()
	if not shots_dir.is_empty():
		_shot()
	_next_room()


func _next_room() -> void:
	oi += 1
	while oi < order.size():
		var id: String = game.rooms[order[oi]].room.id
		if sections.has(id):
			break
		print("room %-14s NO SCRIPT (add a [room %s] section to %s)" % [id, id, replay_path.get_file()])
		results.append([id, false])
		oi += 1
	if oi >= order.size():
		_report()
		return
	game.debug_goto_room(order[oi])
	phase = "settle"
	wait = 0


func _report() -> void:
	phase = "done"
	var ok := 0
	for r in results:
		if r[1]:
			ok += 1
	print("RESULT: %d/%d rooms cleared" % [ok, results.size()])
	quit(0 if ok == results.size() and parse_errors.is_empty() else 1)


func _shot() -> void:
	var img := root.get_texture().get_image()
	if img == null:
		return
	var id: String = game.rooms[order[oi]].room.id
	img.save_png("%s/%s_%04d.png" % [shots_dir, id, room_frames])
