# Linux Desktop Automation (Dotfiles Setup)

Coleção de scripts Bash que transforma uma instalação limpa de Linux em um ambiente de desenvolvimento completo: programas, codecs, repositórios oficiais, ferramentas de linguagem, terminal, temas, extensões, configurações e atalhos do GNOME, e bootloader. A ideia é não precisar configurar nada à mão depois.

- **Alvo principal**: Fedora 41 ou superior (dnf5), com GNOME. Validado no Fedora 44.
- **Suporte secundário**: Debian, Ubuntu e derivados (apt), sem validação contínua.
- **Não suportado**: RHEL, CentOS, Rocky e Alma (o ramo dnf depende de repositórios exclusivos do Fedora).

Todos os módulos são **idempotentes**: rodar de novo não duplica nada e completa o que ficou faltando numa execução interrompida.

## Sumário
- [Requisitos](#requisitos)
- [Início rápido](#início-rápido)
- [Configuração (.env)](#configuração-env)
- [Casos de uso](#casos-de-uso)
- [Módulos](#módulos)
- [O que o projeto altera no sistema](#o-que-o-projeto-altera-no-sistema)
- [Solução de problemas](#solução-de-problemas)
- [Estrutura do projeto](#estrutura-do-projeto)
- [Desenvolvimento](#desenvolvimento)
- [Trabalhando com agentes de IA](#trabalhando-com-agentes-de-ia)

## Requisitos
- Usuário comum com permissão de `sudo`. **Não execute como root nem com `sudo ./app.sh`**: os módulos instalam coisas no `$HOME` e pedem `sudo` só quando precisam (o projeto bloqueia a execução como root).
- `git` para clonar o repositório e conexão com a internet.
- Fedora Workstation (GNOME) para a experiência completa. Os módulos de temas e GRUB assumem GNOME e GRUB.

## Início rápido
```bash
git clone <url-deste-repositorio> dotfiles
cd dotfiles
cp .env.example .env      # opcional, mas necessário para rodar sem perguntas
$EDITOR .env
./app.sh                  # menu interativo
```
Se o `./app.sh` der "Permissão negada", rode `bash app.sh` uma vez e escolha o módulo `02` (permissões), ou execute `chmod +x app.sh`.

## Configuração (.env)
O `.env` fica na raiz, é ignorado pelo git e guarda os dados pessoais. Nenhum dado pessoal fica nos scripts.

| Chave | Usada por | Função | Se estiver vazia |
| --- | --- | --- | --- |
| `GIT_USERNAME` | 07 | `git config --global user.name` | Pergunta no terminal |
| `GIT_EMAIL` | 07 | `git config --global user.email` e comentário da chave SSH | Pergunta no terminal |
| `GITHUB_USER` | 01 | Dono dos forks pessoais clonados (hidetopbar, lockkeys, grub2-theme) | Pergunta no terminal (Enter pula) |
| `GRUB_THEME_ARGS` | 10 | Argumentos do instalador do tema GRUB (ex: `-b -t tela -s 1080p`) | Não instala tema no GRUB |

No Fedora, inclua `-b` em `GRUB_THEME_ARGS`: o `/boot` é uma partição separada, e o tema precisa ficar em `/boot/grub2/themes`.

## Casos de uso

### 1. Configurar uma máquina nova do zero, sem supervisão
```bash
cp .env.example .env && $EDITOR .env   # preencha todas as chaves
./app.sh --all
```
- A senha do `sudo` é pedida **uma única vez**, no início, e mantida ativa durante toda a execução. Ao terminar, as credenciais em cache são invalidadas (`sudo -k`).
- Os módulos rodam em ordem (01 a 11), sem limpar a tela, então a saída de cada um fica no histórico do terminal.
- Rode a partir de um terminal **dentro da sessão do GNOME**: o módulo 11 aplica as configurações pela sessão gráfica.
- Se um módulo falhar, os seguintes continuam. No fim aparece a lista dos módulos com falha, e o comando sai com código `1` (ou `0` se tudo deu certo).
- Sem `.env`, o 01 e o 07 fazem perguntas no meio da execução.
- Depois de terminar, **faça logout e login** (ou reinicie) para aplicar o shell zsh, o grupo `docker` e as fontes.

### 2. Escolher módulos específicos pelo menu
```bash
./app.sh
```
Digite o número do módulo, acompanhe a execução, pressione Enter para voltar ao menu e `q` para sair. **Ctrl+C** durante um módulo interrompe só aquele módulo e volta ao menu; no prompt do menu, Ctrl+C sai. `./app.sh --help` mostra as opções. O resultado (sucesso ou status de erro) aparece ao fim de cada módulo.

### 3. Executar um módulo isolado, sem o menu
```bash
bash scripts/05-flatpakPrograms.sh
```
Útil em scripts próprios ou para repetir uma única etapa. Cada módulo funciona sozinho: dependências básicas (git, curl, flatpak, zsh) são instaladas se faltarem.

### 4. Reparar ou completar uma instalação interrompida
Rode o mesmo módulo (ou o `--all`) de novo. O que já foi feito é detectado e pulado: pacotes instalados, repositórios configurados, clones existentes, fontes, temas, Node LTS e a chave SSH.

### 5. Manter o sistema atualizado
- Módulo `03`: `dnf upgrade --refresh`, `dnf autoremove` e `flatpak update`.
- No dia a dia, o alias `atualizar` do `.zshrc` faz a atualização via dnf/apt.

### 6. Configurar identidade Git e chave SSH (módulo 07)
Define nome, e-mail, branch padrão `main` e cores, e gera uma chave `ed25519` em `~/.ssh/id_ed25519` se ainda não existir nenhuma chave pública. Ao final, a chave pública é exibida para você cadastrar no GitHub/GitLab.
A chave é gerada **sem passphrase**, para não travar o modo automático. Se quiser uma, rode depois `ssh-keygen -p -f ~/.ssh/id_ed25519`.

### 7. Restaurar o terminal em outra máquina (módulo 08)
Instala zsh, oh-my-zsh, os plugins (k, autosuggestions, syntax-highlighting, completions), o tema Spaceship e as Nerd Fonts JetBrainsMono e FiraCode. Também define o zsh como shell padrão e copia `terminal/.zshrc` para `~/.zshrc`.
Se o seu `~/.zshrc` for diferente do versionado, um backup é salvo como `~/.zshrc.bak.<data>` antes da cópia. Para versionar mudanças pessoais, edite `terminal/.zshrc` no repositório e rode o 08 de novo.

### 8. Preparar ambientes de desenvolvimento (módulos 04, 06 e 09)
- **04**: compiladores, cmake, Python, Java (25 e latest), Maven, MariaDB, SQLite, PostgreSQL e Podman.
- **06**: VSCode, Google Chrome, MongoDB 8.0 (com mongosh), Docker Engine (com buildx e compose), todos de repositórios oficiais e atualizados pelo `dnf upgrade`, e o Docker Desktop.
- **09**: dependências do Tauri, Rust (rustup/cargo), eza, uv (Python), Node.js LTS (fnm), pnpm e **Claude Code**, este pelo método recomendado no site oficial (`curl -fsSL https://claude.ai/install.sh | bash`). Ele fica em `~/.local/bin/claude` e se atualiza sozinho. Se o `claude` já existir, o passo é pulado.

Os bancos de dados são apenas instalados; inicialização e serviços ficam a seu critério (ex: `sudo postgresql-setup --initdb`, `sudo systemctl enable --now mariadb`, ou os aliases `mongo-activate`/`mongo-deactivate` do `.zshrc`).

### 9. Personalizar o visual e o boot (módulos 01 e 10)
1. Defina `GITHUB_USER` e `GRUB_THEME_ARGS` no `.env`.
2. Rode o **01**: ele clona seus forks (extensões e tema GRUB) para `~/Dev/linux_projects/gnome/`.
3. Rode o **10**: ele instala o tema GTK Orchis, os ícones Tela Circle e os cursores Vimix (pulando os já instalados), oculta o menu do GRUB (`GRUB_TIMEOUT=0`, `GRUB_TIMEOUT_STYLE=hidden`), instala o tema do GRUB e regenera a configuração.
4. Rode o **11** para ativar os temas e o restante das configurações (caso de uso 11).

O `/etc/default/grub` original é salvo uma única vez como `/etc/default/grub.bak`. Para restaurá-lo:
```bash
sudo cp /etc/default/grub.bak /etc/default/grub
sudo grub2-mkconfig -o /boot/grub2/grub.cfg
```
O menu do GRUB continua acessível: no Fedora, ele reaparece automaticamente após uma falha de boot.

### 10. Instalar os aplicativos de desktop (módulo 05)
Via Flathub (atualização automática): Obsidian, Postman, Insomnia, OnlyOffice, Discord, DBeaver, MongoDB Compass, LocalSend, Extension Manager, Prism Launcher, Zotero, Podman Desktop e Inkscape.

### 11. Restaurar extensões, configurações e atalhos do GNOME (módulo 11)
Deixa o GNOME igual ao da máquina de onde as configurações foram capturadas, sem abrir o Settings nem o Extension Manager:
- **Extensões**: instala as listadas em `style/gnome/extensions.txt` (hoje: User Themes, Clipboard History, Vertical App Grid, Blur my Shell, Just Perfection, Burn My Windows, Compiz Magic Lamp, Lock Keys e Caffeine). Usa o pacote do Fedora quando ele existe; as demais vêm do extensions.gnome.org, na versão do seu GNOME Shell.
- **Configurações das extensões**: blur, efeitos de janela (incluindo o perfil do Burn My Windows), painel do Just Perfection, grade de apps e tema do shell.
- **Sistema**: tema escuro, Orchis-Dark, ícones Tela-circle-dark, cursores Vimix, porcentagem da bateria, teclado ABNT2 (`br`), touchpad, tempo de inatividade, suspensão, luz noturna, lembretes de pausa e limite de tempo de tela.
- **Dock**: apps fixados (Arquivos, Firefox, Chrome, VSCode, Postman, DBeaver e Terminal).
- **Atalhos**: todos os do sistema e os personalizados, por exemplo `Super+T` para o terminal, `Super+W` para fechar a janela, `Super+E` para a pasta pessoal, `Alt+Super+N` para o Chrome e `Ctrl+Alt+Shift+P`/`R` para desligar/reiniciar.
- **Apps**: preferências e atalhos do terminal Ptyxis.

Rode de um terminal dentro da sessão do GNOME e, no fim, **faça logout e login** para as extensões novas carregarem. Rodar de novo não reinstala o que já existe e só reaplica as mesmas chaves. Para que os temas apareçam, o módulo 10 deve ter rodado antes.

O papel de parede não é restaurado, porque a imagem não fica no repositório (ver backlog).

### 12. Salvar no repositório as configurações atuais do GNOME
Mudou um atalho, instalou uma extensão ou ajustou algo no Settings? Capture o estado atual:
```bash
bash style/gnome/bin/export-gnome-settings.sh
git diff style/gnome    # revise antes de commitar
```
O exportador regrava `style/gnome/dconf/*.ini`, `extensions.txt` e os perfis do Burn My Windows. Ele pega só seções da lista permitida e descarta estado da máquina (timestamps, tamanhos de janela, último painel aberto), caminhos de papel de parede e credenciais (como as de Wi-Fi corporativo). Caminhos dentro do seu `$HOME` viram o marcador `@HOME@`.

Proteção contra vazamento de segredos (o repositório pode ser público):
- Chaves com nome de segredo (`token`, `secret`, `password`, `api-key`, `appid`, `credential`, `oauth`, `cookie`) são descartadas quando guardam texto.
- Valores com formato de credencial são descartados: tokens do GitHub, GitLab e Slack, JWT, chaves privadas, `Authorization`/`Bearer` e `password=` em comandos de atalhos ou de perfis do terminal. E-mails também.
- O que foi descartado aparece numa lista no fim da execução; configure esses itens à mão na máquina nova.
- Se, mesmo assim, um valor suspeito ou o caminho do seu `$HOME` chegar aos arquivos, a exportação para com erro.

As regras são heurísticas: revise sempre o `git diff` antes de commitar.

### 13. Adicionar uma nova etapa de automação
Veja [Desenvolvimento](#desenvolvimento). Basta criar `scripts/NN-nome.sh` com o cabeçalho certo: o menu e o `--all` passam a incluí-lo automaticamente.

### 14. Usar agentes de IA para manter o projeto
Antigravity, Claude Code, Cursor e GitHub Copilot já encontram as regras do projeto. Veja [Trabalhando com agentes de IA](#trabalhando-com-agentes-de-ia).

## Módulos

| Nº | Script | O que faz | sudo |
| --- | --- | --- | --- |
| 01 | `01-setupEnv.sh` | Cria `~/Dev/{linux_projects,personal_projects,college_projects}` e clona os forks pessoais do GNOME e do tema GRUB | não |
| 02 | `02-permissions.sh` | Dá permissão de execução a `app.sh`, `scripts/*.sh` e `style/gnome` | não |
| 03 | `03-update.sh` | Atualiza pacotes do sistema e Flatpaks e remove dependências órfãs | sim |
| 04 | `04-commonPrograms.sh` | Remove LibreOffice e bloatware do GNOME; habilita o RPM Fusion; instala codecs (ffmpeg completo e grupo multimedia); instala ferramentas de CLI (zsh, git, fzf, btop, bat, eza, zoxide, tldr, curl, wget), apps (GNOME Tweaks, VLC, Tilix, GIMP, OBS Studio), ferramentas de dev, bancos de dados, Podman, Flatpak, Python, Java, Maven e powerline-fonts; garante o Flathub | sim |
| 05 | `05-flatpakPrograms.sh` | Instala ou atualiza os aplicativos Flatpak listados no caso de uso 10 | sim |
| 06 | `06-externalRepos.sh` | Configura os repositórios oficiais e instala VSCode, Chrome, MongoDB, Docker CE e Docker Desktop; habilita o serviço docker e adiciona o usuário ao grupo `docker` | sim |
| 07 | `07-gitAndSSH.sh` | Identidade Git global e chave SSH ed25519 | não |
| 08 | `08-terminalAndShell.sh` | zsh, oh-my-zsh, plugins, Spaceship, Nerd Fonts, shell padrão e `.zshrc` | só para trocar o shell |
| 09 | `09-devEnvironments.sh` | Dependências do Tauri e toolchain C, Rust, eza, uv, Node.js LTS (fnm), pnpm e Claude Code (instalador nativo oficial) | sim |
| 10 | `10-themesAndGrub.sh` | Orchis, Tela Circle, Vimix, GRUB oculto, tema GRUB opcional e tema Plymouth (se houver instalador) | sim |
| 11 | `11-gnomeSettings.sh` | Extensões do GNOME, configurações do sistema e das extensões, apps do dock e atalhos | só para extensões empacotadas no Fedora |

No Fedora, o pacote `malcontent` (controle parental) **não** é removido, porque o GNOME Settings depende dele; sai apenas a interface `malcontent-control`.

## O que o projeto altera no sistema
Transparência sobre tudo o que sai do `$HOME`:
- **Pacotes**: instalações e remoções via dnf/apt e Flatpak de sistema.
- **Repositórios**: RPM Fusion; `/etc/yum.repos.d/` (`vscode.repo`, `mongodb-org-8.0.repo`, `docker-ce.repo`); habilitação do repositório `google-chrome`; remoto Flathub habilitado e sem filtro.
- **Serviços e grupos**: `docker` habilitado e iniciado; seu usuário entra no grupo `docker`.
- **Usuário**: o shell padrão passa a ser o zsh (`usermod --shell`).
- **Boot**: `/etc/default/grub` (com backup) e `/boot/grub2/grub.cfg`; tema GRUB em `/boot/grub2/themes` (com `-b`).
- **Configurações do GNOME (dconf do seu usuário)**: as chaves de `style/gnome/dconf/*.ini`. Só as chaves listadas são alteradas; o resto fica como está.
- **No `$HOME`**: `~/Dev`, `~/.oh-my-zsh`, `~/.zshrc` (com backup), `~/.local/share/fonts/NerdFonts`, temas em `~/.themes` e `~/.local/share/icons`, extensões em `~/.local/share/gnome-shell/extensions`, `~/.config/burn-my-windows`, `~/.cargo`, `~/.rustup`, `~/.local/share/fnm`, Claude Code em `~/.local/bin/claude` e `~/.local/share/claude`, `~/.gitconfig` e `~/.ssh`.

## Solução de problemas
- **"[ERRO CRITICO] Falha na execucao do script!"**: a mensagem mostra o arquivo, a linha, o comando e o status. Corrija a causa (rede, repositório fora do ar, pacote renomeado) e rode o módulo de novo.
- **"No match for argument" no dnf**: um pacote foi renomeado ou removido numa nova versão do Fedora. Confira com `dnf repoquery --available <nome>` e atualize a lista no módulo.
- **"Do not run this as root"**: rode como seu usuário, sem `sudo` na frente.
- **"Fedora 41+ (dnf5) is required"** ou **"Unsupported distribution"**: a distribuição não é suportada (ver o topo deste README).
- **`docker` exige sudo**: faça logout e login para o grupo `docker` valer.
- **O terminal continua no bash**: o novo shell vale a partir do próximo login.
- **O tema do GRUB não foi instalado**: defina `GRUB_THEME_ARGS` e `GITHUB_USER` no `.env` e rode o 01 e o 10.
- **O `--all` parou pedindo dados**: falta alguma chave no `.env` (ver [Configuração](#configuração-env)).
- **"No D-Bus session found" no módulo 11**: rode a partir de um terminal aberto dentro da sessão do GNOME, não por SSH ou TTY.
- **"Could not install <extensão> for GNOME Shell N"**: a extensão ainda não tem versão para o seu GNOME (comum logo após uma atualização do Fedora). As configurações são aplicadas mesmo assim; rode o 11 de novo mais tarde.
- **Extensões instaladas mas inativas**: faça logout e login (no Wayland o GNOME só carrega extensões novas ao iniciar a sessão).

## Estrutura do projeto
```text
.
├── app.sh                  # Ponto de entrada: menu interativo e modo --all
├── scripts/
│   ├── lib.sh              # Biblioteca compartilhada (cores, distro, helpers, trap de erros)
│   └── NN-nome.sh          # Módulos, executados em ordem numérica
├── terminal/.zshrc         # Configuração do zsh (copiada pelo módulo 08)
├── style/gnome/
│   ├── dconf/*.ini         # Configurações do sistema, extensões, dock e atalhos (módulo 11)
│   ├── extensions.txt      # Extensões a instalar (UUID e pacote Fedora, se houver)
│   ├── burn-my-windows/    # Perfis de efeito da extensão Burn My Windows
│   └── bin/                # export-gnome-settings.sh (captura das configurações)
├── .env.example            # Modelo do .env (o .env real é ignorado pelo git)
├── .agents/rules/          # Regras para agentes de IA (fonte de verdade)
├── tools/check.sh          # Verificações estáticas do projeto (não é um módulo)
├── CLAUDE.md               # Ponto de entrada do Claude Code
├── .cursorrules            # Ponto de entrada do Cursor
└── .github/copilot-instructions.md
```

## Desenvolvimento

### Adicionar um novo módulo
1. Crie `scripts/NN-nome.sh`. O número define a posição no menu e no `--all`.
2. Use o cabeçalho e o preâmbulo padrão:
   ```bash
   #!/bin/bash
   # MENU_DESC: Descrição curta (máximo 44 caracteres)
   # CATEGORY: SECAO          (vazio = continua na seção anterior)
   set -euo pipefail

   SCRIPT_DIR="$(dirname "$(realpath "$0")")"
   source "$SCRIPT_DIR/lib.sh"
   detect_distro

   print_header "Minha tarefa"
   # ... lógica idempotente
   ```
3. Rode `chmod +x scripts/NN-nome.sh`. Não é preciso editar o `app.sh`.

### Funções do `lib.sh`
| Função / variável | Uso |
| --- | --- |
| `detect_distro` | Define `PKG_MANAGER` (`apt`/`dnf`); aborta em distribuições não suportadas |
| `is_apt` / `is_dnf` | Condicionais por gerenciador de pacotes |
| `ensure_command cmd [pkg_apt] [pkg_dnf]` | Instala o pacote se o comando não existir |
| `clone_if_missing repo destino` | `git clone` idempotente |
| `load_env` | Carrega o `.env` da raiz |
| `ensure_flathub` | Garante o remoto Flathub de sistema |
| `print_header "Titulo"` | Título visual de etapa |
| `DOTFILES_DIR` | Raiz do repositório |
| `C_GREEN`, `C_YELLOW`, `C_RED`, ... | Cores para mensagens |

### Padrões obrigatórios
- **Fail-fast**: `set -euo pipefail`; nada de `|| true` para esconder erros e nada de comandos críticos encadeados com `&&`.
- **Idempotência**: cheque antes de instalar, clonar, baixar, anexar ou fazer backup.
- **Sem caminhos fixos**: use `$SCRIPT_DIR`, `$DOTFILES_DIR`, `$HOME` e `mktemp`.
- **Sem dados pessoais no código**: use o `.env`.
- **Fedora**: só sintaxe do dnf5 e nomes de pacote validados (detalhes em `.agents/rules/06-fedora.md`).

### Validar mudanças sem tocar no sistema
```bash
bash tools/check.sh                       # sintaxe, shellcheck, convenções, menu, dados pessoais
dnf repoquery --available <pacote>        # o pacote existe?
dnf install --assumeno <lista de pacotes> # a transação resolve? (sem root)
dnf remove --assumeno <pacote>            # o que mais seria removido? (sem root)
```
O `tools/check.sh` nunca executa módulos nem usa `sudo`. Para o shellcheck, usa o instalado no sistema ou, na falta dele, um container via podman.
Módulos que não exigem root (01, 07, 08) podem ser testados com `HOME` apontando para um diretório temporário.

### Commits
Em inglês, no padrão Conventional Commits (`feat:`, `fix:`, `chore:`, `refactor:`, `docs:`), com título curto e corpo explicando o porquê. Detalhes em `.agents/rules/05-security-and-git.md`.

## Trabalhando com agentes de IA
As regras do projeto ficam em `.agents/rules/` (formato do Antigravity, carregadas automaticamente por ele) e cobrem contexto, arquitetura, padrões, backlog, segurança e Fedora. Cada ferramenta tem seu ponto de entrada:

| Ferramenta | Arquivo | Como carrega as regras |
| --- | --- | --- |
| Antigravity | `.agents/rules/*.md` | Nativamente (`trigger: always_on`) |
| Claude Code | `CLAUDE.md` | Resumo e importação automática (`@`) dos arquivos de regras |
| Cursor | `.cursorrules` | Resumo e indicação dos arquivos de regras |
| GitHub Copilot | `.github/copilot-instructions.md` | Resumo e indicação dos arquivos de regras |

Ao mudar uma regra, edite `.agents/rules/` e, se ela fizer parte do resumo, replique-a nos três pontos de entrada. Itens do `04-backlog.md` só são implementados com aprovação explícita do dono do repositório.
