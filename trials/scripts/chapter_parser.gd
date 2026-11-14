extends RefCounted
# Trials bölüm dosyası ayrıştırıcı. Biçim: trials/AUTHORING.md.
# Parses a Trials chapter (ASCII rooms + metadata) into plain Dictionaries and validates it.
#
#   var ch := ChapterParser.parse_file("res://trials/chapters/chapter1.gd")
#   ch.errors / ch.warnings : Array[String] ("file:line: message")
#   ch.rooms : Array[Dictionary]  (see _new_room)

const TILE := 32

# Lejant: karakter -> tür. Legend: char -> kind.
const LEGEND := {
	".": "air",
	"#": "solid",
	"=": "oneway",
	"^": "spike_up",
	"v": "spike_down",
	"<": "spike_left",
	">": "spike_right",
	"o": "orb_jump",
	"*": "orb_dash",
	"|": "vine",
	"e": "enemy",
	"x": "killzone",
	"c": "collectible",
	"P": "spawn",
	"E": "exit",
	"L": "lamp",
	"D": "darkness",
	"M": "platform",
	"m": "platform_end",
}

const THEMES := ["forest", "cave", "deep"]
const MUSIC_KEYS := ["forest", "lantern", "menu", "none"]
const CHASE_SPEEDS := {"fast": 0.11, "medium": 0.12, "slow": 0.2}
const HEADER_KEYS := ["title", "subtitle", "theme", "music", "author", "note"]
const ROOM_KEYS := ["at", "name", "dark", "drain", "chase", "chase_delay", "platform_speed",
	"platform_wait", "orb_respawn", "note"]

# Ekran: kamera zoom 2 -> 576x324 dünya pikseli = 18 x 10.125 karo.
const SCREEN_TILES := Vector2i(18, 10)


static func parse_file(path: String) -> Dictionary:
	var text := ""
	var line_offset := 0
	if path.ends_with(".gd"):
		var res := _load_gd_text(path)
		text = res[0]
		line_offset = res[1]
		if text.is_empty():
			var ch := _new_chapter(path)
			ch.errors.append("%s: could not read chapter text (expected `const TEXT := r\"\"\"...\"\"\"`)" % path)
			return ch
	else:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			var ch2 := _new_chapter(path)
			ch2.errors.append("%s: cannot open file" % path)
			return ch2
		text = f.get_as_text()
	return parse_text(text, path, line_offset)


# .gd bölüm dosyası: metin `const TEXT := r"""...` sabitinde. Dışa aktarılmış oyunda kaynak
# okunamayabilir; o yüzden metin her zaman sabitten alınır, satır kayması kaynaktan hesaplanır.
static func _load_gd_text(path: String) -> Array:
	var text := ""
	var offset := 0
	if ResourceLoader.exists(path):
		var scr = load(path)
		if scr != null and scr is Script:
			var consts: Dictionary = (scr as Script).get_script_constant_map()
			if consts.has("TEXT"):
				text = str(consts["TEXT"])
	var f := FileAccess.open(path, FileAccess.READ)
	if f != null:
		var src := f.get_as_text()
		var lines := src.split("\n")
		for i in lines.size():
			if lines[i].find("TEXT") != -1 and lines[i].find("r\"\"\"") != -1:
				offset = i # TEXT'in 1. satırı (r""" sonrası) dosyanın i+1. satırı (1 tabanlı)
				break
		if text.is_empty():
			var a := src.find("r\"\"\"", maxi(src.find("const TEXT"), 0))
			var b := src.find("\"\"\"", a + 4)
			if a != -1 and b != -1:
				text = src.substr(a + 4, b - a - 4)
	return [text, offset]


static func _new_chapter(path: String) -> Dictionary:
	return {
		"path": path,
		"file": path.get_file(),
		"title": "",
		"subtitle": "",
		"theme": "forest",
		"music": "",
		"rooms": [],
		"room_index": {},
		"errors": [],
		"warnings": [],
		"collectible_total": 0,
	}


static func _new_room(id: String, line: int) -> Dictionary:
	return {
		"id": id,
		"line": line,
		"name": id,
		"at": "",
		"at_line": line,
		"x": 0, "y": 0, "w": 0, "h": 0,
		"placed": false,
		"rows": PackedStringArray(),
		"row_lines": PackedInt32Array(),
		"dark": false,
		"drain": false,
		"chase": -1.0,
		"chase_delay": 0.6,
		"platform_speed": 64.0,
		"platform_wait": 0.4,
		"orb_respawn": 2.5,
		"spawns": [],         # Array[Vector2i] yerel hücre
		"links": [],          # [{to, side, cells}] oda geçişleri
		"index": 0,
	}


static func parse_text(text: String, path: String = "<text>", line_offset: int = 0) -> Dictionary:
	var ch := _new_chapter(path)
	var lines := text.split("\n")
	var room: Dictionary = {}
	var grid_closed := false
	var file := path.get_file()
	for i in lines.size():
		var ln := i + 1 + line_offset
		var raw: String = lines[i].replace("\r", "").replace("\t", "    ")
		var stripped := raw.strip_edges()
		if stripped.is_empty():
			if not room.is_empty() and room.rows.size() > 0:
				grid_closed = true
			continue
		if stripped.begins_with("//"):
			continue
		var cpos := stripped.find(" //")
		if cpos != -1:
			stripped = stripped.substr(0, cpos).strip_edges()
		if stripped.begins_with("["):
			if not stripped.ends_with("]") or not stripped.to_lower().begins_with("[room"):
				ch.errors.append("%s:%d: bad section header '%s' (expected [room <id>])" % [file, ln, stripped])
				continue
			var id := stripped.substr(5, stripped.length() - 6).strip_edges()
			if id.is_empty() or not _valid_id(id):
				ch.errors.append("%s:%d: bad room id '%s' (letters, digits, _ and - only)" % [file, ln, id])
				id = "room%d" % ch.rooms.size()
			if ch.room_index.has(id):
				ch.errors.append("%s:%d: duplicate room id '%s'" % [file, ln, id])
			room = _new_room(id, ln)
			room.index = ch.rooms.size()
			ch.room_index[id] = ch.rooms.size()
			ch.rooms.append(room)
			grid_closed = false
			continue
		var colon := stripped.find(":")
		if colon != -1:
			var key := stripped.substr(0, colon).strip_edges().to_lower()
			var val := stripped.substr(colon + 1).strip_edges()
			if room.is_empty():
				_header_kv(ch, key, val, file, ln)
			else:
				if room.rows.size() > 0 and not grid_closed:
					ch.errors.append("%s:%d: room '%s': metadata line inside the grid (put all 'key: value' lines above the grid)" % [file, ln, room.id])
				_room_kv(ch, room, key, val, file, ln)
			continue
		# grid satırı
		if room.is_empty():
			ch.errors.append("%s:%d: grid row outside any [room ...] section" % [file, ln])
			continue
		if grid_closed:
			ch.errors.append("%s:%d: room '%s': blank line inside the grid (grids must be contiguous)" % [file, ln, room.id])
			grid_closed = false
		if stripped.find(" ") != -1:
			ch.errors.append("%s:%d: room '%s': space inside grid row (use '.' for air)" % [file, ln, room.id])
			stripped = stripped.replace(" ", ".")
		room.rows.append(stripped)
		room.row_lines.append(ln)

	if ch.title.is_empty():
		ch.warnings.append("%s: missing 'title:' header" % file)
	if ch.rooms.is_empty():
		ch.errors.append("%s: no rooms ([room <id>] sections)" % file)
		return ch
	for r in ch.rooms:
		_check_grid(ch, r, file)
	_place_rooms(ch, file)
	_check_overlaps(ch, file)
	for r in ch.rooms:
		_check_contents(ch, r, file)
	_compute_links(ch, file)
	_check_reachability(ch, file)
	return ch


static func _valid_id(id: String) -> bool:
	for c in id:
		if not (c == "_" or c == "-" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")):
			return false
	return true


static func _yes(val: String) -> int:
	var v := val.to_lower()
	if v in ["yes", "true", "on", "1"]:
		return 1
	if v in ["no", "false", "off", "0"]:
		return 0
	return -1


static func _header_kv(ch: Dictionary, key: String, val: String, file: String, ln: int) -> void:
	match key:
		"title":
			ch.title = val
		"subtitle":
			ch.subtitle = val
		"theme":
			if not val.to_lower() in THEMES:
				ch.errors.append("%s:%d: unknown theme '%s' (forest | cave | deep)" % [file, ln, val])
			else:
				ch.theme = val.to_lower()
		"music":
			if not val.to_lower() in MUSIC_KEYS:
				ch.errors.append("%s:%d: unknown music '%s' (%s)" % [file, ln, val, " | ".join(MUSIC_KEYS)])
			else:
				ch.music = val.to_lower()
		"author", "note":
			pass
		_:
			ch.warnings.append("%s:%d: unknown header key '%s' (known: %s)" % [file, ln, key, ", ".join(HEADER_KEYS)])


static func _room_kv(ch: Dictionary, room: Dictionary, key: String, val: String, file: String, ln: int) -> void:
	match key:
		"at":
			room.at = val
			room.at_line = ln
		"name":
			room.name = val
		"dark", "drain":
			var b := _yes(val)
			if b == -1:
				ch.errors.append("%s:%d: room '%s': %s must be yes/no" % [file, ln, room.id, key])
			else:
				room[key] = b == 1
		"chase":
			var v := val.to_lower()
			if CHASE_SPEEDS.has(v):
				room.chase = CHASE_SPEEDS[v]
			elif v.is_valid_float() and float(v) > 0.0:
				room.chase = float(v)
			elif v in ["no", "off", "none"]:
				room.chase = -1.0
			else:
				ch.errors.append("%s:%d: room '%s': chase must be fast | medium | slow | <seconds> | no" % [file, ln, room.id])
		"chase_delay", "platform_speed", "platform_wait", "orb_respawn":
			if not val.is_valid_float() or float(val) < 0.0:
				ch.errors.append("%s:%d: room '%s': %s must be a number >= 0" % [file, ln, room.id, key])
			else:
				room[key] = float(val)
		"note":
			pass
		_:
			ch.warnings.append("%s:%d: room '%s': unknown key '%s' (known: %s)" % [file, ln, room.id, key, ", ".join(ROOM_KEYS)])


static func _check_grid(ch: Dictionary, r: Dictionary, file: String) -> void:
	if r.rows.is_empty():
		ch.errors.append("%s:%d: room '%s' has no grid rows" % [file, r.line, r.id])
		r.w = 1
		r.h = 1
		r.rows = PackedStringArray(["#"])
		r.row_lines = PackedInt32Array([r.line])
		return
	r.h = r.rows.size()
	r.w = r.rows[0].length()
	for y in r.h:
		var row: String = r.rows[y]
		if row.length() != r.w:
			ch.errors.append("%s:%d: room '%s': row %d has %d chars, expected %d (all rows must have the width of the first row)" % [file, r.row_lines[y], r.id, y, row.length(), r.w])
			row = (row + ".".repeat(r.w)).substr(0, r.w)
			r.rows[y] = row
		for x in r.w:
			var c := row[x]
			if not LEGEND.has(c):
				ch.errors.append("%s:%d: room '%s': unknown legend char '%s' at col %d row %d" % [file, r.row_lines[y], r.id, c, x, y])
	if r.w < SCREEN_TILES.x or r.h < SCREEN_TILES.y:
		ch.warnings.append("%s:%d: room '%s' is %dx%d, smaller than one screen (%dx%d): the camera centres it and shows the void around it" % [file, r.line, r.id, r.w, r.h, SCREEN_TILES.x, SCREEN_TILES.y])


static func _place_rooms(ch: Dictionary, file: String) -> void:
	var rooms: Array = ch.rooms
	if rooms[0].at.is_empty():
		rooms[0].at = "0 0"
	for _pass in rooms.size() + 1:
		var progress := false
		for r in rooms:
			if r.placed:
				continue
			if r.at.is_empty():
				continue
			var parts: PackedStringArray = r.at.split(" ", false)
			if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
				r.x = int(parts[0])
				r.y = int(parts[1])
				r.placed = true
				progress = true
				continue
			if parts.size() < 2 or parts.size() > 3:
				continue
			if not ch.room_index.has(parts[0]):
				continue
			var a: Dictionary = rooms[ch.room_index[parts[0]]]
			if not a.placed:
				continue
			var side := parts[1].to_lower()
			var off_s := parts[2].to_lower() if parts.size() == 3 else "0"
			var off := 0
			match side:
				"right", "left":
					if off_s == "top":
						off = 0
					elif off_s == "bottom":
						off = a.h - r.h
					elif off_s.is_valid_int():
						off = int(off_s)
					else:
						continue
					r.y = a.y + off
					r.x = a.x + a.w if side == "right" else a.x - r.w
				"above", "below":
					if off_s == "left":
						off = 0
					elif off_s == "right":
						off = a.w - r.w
					elif off_s.is_valid_int():
						off = int(off_s)
					else:
						continue
					r.x = a.x + off
					r.y = a.y - r.h if side == "above" else a.y + a.h
				_:
					continue
			r.placed = true
			progress = true
		if not progress:
			break
	for r in rooms:
		if r.placed:
			continue
		if r.at.is_empty():
			ch.errors.append("%s:%d: room '%s' has no 'at:' line (use 'at: X Y' or 'at: <room> right|left|above|below [offset]')" % [file, r.line, r.id])
		else:
			ch.errors.append("%s:%d: room '%s': cannot resolve 'at: %s' (syntax: 'X Y' or '<room> right|left [N|top|bottom]' or '<room> above|below [N|left|right]'; referenced room must exist and be placeable)" % [file, r.at_line, r.id, r.at])
		r.placed = true


static func _check_overlaps(ch: Dictionary, file: String) -> void:
	var rooms: Array = ch.rooms
	for i in rooms.size():
		for j in range(i + 1, rooms.size()):
			if room_rect(rooms[i]).intersects(room_rect(rooms[j])):
				ch.errors.append("%s:%d: room '%s' %s overlaps room '%s' %s" % [file, rooms[j].line, rooms[j].id, str(room_rect(rooms[j])), rooms[i].id, str(room_rect(rooms[i]))])


static func room_rect(r: Dictionary) -> Rect2i:
	return Rect2i(r.x, r.y, r.w, r.h)


static func cell(r: Dictionary, x: int, y: int) -> String:
	if x < 0 or y < 0 or x >= r.w or y >= r.h:
		return ""
	return r.rows[y][x]


static func is_solid_char(c: String) -> bool:
	return c == "#"


static func is_support_char(c: String) -> bool:
	return c == "#" or c == "="


# Dünya hücresindeki karakter ve oda; oda dışında ["", -1].
static func world_cell(ch: Dictionary, wx: int, wy: int) -> Array:
	for r in ch.rooms:
		if wx >= r.x and wy >= r.y and wx < r.x + r.w and wy < r.y + r.h:
			return [r.rows[wy - r.y][wx - r.x], r.index]
	return ["", -1]


static func _check_contents(ch: Dictionary, r: Dictionary, file: String) -> void:
	var exits := 0
	var darkness := 0
	r.spawns = []
	for y in r.h:
		var ln: int = r.row_lines[y] if y < r.row_lines.size() else r.line
		for x in r.w:
			var c: String = r.rows[y][x]
			var below := cell(r, x, y + 1)
			var above := cell(r, x, y - 1)
			var where := "%s:%d: room '%s' col %d row %d" % [file, ln, r.id, x, y]
			match c:
				"P":
					r.spawns.append(Vector2i(x, y))
					if not is_support_char(below):
						ch.errors.append("%s: spawn 'P' must stand on '#' or '=' (cell below is '%s')" % [where, below])
					if above == "#" or above in ["^", "v", "<", ">", "x"]:
						ch.warnings.append("%s: spawn 'P' has '%s' directly above (player is ~1 tile tall; keep the cell above free)" % [where, above])
					for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]:
						if cell(r, x + d.x, y + d.y) in ["^", "v", "<", ">", "x", "e"]:
							ch.warnings.append("%s: spawn 'P' is right next to a hazard '%s' (unsafe spawn)" % [where, cell(r, x + d.x, y + d.y)])
				"E":
					exits += 1
					if not is_support_char(below):
						ch.errors.append("%s: exit 'E' must stand on '#' or '=' (cell below is '%s')" % [where, below])
					if above == "#":
						ch.errors.append("%s: exit 'E' is 2 tiles tall; the cell above it must not be '#'" % where)
				"^":
					if not is_solid_char(below):
						ch.warnings.append("%s: spike '^' should have '#' below it" % where)
				"v":
					if not is_solid_char(above):
						ch.warnings.append("%s: spike 'v' should have '#' above it" % where)
				"<":
					if not is_solid_char(cell(r, x + 1, y)):
						ch.warnings.append("%s: spike '<' (points left) should have '#' to its right" % where)
				">":
					if not is_solid_char(cell(r, x - 1, y)):
						ch.warnings.append("%s: spike '>' (points right) should have '#' to its left" % where)
				"|":
					var l := cell(r, x - 1, y)
					var rr := cell(r, x + 1, y)
					if not (is_solid_char(l) or is_solid_char(rr)):
						ch.errors.append("%s: vine '|' needs a '#' wall directly left or right of it" % where)
				"e", "L":
					if not is_support_char(below):
						ch.warnings.append("%s: '%s' should stand on '#' or '=' (cell below is '%s')" % [where, c, below])
					if c == "L" and above == "#":
						ch.warnings.append("%s: lamp 'L' is ~2.5 tiles tall; it overlaps the '#' above" % where)
				"D":
					darkness += 1
					if r.chase <= 0.0:
						ch.errors.append("%s: darkness origin 'D' in a room without 'chase:'" % where)
				"M":
					if _platform_partner(r, x, y) == Vector2i(-1, -1):
						ch.errors.append("%s: moving platform 'M' has no 'm' end marker in the same row or column (with only air/'.' between)" % where)
				"m":
					var found := false
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var p: Vector2i = Vector2i(x, y) + d
						while cell(r, p.x, p.y) != "" and cell(r, p.x, p.y) != "m" and not cell(r, p.x, p.y) in ["#"]:
							if cell(r, p.x, p.y) == "M":
								found = true
								break
							p += d
						if found:
							break
					if not found:
						ch.errors.append("%s: 'm' (platform end) has no 'M' in the same row or column" % where)
				"c":
					ch.collectible_total += 1
	if r.spawns.is_empty():
		ch.errors.append("%s:%d: room '%s' has no spawn point 'P'" % [file, r.line, r.id])
	if r.chase > 0.0 and darkness != 1:
		ch.errors.append("%s:%d: room '%s' has 'chase:' but %d darkness origins 'D' (need exactly 1)" % [file, r.line, r.id, darkness])
	r["exit_count"] = exits


# M için eşleşen m (aynı satır/sütunda, arada '#', 'M' yok). Yoksa (-1,-1).
static func _platform_partner(r: Dictionary, x: int, y: int) -> Vector2i:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var p: Vector2i = Vector2i(x, y) + d
		while true:
			var c := cell(r, p.x, p.y)
			if c == "" or c == "#" or c == "M":
				break
			if c == "m":
				return p
			p += d
	return Vector2i(-1, -1)


static func platform_partner(r: Dictionary, x: int, y: int) -> Vector2i:
	return _platform_partner(r, x, y)


# Oda kenarındaki açıklıklar -> komşu oda bağlantıları.
static func _compute_links(ch: Dictionary, file: String) -> void:
	var exit_total := 0
	for r in ch.rooms:
		exit_total += int(r.get("exit_count", 0))
		r.links = []
		var by_target := {}
		var outside := {"left": 0, "right": 0, "top": 0}
		var blocked := []
		for side in ["left", "right", "top", "bottom"]:
			var n: int = r.h if side in ["left", "right"] else r.w
			for i in n:
				var lx := 0
				var ly := 0
				var ox := 0
				var oy := 0
				match side:
					"left":
						lx = 0; ly = i; ox = -1; oy = 0
					"right":
						lx = r.w - 1; ly = i; ox = 1; oy = 0
					"top":
						lx = i; ly = 0; ox = 0; oy = -1
					"bottom":
						lx = i; ly = r.h - 1; ox = 0; oy = 1
				var c: String = r.rows[ly][lx]
				if c == "#":
					continue
				var wc := world_cell(ch, r.x + lx + ox, r.y + ly + oy)
				if wc[1] == -1:
					if side != "bottom":
						outside[side] += 1
					continue
				if wc[0] == "#":
					blocked.append("%s %d" % [side, i])
					continue
				var key := "%d:%s" % [wc[1], side]
				if not by_target.has(key):
					by_target[key] = {"to": wc[1], "side": side, "cells": []}
				by_target[key].cells.append(Vector2i(lx, ly))
		for k in by_target:
			r.links.append(by_target[k])
		for side in outside:
			if outside[side] > 0:
				ch.warnings.append("%s:%d: room '%s': %d open border cell(s) on the %s side lead outside every room (an invisible wall blocks them)" % [file, r.line, r.id, outside[side], side])
		if not blocked.is_empty():
			ch.warnings.append("%s:%d: room '%s': opening(s) at %s run into '#' of the neighbouring room" % [file, r.line, r.id, ", ".join(PackedStringArray(blocked))])
	if exit_total == 0:
		ch.errors.append("%s: no chapter exit 'E' in any room" % file)
	elif exit_total > 1:
		ch.warnings.append("%s: %d chapter exits 'E' (usually exactly one)" % [file, exit_total])


static func _check_reachability(ch: Dictionary, file: String) -> void:
	var rooms: Array = ch.rooms
	var seen := {0: true}
	var queue := [0]
	while not queue.is_empty():
		var i: int = queue.pop_front()
		for l in rooms[i].links:
			if not seen.has(l.to):
				seen[l.to] = true
				queue.append(l.to)
	for r in rooms:
		if not seen.has(r.index):
			ch.errors.append("%s:%d: room '%s' is unreachable from the first room '%s' (no chain of border openings connects them)" % [file, r.line, r.id, rooms[0].id])
		if r.links.is_empty() and int(r.get("exit_count", 0)) == 0 and rooms.size() > 1:
			ch.errors.append("%s:%d: room '%s' has no openings to other rooms and no exit 'E' (dead end)" % [file, r.line, r.id])
		if r.chase > 0.0 and chase_goal(ch, r) == Vector2i(-1, -1):
			ch.errors.append("%s:%d: chase room '%s' needs an opening to the next room (file order) or an exit 'E' as the darkness goal" % [file, r.line, r.id])
	# Sıradaki oda bağlantısı (oda numarası = dosya sırası); uyarı olarak
	for i in range(rooms.size() - 1):
		var linked := false
		for l in rooms[i].links:
			if l.to == i + 1:
				linked = true
		if not linked:
			ch.warnings.append("%s:%d: room '%s' has no opening into the next room in file order ('%s'); room numbers in the HUD follow file order" % [file, rooms[i].line, rooms[i].id, rooms[i + 1].id])


# Kovalamaca hedefi (yerel hücre): sıradaki odaya açıklık, yoksa E. Bulunamazsa (-1,-1).
static func chase_goal(ch: Dictionary, r: Dictionary) -> Vector2i:
	for l in r.links:
		if l.to == r.index + 1 and not l.cells.is_empty():
			return l.cells[l.cells.size() / 2]
	for y in r.h:
		for x in r.w:
			if r.rows[y][x] == "E":
				return Vector2i(x, y)
	return Vector2i(-1, -1)


static func summary(ch: Dictionary) -> String:
	var out := PackedStringArray()
	out.append("chapter '%s' theme=%s rooms=%d collectibles=%d" % [ch.title, ch.theme, ch.rooms.size(), ch.collectible_total])
	for r in ch.rooms:
		var flags := PackedStringArray()
		if r.dark:
			flags.append("dark")
		if r.drain:
			flags.append("drain")
		if r.chase > 0.0:
			flags.append("chase=%s" % str(r.chase))
		var links := PackedStringArray()
		for l in r.links:
			links.append("%s->%s" % [l.side, ch.rooms[l.to].id])
		out.append("  #%d %-12s at (%d,%d) size %dx%d spawns=%d %s links: %s" % [r.index + 1, r.id, r.x, r.y, r.w, r.h, r.spawns.size(), " ".join(flags), ", ".join(links)])
	return "\n".join(out)
