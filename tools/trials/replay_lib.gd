extends Node
# Trials replay DSL sürücüsü: her fizik karesinin sonunda bir sonraki karenin girdilerini uygular.
# Scripted-input driver for the Trials replay DSL. Runs AFTER the player each physics frame and sets
# the inputs for the NEXT frame (Input.action_press is seen as "just pressed" one physics frame later,
# exactly like a real key press arriving between frames).
# Frame = 1/60 s (run Godot with --fixed-fps 60). Grammar: see trials/AUTHORING.md "Replay DSL".

const DIRS := ["left", "right", "up", "down"]
# Oyuncu kökü ayakların 17.5 px ALTINDA (asil_karakter.tscn: çarpışma kutusu y -46.5..-17.5)
const FEET := 17.5
const ACT := {"left": "move_left", "right": "move_right", "up": "move_up", "down": "move_down"}

var player: CharacterBody2D
var game: Node
var cmds: Array = []            # [{op, a, b, line}]
var pc := 0
var held := {}                  # dir -> true
var frames_left := 0            # aktif zamanlı komutun kalan karesi
var active: Dictionary = {}
var error := ""                 # wait_* zaman aşımı vb.
var finished := false
var frame := 0                  # bu betikte geçen kare


static func parse(text: String, first_line := 1) -> Dictionary:
	var out: Array = []
	var errors: PackedStringArray = PackedStringArray()
	var stack: Array = []        # repeat blokları: [count, start_index, line]
	var lines := text.split("\n")
	for i in lines.size():
		var ln := first_line + i
		var l := lines[i]
		var c := l.find("//")
		if c != -1:
			l = l.substr(0, c)
		for part in l.split(";"):
			var t := part.strip_edges().to_lower()
			if t.is_empty():
				continue
			var w := t.split(" ", false)
			var op := w[0]
			var e := _parse_cmd(op, w, ln)
			if e.has("error"):
				errors.append("line %d: %s ('%s')" % [ln, e.error, t])
				continue
			if op == "repeat":
				stack.append([e.a, out.size(), ln])
				continue
			if op == "endrepeat" or op == "end_repeat":
				if stack.is_empty():
					errors.append("line %d: endrepeat without repeat" % ln)
					continue
				var top: Array = stack.pop_back()
				var body := out.slice(top[1])
				for _k in range(int(top[0]) - 1):
					out.append_array(body.duplicate(true))
				continue
			out.append(e)
	for s in stack:
		errors.append("line %d: repeat without endrepeat" % s[2])
	return {"cmds": out, "errors": errors}


static func _dirs_ok(s: String) -> bool:
	if s == "none":
		return true
	for d in s.split("+"):
		if not d in DIRS:
			return false
	return true


static func _parse_cmd(op: String, w: PackedStringArray, ln: int) -> Dictionary:
	var e := {"op": op, "a": null, "b": null, "line": ln}
	match op:
		"hold", "release":
			if w.size() < 2:
				if op == "release":
					e.a = "all"
					return e
				return {"error": "hold needs directions, e.g. 'hold right' or 'hold right+up'"}
			if w[1] != "all" and not _dirs_ok(w[1]):
				return {"error": "unknown direction (left right up down, joined with +)"}
			e.a = w[1]
		"wait":
			if w.size() < 2 or not w[1].is_valid_int():
				return {"error": "wait needs a frame count"}
			e.a = int(w[1])
		"jump", "dash_hold":
			e.a = int(w[1]) if w.size() > 1 and w[1].is_valid_int() else 1
		"dash":
			e.a = w[1] if w.size() > 1 else ""
			if e.a != "" and not _dirs_ok(e.a):
				return {"error": "dash direction must be left/right/up/down combos, e.g. 'dash up+right'"}
		"tap":
			if w.size() < 2:
				return {"error": "tap needs an action name (jump, dash, flashlight, move_left...)"}
			e.a = w[1]
			e.b = int(w[2]) if w.size() > 2 and w[2].is_valid_int() else 1
		"run":
			if w.size() < 3 or not _dirs_ok(w[1]) or not w[2].is_valid_int():
				return {"error": "run needs a direction and frames, e.g. 'run right 30'"}
			e.a = w[1]
			e.b = int(w[2])
		"wait_floor", "wait_air", "wait_wall", "wait_fall", "wait_room":
			e.a = int(w[1]) if w.size() > 1 and w[1].is_valid_int() else 240
		"until":
			# until col >= 12 [max]   until x < 300   (col/row = oda içi hücre (gövde merkezi);
			# x = oda içi px (oyuncu merkezi), y = oda içi px (ayak hizası))
			if w.size() < 4 or not w[1] in ["col", "row", "x", "y"] or not w[2] in [">=", "<=", ">", "<"] or not w[3].is_valid_float():
				return {"error": "until syntax: until col|row|x|y >=|<=|>|< N [max_frames]"}
			e.a = [w[1], w[2], float(w[3])]
			e.b = int(w[4]) if w.size() > 4 and w[4].is_valid_int() else 300
		"repeat":
			if w.size() < 2 or not w[1].is_valid_int():
				return {"error": "repeat needs a count"}
			e.a = int(w[1])
		"endrepeat", "end_repeat", "log":
			pass
		_:
			return {"error": "unknown command '%s'" % op}
	return e


func start(commands: Array) -> void:
	cmds = commands.duplicate(true)
	pc = 0
	held = {}
	frames_left = 0
	active = {}
	error = ""
	finished = false
	frame = 0
	release_all()


func release_all() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down", "jump", "dash", "flashlight"]:
		if InputMap.has_action(a):
			Input.action_release(a)


func _ready() -> void:
	process_physics_priority = 1000
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _physics_process(_delta: float) -> void:
	if finished or player == null:
		return
	step()


# Bir kare ilerlet: anlık komutları işle, zamanlı komutun girdilerini bu kare için uygula.
func step() -> void:
	frame += 1
	var override_dirs = null
	var press := {}
	var guard := 0
	while frames_left <= 0:
		guard += 1
		if guard > 10000:
			error = "too many zero-time commands"
			finished = true
			return
		if pc >= cmds.size():
			finished = true
			_apply(null, {})
			return
		active = cmds[pc]
		pc += 1
		match active.op:
			"hold":
				for d in str(active.a).split("+"):
					if d != "none":
						held[d] = true
			"release":
				if active.a == "all":
					held = {}
				else:
					for d in str(active.a).split("+"):
						held.erase(d)
			"log":
				print("    [f%d] %s" % [frame, state_string()])
			"wait":
				frames_left = active.a
			"jump":
				frames_left = active.a
			"dash_hold":
				frames_left = active.a
			"dash":
				frames_left = 1
			"tap":
				frames_left = active.b
			"run":
				frames_left = active.b
			"wait_floor", "wait_air", "wait_wall", "wait_fall", "wait_room":
				frames_left = active.a
				active["room0"] = game.current if game != null else -1
				if _cond_met():
					frames_left = 0
			"until":
				frames_left = active.b
				if _cond_met():
					frames_left = 0
	# Basma komutları "taze" basış ister: tuş zaten basılıysa önce bir kare bırakılır (gap).
	if not active.has("gap") and active.op in ["jump", "dash_hold", "dash", "tap"]:
		var act: String = active.a if active.op == "tap" else ("jump" if active.op == "jump" else "dash")
		active["gap"] = InputMap.has_action(act) and Input.is_action_pressed(act)
		if active.gap:
			frames_left += 1
	var gap_frame: bool = active.get("gap", false) and not active.get("gap_done", false)
	if gap_frame:
		active["gap_done"] = true
	# zamanlı komut
	match active.op:
		"jump":
			if not gap_frame:
				press["jump"] = true
		"dash_hold":
			if not gap_frame:
				press["dash"] = true
		"dash":
			if not gap_frame:
				press["dash"] = true
			if active.a != "":
				override_dirs = {}
				for d in str(active.a).split("+"):
					override_dirs[d] = true
		"tap":
			if not gap_frame:
				press[active.a] = true
		"run":
			override_dirs = held.duplicate()
			for d in str(active.a).split("+"):
				override_dirs[d] = true
	_apply(override_dirs, press)
	frames_left -= 1
	if active.op in ["wait_floor", "wait_air", "wait_wall", "wait_fall", "wait_room", "until"]:
		if _cond_met():
			frames_left = 0
		elif frames_left <= 0:
			error = "line %d: %s timed out" % [active.line, active.op]
			finished = true


func _cond_met() -> bool:
	match active.op:
		"wait_floor":
			return player.is_on_floor()
		"wait_air":
			return not player.is_on_floor()
		"wait_wall":
			return player.is_on_wall() and not player.is_on_floor()
		"wait_fall":
			return player.velocity.y > 0.0 and not player.is_on_floor()
		"wait_room":
			return game != null and game.current != active.get("room0", -1)
		"until":
			var v := 0.0
			var p := player.global_position + Vector2(0, -32) # gövde merkezi
			var r: Dictionary = game.rooms[game.current].room if game != null else {"x": 0, "y": 0}
			match active.a[0]:
				"x":
					v = player.global_position.x - r.x * 32.0
				"y":
					v = player.global_position.y - FEET - r.y * 32.0
				"col":
					v = floorf(p.x / 32.0) - r.x
				"row":
					v = floorf(p.y / 32.0) - r.y
			var n: float = active.a[2]
			match active.a[1]:
				">=":
					return v >= n
				"<=":
					return v <= n
				">":
					return v > n
				"<":
					return v < n
	return false


func _apply(override_dirs, press: Dictionary) -> void:
	var dirs: Dictionary = override_dirs if override_dirs != null else held
	for d in DIRS:
		var a: String = ACT[d]
		if not InputMap.has_action(a):
			continue
		if dirs.has(d):
			if not Input.is_action_pressed(a):
				Input.action_press(a)
		elif Input.is_action_pressed(a):
			Input.action_release(a)
	for a in ["jump", "dash", "flashlight"]:
		if press.has(a):
			if not Input.is_action_pressed(a):
				Input.action_press(a)
		elif Input.is_action_pressed(a):
			Input.action_release(a)
	for a in press:
		if not a in ["jump", "dash", "flashlight"] and InputMap.has_action(a):
			Input.action_press(a)


func state_string() -> String:
	if player == null:
		return "-"
	var p := player.global_position
	var s := "pos=(%.1f,%.1f) cell=(%d,%d) v=(%.0f,%.0f)" % [p.x, p.y, int(floor(p.x / 32.0)), int(floor((p.y - 32.0) / 32.0)), player.velocity.x, player.velocity.y]
	if game != null and game.current >= 0:
		var r: Dictionary = game.rooms[game.current].room
		s += " room=%s col,row=(%d,%d) x,y=(%.1f,%.1f)" % [r.id, int(floor(p.x / 32.0)) - r.x, int(floor((p.y - 32.0) / 32.0)) - r.y, p.x - r.x * 32.0, p.y - FEET - r.y * 32.0]
	s += " floor=%s wall=%s dash=%s" % [player.is_on_floor(), player.is_on_wall(), player.dash_component.can_dash]
	return s
