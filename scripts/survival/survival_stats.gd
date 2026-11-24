class_name SurvivalStats
extends Node
## Atributos de sobrevivência: vida, fome (comida), sede (água) e stamina.
## Valores de 0 a 100. Os sistemas se influenciam:
##   - fome/sede caem com o tempo, mais rápido correndo;
##   - comida ou água zeradas tiram vida;
##   - vida só se recupera bem alimentado e hidratado;
##   - com fome ou sede, a stamina recupera mais devagar.

signal stats_changed
signal died
signal damaged(amount: float)

enum Exertion { IDLE, WALK, JOG, SPRINT }

const MAX := 100.0

@export_group("Fome e sede (minutos reais para zerar, parado)")
@export var food_minutes := 40.0
@export var water_minutes := 25.0

@export_group("Stamina")
@export var sprint_cost_per_sec := 14.0
@export var jump_cost := 12.0
@export var regen_per_sec := 22.0
@export var regen_delay := 1.0
## Depois de esgotar, só volta a correr a partir deste valor.
@export var exhausted_recover_at := 25.0

@export_group("Vida")
@export var starving_damage_per_sec := 0.25
@export var dehydration_damage_per_sec := 0.4
@export var regen_health_per_sec := 0.12

var health := MAX
var food := MAX
var water := MAX
var stamina := MAX
var is_exhausted := false
var is_dead := false

var _since_stamina_use := 99.0
var _emit_timer := 0.0

const EXERTION_MULT := {Exertion.IDLE: 1.0, Exertion.WALK: 1.0, Exertion.JOG: 1.3, Exertion.SPRINT: 2.0}


func tick(delta: float, exertion: int) -> void:
	if is_dead:
		return
	var mult: float = EXERTION_MULT.get(exertion, 1.0)
	food = maxf(food - MAX / (food_minutes * 60.0) * mult * delta, 0.0)
	water = maxf(water - MAX / (water_minutes * 60.0) * mult * delta, 0.0)

	# Stamina
	_since_stamina_use += delta
	if exertion == Exertion.SPRINT:
		spend_stamina(sprint_cost_per_sec * delta)
	elif _since_stamina_use >= regen_delay and stamina < MAX:
		stamina = minf(stamina + regen_per_sec * stamina_regen_factor() * delta, MAX)
	if is_exhausted and stamina >= exhausted_recover_at:
		is_exhausted = false

	# Vida
	var harm := 0.0
	if food <= 0.0:
		harm += starving_damage_per_sec * delta
	if water <= 0.0:
		harm += dehydration_damage_per_sec * delta
	if harm > 0.0:
		apply_damage(harm, false)
	elif health < MAX:
		health = minf(health + regen_health_per_sec * health_regen_factor() * delta, MAX)

	# Avisa a HUD 4x por segundo (evita trabalho desnecessário todo quadro)
	_emit_timer += delta
	if _emit_timer >= 0.25:
		_emit_timer = 0.0
		stats_changed.emit()


## 0 a 1: só recupera vida com comida e água acima de 50%.
func health_regen_factor() -> float:
	var lowest := minf(food, water)
	return clampf((lowest - 50.0) / 40.0, 0.0, 1.0)


## 1 normal · 0,5 com fome ou sede abaixo de 25%.
func stamina_regen_factor() -> float:
	return 0.5 if minf(food, water) < 25.0 else 1.0


func can_sprint() -> bool:
	return not is_exhausted and stamina > 0.0


func can_jump() -> bool:
	return not is_exhausted and stamina >= jump_cost


func spend_stamina(amount: float) -> void:
	stamina = maxf(stamina - amount, 0.0)
	_since_stamina_use = 0.0
	if stamina <= 0.0:
		is_exhausted = true


func apply_damage(amount: float, notify := true) -> void:
	if is_dead or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	if notify:
		damaged.emit(amount)
		stats_changed.emit()
	if health <= 0.0:
		is_dead = true
		stats_changed.emit()
		died.emit()


## Aplica o efeito de comer/beber/usar um item.
func consume(item: ItemData) -> void:
	health = minf(health + item.restore_health, MAX)
	food = minf(food + item.restore_food, MAX)
	water = minf(water + item.restore_water, MAX)
	stamina = minf(stamina + item.restore_stamina, MAX)
	stats_changed.emit()


func to_dict() -> Dictionary:
	return {"health": health, "food": food, "water": water, "stamina": stamina}


func load_dict(d: Dictionary) -> void:
	health = d.get("health", MAX)
	food = d.get("food", MAX)
	water = d.get("water", MAX)
	stamina = d.get("stamina", MAX)
	stats_changed.emit()
