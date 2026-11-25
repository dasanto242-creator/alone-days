class_name ItemData
extends Resource
## Definição de um tipo de item (como um "molde"). Cada item do jogo é um
## arquivo .tres em data/items/. Para criar um item novo basta criar outro
## arquivo — nenhum código novo é necessário.

enum Category { FOOD, DRINK, MEDICAL, BACKPACK, CLOTHING, TOOL, WEAPON, AMMO, MISC }
enum Slot { NONE, BACK, BODY, MELEE, SIDEARM }
enum WeaponKind { NONE, MELEE, PISTOL }
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

@export_group("Arma")
@export var weapon_kind: WeaponKind = WeaponKind.NONE
@export var damage := 0.0
## Alcance em metros (golpe ou tiro).
@export var attack_range := 1.5
@export var attack_stamina := 0.0
## Tempo mínimo entre ataques/disparos (s).
@export var attack_cooldown := 0.8
## Força de corte em árvores (0 = não corta; o machado tem 1).
@export var chop_power := 0.0
@export var magazine_size := 0
@export var ammo_item: StringName = &""

@export_group("No mundo")
## Modelo 3D (.glb). Sem modelo, usa uma forma simples (world_shape).
@export var model: PackedScene
## Rotação do modelo quando largado no chão (graus).
@export var world_rotation := Vector3.ZERO
@export var world_shape: WorldShape = WorldShape.BOX
@export var world_size := Vector3(0.2, 0.2, 0.2)
@export var world_color := Color(0.5, 0.5, 0.5)


func is_usable() -> bool:
	return not use_verb.is_empty()


func is_weapon() -> bool:
	return weapon_kind != WeaponKind.NONE


func is_equipment() -> bool:
	return equip_slot != Slot.NONE


func category_name() -> String:
	return CATEGORY_NAMES.get(category, "")
