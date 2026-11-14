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
#
# Miks hiyerarşisi (efektif seviye = dosya loudness + ses başı dB + bus dB; tablo: audio/CREDITS.md):
#   kovalamaca müziği (~-15 LUFS) > oyun SFX'i (zıplama/dash ~-18, hasar ~-15.5, ölüm ~-17 maxM)
#   > alma/iyileşme/checkpoint (~-21..-23, tık ~-34) > orman/fener/menü müziği (~-22..-23 LUFS)
#   > ambiyans (~-32..-42 LUFS). Ayak sesleri kısa ve hafif (~-40 maxM).

# ---- Genel ses ayarları (ekip buradan ayarlar; _ready'de bus'lara uygulanır) ----
const MASTER_VOLUME_DB := 0.0
const MUSIC_VOLUME_DB := -3.0
const SFX_VOLUME_DB := 0.0
const AMBIENT_VOLUME_DB := -2.0
const MASTER_LIMITER_CEILING_DB := -1.0  # Master'daki HardLimiter: üst üste binen sesler kırpılmasın

const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"
const AMBIENT_BUS := &"Ambient"

const MUSIC := {
	"menu": "res://audio/music/menu_theme.ogg",
	"forest": "res://audio/music/forest_theme.ogg",
	"lantern": "res://audio/music/lantern_cave.ogg",
}
const ENDING_STING := "res://audio/music/ending_sting.ogg"
# Parça başına seviye (dB). Dosyalar ~-17 LUFS; orman/menü oyunun arkasında kalsın diye kısık.
const MUSIC_DB := {"menu": -3.0, "forest": -3.0, "lantern": -1.0}
const ENDING_STING_DB := -1.0

const AMBIENT := {
	"forest": "res://audio/ambient/forest_ambient.ogg",
	"cave": "res://audio/ambient/cave_ambient.ogg",
}

# Sahne -> ses ayarı. music/ambient boş string = o katman susar.
# ambient_db: ambiyans seviyesi (dB), surface: karonun tanınamadığı durumda ayak sesi zemini.
const SCENE_AUDIO := {
	"res://scenes/main_menu.tscn": {"music": "menu", "ambient": "forest", "ambient_db": -13.0, "surface": "grass"},
	"res://scenes/levels/3_part.tscn": {"music": "forest", "ambient": "forest", "ambient_db": -3.0, "surface": "grass"},
	"res://scenes/levels/level2.tscn": {"music": "forest", "ambient": "forest", "ambient_db": -3.0, "surface": "grass"},
	# Kovalamaca bölümü: kendi müziği var (canavar_escape) -> sadece sessiz mağara ambiyansı
	"res://scenes/levels/level1.tscn": {"music": "", "ambient": "cave", "ambient_db": -5.0, "surface": "stone"},
	"res://scenes/levels/level1_2.tscn": {"music": "lantern", "ambient": "cave", "ambient_db": -3.0, "surface": "stone"},
	# Trials bölümleri (tema varsayılanları; kovalamaca odalarında Trials sahnesi müziği susturur,
	# tema farklıysa trials_game.gd temanın müziğine geçer)
	"res://trials/scenes/trials_chapter1.tscn": {"music": "forest", "ambient": "forest", "ambient_db": -3.0, "surface": "grass"},
	"res://trials/scenes/trials_chapter2.tscn": {"music": "lantern", "ambient": "cave", "ambient_db": -3.0, "surface": "stone"},
	"res://trials/scenes/trials_chapter3.tscn": {"music": "lantern", "ambient": "cave", "ambient_db": -3.0, "surface": "stone"},
}
const ENDING_FROM_SCENE := "res://scenes/levels/level1_2.tscn"

# Sahnede bulunup Music bus'ına taşınacak hazır müzik düğümleri (level1 kovalamaca müziği)
const SCENE_MUSIC_NODE_NAMES := ["Muzik"]
# canavar_escape.wav ~ -12.4 LUFS -> 0 dB + Music bus -3 = ~-15.4 LUFS: oyunun en yüksek müziği
# (orman ~-23, fener mağarası ~-22). Dosyanın tepe değeri ~+0.3 dBTP; Master limiter korur.
const SCENE_MUSIC_NODE_DB := 3.0

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
# Ses başına ek seviye (dB). Yorum: dosyanın max-momentary loudness'ı -> hedef efektif seviye.
const SFX_DB := {
	"jump": -8.5,            # -14.4 -> -17.9
	"orb_jump": -6.5,        # -17.5 -> -19.0
	"dash": -7.0,            # -15.6 -> -18.1
	"orb_dash": -6.0,        # -17.4 -> -18.9
	"land": -2.0,            # -26.2 -> -28.2 (kısa darbe)
	"hurt": -3.0,            # -12.5 -> -15.5
	"death": -3.0,           # -14.1 -> -17.1 (yumuşatılmış yeni ses, üstüne müzik kısılır)
	"pickup": -9.0,          # -12.8 -> -21.8
	"lantern_pickup": -8.0,  # -12.8 -> -20.8
	"checkpoint": -7.0,      # -15.9 -> -22.9 (her checkpoint'te sadece ilk sefer)
	"heal": -10.0,           # -23.6 -> -33.6 (iyileşme alanında 0.5 s'de bir tık: çok hafif)
	"lantern_on": -2.0,      # -19.8 -> -21.8
	"lantern_off": 0.0,      # -26.7
	"lantern_empty": 0.0,    # -22.9
	"ui_hover": -4.0,        # -29.3 -> -33.3
	"ui_click": -1.0,        # -21.0 -> -22.0
	"ui_start": -4.0,        # -14.7 -> -18.7
	"whoosh": -8.0,          # -15.2 -> -23.2
}
# Aynı sesin en sık tekrar aralığı (s). Listede olmayanlar SFX_DEFAULT_COOLDOWN kullanır:
# aynı karede/peş peşe gelen çağrılar (ör. birden çok tehlike aynı anda öldürürse) tek sese iner.
const SFX_DEFAULT_COOLDOWN := 0.05
const SFX_MIN_INTERVAL := {
	"hurt": 0.25, "land": 0.08, "heal": 0.45, "ui_hover": 0.05, "death": 1.0,
	"pickup": 0.3, "lantern_pickup": 0.3, "checkpoint": 0.5, "whoosh": 0.3,
}
# Aynı ses dosyasından aynı anda çalabilecek en fazla kopya (ayak sesleri dahil)
const MAX_VOICES_PER_SOUND := 2

const FOOTSTEPS := {
	"grass": ["res://audio/footsteps/grass_0.wav", "res://audio/footsteps/grass_1.wav",
		"res://audio/footsteps/grass_2.wav", "res://audio/footsteps/grass_3.wav",
		"res://audio/footsteps/grass_4.wav"],
	"stone": ["res://audio/footsteps/stone_0.wav", "res://audio/footsteps/stone_1.wav",
		"res://audio/footsteps/stone_2.wav", "res://audio/footsteps/stone_3.wav",
		"res://audio/footsteps/stone_4.wav"],
}
const FOOTSTEP_DB := {"grass": -7.0, "stone": -8.0}  # dosyalar ~-32.5 / -33 maxM

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
var _music_base_db := {}        # müzik oynatıcısı -> o parçanın normal seviyesi (duck sonrası dönülecek)
var _chimed_checkpoints := {}   # checkpoint sesi çalmış alanlar (yeniden doğunca tekrar çalmasın)
var _chime_scene_path := ""


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
	var min_gap: float = SFX_MIN_INTERVAL.get(sfx_name, SFX_DEFAULT_COOLDOWN)
	if min_gap > 0.0 and now - float(_last_played.get(sfx_name, -100.0)) < min_gap:
		return
	if sfx_name == "checkpoint" and not _claim_checkpoint_chime():
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
	_crossfade(_music_players, true, MUSIC.get(key, ""), float(MUSIC_DB.get(key, 0.0)), fade)


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
	_sting_player.volume_db = ENDING_STING_DB
	_sting_player.play()


## Müziği geçici olarak amount_db kadar kısar (ölüm sesi duyulsun), sonra parçanın normal seviyesine döner.
## level1'deki sahne müziği (Muzik) de kısılır.
func duck_music(amount_db: float, duration: float) -> void:
	var p := _music_players[_music_idx]
	if p.playing:
		if _music_tweens.has(p) and _music_tweens[p] is Tween and _music_tweens[p].is_valid():
			_music_tweens[p].kill()
		var base: float = _music_base_db.get(p, 0.0)
		var tw := create_tween()
		tw.set_ignore_time_scale(true)
		tw.tween_property(p, "volume_db", base + amount_db, 0.15)
		tw.tween_interval(duration)
		tw.tween_property(p, "volume_db", base, 1.0)
		_music_tweens[p] = tw
	if is_instance_valid(_last_scene):
		for n in _scene_music_nodes(_last_scene):
			if not n.playing:
				continue
			# tween düğümün kendisine bağlı: sahne yeniden yüklenince onunla birlikte biter
			var tw2: Tween = n.create_tween()
			tw2.set_ignore_time_scale(true)
			tw2.tween_property(n, "volume_db", SCENE_MUSIC_NODE_DB + amount_db, 0.15)
			tw2.tween_interval(duration)
			tw2.tween_property(n, "volume_db", SCENE_MUSIC_NODE_DB, 1.0)


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
	if path != _chime_scene_path:  # başka bölüme geçildi -> checkpoint sesleri yeniden çalabilir
		_chime_scene_path = path
		_chimed_checkpoints.clear()
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
	for n in _scene_music_nodes(scene):
		n.bus = MUSIC_BUS
		n.volume_db = SCENE_MUSIC_NODE_DB


func _scene_music_nodes(scene: Node) -> Array[Node]:
	var out: Array[Node] = []
	for node_name in SCENE_MUSIC_NODE_NAMES:
		for n in scene.find_children(node_name, "", true, false):
			if n is AudioStreamPlayer or n is AudioStreamPlayer2D:
				out.append(n)
	return out


## Checkpoint sesi her alan için yalnızca ilk aktivasyonda çalar. Ölüp sahne yeniden yüklenince heal.gd'nin
## 'notified' bayrağı sıfırlanır ve oyuncu alanın içinde doğar; bu yüzden hangi alanların çaldığını burada
## (sahne yolu + düğüm yolu ile) tutuyoruz. Oyuncuyu içeren alan bulunamazsa ses çalar.
func _claim_checkpoint_chime() -> bool:
	if not is_instance_valid(_last_scene):
		return true
	var keys: Array[String] = []
	for area in _last_scene.find_children("*", "Area2D", true, false):
		if "player_in_area" in area and "checkpoint_index" in area and area.get("player_in_area") != null:
			keys.append(String(_last_scene.get_path_to(area)))
	if keys.is_empty():
		return true
	var is_new := false
	for k in keys:
		if not _chimed_checkpoints.has(k):
			is_new = true
			_chimed_checkpoints[k] = true
	return is_new


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
	AudioServer.set_bus_volume_db(0, MASTER_VOLUME_DB)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(MUSIC_BUS), MUSIC_VOLUME_DB)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(SFX_BUS), SFX_VOLUME_DB)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(AMBIENT_BUS), AMBIENT_VOLUME_DB)
	# Master limiter (default_bus_layout.tres'te de var; yoksa burada eklenir)
	var limiter: AudioEffectHardLimiter = null
	for i in AudioServer.get_bus_effect_count(0):
		var fx := AudioServer.get_bus_effect(0, i)
		if fx is AudioEffectHardLimiter:
			limiter = fx
	if limiter == null:
		limiter = AudioEffectHardLimiter.new()
		AudioServer.add_bus_effect(0, limiter)
	limiter.ceiling_db = MASTER_LIMITER_CEILING_DB


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
	# aynı dosyadan zaten MAX_VOICES_PER_SOUND kopya çalıyorsa yenisini ekleme (üst üste binip patlamasın)
	var same := 0
	for q in _sfx_pool:
		if q.playing and q.stream == stream:
			same += 1
	if same >= MAX_VOICES_PER_SOUND:
		return
	# boş bir oynatıcı seç; hepsi doluysa sıradakini (en eskiyi) kes
	var p := _sfx_pool[_sfx_next]
	for i in _sfx_pool.size():
		var cand := _sfx_pool[(_sfx_next + i) % _sfx_pool.size()]
		if not cand.playing:
			p = cand
			_sfx_next = (_sfx_next + i) % _sfx_pool.size()
			break
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
	if is_music:
		_music_base_db[nxt] = target_db
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
