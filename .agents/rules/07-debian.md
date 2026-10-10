# Debian: Regras Específicas

O Debian 13 (trixie) ou mais novo, com GNOME, é suportado e validado num container `debian:13` com apt real. O ramo `apt` também atende o Ubuntu, que segue secundário. Estas regras completam as gerais; o Fedora tem as suas em `06-fedora.md`.

## 1. Versão e Detecção
- O `detect_distro` recusa Debian anterior ao 13 (`VERSION_ID`). Testing e sid não têm `VERSION_ID` e passam.
- `is_debian` (`ID=debian`) separa o Debian do Ubuntu e derivados, que também são `is_apt`.
- A interface gráfica precisa da libadwaita 1.7 (`Adw.ToggleGroup`), que o Debian 13 tem e o 12 não.

## 2. sudo, Grupos e PATH
- Quando a instalação define uma senha de root, o primeiro usuário fica fora do grupo `sudo`, e o pacote `sudo` pode nem estar instalado. O módulo 00 resolve com um único `su --login root --command "..."` (a senha de root é pedida uma vez e nunca guardada): instala o `sudo` se faltar e adiciona os grupos `sudo`, `adm` e `systemd-journal`. Ele nunca remove grupos, por isso faz o mesmo nos dois modos.
- O sudo usa os grupos da sessão: um grupo novo só vale depois de logout e login (ou `newgrp sudo`). O `app.sh --all` checa `has_sudo_access` antes de pedir a senha do sudo; sem acesso, roda o 00 e para, pedindo um novo login.
- Ferramentas de administração ficam em `/usr/sbin`, fora do PATH de um usuário comum (ex: `plymouth-set-default-theme`). Procure também lá antes de concluir que a ferramenta não existe; senão o módulo cai no caminho errado (aconteceu com o Plymouth).
- Funções que respondem "sim ou não" (`is_gnome`, `has_sudo_access`) devem ser chamadas dentro de `if` quando o `lib.sh` é carregado num `bash -c`: fora de uma condição, a armadilha de erros do `lib.sh` imprime "[ERRO CRITICO]" para um simples "não".

## 3. Repositórios e Pacotes
- **contrib e non-free**: o Debian só habilita `main` (e `non-free-firmware`). Codecs e o driver de vídeo da Intel (`intel-media-va-driver-non-free`) estão em `contrib`/`non-free`, o equivalente do RPM Fusion. O módulo 04 acrescenta os dois componentes em `/etc/apt/sources.list.d/debian.sources` (formato deb822, linhas `Components:`) e nas linhas `deb` do `/etc/apt/sources.list` que apontam para o Debian, com backup `.bak` uma única vez.
- **Nomes diferentes do Ubuntu e do Fedora**: o cliente `tldr` é o pacote `tealdeer` (mesmo comando `tldr`); o `bat` instala o comando `batcat` (o módulo 08 cria `~/.local/bin/bat`); o `script` vem do `bsdutils`, que já vem instalado.
- Como no dnf5, um nome inexistente derruba a transação inteira do apt ("Unable to locate package"). Valide todo nome novo com `apt-cache policy <pacote>` e a lista completa com `apt-get install -s` num container `debian:13`.
- **MongoDB**: o servidor (`mongodb-org`) não é publicado para o trixie, só o `mongosh` e as ferramentas. O módulo 06 lê o índice `Packages` da versão do sistema e, sem o servidor, usa o repositório do bookworm (testado: o `mongod` 8.0 instala e roda no Debian 13), como o Fedora usa o do RHEL 9. Leia o índice inteiro antes de procurar nele: com `pipefail`, um `curl | grep -q` pode falhar quando o `grep` para de ler no meio do download.
- **Docker CE** tem a suite `trixie`. O Docker Desktop (`.deb` de 500 MB) não foi validado no container.

## 4. Boot
- O GRUB é atualizado com `update-grub`.
- A linha padrão do Debian é `GRUB_CMDLINE_LINUX_DEFAULT="quiet"`. Sem `splash`, o Plymouth não mostra o tema; o módulo 10 acrescenta `splash` no modo `full` (no `missing`, as configurações do GRUB ficam como estão).
- O tema do Plymouth fica em `/etc/plymouth/plymouthd.conf` (o padrão vem de `/usr/share/plymouth/plymouthd.defaults`: `ceratopsian` no Debian 13). Use `plymouth-set-default-theme -R`, que grava o tema e reconstrói o initramfs (`update-initramfs`). A alternativa `default.plymouth` é do Ubuntu e é ignorada no Debian. O plugin de script, usado pelo deus_ex, vem no próprio pacote `plymouth`.

## 5. Validação em Container
Nunca rode os módulos no sistema do usuário para testar. No container (descartável), o apt pode rodar de verdade:
- `podman run --rm -v "$PWD:/repo:ro,Z" docker.io/library/debian:13` e um usuário comum com `sudo` sem senha.
- **Instalações simuladas**: um `sudo` falso no PATH desse usuário que acrescenta `-s` a `apt-get install`/`remove` e só registra `systemctl`, `update-grub`, `update-initramfs`, `flatpak` e `plymouth-set-default-theme` (compare pelo `basename`, porque o módulo pode chamar o caminho completo). Fontes, chaves e `apt-get update` rodam de verdade, o que valida os repositórios de fornecedor no trixie.
- **Módulo 00**: usuário sem sudo, senha de root definida (`chpasswd`) e um driver em pseudo-terminal (`pty` do Python) que digita a senha quando aparece `Password:`.
- **Sessão GNOME**: um `gnome-shell` falso no PATH e `XDG_CURRENT_DESKTOP=GNOME` ativam as etapas do GNOME.
- **Interface gráfica**: `python3-gi`, `gir1.2-adw-1`, `gir1.2-vte-3.91` e `libgtk-4-bin` (traz o `gtk4-broadwayd`), e a janela construída num display broadway.
