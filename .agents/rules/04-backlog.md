---
description: Documento mestre de revisão e auditoria do projeto. Contém o Kanban de tarefas.
trigger: always_on
---

# Revisão do Projeto e Backlog (Roadmap)

**STATUS DO PROJETO:** **ATIVO**
Revisão completa em 2026-10-02 e pendências resolvidas em 2026-10-03 (Fedora 44): validação por dry-run do dnf5, shellcheck, testes em `HOME` isolado e em pseudo-terminal, containers Fedora 44 e Ubuntu 24.04. Resta apenas o Antigravity Desktop.

## DIRETRIZ CRÍTICA DE INTERAÇÃO (PARA A IA)
**AÇÃO DO USUÁRIO REQUERIDA:** Como Inteligência Artificial, você **NÃO DEVE** tentar resolver, implementar ou apagar os itens desta lista de forma autônoma e silenciosa.
1. Se você notar algo nesta lista que faça sentido ser feito, **converse com o usuário primeiro**.
2. Apresente o problema (ex: "Notei que o link do MongoDB está hardcoded e desatualizado") e proponha a solução.
3. Aguarde o **consenso e aprovação explícita** do usuário.
4. Após o "OK", execute a mudança no código e atualize o status neste arquivo.

---

## FEITO (Done)
- **Extirpar o Ecossistema Snap e Hyprland**: Migração finalizada para Flatpak e remoção completa de arquivos de Tiling WMs (`style/hyprland` apagada).
- **Limpeza de Software Obsoleto**: Remoção de Node.js via APT, NetBeans, Mosquitto, GitKraken, Linuxtoys, Zen Browser, LibreOffice e Spotify a pedido do usuário. Remoção de *GNOME Bloatware* (Yelp, GNOME Tour, Contacts, Simple Scan e a interface do controle parental) no `04-commonPrograms.sh`. No Fedora, o pacote `malcontent` é mantido: ele é dependência do `gnome-control-center`, do qual o `gnome-shell` depende.
- **Estratégia de Repositórios Nativos**: O `06-externalRepos.sh` usa os repositórios e chaves GPG oficiais (VSCode, Google Chrome, Docker, MongoDB), garantindo autoupdate via `dnf upgrade`/`apt upgrade`. O único pacote avulso é o Docker Desktop (exigência do fornecedor), instalado apenas se ausente. O MongoDB Compass vem do Flathub.
- **Suporte a Dev Moderno (Python, Node & Rust)**: O `09-devEnvironments.sh` instala as dependências do Tauri (incluindo `libxdo-devel` e o grupo `c-development`), Rust via `rustup`, `uv`, Node.js LTS via `fnm`, `pnpm` e o Claude Code pelo instalador nativo recomendado no site oficial (com atualização automática). No Fedora, `rustup`, `uv` e `eza` vêm do dnf.
- **Automação Completa do GNOME (Extensões e Configurações)**: O `11-gnomeSettings.sh` instala as extensões listadas em `style/gnome/extensions.txt` (pacote Fedora quando existe, senão extensions.gnome.org na versão do GNOME Shell instalado) e aplica via `dconf load` as configurações do sistema, das extensões, os apps fixados no dock e todos os atalhos (`style/gnome/dconf/*.ini`). O `style/gnome/bin/export-gnome-settings.sh` recaptura tudo de uma máquina configurada, filtrando estado, segredos (por nome de chave e formato de valor) e e-mails, com travas que abortam a exportação se algo suspeito passar. Substituiu o antigo `keybinds.conf`, que estava desatualizado (atalhos do Pop!_OS e comandos inexistentes).
- **Utilitários de Terminal Modernizados**: `btop`, `bat`, `eza`, `zoxide` e `tldr`, junto com as Nerd Fonts JetBrainsMono e FiraCode (pacotes `.tar.xz`, 15 vezes menores que os `.zip`).
- **Refatoração de Performance em Gerenciadores de Pacote**: O `04-commonPrograms.sh` divide os pacotes em variáveis de categorias lógicas (`CLI_TOOLS`, `DATABASES` etc.), executadas numa única transação.
- **Modo "Non-Interactive" / Automação Silenciosa**: `./app.sh --all` pede o sudo uma vez, o mantém ativo e o invalida ao terminar (`sudo -k`), não limpa a tela entre módulos, continua após falhas e termina com um resumo dos módulos que falharam e código de saída. O `.env` fornece `GIT_USERNAME`, `GIT_EMAIL`, `GITHUB_USER`, `GRUB_THEME_ARGS` e `UPDATE_POLICY`.
- **Fail-Fast**: `set -euo pipefail` em todos os módulos e `trap ERR` com `errtrace` no `lib.sh`, que aponta arquivo e linha mesmo para falhas dentro de funções.
- **Gestão de Temas (Orchis, Tela Circle, Vimix, GRUB)**: O `10-themesAndGrub.sh` instala Orchis, Tela Circle e Vimix (pulando os já instalados; são os temas que o módulo 11 ativa), oculta o GRUB (`TIMEOUT=0` e `STYLE=hidden`, adicionando a chave quando ausente) e instala o tema GRUB pessoal quando `GRUB_THEME_ARGS` está definido.
- **Revisão de 2026-10-02 (Fedora 44)**: Corrigidos o erro de sintaxe no 01; comandos do dnf4 inexistentes no dnf5 (`groupupdate`, `config-manager --set-enabled`/`--add-repo`); pacotes inexistentes no F44 que abortavam transações inteiras (`gnome-software-plugin-flatpak`, `java-21-openjdk-devel`, `mongodb-compass` no repositório do MongoDB); a remoção do `malcontent`; o `grub2-mkconfig` sobre o stub EFI; o instalador do tema GRUB abrindo TUI no modo headless; a linha do zoxide fundida no `.zshrc`; o menu do `app.sh` corrompido por variável global no laço; o username do GitHub fixo no 01; e o `.env.example` ignorado pelo git.
- **Checkup de 2026-10-03**: o módulo 09 respeita a versão padrão de Node já escolhida no fnm (antes trocaria a escolha do usuário); `app.sh` com `--help`, recusa de opções desconhecidas e Ctrl+C que interrompe só o módulo em execução; `detect_distro` recusa o Fedora Atomic; limite de 39 caracteres no `GITHUB_USER`; o 07 recria o `.pub` quando só existe a chave privada; o Orchis é instalado só na cor padrão (a usada); novo `tools/check.sh` com as verificações estáticas.

- **Pendências resolvidas em 2026-10-03 (aprovadas pelo usuário)**: tela de boot Plymouth deus_ex (pack_2 de adi1090x/plymouth-themes, clone esparso, também no Ubuntu via alternatives); `changeWallpaper` removido e papel de parede mantido manual (repositório público); ramo apt validado em container Ubuntu 24.04 (remoção de bloatware com simulação, repositórios por distro, EULA das fontes pré-aceita, eza nativo); driver VA-API conforme a GPU; avisos de firmware e reinício no 03; o `.zshrc` versionado passou a ser o de uso diário do usuário (funções `update`, `dnf*` e de git), com o caminho pessoal removido e o PATH do pnpm ajustado para `$PNPM_HOME/bin`; pnpm autônomo e Antigravity CLI pelos instaladores oficiais sem tocar no `.zshrc`; log de cada `--all`; CI no GitHub Actions; `tools/check.sh` reprodutível (shellcheck fixo, UTF-8, sem `awk` para larguras).
- **Política de versões (pedido do usuário em 2026-10-03)**: nada que já está instalado é atualizado em silêncio. Pacotes do sistema, Flatpaks, linguagens (Rust, Node, pnpm, uv), temas, Nerd Fonts, tema do GRUB, Plymouth, plugins do zsh, forks pessoais e extensões do GNOME mostram `atual -> nova` com o aviso de que versões novas podem quebrar recursos. Políticas `ask` (padrão do menu, uma pergunta por grupo), `update` e `keep` (padrão do `--all`), por flag (`--ask`, `--update`, `--keep`) ou `UPDATE_POLICY` no `.env`. Clones com alterações locais ou divergentes nunca são atualizados. Versões do que não vem de pacote ficam em `~/.local/state/dotfiles/versions/`. Correção junto: o keepalive do sudo segurava o log do `--all` aberto por até 50 s ao terminar.
- **Papel de parede e foto do usuário (pedido do usuário em 2026-10-03)**: novo módulo `12-wallpaperAndAvatar.sh`. As imagens vêm do `.env` (`WALLPAPER_IMAGE`, `AVATAR_IMAGE`) ou de um seletor de arquivos (`zenity`; sem ambiente gráfico, caminho digitado no terminal), e Cancelar mantém a atual. O papel de parede é copiado para `~/.local/share/backgrounds` (nome com hash do conteúdo, reaproveitado em novas execuções) e aplicado nas chaves que o GNOME Settings usa. A foto é recortada em quadrado e reduzida para 512x512 com GdkPixbuf (respeita a rotação EXIF) e entregue ao AccountsService sem sudo. As imagens continuam fora do repositório.
- **Detecção do GNOME (pedido do usuário em 2026-10-03)**: `is_gnome`, `gnome_only` e `require_gnome` no `lib.sh`. Em outros desktops, as etapas do GNOME são puladas com aviso, sem erro: forks das extensões (01), bloatware do GNOME e GNOME Tweaks (04, que agora só remove o LibreOffice fora do GNOME), Extension Manager (05), temas e `sassc` (10) e os módulos 11 e 12. O `tools/check.sh` exige a proteção em módulos que usam `gsettings`, `dconf` ou `gnome-extensions`.

---

## A REVISAR / CORRIGIR (To Review & Fix)
*Sem pendências.*

---

## A MELHORAR (To Implement / Improve)
**1. Antigravity Desktop**
- A CLI (`agy`) já é instalada pelo módulo 09. O aplicativo Desktop ainda depende de uma fonte oficial de instalação não interativa validada pelo usuário.

---

## A REMOVER (To Remove)
*As pastas `dev/` obsoletas e os scripts legados (`style/gnome/scripts/`) já foram removidos. Nada pendente para remoção.*
