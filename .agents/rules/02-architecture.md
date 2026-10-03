---
description: Arquitetura e estrutura de pastas do projeto
trigger: always_on
---

# Arquitetura do Projeto

O repositório é projetado em torno de um padrão CLI Menu -> Módulo.

## Estrutura de Diretórios
- `app.sh` (Raiz): **O Ponto de Entrada**. Descobre os módulos dinamicamente, lendo `scripts/*.sh` (exceto `lib.sh`) em ordem alfabética, por isso o prefixo numérico. Renderiza o menu interativo e aceita `--all` (execução headless) e `--help`; qualquer outra opção é recusada. O `app.sh` NUNCA executa comandos de sistema pesados diretamente; ele apenas delega para os scripts.
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
  - `detect_distro`: define `PKG_MANAGER` (`apt` ou `dnf`), exige dnf5 no Fedora e recusa a família RHEL e o Fedora Atomic (Silverblue, Kinoite).
  - `is_apt` / `is_dnf`.
  - `ensure_command <cmd> [pkg_apt] [pkg_dnf]`: instala o pacote se o comando não existir.
  - `clone_if_missing <repo> <destino>`.
  - `load_env`: carrega o `.env` da raiz, se existir.
  - `ensure_flathub`: garante o remoto Flathub de sistema, habilitado e sem filtro.
- `style/gnome/`: configuração do GNOME capturada de uma máquina já configurada e aplicada pelo módulo 11:
  - `dconf/*.ini`: chaves do dconf no formato de `dconf dump /` (`keybindings.ini`, `desktop.ini`, `shell.ini`, `apps.ini`). O marcador `@HOME@` é trocado pelo `$HOME` de quem aplica.
  - `extensions.txt`: extensões ativas, uma por linha (`UUID [pacote Fedora]`).
  - `burn-my-windows/profiles/`: perfis de efeito referenciados pelas configurações da extensão.
  - `bin/export-gnome-settings.sh`: gera os três itens acima a partir do GNOME em execução, filtrando estado da máquina (timestamps, tamanhos de janela) e caminhos de papel de parede, e descartando chaves e valores com cara de segredo ou e-mail (lista o que descartou e aborta se algo suspeito passar). Não edite os `.ini` à mão quando der para reexportar.
- `.github/workflows/check.yml`: CI que roda o `tools/check.sh` a cada push e pull request (ação de checkout fixada por hash, token só de leitura).
- `tools/check.sh`: verificações estáticas do projeto (sintaxe, shellcheck, convenções dos módulos, largura do menu, dados pessoais, emojis). Fica fora de `scripts/` para não virar item do menu.
- `terminal/.zshrc`: copiado para `~/.zshrc` pelo módulo 08, com backup quando o arquivo existente for diferente.
- `.env` (ignorado pelo git) e `.env.example` (modelo versionado): configurações pessoais.

## Módulos
| Módulo | Responsabilidade | sudo | `.env` |
| --- | --- | --- | --- |
| `01-setupEnv.sh` | Cria a estrutura `~/Dev` e clona os forks pessoais do GNOME e do tema GRUB | não | `GITHUB_USER` |
| `02-permissions.sh` | Permissão de execução em `app.sh` e nos scripts de `scripts/`, `style/` e `tools/` | não | - |
| `03-update.sh` | Atualiza sistema e Flatpaks; avisa sobre firmware (`fwupdmgr`) e reinício pendente | sim | - |
| `04-commonPrograms.sh` | Remove bloatware (no apt, só o que não arrasta outros pacotes), habilita RPM Fusion, codecs, driver VA-API da GPU (AMD/Intel) e pacotes base | sim | - |
| `05-flatpakPrograms.sh` | Aplicativos via Flathub | sim | - |
| `06-externalRepos.sh` | Repositórios de fornecedores (VSCode, Chrome, MongoDB, Docker) e Docker Desktop | sim | - |
| `07-gitAndSSH.sh` | Identidade Git global e chave SSH | não | `GIT_USERNAME`, `GIT_EMAIL` |
| `08-terminalAndShell.sh` | zsh, oh-my-zsh, plugins, Spaceship, Nerd Fonts, shell padrão, `.zshrc` | só para trocar o shell | - |
| `09-devEnvironments.sh` | Dependências do Tauri, Rust, eza, uv, Node (fnm), pnpm autônomo, Claude Code e Antigravity CLI | sim | - |
| `10-themesAndGrub.sh` | Temas GNOME (Orchis, Tela Circle, Vimix), GRUB oculto, tema GRUB opcional e Plymouth deus_ex | sim | `GRUB_THEME_ARGS` |
| `11-gnomeSettings.sh` | Extensões do GNOME, configurações do sistema e das extensões, apps fixados e atalhos | só para extensões empacotadas | - |

## O Fluxo de Execução

### Interativo (`./app.sh`)
1. O usuário executa `./app.sh` como usuário normal.
2. O `app.sh` descobre os módulos e lê `MENU_DESC` e `CATEGORY` de cada um.
3. O usuário seleciona o número de um módulo.
4. O `app.sh` invoca `bash scripts/<modulo>.sh`.
5. O módulo importa `lib.sh`, detecta a distro, roda com segurança (`set -euo pipefail`) e retorna um código de saída.
6. O `app.sh` exibe o resultado (`exec_footer`) e volta ao menu.
7. Ctrl+C durante um módulo interrompe apenas o módulo (status 130) e volta ao menu; no prompt do menu, Ctrl+C sai.

### Headless (`./app.sh --all`)
1. Grava a execução inteira em `~/.local/state/dotfiles/logs/setup-<data>.log` (pasta 700, os 10 mais recentes são mantidos). Com o `script` do util-linux disponível, o `app.sh` se reexecuta dentro dele (mantém o terminal, as barras de progresso e as cores); sem ele, usa `tee`. Só a saída é gravada, nunca o que é digitado.
2. Pede a senha do sudo uma única vez e mantém o timestamp ativo em segundo plano enquanto roda. Ao terminar (inclusive por Ctrl+C), invalida as credenciais em cache (`sudo -k`).
3. Executa todos os módulos em ordem, sem limpar a tela, preservando a saída de cada um.
4. A falha de um módulo não interrompe os seguintes. Ao final, lista os módulos que falharam, mostra o caminho do log e sai com código 1 (ou 0 se tudo deu certo).
5. Sem `.env`, os módulos 01 e 07 perguntam os dados no terminal: o 01 permite pular, o 07 exige os dados.

## Dependências entre Módulos
- O 10 instala o tema GRUB a partir do repositório clonado pelo 01.
- O 05 precisa do `flatpak`, instalado pelo 04 (o `ensure_command` cobre a execução isolada).
- O `.zshrc` copiado pelo 08 é o do uso diário do dono do repositório. Ele coloca no PATH o que o 09 instala (fnm, pnpm em `$PNPM_HOME/bin`, cargo) e carrega cada ferramenta só se ela existir. Mudanças nele devem partir do `~/.zshrc` em uso, sem caminhos `/home/<usuário>`.
- O 11 aplica os temas instalados pelo 10 (`Orchis-Dark`, `Tela-circle-dark`, `Vimix-cursors`) e fixa no dock apps instalados pelo 05 e pelo 06. Se mudar um tema no 10, reexporte as configurações.
- O log do `--all` usa o `script`, que no Fedora vem do pacote `util-linux-script`, instalado pelo 04 (na primeira execução numa máquina nova, o log é feito com `tee`).
- O 11 precisa rodar dentro da sessão gráfica do GNOME (usa o D-Bus da sessão). Extensões novas só carregam depois de logout e login (Wayland).
