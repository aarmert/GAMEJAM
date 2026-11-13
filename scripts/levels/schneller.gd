extends Area2D

# Gizli tetik: oyuncu geçince karanlığı (canavarı) hızlandırır, müzik orta/hızlı bölüme geçer.
# hiz = Manager_Darkness.speed (blok dalgası aralığı, küçük = hızlı). Müzik eşikleri:
# <= 0.115 hızlı, < 0.16 orta, diğerleri yavaş (Manager_Darkness._muzik_bolumu_sec).
@export var manager_darkness: Node2D
@export var hiz: float = 0.12


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player") or manager_darkness == null:
		return
	manager_darkness.speed = hiz
