extends Area2D

# Karanlık bloğu: oyuncuya değerse öldürür.
# Not: Area2D TileMap'i de "body" olarak algılar. Eskiden die() metodu olmayan her
# gövdede sahne yeniden yükleniyordu; blok bir duvara sürtününce oyun kendi kendine
# baştan başlıyordu. Artık sadece die() olan gövdelere tepki veriyoruz.


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("die"):
		body.die()
