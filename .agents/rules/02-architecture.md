---
description: Arquitetura e estrutura de pastas do projeto
trigger: always_on
---

# Arquitetura do Projeto

O repositório é projetado em torno de um padrão CLI Menu -> Módulo.

## Estrutura de Diretórios
- `app.sh` (Raiz): **O Ponto de Entrada**. Descobre os módulos dinamicamente, lendo `scripts/*.sh` (exceto `lib.sh`) em ordem alfabética, por isso o prefixo numérico. Renderiza o menu interativo e aceita, em qualquer ordem, `--all` (execução headless) ou `--gui` (interface gráfica, que recebe a política e o modo resolvidos), uma política de versões (`--ask`, `--update` ou `--keep`), um modo de configuração (`--full` ou `--only-missing`) e `--help`; qualquer outra opção é recusada. Resolve o modo (flag > `CONFIG_MODE` do `.env` > `full`) e a política (flag > `UPDATE_POLICY` do `.env` > padrão: `ask` no menu, `keep` no `--all` e no `--only-missing`), mostra os dois no topo do menu e os repassa aos módulos em `DOTFILES_CONFIG_MODE` e `DOTFILES_UPDATE_POLICY`. O `app.sh` NUNCA executa comandos de sistema pesados diretamente; ele apenas delega para os scripts.
- `gui/dotfiles_gui.py`: **a interface gráfica** (Python + GTK 4 + libadwaita + VTE, tudo já instalado no Fedora Workstation: o Ptyxis depende do VTE). Lê os módulos com as mesmas regras do `app.sh` e roda cada um num terminal embutido (VTE), onde a senha do sudo, as perguntas da política de versões, o seletor do 12 e o Ctrl+C funcionam como no menu; "Run All" executa `./app.sh --all --<política>`. Tem a chave "Only What Is Missing" (modo completar; ligada, muda a política para Keep). Segue o estilo do sistema (claro/escuro, cor de destaque, alto contraste) e permite forçar claro ou escuro (preferência em `~/.config/dotfiles/gui.ini`). O menu da janela cria o atalho `~/.local/share/applications/local.dotfiles.Setup.desktop` (ícone `gui/dotfiles.svg`). Sem display, sai com erro e indica o menu do terminal.
- `scripts/NN-nome.sh`: os módulos, onde toda a "mão na massa" acontece. O nome do arquivo deve ter no máximo 24 caracteres (largura da coluna do menu; acima disso é truncado). Cada módulo declara seus metadados no cabeçalho:
  ```bash
  # MENU_DESC: Descricao curta (maximo 44 caracteres; acima disso e truncada no menu)
  # CATEGORY: NOME_DA_SECAO
  ```
  A `CATEGORY` vazia mantém o módulo na seção anterior. Módulos consecutivos com a mesma `CATEGORY` compartilham um único cabeçalho de seção.
- `scripts/lib.sh`: **O Núcleo Utilitário**, injetado (`source`) no topo de cada módulo. Fornece:
  - Cores: `C_RESET`, `C_RED`, `C_GREEN`, `C_YELLOW`, `C_BLUE`, `C_CYAN`, `C_BOLD`, `C_DIM`.
  - `DOTFILES_DIR`: caminho absoluto da raiz do repositório.
  - Guarda de root: aborta se o módulo for executado como root ou via `sudo`.
  - Trap de erros global (`trap ERR` + `errtrace`): imprime arquivo, linha, comando e status, inclusive para falhas dentro de funções.
  - `print_header "Titulo"`.
  - `detect_distro`: define `PKG_MANAGER` (`apt` ou `dnf`), exige dnf5 no Fedora e Debian 13+ no Debian, e recusa a família RHEL e o Fedora Atomic (Silverblue, Kinoite).
  - `is_apt` / `is_dnf` / `is_debian` (o Debian em si, não o Ubuntu).
  - `admin_group` (`wheel` no Fedora, `sudo` no Debian/Ubuntu) e `has_sudo_access` (o comando existe e a sessão tem o grupo de administrador, ou há credencial do sudo em cache).
  - `is_gnome`, `gnome_only "etapa"` e `require_gnome`: detecção do GNOME (critério em `01-context.md`). `gnome_only` devolve 1 e avisa o que foi pulado; `require_gnome` encerra com sucesso os módulos que só configuram o GNOME (11 e 12).
  - Modo de configuração (`CONFIG_MODE`: `full` ou `missing`, de `DOTFILES_CONFIG_MODE` ou do `.env`): `only_missing` (verdadeiro no modo completar) e `keep_existing "o quê"` (avisa o que foi mantido). Regras de uso em `03-standards.md`, seção 2.2.
  - `ensure_command <cmd> [pkg_apt] [pkg_dnf]`: instala o pacote se o comando não existir.
  - `clone_if_missing <repo> <destino>`.
  - `load_env`: carrega o `.env` da raiz, se existir.
  - `ensure_flathub`: garante o remoto Flathub de sistema, habilitado e sem filtro.
  - Política de versões (`UPDATE_POLICY`: `ask`, `update` ou `keep`; `ask` sem terminal vira `keep`):
    - `install_packages <titulo> <pacotes...>`: instala os que faltam e oferece as versões novas dos instalados. Separados: `install_missing_packages` (nunca atualiza) e `offer_package_upgrades <titulo> <pacotes...>`. Grupos `@...` são sempre passados ao gerenciador.
    - `install_flatpaks <apps...>`: o mesmo para Flatpaks de sistema.
    - `offer_git_updates <titulo> <pastas...>`: avanço rápido (`merge --ff-only`) de clones atrás da origem; clones com alterações locais ou histórico divergente são só informados.
    - `confirm_updates <titulo> <linhas...>`: imprime as linhas `nome atual -> nova`, o aviso de quebra e decide pela política (retorna 0 para atualizar). Sem linhas, retorna 1 sem imprimir nada.
    - `version_gt <a> <b>`, `record_version <nome> <versao>` e `recorded_version <nome>` (registro em `~/.local/state/dotfiles/versions/` para o que não vem de pacote: temas, fontes, tema do GRUB, Plymouth).
- `style/gnome/`: configuração do GNOME capturada de uma máquina já configurada e aplicada pelo módulo 11:
  - `dconf/*.ini`: chaves do dconf no formato de `dconf dump /` (`keybindings.ini`, `desktop.ini`, `shell.ini`, `apps.ini`). O marcador `@HOME@` é trocado pelo `$HOME` de quem aplica.
  - `extensions.txt`: extensões a instalar, uma por linha (`[disabled] UUID [pacote Fedora]`). As marcadas `disabled` são instaladas mas ficam desligadas: o que fica ativo é decidido por `enabled-extensions`/`disabled-extensions` em `dconf/shell.ini`. O exportador lista as ativas e as desativadas instaladas pelo usuário (pasta `~/.local/share/gnome-shell/extensions` ou pacote com motivo `User` no dnf5), nunca as que vêm com o sistema.
  - `burn-my-windows/profiles/`: perfis de efeito referenciados pelas configurações da extensão.
  - `bin/export-gnome-settings.sh`: gera os três itens acima a partir do GNOME em execução, filtrando estado da máquina (timestamps, tamanhos de janela) e caminhos de papel de parede, e descartando chaves e valores com cara de segredo ou e-mail (lista o que descartou e aborta se algo suspeito passar). Não edite os `.ini` à mão quando der para reexportar.
- `.github/workflows/check.yml`: CI que roda o `tools/check.sh` a cada push e pull request (ação de checkout fixada por hash, token só de leitura).
- `tools/check.sh`: verificações estáticas do projeto (sintaxe, shellcheck, convenções dos módulos e proteção do GNOME, largura do menu, dados pessoais, emojis). Fica fora de `scripts/` para não virar item do menu.
- `terminal/.zshrc`: copiado para `~/.zshrc` pelo módulo 08, com backup quando o arquivo existente for diferente.
- `.env` (ignorado pelo git) e `.env.example` (modelo versionado): configurações pessoais.

## Módulos
| Módulo | Responsabilidade | sudo | `.env` |
| --- | --- | --- | --- |
| `00-sudoAccess.sh` | Instala o `sudo` se faltar e adiciona o usuário a `sudo`/`wheel`, `adm` e `systemd-journal`; sem sudo, usa o `su` (senha de root) uma única vez. Só adiciona, igual nos dois modos | só `su`, quando falta | - |
| `01-setupEnv.sh` | Cria a estrutura `~/Dev` e clona os forks pessoais das extensões do GNOME (só no GNOME) e do tema GRUB | não | `GITHUB_USER` |
| `02-permissions.sh` | Permissão de execução em `app.sh` e nos scripts de `scripts/`, `style/` e `tools/` | não | - |
| `03-update.sh` | Atualiza sistema e Flatpaks conforme a política de versões; avisa sobre firmware (`fwupdmgr`) e reinício pendente | sim | - |
| `04-commonPrograms.sh` | Remove o LibreOffice e, no GNOME, o bloatware do GNOME (no apt, só o que não arrasta outros pacotes), habilita RPM Fusion (no Debian, `contrib`/`non-free`), codecs, driver VA-API da GPU (AMD/Intel) e pacotes base (GNOME Tweaks só no GNOME) | sim | - |
| `05-flatpakPrograms.sh` | Aplicativos via Flathub (Extension Manager só no GNOME; atualizações conforme a política de versões) | sim | - |
| `06-externalRepos.sh` | Repositórios de fornecedores (VSCode, Chrome, MongoDB, Docker) e Docker Desktop; no Debian sem servidor MongoDB publicado (13), usa o build do bookworm | sim | - |
| `07-gitAndSSH.sh` | Identidade Git global e chave SSH | não | `GIT_USERNAME`, `GIT_EMAIL` |
| `08-terminalAndShell.sh` | zsh, oh-my-zsh, plugins, Spaceship, Nerd Fonts, shell padrão, `.zshrc` | só para trocar o shell | - |
| `09-devEnvironments.sh` | Dependências do Tauri, Rust, eza, uv, Node (fnm), pnpm autônomo, Claude Code e Antigravity CLI | sim | - |
| `10-themesAndGrub.sh` | Temas GNOME (Orchis, Tela Circle, Vimix; só no GNOME), GRUB oculto (no Debian, com `splash`), tema GRUB opcional e Plymouth deus_ex | sim | `GRUB_THEME_ARGS` |
| `11-gnomeSettings.sh` | Só no GNOME (`require_gnome`): extensões, configurações do sistema e das extensões, apps fixados e atalhos | só para extensões empacotadas | - |
| `12-wallpaperAndAvatar.sh` | Só no GNOME (`require_gnome`): papel de parede (cópia em `~/.local/share/backgrounds`, chaves via `gsettings`) e foto do usuário (recorte 512x512 com GdkPixbuf, entregue ao AccountsService via `busctl`), escolhidos no seletor do `zenity` ou pelo `.env` | só para instalar o `zenity`, se faltar | `WALLPAPER_IMAGE`, `AVATAR_IMAGE` |

## O Fluxo de Execução

### Interativo (`./app.sh`)
1. O usuário executa `./app.sh` como usuário normal.
2. O `app.sh` descobre os módulos e lê `MENU_DESC` e `CATEGORY` de cada um.
3. O usuário digita o número de um módulo, que é o prefixo do arquivo (`0` ou `00` para o `00-sudoAccess.sh`). A interface gráfica mostra o mesmo número.
4. O `app.sh` invoca `bash scripts/<modulo>.sh`.
5. O módulo importa `lib.sh`, detecta a distro, roda com segurança (`set -euo pipefail`) e retorna um código de saída.
6. O `app.sh` exibe o resultado (`exec_footer`) e volta ao menu.
7. Ctrl+C durante um módulo interrompe apenas o módulo (status 130) e volta ao menu; no prompt do menu, Ctrl+C sai.

### Interface gráfica (`./app.sh --gui`)
1. O `app.sh` resolve a política de versões e executa `gui/dotfiles_gui.py`, que a mostra como valor inicial (Ask, Update ou Keep).
2. A janela lista os módulos por categoria. Cada execução pede confirmação e abre a página de execução, com o módulo (`bash scripts/<modulo>.sh`) num terminal embutido, `DOTFILES_UPDATE_POLICY` com a política escolhida e `DOTFILES_CONFIG_MODE` com o modo ("Run All" passa `--full` ou `--only-missing`).
3. "Stop" envia Ctrl+C ao módulo. Ao terminar, a barra inferior mostra sucesso, interrupção ou o status de erro; fechar a janela com um módulo rodando pede confirmação.
4. Fora do GNOME, um aviso no topo indica que as etapas do GNOME serão puladas (a regra é a do `is_gnome`, consultada no `lib.sh`).

### Headless (`./app.sh --all`)
1. Grava a execução inteira em `~/.local/state/dotfiles/logs/setup-<data>.log` (pasta 700, os 10 mais recentes são mantidos). Com o `script` do util-linux disponível, o `app.sh` se reexecuta dentro dele (mantém o terminal, as barras de progresso e as cores); sem ele, usa `tee`. Só a saída é gravada, nunca o que é digitado.
2. Checa se a sessão já pode usar o sudo (`has_sudo_access`). Se não pode (Debian instalado com senha de root), roda só o módulo 00, que pede a senha de root, e para pedindo logout e login. Depois, pede a senha do sudo uma única vez e mantém o timestamp ativo em segundo plano enquanto roda. Ao terminar (inclusive por Ctrl+C), invalida as credenciais em cache (`sudo -k`).
3. Executa todos os módulos em ordem, sem limpar a tela, preservando a saída de cada um.
4. A falha de um módulo não interrompe os seguintes. Ao final, lista os módulos que falharam, mostra o caminho do log e sai com código 1 (ou 0 se tudo deu certo).
5. Sem `.env`, os módulos 01 e 07 perguntam os dados no terminal: o 01 permite pular, o 07 exige os dados. O 12 abre o seletor de arquivos (Cancelar mantém a imagem atual).
6. A política de versões padrão é `keep`: só instala o que falta e lista o que tem versão nova. `--all --ask` pergunta uma vez por grupo; `--all --update` atualiza tudo.

### Modo completar (`--only-missing`)
Para máquinas já configuradas em parte. O que cada módulo faz de diferente:
- 01: clona só os forks que faltam (sem forks faltando, nem pede o `GITHUB_USER`; isso vale nos dois modos).
- 04: não remove nenhum programa (LibreOffice, bloatware do GNOME).
- 06: não regrava arquivos de repositório existentes; com o Chrome instalado, não mexe no estado do repositório dele; serviço e grupo do Docker só se o `docker-ce` foi instalado nesta execução.
- 07: mantém `user.name`, `user.email`, `init.defaultBranch` e `color.ui` já definidos, sem perguntar.
- 08: mantém o `~/.zshrc` existente e o shell padrão (exceto se o zsh foi instalado nesta execução).
- 10: não muda `GRUB_TIMEOUT`/`GRUB_TIMEOUT_STYLE` (e não regenera o `grub.cfg` sem mudança), mantém um `GRUB_THEME` que o projeto não instalou e a tela de boot atual.
- 11: carrega só as chaves que o usuário ainda não definiu (`dconf read` vazio); em `enabled-extensions`, acrescenta as extensões do repositório que não estão ativas nem em `disabled-extensions`; não sobrescreve perfis do Burn My Windows.
- 12: mantém um papel de parede definido (chave `picture-uri` no dconf) e uma foto existente no AccountsService.
- 00: igual nos dois modos (só adiciona grupos).

## Dependências entre Módulos
- Todo módulo que usa `sudo` depende do acesso que o 00 garante (no Debian instalado com senha de root, o usuário começa sem sudo). O `--all` checa isso antes de começar.
- O 10 instala o tema GRUB a partir do repositório clonado pelo 01.
- O 05 precisa do `flatpak`, instalado pelo 04 (o `ensure_command` cobre a execução isolada).
- O `.zshrc` copiado pelo 08 é o do uso diário do dono do repositório. Ele coloca no PATH o que o 09 instala (fnm, pnpm em `$PNPM_HOME/bin`, cargo) e carrega cada ferramenta só se ela existir. Mudanças nele devem partir do `~/.zshrc` em uso, sem caminhos `/home/<usuário>`.
- O 11 aplica os temas instalados pelo 10 (`Orchis-Dark`, `Tela-circle-dark`, `Vimix-cursors`) e fixa no dock apps instalados pelo 05 e pelo 06. Se mudar um tema no 10, reexporte as configurações.
- O log do `--all` usa o `script`, que no Fedora vem do pacote `util-linux-script`, instalado pelo 04 (na primeira execução numa máquina nova, o log é feito com `tee`).
- O 11 precisa rodar dentro da sessão gráfica do GNOME (usa o D-Bus da sessão). Extensões novas só carregam depois de logout e login (Wayland). O 12 também (`gsettings` e o seletor do `zenity`).
- O papel de parede e a foto do usuário nunca entram no repositório: o exportador descarta os `picture-uri` e o 12 lê as imagens do `.env` ou do seletor.
