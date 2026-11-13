extends Area2D

# Karakter bu alana girdiginde sonraki sahneye geçer.
#
# Inspector'da ayarla:
#   - next_scene_path: Geçilecek sahnenin yolu, ör. "res://scenes/levels/level2.tscn"
#   - story_lines: Geçis sirasinda gösterilecek hikaye satirlari (bos birakilabilir)
#   - story_image_paths: Geçis sirasinda gösterilecek cutscene görselleri (bos birakilabilir)
#   - trigger_group: Tetikleyici grup (varsayilan "player")
#
# Tek seferlik tetiklenir — üzerine tekrar girilse de bir daha çalismaz.
#
# Görsel: animasyonlu portal (assets/portal-Sheet.png, 3 kare 32x64) + yumusak isik.
# Sahnenin orijini 32x64'lük çarpisma kutusunun merkezidir; portalin alt kenari kutunun
# alt kenarina oturur. Yani zemin üstüne koymak için: position.y = zemin_y - 32.

@export_file("*.tscn") var next_scene_path: String = ""
@export var story_lines: PackedStringArray = PackedStringArray()
@export var story_image_paths: PackedStringArray = PackedStringArray()
@export var trigger_group: String = "player"

var _triggered: bool = false


func _ready() -> void:
	# Editor'da yanlislikla collision_layer/mask sifir kalmasin diye guard:
	# Bu Area2D player'i tespit etmeli — layer 1 ve 2 ikisini de kapsa.
	if collision_mask == 0:
		collision_mask = 3

	body_entered.connect(_on_body_entered)
	_start_light_pulse()


func _start_light_pulse() -> void:
	var light := get_node_or_null("PortalLight") as PointLight2D
	if light == null:
		return
	var base := light.energy
	var tw := create_tween().set_loops()
	# Önizleme kamerasi oyunu durdururken de portal "nefes alsin"
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(light, "energy", base * 1.35, 1.1)
	tw.tween_property(light, "energy", base * 0.8, 1.1)


func _on_body_entered(body: Node) -> void:
	if _triggered:
		return
	if not body.is_in_group(trigger_group):
		return
	if next_scene_path.is_empty():
		push_warning("[LevelExit] next_scene_path bos — geçis yapilamaz (%s)" % name)
		return

	_triggered = true
	_freeze_player(body)

	# SceneTransition autoload'i kayitliysa onu kullan, degilse direkt sahne degistir
	var st := get_node_or_null("/root/SceneTransition")
	if st != null and st.has_method("transition_to"):
		st.transition_to(next_scene_path, story_lines, story_image_paths)
	else:
		push_warning("[LevelExit] SceneTransition autoload bulunamadi — direkt geçis yapiliyor")
		Engine.time_scale = 1.0
		get_tree().change_scene_to_file(next_scene_path)


# Geçis (fade + hikaye ekrani) sürerken oyuncu yürümeye devam etmesin ve karanlik
# hasari yüzünden ekran kararmisken ölüp sahneyi yeniden yüklemesin.
func _freeze_player(body: Node) -> void:
	if body is CharacterBody2D:
		(body as CharacterBody2D).velocity = Vector2.ZERO
	body.set_physics_process(false)
	if "safe_zones" in body:
		body.safe_zones += 1
	if body is CanvasItem:
		var tw := create_tween()
		tw.tween_property(body, "modulate:a", 0.0, 0.5)
