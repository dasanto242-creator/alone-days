class_name ItemData
extends Resource
## Definição de um tipo de item (como um "molde"). Cada item do jogo é um
## arquivo .tres em data/items/. Para criar um item novo basta criar outro
## arquivo — nenhum código novo é necessário.

enum Category { FOOD, DRINK, MEDICAL, BACKPACK, CLOTHING, TOOL, WEAPON, AMMO, MISC }
enum Slot { NONE, BACK, BODY }
enum WorldShape { BOX, CYLINDER, BAG }

const CATEGORY_NAMES := {
	Category.FOOD: "Comida", Category.DRINK: "Bebida", Category.MEDICAL: "Médico",
	Category.BACKPACK: "Mochila", Category.CLOTHING: "Roupa", Category.TOOL: "Ferramenta",
	Category.WEAPON: "Arma", Category.AMMO: "Munição", Category.MISC: "Diversos",
}

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export var icon: Texture2D
@export var category: Category = Category.MISC
## Peso de UMA unidade, em kg.
@export var weight := 0.1
@export var max_stack := 1
## 0 = item sem desgaste.
@export var max_durability := 0.0

@export_group("Ao usar")
## Texto do botão principal (ex.: "Comer", "Beber"). Vazio = não pode ser usado.
@export var use_verb := ""
@export var restore_health := 0.0
@export var restore_food := 0.0
@export var restore_water := 0.0
@export var restore_stamina := 0.0

@export_group("Equipamento")
@export var equip_slot: Slot = Slot.NONE
## Capacidade extra de carga (kg) enquanto equipado.
@export var capacity_bonus := 0.0

@export_group("No mundo")
@export var world_shape: WorldShape = WorldShape.BOX
@export var world_size := Vector3(0.2, 0.2, 0.2)
@export var world_color := Color(0.5, 0.5, 0.5)


func is_usable() -> bool:
	return not use_verb.is_empty()


func is_equipment() -> bool:
	return equip_slot != Slot.NONE


func category_name() -> String:
	return CATEGORY_NAMES.get(category, "")
