# ALONE DAYS — Status do desenvolvimento

**Engine:** Godot 4.7.2 (versão padrão, GDScript) · Renderizador Mobile (Vulkan, com fallback OpenGL) · Android ARM64 · Terceira pessoa

## Etapa 1 — Protótipo jogável

| # | Tarefa | Status |
|---|---|---|
| 1.1 | Projeto Godot + configurações Android (paisagem, ARM64, vibração, imersivo) | ✅ Concluído |
| 1.2 | Estrutura de pastas e arquitetura (autoloads Events / GameSettings / TouchInput) | ✅ Concluído |
| 1.3 | Primeiro APK rodando no celular | ✅ Build automático no GitHub (Releases) |
| 1.4 | Perfis gráficos Baixo/Médio/Alto + limite 30/45/60 FPS (salvos) | ✅ Concluído |
| 1.5 | Cenário de teste: casa com interior, porta, escada, caixotes, carro, árvores | ✅ Concluído |
| 1.6 | Personagem 3D + animações | 🟡 Parcial — boneco provisório com animação procedural; modelo definitivo pendente |
| 1.7 | Movimento: andar, correr, sprint, agachar, pular, girar | ✅ Concluído (testado) |
| 1.8 | Câmera TPS: órbita, limites, colisão com parede, ajuste em interiores | ✅ Concluído (testado) |
| 1.9 | Joystick flutuante + câmera por toque, multitoque | ✅ Concluído (testado) |
| 1.10 | Botões Pular / Agachar / Correr / Interagir + feedback visual e vibração | ✅ Concluído (vibração só testável no celular) |
| 1.11 | Interação: porta abre/fecha, botão aparece só perto | ✅ Concluído (testado) |
| 1.12 | APK da Etapa 1 + desempenho no aparelho | ✅ 40 FPS estáveis no celular do usuário |

## Etapa 2 — Sobrevivência

| # | Tarefa | Status |
|---|---|---|
| 2.1 | Vida, fome, sede, stamina (0–100) com interação entre eles | ✅ Concluído (testado) |
| 2.2 | Correr gasta mais comida/água; sprint e pulo gastam stamina; exaustão | ✅ Concluído (testado) |
| 2.3 | Fome/sede zeradas tiram vida; só recupera vida bem alimentado; com fome a stamina recupera devagar | ✅ Concluído (testado) |
| 2.4 | Itens como dados (`data/items/*.tres`): nome, descrição, ícone, categoria, peso, pilha, durabilidade, efeito | ✅ 7 itens |
| 2.5 | Inventário por peso, empilhamento, equipar mochila/jaqueta (aparecem no personagem) | ✅ Concluído (testado) |
| 2.6 | Coleta de itens no mundo + largar no chão | ✅ 10 itens espalhados no cenário |
| 2.7 | Tela de inventário por toque com ações contextuais (Comer, Beber, Usar, Equipar, Largar) | ✅ Concluído (testado) |
| 2.8 | HUD discreta (vida, fome, sede, stamina), avisos na tela, tela de morte | ✅ Concluído |

**Testes automáticos:** `tools/smoke_test.tscn` — 54 verificações, 54 aprovadas (rodam também no GitHub a cada build).

## Com problemas / limitações conhecidas
- Personagem é provisório (formas simples). Será trocado por modelo 3D com licença livre.
- Escadas usam rampa invisível de colisão (técnica comum; sobe sem travar). Escalar obstáculos fica para depois.
- Temperatura, sangramento e doenças ficam para uma etapa seguinte (a estrutura de atributos já comporta).
- Ainda sem salvamento: fechar o jogo reinicia a partida.

## Próximos passos
1. Modelo 3D definitivo do sobrevivente com animações (1.6) — via Mixamo.
2. Sistema de salvamento (inventário e atributos já são serializáveis).
3. Etapa 3 — Infectados: modelos, animações, IA, perseguição, ataque, dano.

## Histórico de arquivos (Etapa 1)
Todos novos: `project.godot`, `export_presets.cfg`, `icon.svg`, `.gitignore`,
`scripts/core/{events,game_settings}.gd`,
`scripts/input/{touch_input,touch_joystick,action_button,mobile_controls}.gd`,
`scripts/player/{player_controller,camera_rig,placeholder_animator}.gd`,
`scripts/world/{door,indoor_zone,sun_light}.gd`,
`scripts/diagnostics/performance_overlay.gd`,
`scenes/player/{player,camera_rig}.tscn`, `scenes/ui/hud.tscn`, `scenes/world/test_sandbox.tscn`,
`tools/{configure_project,build_scenes,smoke_test,screenshot}.gd/.tscn`.
