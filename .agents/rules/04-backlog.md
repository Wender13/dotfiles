---
description: Documento mestre de revisão e auditoria do projeto. Contém o Kanban de tarefas.
trigger: always_on
---

# Revisão do Projeto e Backlog (Roadmap)

**STATUS DO PROJETO:** **ATIVO**
Revisão completa em 2026-10-02 no Fedora 44: os módulos foram corrigidos e validados por dry-run do dnf5, shellcheck e testes em `HOME` isolado. As pendências reais estão listadas abaixo; o ramo apt não foi revalidado.

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
- **Utilitários de Terminal Modernizados**: `btop`, `bat`, `eza`, `zoxide` (iniciado pelo `.zshrc` só se estiver instalado) e `tldr`, junto com as Nerd Fonts JetBrainsMono e FiraCode (pacotes `.tar.xz`, 15 vezes menores que os `.zip`).
- **Refatoração de Performance em Gerenciadores de Pacote**: O `04-commonPrograms.sh` divide os pacotes em variáveis de categorias lógicas (`CLI_TOOLS`, `DATABASES` etc.), executadas numa única transação.
- **Modo "Non-Interactive" / Automação Silenciosa**: `./app.sh --all` pede o sudo uma vez, o mantém ativo e o invalida ao terminar (`sudo -k`), não limpa a tela entre módulos, continua após falhas e termina com um resumo dos módulos que falharam e código de saída. O `.env` fornece `GIT_USERNAME`, `GIT_EMAIL`, `GITHUB_USER` e `GRUB_THEME_ARGS`.
- **Fail-Fast**: `set -euo pipefail` em todos os módulos e `trap ERR` com `errtrace` no `lib.sh`, que aponta arquivo e linha mesmo para falhas dentro de funções.
- **Gestão de Temas (Orchis, Tela Circle, Vimix, GRUB)**: O `10-themesAndGrub.sh` instala Orchis, Tela Circle e Vimix (pulando os já instalados; são os temas que o módulo 11 ativa), oculta o GRUB (`TIMEOUT=0` e `STYLE=hidden`, adicionando a chave quando ausente) e instala o tema GRUB pessoal quando `GRUB_THEME_ARGS` está definido.
- **Revisão de 2026-10-02 (Fedora 44)**: Corrigidos o erro de sintaxe no 01; comandos do dnf4 inexistentes no dnf5 (`groupupdate`, `config-manager --set-enabled`/`--add-repo`); pacotes inexistentes no F44 que abortavam transações inteiras (`gnome-software-plugin-flatpak`, `java-21-openjdk-devel`, `mongodb-compass` no repositório do MongoDB); a remoção do `malcontent`; o `grub2-mkconfig` sobre o stub EFI; o instalador do tema GRUB abrindo TUI no modo headless; a linha do zoxide fundida no `.zshrc`; o menu do `app.sh` corrompido por variável global no laço; o username do GitHub fixo no 01; e o `.env.example` ignorado pelo git.
- **Checkup de 2026-10-03**: o módulo 09 respeita a versão padrão de Node já escolhida no fnm (antes trocaria a escolha do usuário); `app.sh` com `--help`, recusa de opções desconhecidas e Ctrl+C que interrompe só o módulo em execução; `detect_distro` recusa o Fedora Atomic; limite de 39 caracteres no `GITHUB_USER`; o 07 recria o `.pub` quando só existe a chave privada; o Orchis é instalado só na cor padrão (a usada); novo `tools/check.sh` com as verificações estáticas.

---

## A REVISAR / CORRIGIR (To Review & Fix)
**1. Plymouth sem origem definida**
- O `10-themesAndGrub.sh` só instala um tema Plymouth se existir `~/Dev/linux_projects/gnome/plymouth/install.sh`, mas nenhum módulo coloca nada nessa pasta. Hoje a etapa é sempre pulada. Decidir o repositório do tema (ou remover a etapa).

**2. Ramo apt sem validação**
- As correções foram validadas apenas no Fedora 44. No ramo apt continuam pontos frágeis: o codinome `noble` fixo no repositório do MongoDB, a remoção de bloatware com `|| true` sem checagem de dependências reversas e o `cargo install eza` como alternativa.

**3. Papel de parede não versionado**
- O exportador descarta `picture-uri` porque a imagem fica fora do repositório (`~/.local/share/backgrounds`). O `style/gnome/bin/changeWallpaper` existe, mas nenhum módulo o usa. Decidir se a imagem (ou uma pasta de papéis de parede) entra no repositório.

**4. Aliases desatualizados no `.zshrc`**
- `dotf` aponta para `~/Dev/linux_projects/dotfiles`, que não é o local atual do repositório.
- `codef` executa o VSCode Flatpak, mas o VSCode é instalado via repositório RPM/DEB.
- O bloco do NVM não é mais usado (o Node vem do fnm) e o alias `atualizar` repete `dnf update` e `dnf upgrade` (são o mesmo comando) sem atualizar os Flatpaks.

---

## A MELHORAR (To Implement / Improve)
**1. Integração do Antigravity CLI e Desktop**
- Injetar os binários de acesso do Antigravity (`agy`) nos scripts assim que as fontes oficiais de instalação em lote (Headless) do Desktop forem validadas pelo usuário.

**2. Sistema de Log e Monitoramento**
- Atualmente o feedback é apenas visual no terminal. Seria ideal ter um arquivo `setup.log` capturando toda a saída (STDOUT e STDERR) do `app.sh` e dos módulos para debug futuro.
**3. Integração Contínua (CI)**
- Workflow do GitHub Actions rodando `bash tools/check.sh` a cada push, para pegar erros de sintaxe, shellcheck e convenções antes de chegarem a uma máquina nova.

**4. Aceleração de vídeo por hardware**
- Instalar o driver de VA-API conforme a GPU detectada (`intel-media-driver`; `mesa-va-drivers-freeworld` para AMD; driver NVIDIA do RPM Fusion), como recomenda o guia de multimídia do RPM Fusion. Depende do hardware de cada máquina.

**5. Firmware e reinício no módulo 03**
- Atualizar firmware com `fwupdmgr` e avisar quando o sistema precisa reiniciar após a atualização (kernel, glibc).

**6. pnpm independente da versão do Node**
- Hoje o pnpm é instalado com `npm install -g` dentro da versão do Node ativa no fnm; ao trocar de versão, ele some. Avaliar o instalador oficial do pnpm ou o Corepack.


---

## A REMOVER (To Remove)
*As pastas `dev/` obsoletas e os scripts legados (`style/gnome/scripts/`) já foram removidos. Nada pendente para remoção.*
