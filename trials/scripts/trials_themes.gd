extends RefCounted
# Trials temaları: karo seti (mevcut doku sayfaları), otomatik kenar/köşe seçimi, arka plan.
# Kenar/köşe eşlemesi el yapımı bölümlerdeki (level2 / level1 / level1_2) kullanım istatistiğinden çıkarıldı.
# Themes: tileset built from the existing sheets, automatic edge/corner selection, backgrounds.

const FOREST_SHEET := "res://assets/tileset-Sheet.png"
const CAVE_SHEET := "res://assets/DeepCaveTile-Sheet-export-export.png"

const SRC_FOREST := 0
const SRC_CAVE := 1

# Katmanlar: 0 = katı (çarpışma + ışık engeli; Manager_Darkness ve sarmaşık bunu okur),
# 1 = tek yönlü platform, 2 = tehlike süsü (x hücreleri, çarpışmasız)
const LAYER_SOLID := 0
const LAYER_ONEWAY := 1
const LAYER_DECOR := 2

# Otomatik karo kuralları. Anahtarlar: fill, top[], bottom[], left_edge (W boş), right_edge (E boş),
# nw/ne/sw/se dış köşe, in_nw/in_ne/in_se/in_sw iç köşe (yalnız o çapraz boş).
const RULES_FOREST := {
	"src": SRC_FOREST,
	"fill": [Vector2i(0, 3)],
	"top": [Vector2i(2, 3), Vector2i(3, 0)],
	"bottom": [Vector2i(0, 2)],
	"w_edge": [Vector2i(3, 2)],
	"e_edge": [Vector2i(2, 2)],
	"nw": Vector2i(1, 1), "ne": Vector2i(2, 1), "sw": Vector2i(4, 3), "se": Vector2i(0, 4),
	"in_nw": Vector2i(3, 3), "in_ne": Vector2i(1, 3), "in_se": Vector2i(4, 1), "in_sw": Vector2i(1, 2),
}
const RULES_CAVE := {
	"src": SRC_CAVE,
	"fill": [Vector2i(4, 5)],
	"top": [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)],
	"bottom": [Vector2i(3, 4), Vector2i(4, 4)],
	"w_edge": [Vector2i(4, 2), Vector2i(3, 3)],
	"e_edge": [Vector2i(1, 3), Vector2i(0, 2)],
	"nw": Vector2i(0, 0), "ne": Vector2i(4, 0), "sw": Vector2i(2, 4), "se": Vector2i(1, 5),
	"in_nw": Vector2i(1, 4), "in_ne": Vector2i(4, 3), "in_se": Vector2i(0, 1), "in_sw": Vector2i(3, 1),
}

# Tek yönlü platform karoları (orman sayfası, ince kenar): tek, sol uç, orta, sağ uç
const ONEWAY_SINGLE := Vector2i(0, 1)
const ONEWAY_LEFT := Vector2i(1, 4)
const ONEWAY_MID := Vector2i(2, 4)
const ONEWAY_RIGHT := Vector2i(3, 4)
# Tehlike (x) süsü: mağara sayfasındaki kırmızı kristal sütunu (iki yarım)
const HAZARD_A := Vector2i(2, 5)
const HAZARD_B := Vector2i(3, 5)

const FOREST_BG := [
	"res://assets/parallax-demon-woods-bg.png",
	"res://assets/parallax-demon-woods-far-trees.png",
	"res://assets/parallax-demon-woods-mid-trees.png",
	"res://assets/parallax-demon-woods-close-trees.png",
]
const CAVE_BG := [
	"res://assets/DeepCaveBG-Base.png",
	"res://assets/DeepCaveBG-Layer1.png",
	"res://assets/DeepCaveBG-Layer2.png",
	"res://assets/DeepCaveBG-Layer3.png",
]

# music: AudioManager MUSIC anahtarı ("" = sessiz); surface: ayak sesi zemini
const THEMES := {
	"forest": {
		"rules": "forest", "bg": FOREST_BG, "parallax": [0.05, 0.15, 0.3, 0.5],
		"world": Color(1, 1, 1), "bg_mod": Color(1, 1, 1), "dark": Color(0.16, 0.15, 0.22),
		"music": "forest", "ambient": "forest", "ambient_db": -3.0, "clear": Color(0.04, 0.03, 0.07),
	},
	"cave": {
		"rules": "cave", "bg": CAVE_BG, "parallax": [0.05, 0.15, 0.3, 0.5],
		"world": Color(1, 1, 1), "bg_mod": Color(0.85, 0.85, 0.95), "dark": Color(0.16, 0.16, 0.22),
		"music": "lantern", "ambient": "cave", "ambient_db": -3.0, "clear": Color(0.03, 0.03, 0.05),
	},
	"deep": {
		"rules": "deep", "bg": CAVE_BG, "parallax": [0.05, 0.15, 0.3, 0.5],
		"world": Color(0.62, 0.6, 0.74), "bg_mod": Color(0.45, 0.42, 0.6), "dark": Color(0.18, 0.18, 0.24),
		"music": "lantern", "ambient": "cave", "ambient_db": -3.0, "clear": Color(0.02, 0.02, 0.04),
	},
}


static func theme(id: String) -> Dictionary:
	return THEMES.get(id, THEMES["forest"])


static func rules_for(theme_id: String) -> Dictionary:
	match theme(theme_id).rules:
		"cave":
			return RULES_CAVE
		"deep":
			var r := RULES_FOREST.duplicate(true)
			r.fill = [Vector2i(4, 5)]
			r.fill_src = SRC_CAVE
			return r
	return RULES_FOREST


static var _tileset_cache: TileSet = null


# Tüm temalar aynı TileSet'i kullanır (iki kaynak). Katı karolar tam kare çarpışma + ışık engeli,
# platform karoları üst 8 px tek yönlü çarpışma, tehlike süsü çarpışmasız.
static func get_tileset() -> TileSet:
	if _tileset_cache != null:
		return _tileset_cache
	var ts := TileSet.new()
	ts.tile_size = Vector2i(32, 32)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 1)
	ts.add_occlusion_layer()
	var square := PackedVector2Array([Vector2(-16, -16), Vector2(16, -16), Vector2(16, 16), Vector2(-16, 16)])
	var top_strip := PackedVector2Array([Vector2(-16, -16), Vector2(16, -16), Vector2(16, -8), Vector2(-16, -8)])
	var oneway := [ONEWAY_SINGLE, ONEWAY_LEFT, ONEWAY_MID, ONEWAY_RIGHT]
	for sid in [SRC_FOREST, SRC_CAVE]:
		var src := TileSetAtlasSource.new()
		src.texture = load(FOREST_SHEET if sid == SRC_FOREST else CAVE_SHEET)
		src.texture_region_size = Vector2i(32, 32)
		ts.add_source(src, sid)
		var grid := src.get_atlas_grid_size()
		for ay in grid.y:
			for ax in grid.x:
				var c := Vector2i(ax, ay)
				src.create_tile(c)
				var td := src.get_tile_data(c, 0)
				if sid == SRC_FOREST and c in oneway:
					td.add_collision_polygon(0)
					td.set_collision_polygon_points(0, 0, top_strip)
					td.set_collision_polygon_one_way(0, 0, true)
				elif sid == SRC_CAVE and (c == HAZARD_A or c == HAZARD_B):
					pass
				else:
					td.add_collision_polygon(0)
					td.set_collision_polygon_points(0, 0, square)
					var occ := OccluderPolygon2D.new()
					occ.polygon = square
					td.set_occluder(0, occ)
	_tileset_cache = ts
	return ts


static func _h(x: int, y: int) -> int:
	return absi((x * 73856093) ^ (y * 19349663))


static func _pick(arr: Array, x: int, y: int) -> Vector2i:
	return arr[_h(x, y) % arr.size()]


# solid_at: Callable(wx, wy) -> bool. Döner: [source_id, atlas_coords]
static func autotile(rules: Dictionary, wx: int, wy: int, solid_at: Callable) -> Array:
	var n: bool = solid_at.call(wx, wy - 1)
	var e: bool = solid_at.call(wx + 1, wy)
	var s: bool = solid_at.call(wx, wy + 1)
	var w: bool = solid_at.call(wx - 1, wy)
	var src: int = rules.src
	if not n:
		if not w and e:
			return [src, rules.nw]
		if not e and w:
			return [src, rules.ne]
		return [src, _pick(rules.top, wx, wy)]
	if not s:
		if not w and e:
			return [src, rules.sw]
		if not e and w:
			return [src, rules.se]
		return [src, _pick(rules.bottom, wx, wy)]
	if not w:
		return [src, _pick(rules.w_edge, wx, wy)]
	if not e:
		return [src, _pick(rules.e_edge, wx, wy)]
	if not solid_at.call(wx - 1, wy - 1):
		return [src, rules.in_nw]
	if not solid_at.call(wx + 1, wy - 1):
		return [src, rules.in_ne]
	if not solid_at.call(wx + 1, wy + 1):
		return [src, rules.in_se]
	if not solid_at.call(wx - 1, wy + 1):
		return [src, rules.in_sw]
	return [int(rules.get("fill_src", src)), _pick(rules.fill, wx, wy)]
