# ALONE DAYS

Jogo de sobrevivência em mundo aberto para Android, em terceira pessoa, feito no Godot 4.

## Abrir e jogar no PC
1. Baixe o **Godot 4.7.2 (versão padrão, não a .NET)** em godotengine.org. Não precisa instalar: é só descompactar e abrir.
2. No Godot: **Importar** → escolha o arquivo `project.godot` desta pasta.
3. Aperte **F5** (ou o botão ▶) para jogar.

Controles no PC (o mouse imita o dedo):
- **Arrastar no lado esquerdo** da tela: joystick · **arrastar no lado direito**: câmera
- Clicar nos botões redondos: Pular, Agachar, Correr, Interagir
- Teclado: **W A S D** mover · **Shift** correr rápido · **C** agachar · **Espaço** pular · **E** interagir

## Gerar o APK para o celular
Só precisa fazer a preparação uma vez:
1. Instale o **Android Studio** (developer.android.com/studio) e abra-o uma vez para baixar o Android SDK.
2. No Godot: **Editor → Configurações do Editor → Exportar → Android**: aponte "Android SDK Path" para a pasta do SDK
   (normalmente `C:\Users\<você>\AppData\Local\Android\Sdk`). O Java (JDK 17) vem junto com o Android Studio
   (`C:\Program Files\Android\Android Studio\jbr`).
3. No Godot: **Editor → Gerenciar Modelos de Exportação → Baixar e Instalar**.
4. **Projeto → Exportar → Android → Exportar Projeto** → salve `AloneDays.apk`.
5. Copie o APK para o celular e instale (permita "instalar apps de fontes desconhecidas").

Atalho: com o celular ligado no cabo USB e a **Depuração USB** ativada, aparece um ícone de Android no canto superior direito do Godot que instala e abre o jogo direto no celular.

## Arquitetura
- `scripts/core/` — autoloads globais: **Events** (barramento de sinais), **GameSettings** (qualidade, FPS, sensibilidade, vibração).
- `scripts/input/` — controles touch. Joystick e botões acionam as **mesmas ações** do teclado (InputMap), então o personagem não sabe de onde vem a entrada. **TouchInput** acumula a rotação da câmera.
- `scripts/player/` — **PlayerController** (movimento), **CameraRig** (câmera TPS com SpringArm3D, colisão e modo interior), **PlaceholderAnimator** (animação provisória).
- `scripts/world/` — objetos do mundo. Objetos interativos implementam `get_interaction_prompt()` e `interact(actor)`.
- `scenes/` — cenas do jogo. `tools/` — ferramentas de desenvolvimento (não vão para o APK).

Camadas de física: 1 world · 2 player · 3 interactable · 4 trigger.

## Ferramentas (desenvolvimento)
```
godot --headless --path . res://tools/smoke_test.tscn    # testes automáticos
godot --headless --path . res://tools/build_scenes.tscn  # regera as cenas da Etapa 1 (sobrescreve edições manuais!)
```

Status e pendências: ver `STATUS.md`.
