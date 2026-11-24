extends SceneTree
## Ferramenta de desenvolvimento: grava as configurações do projeto (project.godot).
## Uso: godot --headless --path . -s tools/configure_project.gd

func _init() -> void:
	var s := ProjectSettings

	s.set_setting("application/config/name", "ALONE DAYS")
	s.set_setting("application/config/version", "0.1.0")
	s.set_setting("application/config/description", "Sobrevivência em mundo aberto para Android, terceira pessoa.")
	s.set_setting("application/config/icon", "res://icon.svg")
	s.set_setting("application/config/features", PackedStringArray(["4.7", "Mobile"]))
	s.set_setting("application/run/main_scene", "res://scenes/world/test_sandbox.tscn")
	s.set_setting("application/boot_splash/bg_color", Color(0.07, 0.07, 0.07))

	# Autoloads (ordem importa: Events primeiro)
	s.set_setting("autoload/Events", "*res://scripts/core/events.gd")
	s.set_setting("autoload/GameSettings", "*res://scripts/core/game_settings.gd")
	s.set_setting("autoload/Items", "*res://scripts/core/items.gd")
	s.set_setting("autoload/TouchInput", "*res://scripts/input/touch_input.gd")

	# Tela: base 1280x720, paisagem com sensor, escala para qualquer proporção
	s.set_setting("display/window/size/viewport_width", 1280)
	s.set_setting("display/window/size/viewport_height", 720)
	s.set_setting("display/window/stretch/mode", "canvas_items")
	s.set_setting("display/window/stretch/aspect", "expand")
	s.set_setting("display/window/handheld/orientation", DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	s.set_setting("display/window/energy_saving/keep_screen_on", true)

	# No PC, o mouse simula toque para testar os controles no editor
	s.set_setting("input_devices/pointing/emulate_touch_from_mouse", true)

	# Renderização para celular
	s.set_setting("rendering/renderer/rendering_method", "mobile")
	s.set_setting("rendering/renderer/rendering_method.mobile", "mobile")
	s.set_setting("rendering/rendering_device/fallback_to_opengl3", true)
	s.set_setting("rendering/textures/vram_compression/import_etc2_astc", true)
	s.set_setting("rendering/anti_aliasing/quality/msaa_3d", 0)

	# Física
	s.set_setting("physics/3d/physics_engine", "Jolt Physics")
	s.set_setting("physics/common/physics_ticks_per_second", 60)
	s.set_setting("physics/common/physics_interpolation", true)

	# Camadas de física
	s.set_setting("layer_names/3d_physics/layer_1", "world")
	s.set_setting("layer_names/3d_physics/layer_2", "player")
	s.set_setting("layer_names/3d_physics/layer_3", "interactable")
	s.set_setting("layer_names/3d_physics/layer_4", "trigger")

	# Ações (teclado para testar no PC; no celular os controles touch acionam as mesmas)
	_action("move_forward", [KEY_W, KEY_UP], 0.05)
	_action("move_back", [KEY_S, KEY_DOWN], 0.05)
	_action("move_left", [KEY_A, KEY_LEFT], 0.05)
	_action("move_right", [KEY_D, KEY_RIGHT], 0.05)
	_action("sprint", [KEY_SHIFT])
	_action("jump", [KEY_SPACE])
	_action("crouch", [KEY_C])
	_action("interact", [KEY_E])
	_action("inventory", [KEY_TAB, KEY_I])

	var err := s.save()
	print("configure_project: ", "OK" if err == OK else "ERRO %d" % err)
	quit(0 if err == OK else 1)


func _action(action_name: String, keys: Array, deadzone := 0.5) -> void:
	var events: Array = []
	for key in keys:
		var ev := InputEventKey.new()
		ev.device = -1  # qualquer teclado
		ev.physical_keycode = key
		events.append(ev)
	ProjectSettings.set_setting("input/" + action_name, {"deadzone": deadzone, "events": events})
