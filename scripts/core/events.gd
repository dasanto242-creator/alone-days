extends Node
## Barramento global de eventos (autoload "Events").
## Sistemas emitem aqui; HUD e outros sistemas escutam. Assim o personagem
## nunca precisa conhecer a interface, e vice-versa.

## Texto da ação disponível (ex.: "Abrir"). String vazia = nada para interagir.
signal interaction_target_changed(prompt: String)

## Estado de movimento do jogador, usado pelos botões para mostrar se estão ativos.
signal player_movement_state_changed(is_crouching: bool, is_sprinting: bool)

## Perfil gráfico alterado (GameSettings.Quality).
signal quality_changed(level: int)
