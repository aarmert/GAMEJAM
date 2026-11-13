extends Node

# AudioManager (autoload) — müzik, ambiyans, SFX ve ayak sesleri.
#
# - Aktif sahne değişince (SceneTransition veya reload) sahne yoluna göre müzik + ambiyans seçer,
#   aynı parça zaten çalıyorsa dokunmaz (ölünce müzik baştan başlamaz), farklıysa crossfade yapar.
# - level1'deki kovalamaca müziği (Manager_Darkness/Muzik) sahnede kalır; burada sadece "Music"
#   bus'ına taşınır ve seviyesi diğer parçalarla dengelenir.
# - Oyuncuya otomatik bir PlayerAudio düğümü ekler (ayak sesi, iniş, fener sesleri).
#
# Kullanım:
#   AudioManager.play_sfx("jump")            # pitch_jitter varsayılan 0.05
#   AudioManager.play_sfx("hurt", 0.1)
#   AudioManager.play_footstep(AudioManager.get_surface_at(pos))

const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"
const AMBIENT_BUS := &"Ambient"

const MUSIC := {
	"menu": "res://audio/music/menu_theme.ogg",
	"forest": "res://audio/music/forest_theme.ogg",
	"lantern": "res://audio/music/lantern_cave.ogg",
}
const ENDING_STING := "res://audio/music/ending_sting.ogg"

const AMBIENT := {
	"forest": "res://audio/ambient/forest_ambient.ogg",
	"cave": "res://audio/ambient/cave_ambient.ogg",
}

# Sahne -> ses ayarı. music/ambient boş string = o katman susar.
# ambient_db: ambiyans seviyesi (dB), surface: karonun tanınamadığı durumda ayak sesi zemini.
const SCENE_AUDIO := {
	"res://scenes/main_menu.tscn": {"music": "menu", "ambient": "forest", "ambient_db": -12.0, "surface": "grass"},
	"res://scenes/levels/3_part.tscn": {"music": "forest", "ambient": "forest", "ambient_db": 0.0, "surface": "grass"},
	"res://scenes/levels/level2.tscn": {"music": "forest", "ambient": "forest", "ambient_db": 0.0, "surface": "grass"},
	# Kovalamaca bölümü: kendi müziği var (canavar_escape) -> sadece sessiz mağara ambiyansı
	"res://scenes/levels/level1.tscn": {"music": "", "ambient": "cave", "ambient_db": -4.0, "surface": "stone"},
	"res://scenes/levels/level1_2.tscn": {"music": "lantern", "ambient": "cave", "ambient_db": 0.0, "surface": "stone"},
}
const ENDING_FROM_SCENE := "res://scenes/levels/level1_2.tscn"

# Sahnede bulunup Music bus'ına taşınacak hazır müzik düğümleri (level1 kovalamaca müziği)
const SCENE_MUSIC_NODE_NAMES := ["Muzik"]
const SCENE_MUSIC_NODE_DB := -5.0  # canavar_escape.wav ~ -12 LUFS, bizim parçalar ~ -17 LUFS

const SFX := {
	"jump": "res://audio/sfx/jump.wav",
	"orb_jump": "res://audio/sfx/orb_jump.wav",
	"land": "res://audio/sfx/land.wav",
	"dash": "res://audio/sfx/dash.wav",
	"orb_dash": "res://audio/sfx/orb_dash.wav",
	"hurt": "res://audio/sfx/hurt.wav",
	"death": "res://audio/sfx/death.wav",
	"heal": "res://audio/sfx/heal.wav",
	"checkpoint": "res://audio/sfx/checkpoint.wav",
	"pickup": "res://audio/sfx/pickup.wav",
	"lantern_pickup": "res://audio/sfx/lantern_pickup.wav",
	"lantern_on": "res://audio/sfx/lantern_on.wav",
	"lantern_off": "res://audio/sfx/lantern_off.wav",
	"lantern_empty": "res://audio/sfx/lantern_empty.wav",
	"ui_hover": "res://audio/sfx/ui_hover.wav",
	"ui_click": "res://audio/sfx/ui_click.wav",
	"ui_start": "res://audio/sfx/ui_start.wav",
	"whoosh": "res://audio/sfx/whoosh.wav",
}
# Ses başına ek seviye (dB) ve aynı sesin en sık tekrar aralığı (s)
const SFX_DB := {"land": -4.0, "heal": -6.0, "whoosh": -6.0, "ui_hover": -4.0, "lantern_off": -2.0}
const SFX_MIN_INTERVAL := {"hurt": 0.25, "land": 0.08, "heal": 0.3, "ui_hover": 0.05}

const FOOTSTEPS := {
	"grass": ["res://audio/footsteps/grass_0.wav", "res://audio/footsteps/grass_1.wav",
		"res://audio/footsteps/grass_2.wav", "res://audio/footsteps/grass_3.wav",
		"res://audio/footsteps/grass_4.wav"],
	"stone": ["res://audio/footsteps/stone_0.wav", "res://audio/footsteps/stone_1.wav",
		"res://audio/footsteps/stone_2.wav", "res://audio/footsteps/stone_3.wav",
		"res://audio/footsteps/stone_4.wav"],
}
const FOOTSTEP_DB := {"grass": -9.0, "stone": -10.0}

# Tileset texture yolu içindeki anahtar kelime -> zemin
const SURFACE_KEYWORDS := [
	["deepcave", "stone"],
	["cave", "stone"],
	["tileset-sheet", "grass"],
	["grass", "grass"],
]

const CROSSFADE_TIME := 1.5
const SFX_POOL_SIZE := 16

var current_music_key := ""
var current_ambient_key := ""

var _music_players: Array[AudioStreamPlayer] = []
var _music_idx := 0
var _ambient_players: Array[AudioStreamPlayer] = []
var _ambient_idx := 0
var _sting_player: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _streams := {}
var _last_played := {}
var _last_footstep := {}
var _surface_cache := {}
var _tilemaps: Array[Node] = []
var _last_scene: Node = null
var _scene_surface := "grass"
var _music_tweens := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	for i in 2:
		_music_players.append(_make_player("Music%d" % i, MUSIC_BUS))
		_ambient_players.append(_make_player("Ambient%d" % i, AMBIENT_BUS))
	_sting_player = _make_player("Sting", MUSIC_BUS)
	for i in SFX_POOL_SIZE:
		_sfx_pool.append(_make_player("Sfx%d" % i, SFX_BUS))
	var st := get_node_or_null("/root/SceneTransition")
	if st != null and st.has_signal("transition_started"):
		st.transition_started.connect(_on_transition_started)


func _exit_tree() -> void:
	# Çıkışta çalan stream'leri bırak (yoksa "resources still in use at exit" uyarısı)
	for p in _music_players + _ambient_players + _sfx_pool + [_sting_player]:
		p.stop()
		p.stream = null
	_streams.clear()


func _process(_delta: float) -> void:
	var scene := get_tree().current_scene
	if scene != _last_scene and scene != null and scene.is_node_ready():
		_last_scene = scene
		_on_scene_changed(scene)


# ------------------------------------------------------------------ public API

func play_sfx(sfx_name: String, pitch_jitter: float = 0.05, volume_db: float = 0.0) -> void:
	if not SFX.has(sfx_name):
		push_warning("[AudioManager] bilinmeyen sfx: %s" % sfx_name)
		return
	var now := Time.get_ticks_msec() / 1000.0
	var min_gap: float = SFX_MIN_INTERVAL.get(sfx_name, 0.0)
	if min_gap > 0.0 and now - float(_last_played.get(sfx_name, -100.0)) < min_gap:
		return
	_last_played[sfx_name] = now
	_play_stream(_get_stream(SFX[sfx_name]), volume_db + float(SFX_DB.get(sfx_name, 0.0)), pitch_jitter)
	if sfx_name == "death":
		duck_music(-10.0, 2.5)


func play_footstep(surface: String = "", volume_db: float = 0.0) -> void:
	if surface.is_empty() or not FOOTSTEPS.has(surface):
		surface = _scene_surface
	var list: Array = FOOTSTEPS[surface]
	var idx := randi() % list.size()
	if list.size() > 1 and idx == int(_last_footstep.get(surface, -1)):
		idx = (idx + 1) % list.size()  # aynı örneği arka arkaya çalma
	_last_footstep[surface] = idx
	_play_stream(_get_stream(list[idx]), float(FOOTSTEP_DB[surface]) + volume_db, 0.08)


func get_scene_surface() -> String:
	return _scene_surface


## Dünya koordinatındaki karonun zeminini döndürür ("grass" / "stone"); bulunamazsa sahne varsayılanı.
func get_surface_at(world_pos: Vector2) -> String:
	var surf := find_surface_at(world_pos)
	return _scene_surface if surf.is_empty() else surf


## Aynısı ama tanınan karo yoksa "" döner.
func find_surface_at(world_pos: Vector2) -> String:
	for tm in _tilemaps:
		if not is_instance_valid(tm) or not tm.is_visible_in_tree():
			continue
		var surf := _surface_in_tilemap(tm, world_pos)
		if not surf.is_empty():
			return surf
	return ""


func play_music(key: String, fade: float = CROSSFADE_TIME) -> void:
	if key == current_music_key:
		return
	current_music_key = key
	_crossfade(_music_players, true, MUSIC.get(key, ""), 0.0, fade)


func play_ambient(key: String, volume_db: float = 0.0, fade: float = CROSSFADE_TIME) -> void:
	if key == current_ambient_key:
		var cur := _ambient_players[_ambient_idx]
		_tween_db(cur, volume_db, fade)
		return
	current_ambient_key = key
	_crossfade(_ambient_players, false, AMBIENT.get(key, ""), volume_db, fade)


func play_ending_sting() -> void:
	play_music("", 0.8)
	_sting_player.stream = _get_stream(ENDING_STING)
	_sting_player.volume_db = 0.0
	_sting_player.play()


func duck_music(amount_db: float, duration: float) -> void:
	var p := _music_players[_music_idx]
	if not p.playing:
		return
	if _music_tweens.has(p) and _music_tweens[p] is Tween and _music_tweens[p].is_valid():
		_music_tweens[p].kill()
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(p, "volume_db", amount_db, 0.15)
	tw.tween_interval(duration)
	tw.tween_property(p, "volume_db", 0.0, 1.0)
	_music_tweens[p] = tw


## Test/teşhis için: şu an çalan müzik ve ambiyans dosyaları.
func get_debug_state() -> Dictionary:
	var m := _music_players[_music_idx]
	var a := _ambient_players[_ambient_idx]
	return {
		"scene": _last_scene.scene_file_path if is_instance_valid(_last_scene) else "",
		"music_key": current_music_key,
		"music_stream": m.stream.resource_path if (m.playing and m.stream) else "",
		"ambient_key": current_ambient_key,
		"ambient_stream": a.stream.resource_path if (a.playing and a.stream) else "",
		"surface_default": _scene_surface,
	}


# ------------------------------------------------------------------ internals

func _on_scene_changed(scene: Node) -> void:
	var path := scene.scene_file_path
	var cfg: Dictionary = SCENE_AUDIO.get(path, {})
	if cfg.is_empty():
		push_warning("[AudioManager] %s için ses ayarı yok, mevcut müzik devam ediyor" % path)
	else:
		_scene_surface = cfg.get("surface", "grass")
		play_music(cfg.get("music", ""))
		play_ambient(cfg.get("ambient", ""), float(cfg.get("ambient_db", 0.0)))
	_route_scene_music(scene)
	_collect_tilemaps(scene)
	_attach_player_audio()


func _on_transition_started() -> void:
	play_sfx("whoosh", 0.0)
	if is_instance_valid(_last_scene) and _last_scene.scene_file_path == ENDING_FROM_SCENE:
		play_ending_sting()


func _route_scene_music(scene: Node) -> void:
	for node_name in SCENE_MUSIC_NODE_NAMES:
		for n in scene.find_children(node_name, "", true, false):
			if n is AudioStreamPlayer or n is AudioStreamPlayer2D:
				n.bus = MUSIC_BUS
				n.volume_db = SCENE_MUSIC_NODE_DB


func _collect_tilemaps(scene: Node) -> void:
	_tilemaps.clear()
	_surface_cache.clear()
	for n in scene.find_children("*", "TileMap", true, false):
		_tilemaps.append(n)
	for n in scene.find_children("*", "TileMapLayer", true, false):
		_tilemaps.append(n)


func _attach_player_audio() -> void:
	for p in get_tree().get_nodes_in_group("player"):
		if p is CharacterBody2D and p.get_node_or_null("PlayerAudio") == null:
			var pa := preload("res://scripts/audio/player_audio.gd").new()
			pa.name = "PlayerAudio"
			p.add_child(pa)


func _surface_in_tilemap(tm: Node, world_pos: Vector2) -> String:
	var tile_set: TileSet = tm.tile_set
	if tile_set == null:
		return ""
	var cell: Vector2i = tm.local_to_map(tm.to_local(world_pos))
	if tm is TileMap:
		for layer in tm.get_layers_count():
			if not tm.is_layer_enabled(layer):
				continue
			var surf := _surface_for_source(tile_set, tm.get_cell_source_id(layer, cell))
			if not surf.is_empty():
				return surf
		return ""
	return _surface_for_source(tile_set, tm.get_cell_source_id(cell))


func _surface_for_source(tile_set: TileSet, source_id: int) -> String:
	if source_id < 0 or not tile_set.has_source(source_id):
		return ""
	var key := "%d:%d" % [tile_set.get_instance_id(), source_id]
	if _surface_cache.has(key):
		return _surface_cache[key]
	var surf := ""
	var src := tile_set.get_source(source_id) as TileSetAtlasSource
	if src != null and src.texture != null:
		var tex_path: String = src.texture.resource_path.get_file().to_lower()
		for pair in SURFACE_KEYWORDS:
			if tex_path.contains(pair[0]):
				surf = pair[1]
				break
	_surface_cache[key] = surf
	return surf


func _ensure_buses() -> void:
	for bus_name in [MUSIC_BUS, SFX_BUS, AMBIENT_BUS]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, &"Master")


func _make_player(node_name: String, bus: StringName) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = node_name
	p.bus = bus
	add_child(p)
	return p


func _get_stream(path: String) -> AudioStream:
	if path.is_empty():
		return null
	if not _streams.has(path):
		var s: AudioStream = load(path)
		_streams[path] = s
	return _streams[path]


func _play_stream(stream: AudioStream, volume_db: float, pitch_jitter: float) -> void:
	if stream == null:
		return
	var p := _sfx_pool[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_pool.size()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func _crossfade(players: Array[AudioStreamPlayer], is_music: bool, path: String, target_db: float, fade: float) -> void:
	var idx := _music_idx if is_music else _ambient_idx
	var old := players[idx]
	var nxt := players[1 - idx]
	if old.playing:
		_tween_db(old, -60.0, fade, true)
	if path.is_empty():
		return
	var stream := _get_stream(path)
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	nxt.stream = stream
	nxt.volume_db = -40.0
	nxt.play()
	_tween_db(nxt, target_db, fade)
	if is_music:
		_music_idx = 1 - idx
	else:
		_ambient_idx = 1 - idx


func _tween_db(p: AudioStreamPlayer, db: float, time: float, stop_after := false) -> void:
	if _music_tweens.has(p) and _music_tweens[p] is Tween and _music_tweens[p].is_valid():
		_music_tweens[p].kill()
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(p, "volume_db", db, max(time, 0.01))
	if stop_after:
		tw.tween_callback(p.stop)
	_music_tweens[p] = tw
