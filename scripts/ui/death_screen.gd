class_name DeathScreen
extends Control
## Tela exibida quando o sobrevivente morre.


func _ready() -> void:
	visible = false
	theme = UiTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.02, 0.02, 0.82)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 24)
	add_child(box)
	var title := Label.new()
	title.text = "VOCÊ NÃO SOBREVIVEU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.78, 0.3, 0.25))
	box.add_child(title)
	var button := Button.new()
	button.name = "RestartButton"
	button.text = "Recomeçar"
	button.custom_minimum_size = Vector2(240, 64)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(func() -> void: get_tree().reload_current_scene())
	box.add_child(button)
	Events.player_died.connect(_on_player_died)


func _on_player_died() -> void:
	await get_tree().create_timer(1.2).timeout
	visible = true
	Events.modal_changed.emit(true)
