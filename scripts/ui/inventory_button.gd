class_name InventoryButton
extends Button
## Botão da HUD que abre o inventário. Está no grupo "touch_blocker",
## então o MobileControls não usa esse toque para girar a câmera.

@export var inventory_screen_path: NodePath


func _ready() -> void:
	add_to_group("touch_blocker")
	theme = UiTheme.get_theme()
	focus_mode = Control.FOCUS_NONE
	icon = load("res://assets/icons/ui/bag.svg")
	expand_icon = true
	pressed.connect(_on_pressed)
	Events.modal_changed.connect(func(open: bool) -> void: visible = not open)


func _on_pressed() -> void:
	GameSettings.vibrate()
	(get_node(inventory_screen_path) as InventoryScreen).open()
