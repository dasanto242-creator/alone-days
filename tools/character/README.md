# Personagens 3D (Blender)

O sobrevivente é **gerado por código no Blender** a partir da malha humana base do
[MakeHuman](https://github.com/makehumancommunity/makehuman) (pasta `makehuman/data`),
liberada como **CC0 (domínio público)**. Roupas, mochila, texturas e animações são
criadas pelos scripts desta pasta — todo o resultado pertence ao projeto.

## Gerar de novo
```bash
# 1. Blender como módulo Python (precisa de Python 3.11)
python3.11 -m venv ~/blender-venv && ~/blender-venv/bin/pip install bpy numpy pillow
# 2. Dados base do MakeHuman (CC0)
git clone --depth 1 https://github.com/makehumancommunity/makehuman /tmp/mh
# 3. Gerar
~/blender-venv/bin/python tools/character/build_survivor.py /tmp/mh/makehuman/data assets/models/survivor/survivor.glb
```

## Arquivos
- `mh_base.py` — lê malha, alvos de forma, esqueleto e pesos do MakeHuman.
- `build_survivor.py` — corpo, esqueleto de jogo (67 ossos), roupas geradas sobre o corpo, botas, gorro, mochila, olhos, otimização (~22 mil triângulos) e exportação GLB.
- `survivor_materials.py` — pele, sobrancelhas, lábios, barba e tecidos procedurais, "assados" em texturas.
- `survivor_anims.py` — animações por código com cinemática inversa nas pernas:
  idle, walk, run, sprint, crouch_idle, crouch_walk, jump, death.

- `build_weapons.py` — taco, chave grifo, pistola e munição (GLB em `assets/models/weapons/`) e seus ícones:
  `~/blender-venv/bin/python tools/character/build_weapons.py assets/models/weapons assets/icons/items`

Para mudar a aparência: ajuste `BODY_TARGETS` (forma do corpo) e as cores em `GARMENTS`/`SKIN`.
