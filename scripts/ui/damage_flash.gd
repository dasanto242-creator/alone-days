class_name DamageFlash
extends ColorRect
## Borda vermelha que pisca quando o jogador leva dano e some aos poucos.

var _strength := 0.0


func _ready() -> void:
	color = Color(0.6, 0.0, 0.0, 0.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Events.player_damaged.connect(_on_damaged)
	set_process(false)


func _on_damaged(amount: float) -> void:
	_strength = clampf(_strength + 0.25 + amount * 0.015, 0.0, 0.6)
	color.a = _strength
	set_process(true)


func _process(delta: float) -> void:
	_strength = maxf(_strength - delta * 0.8, 0.0)
	color.a = _strength
	if _strength <= 0.0:
		set_process(false)
