extends Node
## Barramento global de eventos (autoload "Events").
## Sistemas emitem aqui; HUD e outros sistemas escutam. Assim o personagem
## nunca precisa conhecer a interface, e vice-versa.

## Ação disponível (verbo, ex.: "Pegar") e o nome do alvo (ex.: "Garrafa de água").
## Verbo vazio = nada para interagir.
signal interaction_target_changed(verb: String, target_name: String)

## Estado de movimento do jogador, usado pelos botões para mostrar se estão ativos.
signal player_movement_state_changed(is_crouching: bool, is_sprinting: bool)

## Perfil gráfico alterado (GameSettings.Quality).
signal quality_changed(level: int)

## Mensagem curta na tela (ex.: "+ Garrafa de água").
signal notify(text: String)

## Uma tela cheia (inventário, morte) abriu ou fechou: controles de jogo ficam desativados.
signal modal_changed(is_open: bool)

## O jogador morreu.
signal player_died

## Arma em mãos mudou. kind = ItemData.WeaponKind; ammo_text vazio para armas brancas.
signal weapon_state_changed(kind: int, ammo_text: String, has_weapons: bool)

## Algo foi atingido por um ataque (para efeitos e testes).
signal hit_landed(target: Node, amount: float, point: Vector3)
