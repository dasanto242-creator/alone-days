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
| 1.6 | Personagem 3D + animações | ✅ Sobrevivente realista próprio (Blender, base CC0), 8 animações |
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

**Testes automáticos:** `tools/smoke_test.tscn` — 89 verificações, 89 aprovadas (rodam também no GitHub a cada build).

## Com problemas / limitações conhecidas
- Rosto ainda sem textura fotográfica (pele procedural); cabelo raspado pintado sob o gorro.
- Escadas usam rampa invisível de colisão (técnica comum; sobe sem travar). Escalar obstáculos fica para depois.
- Temperatura, sangramento e doenças ficam para uma etapa seguinte (a estrutura de atributos já comporta).
- Ainda sem salvamento: fechar o jogo reinicia a partida.

## Armas (antecipado da Etapa 6)
| Item | Status |
|---|---|
| Modelos 3D próprios: taco de beisebol, chave grifo, pistola 9 mm, caixa de munição, coldre | ✅ |
| Ao pegar: arma branca vai para as costas (sobre a mochila se houver), pistola para o coldre da coxa | ✅ |
| Botão "Arma" alterna mãos livres → arma branca → pistola | ✅ |
| Golpe com as duas mãos: gasta stamina, desgasta a arma, acerta o que estiver à frente | ✅ |
| Pistola: mira no centro da tela, coice, clarão, marca de tiro, carregador de 15, recarga com munição da mochila | ✅ |
| Alvos de treino: placa de tiro e boneco de pancada | ✅ |
| Dano em infectados | ⏳ Etapa 3 (as armas já usam `apply_damage`) |
| Sons de disparo/golpe | ⏳ Etapa 5 |

## Ajustes de 25/11
- Casa: a porta abria para fora e a colisão dela não acompanhava o giro — corrigido (entra andando).
- Personagem sobe degraus de até 30 cm sozinho (calçadas, soleiras); calçadas adicionadas na estrada.
- Animações direcionais: andar/correr de lado e de costas (com arma em mãos o corpo encara a câmera;
  de lado é 72% e de costas ~60% da velocidade). No sprint a arma abaixa e o corpo vira para onde corre.
- Empunhadura da arma branca: duas mãos no cabo com punhos fechados (direção da arma prioritária,
  torção do antebraço sem deslocar o punho, dedos dobrando para a palma).
- Otimização: FPS automático (60 se o aparelho sustenta, senão 30 com ritmo regular), árvores em
  MultiMesh, materiais compartilhados, clarão/marcas de tiro reaproveitados, sombras desligadas em
  peças pequenas, camiseta não é desenhada sob a jaqueta.

## Ajustes de 25/11 (2) — braços, ações, física e primeiro zumbi
- Braços na caminhada viraram pêndulos com atraso: o braço é arrastado pelo ombro, o cotovelo dobra
  mais no avanço e a mão relaxada cruza um pouco à frente. Agachado: braços à frente para equilíbrio.
- Novas animações de corpo inteiro: beber (leva a garrafa à boca e inclina a cabeça), comer (mordidas)
  e pegar do chão (agacha, alcança, levanta). O item aparece na mão; o personagem não anda durante a
  ação e a arma volta para a mão no fim. Ao pegar, ele dá um passo curto até o item.
- Colisão: cápsula do corpo mais justa (raio 0,28 m), não atravessa zumbis.
- Itens no chão agora têm física (RigidBody): caem, repousam em cima do que estiver embaixo, não
  atravessam paredes ao serem largados e são empurrados de leve ao esbarrar.
- **Zumbi** (Etapa 3 adiantada): modelo próprio (corpo magro, pele pálida, roupa rasgada e suja,
  sangue na boca e na roupa, olhos opacos), andar lento mancando e torto, idle balançando, ataque,
  reação a golpe e morte.
  - IA: Idle, Patrol, Suspicious, Investigate, Alert, Chase, Attack, Search (+ Stagger, Dead).
  - Sentidos: visão em cone com linha de visada (agachado é visto mais tarde e de mais perto) e
    audição (passos: agachado 1,5 m, andando 4 m, correndo 9 m, sprint 16 m; tiro 45 m).
  - Combate nos dois sentidos: armas causam dano (tiro na cabeça = triplo), zumbi agarra e morde
    (14 de dano, tela pisca vermelho, vibração, empurrão).
  - Desempenho: decisões em intervalos que crescem com a distância; longe (>85 m) fica congelado e
    invisível. Máximo de 3 vivos no cenário de teste; corpos somem e novos nascem longe do jogador.

## Ajustes de 25/11 (3) — parkour, machado, barra de armas, sons
- Parkour com o botão Pular de frente para um obstáculo: muro baixo e fino (0,4–1,3 m) = salto
  apoiando a mão; borda alta ou bloco (0,9–2,1 m) com espaço em cima = escalada (agarra, empurra,
  sobe o joelho). O corpo segue a trajetória das animações, ajustada à altura e espessura reais.
- Marca de tiro não fica mais flutuando: zumbi só sangra; objetos que se movem levam a marca junto.
- Machado (modelo e ícone próprios): arma branca forte que vai nas costas e corta árvores.
- Bosque com 6 árvores cortáveis: cada machadada treme a árvore, solta lascas e aprofunda o corte;
  no 5º golpe ela estala, tomba acelerando, quica, afunda e some (fica o toco). Cresce de novo em 5 min.
  Taco e grifo só batem (aviso "Precisa de um machado").
- Barra de armas no centro, embaixo: até 4 armas (corpo + mochila), toque empunha/guarda e troca a
  arma da mochila com a do corpo; mostra munição e estado. Substitui o botão "Arma".
- Consumíveis no chão: **Pegar** (fica na mão) ou **Guardar** (direto na mochila). Com o item na
  mão: **Beber/Comer/Usar** ou **Guardar**.
- Sons próprios gerados por síntese (sem licença de terceiros): passos (grama e piso duro), tiro,
  recarga, sem munição, golpe no ar, impacto, machadada, árvore estalando e caindo, gemidos,
  ataque, dor e morte do zumbi, dor e esforço do jogador, aterrissagem, comer, beber, pegar,
  mochila, porta e vento ambiente em loop. Gerador: `tools/audio/make_sounds.py`.

## Personagem 3D
- Gerado no Blender por `tools/character/` (ver README lá). Base humana MakeHuman (CC0).
- ~22 mil triângulos, 67 ossos, texturas próprias comprimidas para celular.
- Jaqueta e mochila só aparecem quando equipadas.
- Animações (v2, com peso e impacto: IK de braços e pernas, quadril que afunda no apoio, contra-rotação do tronco): idle, walk, run, sprint, crouch_idle, crouch_walk, jump, death, hold_melee, attack_melee, hold_pistol, fire_pistol, reload_pistol.
- Animação em camadas (AnimationTree): pernas seguem a locomoção, tronco e braços seguram a arma, golpe/disparo por cima.

## Próximos passos
2. Sistema de salvamento (inventário e atributos já são serializáveis).
3. Etapa 3 — Infectados: variações de zumbi (roupas/corpos), navegação por NavMesh em mapas
   grandes, sons (gemidos, passos), zumbis que quebram portas.

## Histórico de arquivos (Etapa 1)
Todos novos: `project.godot`, `export_presets.cfg`, `icon.svg`, `.gitignore`,
`scripts/core/{events,game_settings}.gd`,
`scripts/input/{touch_input,touch_joystick,action_button,mobile_controls}.gd`,
`scripts/player/{player_controller,camera_rig,placeholder_animator}.gd`,
`scripts/world/{door,indoor_zone,sun_light}.gd`,
`scripts/diagnostics/performance_overlay.gd`,
`scenes/player/{player,camera_rig}.tscn`, `scenes/ui/hud.tscn`, `scenes/world/test_sandbox.tscn`,
`tools/{configure_project,build_scenes,smoke_test,screenshot}.gd/.tscn`.
