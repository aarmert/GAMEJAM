extends RefCounted
# Trials en iyi sonuçları: user://trials_progress.cfg
# Best results per chapter: [chapterN] cleared, best_time, best_deaths, best_collectibles, collectibles_total

const PATH := "user://trials_progress.cfg"


static func load_all() -> ConfigFile:
	var cf := ConfigFile.new()
	cf.load(PATH)
	return cf


static func get_best(chapter_id: String) -> Dictionary:
	var cf := load_all()
	if not cf.has_section(chapter_id):
		return {}
	var out := {}
	for k in cf.get_section_keys(chapter_id):
		out[k] = cf.get_value(chapter_id, k)
	return out


## Sonucu kaydeder, eski en iyilerle karşılaştırır. Döner: {new_time, new_deaths, new_collectibles, best...}
static func record(chapter_id: String, stats: Dictionary) -> Dictionary:
	var cf := load_all()
	var had := cf.has_section(chapter_id)
	var bt: float = cf.get_value(chapter_id, "best_time", INF)
	var bd: int = cf.get_value(chapter_id, "best_deaths", 1 << 30)
	var bc: int = cf.get_value(chapter_id, "best_collectibles", -1)
	var res := {
		"new_time": stats.time < bt,
		"new_deaths": stats.deaths < bd,
		"new_collectibles": stats.collectibles > bc and had,
		"first_clear": not had,
	}
	cf.set_value(chapter_id, "cleared", true)
	cf.set_value(chapter_id, "best_time", minf(bt, stats.time))
	cf.set_value(chapter_id, "best_deaths", mini(bd, stats.deaths))
	cf.set_value(chapter_id, "best_collectibles", maxi(bc, stats.collectibles))
	cf.set_value(chapter_id, "collectibles_total", stats.collectibles_total)
	cf.set_value(chapter_id, "clears", int(cf.get_value(chapter_id, "clears", 0)) + 1)
	cf.save(PATH)
	res["best_time"] = minf(bt, stats.time)
	res["best_deaths"] = mini(bd, stats.deaths)
	res["best_collectibles"] = maxi(bc, stats.collectibles)
	return res


static func format_time(t: float) -> String:
	if t == INF or t < 0.0:
		return "--:--.--"
	var cs := int(round(t * 100.0))
	var m := cs / 6000
	var s := (cs / 100) % 60
	return "%d:%02d.%02d" % [m, s, cs % 100]
