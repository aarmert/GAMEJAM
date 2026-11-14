extends SceneTree
# Trials hareket zarfı ölçümü: oyuncuyu Trials kurallarıyla düz bir arenada betikle oynatır ve
# zıplama/dash/küre/sarmaşık mesafelerini ölçer. Çıktı: Markdown tablo (AUTHORING.md'ye kopyalanır).
#   godot --headless --path . --audio-driver Dummy --fixed-fps 60 -s tools/trials/envelope.gd

const Lib := preload("res://tools/trials/replay_lib.gd")
const GameScript := preload("res://trials/scripts/trials_game.gd")
const GAME_SCENE := "res://trials/scenes/trials_chapter1.tscn"
const W := 60
const H := 24

var game: Node
var drv: Node
var tests: Array = []
var ti := -1
var phase := "boot"
var f := 0
var rec := {}
var rows: Array = []


func _arena() -> String:
	var g := []
	for y in H:
		var row := ""
		for x in W:
			var c := "."
			if y == 0 or y >= 22 or x == 0 or x == W - 1:
				c = "#"
			elif x >= 44 and x <= 47 and y >= 3:
				c = "#"
			elif x == 43 and y >= 4 and y <= 21:
				c = "|"
			elif x == 30 and y == 20:
				c = "o"
			elif y == 21 and x in [4, 30, 40]:
				c = "P"
			elif y == 21 and x == 57:
				c = "E"
			row += c
		g.append(row)
	return "title: envelope arena\ntheme: forest\n\n[room arena]\nat: 0 0\n" + "\n".join(g) + "\n"


func _init() -> void:
	var p := "user://trials_envelope_arena.txt"
	var fa := FileAccess.open(p, FileAccess.WRITE)
	fa.store_string(_arena())
	fa.close()
	GameScript.override_path = p
	GameScript.no_save = true
	GameScript.tool_mode = true
	game = load(GAME_SCENE).instantiate()
	root.add_child(game)
	current_scene = game
	drv = Lib.new()
	root.add_child(drv)
	var floor_y := 22 * 32 - 1
	var s1 := Vector2(4 * 32 + 16, floor_y)
	var s_orb := Vector2(30 * 32 + 16, floor_y)
	var s_vine := Vector2(42 * 32 + 16, floor_y)
	tests = [
		["Standing full jump (hold jump)", s1, "jump 40; wait_floor 120"],
		["Shortest hop (tap jump 1 frame)", s1, "jump 1; wait_floor 120"],
		["Running full jump", s1, "hold right; wait 12; jump 40; wait_floor 120"],
		["Running short hop", s1, "hold right; wait 12; jump 1; wait_floor 120"],
		["Ground dash right", s1, "dash right; wait 40"],
		["Ground dash up", s1, "dash up; wait_floor 120"],
		["Ground dash up+right", s1, "dash up+right; wait_floor 120"],
		["Apex dash right (jump, dash at apex)", s1, "jump 20; wait_fall; dash right; wait_floor 120"],
		["Apex dash up", s1, "jump 20; wait_fall; dash up; wait_floor 120"],
		["Apex dash up+right", s1, "jump 20; wait_fall; dash up+right; wait_floor 120"],
		["Apex dash down+right", s1, "jump 20; wait_fall; dash down+right; wait_floor 120"],
		["Apex dash down", s1, "jump 20; wait_fall; dash down; wait_floor 120"],
		["Running jump + apex dash right", s1, "hold right; wait 12; jump 20; wait_fall; dash right; wait_floor 120"],
		["Running jump + apex dash up+right", s1, "hold right; wait 12; jump 20; wait_fall; dash up+right; wait_floor 120"],
		["Running jump + apex dash down+right", s1, "hold right; wait 12; jump 20; wait_fall; dash down+right; wait_floor 120"],
		["Orb double jump (jump into orb at apex, jump again)", s_orb, "jump 20; wait_fall; jump 40; wait_floor 160"],
		["Orb double jump + dash up", s_orb, "jump 20; wait_fall; jump 20; wait_fall; dash up; wait_floor 200"],
		["Vine climb: hold toward vine wall, 6 wall jumps", s_vine, "hold right; jump 30; repeat 6; wait_wall 60; jump 30; endrepeat; wait 20"],
		["Fall from vine top (max fall speed)", s_vine, "hold right; jump 30; repeat 6; wait_wall 60; jump 30; endrepeat; release; hold left; wait 6; release; wait_floor 200"],
	]


func _physics_process(_d: float) -> bool:
	f += 1
	match phase:
		"boot":
			if f < 3:
				return false
			drv.player = game.player
			drv.game = game
			_next()
		"settle":
			if f > 8 and game.player.is_on_floor():
				var t: Array = tests[ti]
				drv.start(Lib.parse(t[2]).cmds)
				phase = "run"
				f = 0
				rec = {"x0": game.player.global_position.x, "y0": game.player.global_position.y,
					"min_y": game.player.global_position.y, "max_x": game.player.global_position.x,
					"take_x": null, "land_x": null, "air": 0, "max_vy": 0.0, "airborne": false,
					"dash_start": null, "dash_end": null}
		"run":
			if OS.get_cmdline_user_args().has("--trace%d" % ti):
				print("  t%d f%d %s jump=%s orbs=%d dj=%d" % [ti, f, drv.state_string(), Input.is_action_pressed("jump"), game.player._t_orbs.size(), game.player.double_jump_orbit_overlap_count])
			var p: Vector2 = game.player.global_position
			var pl = game.player
			rec.min_y = minf(rec.min_y, p.y)
			rec.max_x = maxf(rec.max_x, p.x)
			rec.max_vy = maxf(rec.max_vy, pl.velocity.y)
			var on_floor: bool = pl.is_on_floor()
			if not on_floor:
				rec.air += 1
				if not rec.airborne:
					rec.airborne = true
					rec.take_x = p.x
			elif rec.airborne and rec.land_x == null:
				rec.land_x = p.x
			var dashing: bool = pl.dash_component.dashing
			if dashing and rec.dash_start == null:
				rec.dash_start = p
			if not dashing and rec.dash_start != null and rec.dash_end == null:
				rec.dash_end = p
			if drv.finished or f > 600:
				_record()
				_next()
	return false


func _next() -> void:
	ti += 1
	if ti >= tests.size():
		_print()
		quit(0)
		return
	var t: Array = tests[ti]
	drv.finished = true
	drv.release_all()
	game._reset_room(game.current)
	game.player.trials_respawn(t[1])
	phase = "settle"
	f = 0


func _record() -> void:
	var t: Array = tests[ti]
	var rise: float = rec.y0 - rec.min_y
	var dx := "-"
	if rec.take_x != null and rec.land_x != null:
		dx = "%.0f px (%.1f t)" % [rec.land_x - rec.take_x, (rec.land_x - rec.take_x) / 32.0]
	var dash := "-"
	if rec.dash_start != null:
		var e: Vector2 = rec.dash_end if rec.dash_end != null else game.player.global_position
		var d: Vector2 = e - rec.dash_start
		dash = "(%+.0f, %+.0f) px" % [d.x, d.y]
	rows.append([t[0], "%.0f px (%.2f t)" % [rise, rise / 32.0], dx, dash, "%d f" % rec.air, "%.0f" % rec.max_vy])


func _print() -> void:
	print("| Move | Max rise above start (feet) | Horizontal takeoff→landing | Dash displacement (during dash) | Air time | Max fall speed px/s |")
	print("|---|---|---|---|---|---|")
	for r in rows:
		print("| %s | %s | %s | %s | %s | %s |" % r)
	var pl = game.player
	print("")
	print("Constants: run speed %d px/s, jump velocity %.0f px/s, gravity %.0f px/s², dash %.0f px/s for %.2f s, coyote %.2f s, jump buffer %.2f s, jump-cut factor %.2f, max fall %.0f px/s" % [
		pl.movement_component.speed, pl.jump_component.jump_velocity, ProjectSettings.get_setting("physics/2d/default_gravity"),
		pl.dash_component.dash_speed, pl.movement_rules.dash_duration, pl.movement_rules.coyote_time,
		pl.movement_rules.jump_buffer_time, pl.movement_rules.jump_cut_factor, pl.movement_rules.max_fall_speed])
