# Linux Desktop Automation (Dotfiles Setup)

Coleção de scripts Bash que transforma uma instalação limpa de Linux em um ambiente de desenvolvimento completo: programas, codecs, repositórios oficiais, ferramentas de linguagem, terminal, temas, extensões, configurações e atalhos do GNOME, e bootloader. A ideia é não precisar configurar nada à mão depois.

- **Alvo principal**: Fedora 41 ou superior (dnf5), com GNOME. Validado no Fedora 44.
- **Outros desktops** (KDE, Xfce, COSMIC...): o app detecta o GNOME e, fora dele, pula com um aviso tudo o que é do GNOME (configurações, extensões, temas, GNOME Tweaks, Extension Manager, papel de parede e foto). O resto funciona normalmente.
- **Suporte secundário**: Debian, Ubuntu e derivados (apt). Validado por simulação num container Ubuntu 24.04, não numa instalação real.
- **Não suportado**: RHEL, CentOS, Rocky e Alma (o ramo dnf depende de repositórios exclusivos do Fedora) e Fedora Atomic (Silverblue, Kinoite), onde pacotes são aplicados com rpm-ostree.

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
- [Licença](#licença)

## Requisitos
- Usuário comum com permissão de `sudo`. **Não execute como root nem com `sudo ./app.sh`**: os módulos instalam coisas no `$HOME` e pedem `sudo` só quando precisam (o projeto bloqueia a execução como root).
- `git` para clonar o repositório e conexão com a internet.
- Interface gráfica (opcional): Python com GTK 4, libadwaita e VTE. Já vêm no Fedora Workstation; no Ubuntu, `sudo apt install python3-gi gir1.2-adw-1 gir1.2-vte-3.91`.
- Fedora Workstation (GNOME) para a experiência completa. Em outros desktops, as etapas do GNOME são puladas (ver [Módulos](#módulos)). A parte de boot do módulo 10 assume GRUB; sem `/etc/default/grub`, ela é pulada.

## Início rápido
```bash
git clone <url-deste-repositorio> dotfiles
cd dotfiles
cp .env.example .env      # opcional, mas necessário para rodar sem perguntas
$EDITOR .env
./app.sh                  # menu interativo
./app.sh --gui            # ou a interface gráfica
./app.sh --only-missing   # numa máquina já configurada em parte (caso de uso 4)
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
| `CONFIG_MODE` | todos | O que fazer com o que o sistema já tem: `full` (aplica a configuração do repositório) ou `missing` (só instala e configura o que falta; ver caso de uso 4) | `full` |
| `UPDATE_POLICY` | todos | O que fazer com o que já está instalado e tem versão nova: `ask`, `update` ou `keep` (ver caso de uso 5) | Menu: `ask`; `--all`: `keep` |
| `WALLPAPER_IMAGE` | 12 | Imagem do papel de parede (caminho absoluto ou `~/...`) | Abre um seletor de arquivos (Cancelar mantém o atual) |
| `AVATAR_IMAGE` | 12 | Imagem da foto do usuário (caminho absoluto ou `~/...`) | Abre um seletor de arquivos (Cancelar mantém a atual) |

No Fedora, inclua `-b` em `GRUB_THEME_ARGS`: o `/boot` é uma partição separada, e o tema precisa ficar em `/boot/grub2/themes`.

## Casos de uso

### 1. Configurar uma máquina nova do zero, sem supervisão
```bash
cp .env.example .env && $EDITOR .env   # preencha todas as chaves
./app.sh --all
```
- A senha do `sudo` é pedida **uma única vez**, no início, e mantida ativa durante toda a execução. Ao terminar, as credenciais em cache são invalidadas (`sudo -k`).
- Os módulos rodam em ordem (01 a 12), sem limpar a tela, então a saída de cada um fica no histórico do terminal.
- Por padrão o `--all` **não mexe no que já está instalado** (política `keep`): só instala o que falta e lista o que tem versão mais nova. Para ser perguntado, use `./app.sh --all --ask`; para atualizar tudo, `./app.sh --all --update` (caso de uso 5).
- Rode a partir de um terminal **dentro da sessão do GNOME**: os módulos 11 e 12 aplicam as configurações pela sessão gráfica.
- A máquina já está configurada em parte? Use `./app.sh --all --only-missing`: nada é removido e o que você já configurou fica (caso de uso 4).
- Se um módulo falhar, os seguintes continuam. No fim aparece a lista dos módulos com falha, e o comando sai com código `1` (ou `0` se tudo deu certo).
- Sem `.env`, o 01 e o 07 fazem perguntas no meio da execução, e o 12 abre o seletor de arquivos para o papel de parede e a foto do usuário (Cancelar mantém os atuais).
- **Log completo** de cada execução em `~/.local/state/dotfiles/logs/setup-<data>.log` (pasta só sua, os 10 mais recentes são mantidos); o caminho aparece no resumo final. Leia com `less -R`. Só a saída é gravada: a senha digitada nunca vai para o log.
- Depois de terminar, **faça logout e login** (ou reinicie) para aplicar o shell zsh, o grupo `docker` e as fontes.

### 2. Escolher módulos específicos (menu ou interface gráfica)
```bash
./app.sh
```
Digite o número do módulo, acompanhe a execução, pressione Enter para voltar ao menu e `q` para sair. **Ctrl+C** durante um módulo interrompe só aquele módulo e volta ao menu; no prompt do menu, Ctrl+C sai. `./app.sh --help` mostra as opções. No menu, a política de versões padrão é perguntar (`ask`); `./app.sh --update` ou `./app.sh --keep` mudam isso (caso de uso 5). O resultado (sucesso ou status de erro) aparece ao fim de cada módulo.

**Interface gráfica** (`./app.sh --gui`): uma janela nativa do GNOME (GTK 4 + libadwaita) com os mesmos módulos, agrupados por categoria.
- **Segue o tema do sistema**: claro ou escuro, a cor de destaque e o alto contraste mudam junto com o GNOME, na hora. No menu da janela (botão de três linhas), **System / Light / Dark** força o claro ou o escuro; a escolha fica salva.
- Clique num módulo, confirme, e ele roda num **terminal embutido**: a senha do `sudo`, as perguntas de versão e o seletor de imagens do 12 aparecem ali, como no terminal. **Stop** envia Ctrl+C. No fim, a barra inferior mostra sucesso, interrupção ou o status de erro.
- No topo: a chave **Only What Is Missing** (o modo completar do caso de uso 4; ligada, ela muda a política para Keep), a política de versões (**Ask**, **Update** ou **Keep**; os valores iniciais vêm das flags ou do `.env`), **Run All** (o mesmo que `./app.sh --all`, com log) e **.env** (cria a partir do `.env.example` ou abre para editar).
- **Add to Applications Menu**, no menu da janela, cria o atalho no menu de aplicativos do GNOME; **Open Logs Folder** abre os logs do `--all`.
- Fora do GNOME, um aviso no topo lembra que as etapas do GNOME serão puladas.

### 3. Executar um módulo isolado, sem o menu
```bash
bash scripts/05-flatpakPrograms.sh
```
Útil em scripts próprios ou para repetir uma única etapa. Cada módulo funciona sozinho: dependências básicas (git, curl, flatpak, zsh) são instaladas se faltarem.

### 4. Completar um sistema já configurado (ou uma instalação interrompida)
Para uma instalação interrompida, rode o mesmo módulo (ou o `--all`) de novo. O que já foi feito é detectado e pulado: pacotes instalados, repositórios configurados, clones existentes, fontes, temas, Node LTS e a chave SSH. O que já existe só é atualizado conforme a política de versões (caso de uso 5).

Numa máquina **que você já configurou em parte** (à mão ou com outra ferramenta), use o **modo completar**, que instala e configura só o que falta:
```bash
./app.sh --all --only-missing   # ou ./app.sh --only-missing para escolher os módulos
```
Na interface gráfica, é a chave **Only What Is Missing**. Para deixar como padrão, use `CONFIG_MODE=missing` no `.env`; `--full` volta ao comportamento normal numa execução.

As regras do modo completar:
1. **Instala só o que falta**: pacotes, Flatpaks, repositórios, temas, fontes, ferramentas e extensões que ainda não existem.
2. **Não desinstala nada**: o LibreOffice e o bloatware do GNOME ficam. (A troca do `ffmpeg-free` pelo `ffmpeg` completo continua: ela só acrescenta codecs.)
3. **Não atualiza**: a política de versões passa a ser `keep`, a menos que você escolha outra com `--ask`/`--update` ou no `.env`.
4. **Não sobrescreve**: arquivos só são criados se não existem, e chaves só são gravadas se ainda estão no padrão. O que você personalizou fica.
5. **Ajustes que sempre têm valor ficam como estão** (shell padrão, GRUB, tela de boot, papel de parede, serviço do Docker), exceto quando o programa é instalado na mesma execução: um Docker recém-instalado é habilitado, e um zsh recém-instalado vira o shell padrão.

O que muda em cada módulo:

| Módulo | No modo completar |
| --- | --- |
| 01 | Clona só os forks que faltam; se todos já existem, nem pede o usuário do GitHub |
| 04 | Não remove nenhum programa; instala os que faltam |
| 06 | Mantém os arquivos de repositório que já existem (`vscode.repo` etc.) e o estado do repositório do Chrome se ele já está instalado; serviço e grupo do Docker só são configurados se o Docker foi instalado agora |
| 07 | Mantém nome, e-mail, branch padrão e cores do Git já definidos, sem perguntar; grava só os que faltam |
| 08 | Mantém o seu `~/.zshrc` (cria se não existir) e o shell padrão |
| 10 | Instala os temas que faltam; mantém as configurações do GRUB, um tema do GRUB que você já usa e a tela de boot atual |
| 11 | Instala as extensões que faltam; aplica só as configurações do GNOME que você ainda não definiu; acrescenta à sua lista de extensões ativas as do repositório que você não ativou nem desativou |
| 12 | Mantém o papel de parede e a foto que você já escolheu; só pergunta o que ainda está no padrão |
| 02, 03, 05, 09 | Iguais: só instalam o que falta (o 03 só lista as atualizações, pela política `keep`) |

Cada item mantido aparece na saída como "Only-missing mode: keeping ...". Os Flatpaks e pacotes da lista que você desinstalou de propósito voltam a ser instalados (não há como distinguir "nunca instalado" de "removido"); para evitar, rode pelo menu só os módulos que quiser.

### 5. Controlar versões do que já está instalado
Quando um pacote, aplicativo, linguagem, tema, fonte, plugin ou extensão **já está instalado e existe versão mais nova**, o app segue uma de três políticas:

| Política | Como ativar | O que acontece |
| --- | --- | --- |
| `ask` (perguntar) | padrão do menu; `./app.sh --ask` ou `./app.sh --all --ask` | Mostra `versão atual -> versão nova`, avisa que **versões novas podem mudar comportamento ou quebrar recursos** e pergunta. A resposta padrão (Enter) é **manter**. |
| `update` (atualizar) | `./app.sh --update` ou `./app.sh --all --update` | Atualiza tudo o que tiver versão mais nova, mostrando o mesmo aviso. |
| `keep` (manter) | padrão do `--all`; `./app.sh --keep` | Nunca mexe no que já está instalado; só instala o que falta e lista o que poderia ser atualizado. |

Para mudar o padrão, defina `UPDATE_POLICY=ask`, `update` ou `keep` no `.env`; uma flag na linha de comando tem prioridade. A política em uso aparece no topo do menu. Sem um terminal para responder (por exemplo, com a entrada redirecionada), `ask` vira `keep`.

As perguntas são **uma por grupo** (por exemplo, "04 - programas comuns: 6 item(s) com versão mais nova"), e **uma por linguagem**, porque trocar a versão delas é o que mais quebra projetos:

| O que | Como a versão é comparada | Como atualiza |
| --- | --- | --- |
| Pacotes dnf/apt (04, 06, 09, 10, extensões empacotadas no 11) | versão instalada x repositório | `dnf upgrade` / `apt-get install --only-upgrade` só dos itens listados |
| Flatpaks (05) | `flatpak remote-ls --updates` | `flatpak update` dos itens listados |
| Rust | `rustup check` | `rustup update` |
| Node.js | versão padrão do fnm x LTS mais recente | instala o LTS e o define como padrão (pacotes globais do npm ficam na versão anterior) |
| pnpm | versão x registro do npm | `pnpm self-update` |
| uv (instalado pelo script oficial, no ramo apt) | versão x último release | `uv self update` |
| Temas (Orchis, Tela Circle, Vimix), Plymouth e Nerd Fonts | versão registrada x origem (commit ou release) | reinstala a versão nova |
| oh-my-zsh, plugins, Spaceship e seus forks | commits novos no repositório de origem | avanço rápido (`git merge --ff-only`); repositórios com alterações locais ou histórico divergente nunca são tocados |
| Tema do GRUB | commit do fork + opções do `.env` | reinstala |
| Extensões do extensions.gnome.org | versão instalada x publicada para o seu GNOME | baixa e instala a versão nova |

Claude Code, Antigravity CLI e Docker Desktop se atualizam sozinhos; o app só informa que já estão instalados. As versões de temas, fontes e tema do GRUB ficam registradas em `~/.local/state/dotfiles/versions/`; o que foi instalado antes desse registro aparece como versão "desconhecida".

### 6. Manter o sistema atualizado
- Módulo `03`: `dnf upgrade --refresh`, `dnf autoremove` e `flatpak update`, seguindo a política de versões: com `keep` só lista o que há para atualizar; com `ask` mostra a lista e pergunta uma vez para o sistema e uma vez para os Flatpaks. No fim, **avisa** se há atualização de firmware (`fwupdmgr`; aplicar fica a seu critério com `fwupdmgr update`) e se é preciso reiniciar (kernel, glibc etc.).
- No dia a dia, a função `update` do `.zshrc` atualiza pacotes e Flatpaks, limpa o cache e os Flatpaks sem uso e avisa se é preciso reiniciar.

### 7. Configurar identidade Git e chave SSH (módulo 07)
Define nome, e-mail, branch padrão `main` e cores, e gera uma chave `ed25519` em `~/.ssh/id_ed25519` se ainda não existir nenhuma chave pública. Ao final, a chave pública é exibida para você cadastrar no GitHub/GitLab.
A chave é gerada **sem passphrase**, para não travar o modo automático. Se quiser uma, rode depois `ssh-keygen -p -f ~/.ssh/id_ed25519`.

### 8. Restaurar o terminal em outra máquina (módulo 08)
Instala zsh, oh-my-zsh, os plugins (k, autosuggestions, syntax-highlighting, completions), o tema Spaceship e as Nerd Fonts JetBrainsMono e FiraCode. Também define o zsh como shell padrão e copia `terminal/.zshrc` para `~/.zshrc`.
Se o seu `~/.zshrc` for diferente do versionado, um backup é salvo como `~/.zshrc.bak.<data>` antes da cópia. Para versionar mudanças pessoais, edite `terminal/.zshrc` no repositório e rode o 08 de novo.

O `.zshrc` versionado é o que o dono do repositório usa no dia a dia. Além do tema Spaceship (com usuário, máquina e horário no prompt) e do histórico compartilhado de 50 mil linhas, ele traz:
- **Sistema**: `update` (atualização completa), `dnfs`/`dnfi`/`dnfr` (buscar, instalar e remover pacotes), `dnfinfo`, `dnfp` (qual pacote fornece um arquivo), `dnfl` (pacotes instalados, com filtro opcional) e `dnfh` (histórico do dnf).
- **Git**: `gcommit` (add + commit), `gship` (add + commit + push), `gpush`, `gnew` (nova branch), `gsync` (fetch + pull com rebase), `gundo` (desfaz o último commit mantendo as mudanças), `gfix` (emenda o último commit), `glogp` (log em grafo), `gprune` (apaga branches já mescladas) e `gsave` (stash rápido).
- **Atalhos**: `ll` (listagem com o **eza**: cores, ícones e status do git de cada arquivo; usa o `ls` se o eza não estiver instalado), `lt` (árvore de 2 níveis), `..`, `...`, `zshconfig` (edita o `.zshrc`) e `zshreload`.
- **Navegação com o zoxide**: `z <parte do nome>` pula para uma pasta já visitada (ex: `z dotfiles`); `zi` escolhe numa lista interativa.
- **bat**: `bat arquivo` mostra o arquivo com destaque de sintaxe e números de linha; o `cat` continua o original.
- **Ambientes**: PATH de `~/.local/bin`, fnm, pnpm e cargo; inicialização do conda, se ele existir em `~/anaconda3`.

### 9. Preparar ambientes de desenvolvimento (módulos 04, 06 e 09)
- **04**: compiladores, cmake, Python, Java (25 e latest), Maven, MariaDB, SQLite, PostgreSQL e Podman.
- **06**: VSCode, Google Chrome, MongoDB 8.0 (com mongosh), Docker Engine (com buildx e compose), todos de repositórios oficiais e atualizados pelo `dnf upgrade`, e o Docker Desktop.
- **09**: dependências do Tauri, Rust (rustup/cargo), eza, uv (Python), Node.js LTS (fnm; uma versão padrão que você já tenha escolhido é mantida), **pnpm** autônomo (instalador oficial, em `~/.local/share/pnpm`, independente da versão do Node) e duas CLIs de IA pelos instaladores oficiais, ambas em `~/.local/bin` e com atualização automática: **Claude Code** (`claude`) e **Antigravity** (`agy`). O que já estiver instalado é pulado. Os instaladores do pnpm e do Antigravity tentam editar o perfil do shell; eles rodam com um `HOME` temporário para não mexer no `~/.zshrc` gerenciado pelo repositório.

Os bancos de dados são apenas instalados; inicialização e serviços ficam a seu critério (ex: `sudo postgresql-setup --initdb`, `sudo systemctl enable --now mariadb`, `sudo systemctl start mongod`).

### 10. Personalizar o visual e o boot (módulos 01 e 10)
1. Defina `GITHUB_USER` e `GRUB_THEME_ARGS` no `.env`.
2. Rode o **01**: ele clona seus forks (extensões, só no GNOME, e tema GRUB) para `~/Dev/linux_projects/gnome/`.
3. Rode o **10**: ele instala o tema GTK Orchis, os ícones Tela Circle e os cursores Vimix (só no GNOME, pulando os já instalados), oculta o menu do GRUB (`GRUB_TIMEOUT=0`, `GRUB_TIMEOUT_STYLE=hidden`), instala o tema do GRUB e regenera a configuração. Também instala a tela de boot **Plymouth deus_ex** (do pack_2 de [adi1090x/plymouth-themes](https://github.com/adi1090x/plymouth-themes), baixando só esse tema) e reconstrói o initramfs; se ela já for a ativa, nada é feito.
4. Rode o **11** para ativar os temas e o restante das configurações (caso de uso 12).

O `/etc/default/grub` original é salvo uma única vez como `/etc/default/grub.bak`. Para restaurá-lo:
```bash
sudo cp /etc/default/grub.bak /etc/default/grub
sudo grub2-mkconfig -o /boot/grub2/grub.cfg
```
O menu do GRUB continua acessível: no Fedora, ele reaparece automaticamente após uma falha de boot.

### 11. Instalar os aplicativos de desktop (módulo 05)
Via Flathub (atualização automática): Obsidian, Postman, Insomnia, OnlyOffice, Discord, DBeaver, MongoDB Compass, LocalSend, Extension Manager (só no GNOME), Prism Launcher, Zotero, Podman Desktop e Inkscape.

### 12. Restaurar extensões, configurações e atalhos do GNOME (módulo 11)
Deixa o GNOME igual ao da máquina de onde as configurações foram capturadas, sem abrir o Settings nem o Extension Manager:
- **Extensões**: instala as listadas em `style/gnome/extensions.txt` (hoje: User Themes, Clipboard History, Vertical App Grid, Blur my Shell, Just Perfection, Burn My Windows, Compiz Magic Lamp, Lock Keys, Caffeine e Advanced Alt+Tab Window Switcher). Usa o pacote do Fedora quando ele existe; as demais vêm do extensions.gnome.org, na versão do seu GNOME Shell.
- **Configurações das extensões**: blur, efeitos de janela (incluindo o perfil do Burn My Windows), painel do Just Perfection, grade de apps e tema do shell.
- **Sistema**: tema escuro, Orchis-Dark, ícones Tela-circle-dark, cursores Vimix, porcentagem da bateria, teclado ABNT2 (`br`), touchpad, tempo de inatividade, suspensão, luz noturna, lembretes de pausa e limite de tempo de tela.
- **Dock**: apps fixados (Arquivos, Firefox, Chrome, VSCode, Postman, DBeaver e Terminal).
- **Atalhos**: todos os do sistema e os personalizados, por exemplo `Super+T` para o terminal, `Super+W` para fechar a janela, `Super+E` para a pasta pessoal, `Alt+Super+N` para o Chrome e `Ctrl+Alt+Shift+P`/`R` para desligar/reiniciar.
- **Apps**: preferências e atalhos do terminal Ptyxis.

Rode de um terminal dentro da sessão do GNOME e, no fim, **faça logout e login** para as extensões novas carregarem. Em outro desktop, o módulo avisa e termina sem fazer nada. Rodar de novo não reinstala o que já existe e só reaplica as mesmas chaves. Para que os temas apareçam, o módulo 10 deve ter rodado antes.

O papel de parede e a foto do usuário não ficam no repositório (ele é público, e as imagens são pessoais ou têm direitos autorais): escolha-os com o módulo 12 (caso de uso 14).

### 13. Salvar no repositório as configurações atuais do GNOME
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

### 14. Escolher o papel de parede e a foto do usuário (módulo 12)
```bash
./app.sh    # e escolha o 12
```
- Para cada um, abre um seletor de arquivos na sua pasta de imagens. **Cancelar mantém o atual.** Sem ambiente gráfico, o caminho é digitado no terminal (Tab completa).
- Com `WALLPAPER_IMAGE` e `AVATAR_IMAGE` no `.env`, as imagens são aplicadas sem perguntar, inclusive no `--all`.
- **Papel de parede**: como no GNOME Settings, uma cópia vai para `~/.local/share/backgrounds` (o papel de parede continua lá mesmo se o original for movido ou apagado) e é aplicada nos estilos claro e escuro e na tela de bloqueio. Escolher a mesma imagem de novo reaproveita a cópia.
- **Foto do usuário**: o centro da imagem é recortado em quadrado e reduzido para 512x512, o tamanho que o GNOME Settings usa, respeitando a rotação da foto (EXIF). Aparece na tela de login, na tela de bloqueio e no menu do sistema. Não precisa de `sudo`.
- A imagem é aberta pela mesma biblioteca que o GNOME usa para desenhá-la (GdkPixbuf); um arquivo que não seja imagem é recusado com erro antes de qualquer mudança.
- Só no GNOME: em outro desktop, o módulo avisa e termina sem fazer nada.

### 15. Adicionar uma nova etapa de automação
Veja [Desenvolvimento](#desenvolvimento). Basta criar `scripts/NN-nome.sh` com o cabeçalho certo: o menu e o `--all` passam a incluí-lo automaticamente.

### 16. Usar agentes de IA para manter o projeto
Antigravity, Claude Code, Cursor e GitHub Copilot já encontram as regras do projeto. Veja [Trabalhando com agentes de IA](#trabalhando-com-agentes-de-ia).

## Módulos

| Nº | Script | O que faz | sudo |
| --- | --- | --- | --- |
| 01 | `01-setupEnv.sh` | Cria `~/Dev/{linux_projects,personal_projects,college_projects}` e clona os forks pessoais das extensões do GNOME (só no GNOME) e do tema GRUB | não |
| 02 | `02-permissions.sh` | Dá permissão de execução a `app.sh` e aos scripts de `scripts/`, `style/` e `tools/` | não |
| 03 | `03-update.sh` | Atualiza pacotes do sistema e Flatpaks conforme a política de versões, remove dependências órfãs e avisa sobre firmware e reinício | sim |
| 04 | `04-commonPrograms.sh` | Remove LibreOffice e, no GNOME, o bloatware do GNOME; habilita o RPM Fusion; instala codecs (ffmpeg completo e grupo multimedia) e o driver de aceleração de vídeo da GPU detectada (AMD ou Intel; NVIDIA só recebe um aviso); instala ferramentas de CLI (zsh, git, fzf, btop, bat, eza, zoxide, tldr, curl, wget, script), apps (VLC, Tilix, GIMP, OBS Studio e, no GNOME, GNOME Tweaks), ferramentas de dev, bancos de dados, Podman, Flatpak, Python, Java, Maven e powerline-fonts; garante o Flathub. No apt, só remove o bloatware que não arrastaria outros pacotes | sim |
| 05 | `05-flatpakPrograms.sh` | Instala os aplicativos Flatpak listados no caso de uso 11 que faltam; atualizações seguem a política de versões | sim |
| 06 | `06-externalRepos.sh` | Configura os repositórios oficiais e instala VSCode, Chrome, MongoDB, Docker CE e Docker Desktop; habilita o serviço docker e adiciona o usuário ao grupo `docker` | sim |
| 07 | `07-gitAndSSH.sh` | Identidade Git global e chave SSH ed25519 | não |
| 08 | `08-terminalAndShell.sh` | zsh, oh-my-zsh, plugins, Spaceship, Nerd Fonts, shell padrão e `.zshrc` | só para trocar o shell |
| 09 | `09-devEnvironments.sh` | Dependências do Tauri e toolchain C, Rust, eza, uv, Node.js LTS (fnm), pnpm autônomo, Claude Code e Antigravity CLI (instaladores oficiais) | sim |
| 10 | `10-themesAndGrub.sh` | Orchis, Tela Circle e Vimix (só no GNOME), GRUB oculto, tema GRUB opcional e tela de boot Plymouth deus_ex | sim |
| 11 | `11-gnomeSettings.sh` | Só no GNOME: extensões, configurações do sistema e das extensões, apps do dock e atalhos | só para extensões empacotadas no Fedora |
| 12 | `12-wallpaperAndAvatar.sh` | Só no GNOME: papel de parede e foto do usuário, escolhidos num seletor de arquivos ou pelo `.env` | só para instalar o `zenity` (seletor), se faltar |

No Fedora, o pacote `malcontent` (controle parental) **não** é removido, porque o GNOME Settings depende dele; sai apenas a interface `malcontent-control`.

**Fora do GNOME**, cada módulo pula a sua parte do GNOME e avisa ("GNOME not detected"): o 01 não clona os forks das extensões, o 04 não remove o bloatware do GNOME (só o LibreOffice) nem instala o GNOME Tweaks, o 05 não instala o Extension Manager, o 10 não instala os temas (GRUB e Plymouth continuam), e o 11 e o 12 terminam sem fazer nada. O GNOME é detectado quando o GNOME Shell está instalado e a sessão gráfica é GNOME (`XDG_CURRENT_DESKTOP`); rodando por TTY ou SSH, basta o GNOME Shell estar instalado.

## O que o projeto altera no sistema
Transparência sobre tudo o que sai do `$HOME` (no modo completar, do caso de uso 4, nada é removido e o que já existe fica como está):
- **Pacotes**: instalações e remoções via dnf/apt e Flatpak de sistema.
- **Repositórios**: RPM Fusion; `/etc/yum.repos.d/` (`vscode.repo`, `mongodb-org-8.0.repo`, `docker-ce.repo`); habilitação do repositório `google-chrome`; remoto Flathub habilitado e sem filtro.
- **Serviços e grupos**: `docker` habilitado e iniciado; seu usuário entra no grupo `docker`.
- **Usuário**: o shell padrão passa a ser o zsh (`usermod --shell`); a foto escolhida no módulo 12 é entregue ao AccountsService, que guarda a cópia dele em `/var/lib/AccountsService/icons/`.
- **Boot**: `/etc/default/grub` (com backup) e `/boot/grub2/grub.cfg`; tema GRUB em `/boot/grub2/themes` (com `-b`); tema Plymouth em `/usr/share/plymouth/themes/deus_ex`, com o initramfs reconstruído.
- **Configurações do GNOME (dconf do seu usuário)**: as chaves de `style/gnome/dconf/*.ini`. Só as chaves listadas são alteradas; o resto fica como está. O módulo 12 altera também o papel de parede (`org.gnome.desktop.background` e `org.gnome.desktop.screensaver`).
- **No `$HOME`**: `~/Dev`, `~/.oh-my-zsh`, `~/.zshrc` (com backup), `~/.local/share/fonts/NerdFonts`, temas em `~/.themes` e `~/.local/share/icons`, extensões em `~/.local/share/gnome-shell/extensions`, `~/.config/burn-my-windows`, cópias dos papéis de parede em `~/.local/share/backgrounds`, `~/.cargo`, `~/.rustup`, `~/.local/share/fnm`, `~/.local/share/pnpm`, Claude Code em `~/.local/bin/claude` e `~/.local/share/claude`, Antigravity em `~/.local/bin/agy`, logs em `~/.local/state/dotfiles/logs`, versões registradas em `~/.local/state/dotfiles/versions`, preferência de tema da interface gráfica em `~/.config/dotfiles/gui.ini` e o atalho dela em `~/.local/share/applications/local.dotfiles.Setup.desktop` (só se você pedir), `~/.gitconfig` e `~/.ssh`.

## Solução de problemas
- **"No graphical display found"** ou **"The graphical interface needs GTK 4, libadwaita and VTE"** (`--gui`): rode de dentro da sessão gráfica e instale o que a mensagem indicar; o menu do terminal (`./app.sh`) faz o mesmo.
- **Algo falhou no `--all` e a saída já rolou da tela**: veja o log indicado no resumo final (`~/.local/state/dotfiles/logs/`).
- **"[ERRO CRITICO] Falha na execucao do script!"**: a mensagem mostra o arquivo, a linha, o comando e o status. Corrija a causa (rede, repositório fora do ar, pacote renomeado) e rode o módulo de novo.
- **"No match for argument" no dnf**: um pacote foi renomeado ou removido numa nova versão do Fedora. Confira com `dnf repoquery --available <nome>` e atualize a lista no módulo.
- **"Do not run this as root"**: rode como seu usuário, sem `sudo` na frente.
- **"Fedora 41+ (dnf5) is required"** ou **"Unsupported distribution"**: a distribuição não é suportada (ver o topo deste README).
- **`docker` exige sudo**: faça logout e login para o grupo `docker` valer.
- **O terminal continua no bash**: o novo shell vale a partir do próximo login.
- **O tema do GRUB não foi instalado**: defina `GRUB_THEME_ARGS` e `GITHUB_USER` no `.env` e rode o 01 e o 10.
- **O `--all` parou pedindo dados**: falta alguma chave no `.env` (ver [Configuração](#configuração-env)).
- **"Only-missing mode: keeping ..."**: não é erro. No modo completar, o que você já tinha foi mantido; para aplicar a configuração do repositório nesse item, rode o módulo sem `--only-missing`.
- **"GNOME not detected"**: a sessão gráfica não é o GNOME (ou o GNOME Shell não está instalado), e as etapas do GNOME foram puladas de propósito. Se você está no GNOME, rode de um terminal aberto dentro da sessão.
- **"No D-Bus session found" nos módulos 11 e 12**: rode a partir de um terminal aberto dentro da sessão do GNOME, não por SSH ou TTY.
- **"Could not install <extensão> for GNOME Shell N"**: a extensão ainda não tem versão para o seu GNOME (comum logo após uma atualização do Fedora). As configurações são aplicadas mesmo assim; rode o 11 de novo mais tarde.
- **Extensões instaladas mas inativas**: faça logout e login (no Wayland o GNOME só carrega extensões novas ao iniciar a sessão).

## Estrutura do projeto
```text
.
├── app.sh                  # Ponto de entrada: menu interativo, modo --all e --gui
├── gui/                    # Interface gráfica (dotfiles_gui.py) e o ícone dela
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
└── .github/
    ├── copilot-instructions.md  # Ponto de entrada do GitHub Copilot
    └── workflows/check.yml      # CI: roda o tools/check.sh a cada push
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
| `is_gnome` | Verdadeiro quando o GNOME é detectado (sem mensagem) |
| `gnome_only "etapa"` | Para etapas do GNOME: `if gnome_only "GNOME Tweaks"; then ...; fi`. Fora do GNOME, avisa o que foi pulado |
| `require_gnome` | Para módulos que só configuram o GNOME: fora dele, encerra o módulo com sucesso |
| `ensure_command cmd [pkg_apt] [pkg_dnf]` | Instala o pacote se o comando não existir |
| `clone_if_missing repo destino` | `git clone` idempotente |
| `load_env` | Carrega o `.env` da raiz |
| `ensure_flathub` | Garante o remoto Flathub de sistema |
| `install_packages titulo pacote...` | Instala os pacotes que faltam e oferece as versões novas dos instalados (política de versões) |
| `install_missing_packages pacote...` | Só instala o que falta; nunca atualiza |
| `offer_package_upgrades titulo pacote...` | Só a parte de oferecer versões novas dos instalados |
| `install_flatpaks app...` | O mesmo para Flatpaks |
| `offer_git_updates titulo pasta...` | Oferece avanço rápido de clones git atrás da origem (pula os com alterações locais ou divergentes) |
| `confirm_updates titulo linha...` | Mostra `atual -> nova`, o aviso e decide pela política (`ask` pergunta) |
| `record_version` / `recorded_version` | Registro de versão do que não vem de pacote (temas, fontes) |
| `version_gt a b` | Compara versões (`24.9` < `24.21`) |
| `UPDATE_POLICY` | Política em uso: `ask`, `update` ou `keep` |
| `only_missing` / `CONFIG_MODE` | Verdadeiro no modo completar (`--only-missing`); `CONFIG_MODE` é `full` ou `missing` |
| `keep_existing "o quê"` | Avisa que algo que já existia foi mantido (modo completar) |
| `print_header "Titulo"` | Título visual de etapa |
| `DOTFILES_DIR` | Raiz do repositório |
| `C_GREEN`, `C_YELLOW`, `C_RED`, ... | Cores para mensagens |

### Padrões obrigatórios
- **Fail-fast**: `set -euo pipefail`; nada de `|| true` para esconder erros e nada de comandos críticos encadeados com `&&`.
- **Idempotência**: cheque antes de instalar, clonar, baixar, anexar ou fazer backup.
- **Política de versões**: o que já está instalado nunca é atualizado em silêncio. Use `install_packages`, `install_flatpaks`, `offer_git_updates` ou `confirm_updates`; para o que não vem de pacote, registre a versão com `record_version`. Consultas de versão pela rede nunca podem abortar o módulo (sem rede, a checagem é pulada e o que está instalado é mantido).
- **Modo completar**: toda etapa que remove algo, sobrescreve um arquivo ou muda um ajuste que já existe verifica `only_missing` e, nele, mantém o que existe com `keep_existing` (regras em `.agents/rules/03-standards.md`).
- **GNOME só no GNOME**: módulos que só configuram o GNOME chamam `require_gnome`; etapas do GNOME em outros módulos ficam dentro de `gnome_only`. O `tools/check.sh` falha se um módulo usar `gsettings`, `dconf` ou `gnome-extensions` sem essa proteção.
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
O `tools/check.sh` nunca executa módulos nem usa `sudo`. O shellcheck roda num container com a versão fixa 0.11.0 (podman ou docker), para dar o mesmo resultado em qualquer máquina; sem container, usa o shellcheck local. O **CI** (`.github/workflows/check.yml`) roda o mesmo script a cada push e pull request no GitHub.
Módulos que não exigem root (01, 07, 08) podem ser testados com `HOME` apontando para um diretório temporário. Para ver o comportamento fora do GNOME, rode o módulo com `XDG_CURRENT_DESKTOP=KDE`. Nunca teste o 11 ou o 12 com a sessão D-Bus real: aponte `DBUS_SESSION_BUS_ADDRESS` para um socket inexistente e use `dconf`/`gsettings` falsos (detalhes em `.agents/rules/03-standards.md`). A interface gráfica é testada numa cópia com módulos falsos, num display sem tela (broadway), também descrito lá.

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

## Licença
Distribuído sob a licença MIT (veja [LICENSE](LICENSE)). Temas, extensões, fontes e instaladores que os scripts baixam (Orchis, Tela Circle, Vimix, deus_ex, extensões do GNOME, Nerd Fonts etc.) não fazem parte do repositório e seguem as licenças de seus próprios autores.
