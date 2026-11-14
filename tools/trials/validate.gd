extends SceneTree
# Trials bölüm doğrulayıcı (headless).
#   godot --headless --path . -s tools/trials/validate.gd -- <chapter.gd|.txt> [more...] [--strict]
# Çıkış kodu: 0 = hata yok, 1 = hata var (--strict ile uyarılar da hata sayılır).
const Parser := preload("res://trials/scripts/chapter_parser.gd")
const Builder := preload("res://trials/scripts/chapter_builder.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var strict := args.has("--strict")
	var files: Array[String] = []
	for a in args:
		if not a.begins_with("--"):
			files.append(_res(a))
	if files.is_empty():
		print("usage: validate.gd -- <chapter file> [...] [--strict]")
		quit(2)
		return
	var bad := false
	for f in files:
		var ch := Parser.parse_file(f)
		print("== %s" % f)
		if not ch.rooms.is_empty():
			print(Parser.summary(ch))
		# Kurulum testi: her odayı gerçekten kur (sahne/script hatalarını yakalar)
		if ch.errors.is_empty():
			for r in ch.rooms:
				var info := Builder.build_room(ch, r)
				Builder.build_dynamic(info, {})
				info.node.free()
		for w in ch.warnings:
			print("WARNING: " + w)
		for e in ch.errors:
			print("ERROR: " + e)
		var n_err: int = ch.errors.size() + (ch.warnings.size() if strict else 0)
		print("RESULT %s: %d error(s), %d warning(s)" % [f.get_file(), ch.errors.size(), ch.warnings.size()])
		if n_err > 0:
			bad = true
	quit(1 if bad else 0)


func _res(p: String) -> String:
	if p.begins_with("res://") or p.begins_with("/") or p.begins_with("user://"):
		return p
	return "res://" + p
