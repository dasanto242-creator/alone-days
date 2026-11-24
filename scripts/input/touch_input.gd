extends Node
## Acumula a rotação de câmera pedida pelo toque (autoload "TouchInput").
## Os controles somam graus aqui; a câmera consome uma vez por frame.
## Movimento e botões NÃO passam por aqui: usam as ações do InputMap
## (Input.action_press), então teclado e toque seguem o mesmo caminho.

var _look_delta := Vector2.ZERO


func add_look(delta_degrees: Vector2) -> void:
	_look_delta += delta_degrees


func consume_look() -> Vector2:
	var delta := _look_delta
	_look_delta = Vector2.ZERO
	return delta
