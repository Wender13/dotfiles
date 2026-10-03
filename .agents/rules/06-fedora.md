---
description: Regras específicas do Fedora (dnf5, pacotes, repositórios, remoções e boot)
trigger: always_on
---

# Fedora: Regras Específicas (Alvo Principal)

O Fedora 41+ usa o **dnf5**. Muitos tutoriais na internet (e boa parte do conhecimento de modelos de IA) ainda usam sintaxe do dnf4, que **não existe** no dnf5 e derruba o módulo por causa do `set -e`. Na revisão de 2026-10-02, os módulos 04 e 06 falhavam no Fedora 44 exatamente por isso.

## 1. Sintaxe dnf5 Obrigatória
| Proibido (dnf4) | Correto (dnf5) |
| --- | --- |
| `dnf groupupdate <grupo>` | `dnf install -y @<grupo>` ou `dnf group upgrade <grupo>` |
| `dnf config-manager --set-enabled <repo>` | `dnf config-manager setopt <repo>.enabled=1` |
| `dnf config-manager --add-repo <url>` | `dnf config-manager addrepo --from-repofile=<url>` (falha se o arquivo já existe: cheque antes) |
| `dnf swap <a> <b>` num script idempotente | `dnf install -y --allowerasing <b>` (funciona com ou sem `<a>` instalado) |
| `--setop=...` | `--setopt=...` |

- O `config-manager` do dnf5 vem do pacote `dnf5-plugins` (o `dnf-plugins-core` é o do dnf4).
- Para conferir a sintaxe, consulte `dnf <comando> --help` em vez de confiar em exemplos antigos.

## 2. Uma Transação, Zero Nomes Inválidos
No dnf5, um único nome de pacote inexistente aborta a transação inteira ("No match for argument") e nenhum pacote da lista é instalado. Por isso:
- Valide todo pacote novo antes de usá-lo: `dnf repoquery --available <pacote>` (não exige root). Para repositórios ainda não configurados: `dnf repoquery --repofrompath=<id>,<url> --repo=<id> <pacote>`.
- Valide a transação completa sem instalar nada: `dnf install --assumeno <lista>` (não exige root).
- Nomes do Debian/Ubuntu não existem no Fedora (ex: `gnome-software-plugin-flatpak`, `build-essential`, `libssl-dev`). No Fedora, o suporte a Flatpak já vem dentro do `gnome-software`.
- As versões do Java mudam entre releases. No Fedora 44 existem `java-25-openjdk-devel` (JDK do sistema) e `java-latest-openjdk-devel`; o `java-21-openjdk-devel` não existe mais.
- Um pacote ausente do repositório do fornecedor também derruba a transação (ex: `mongodb-compass` não existe no repositório do MongoDB; ele vem do Flathub como `com.mongodb.Compass`).

## 3. Remoções Exigem Checagem de Dependência Reversa
O `dnf remove -y` remove junto todos os pacotes que dependem do alvo. Antes de adicionar um pacote a uma lista de remoção:
- Consulte quem depende dele: `dnf repoquery --installed --whatrequires <pacote>`.
- Simule a remoção: `dnf remove --assumeno <pacote>` (não exige root).

Exemplo real: `malcontent` é dependência do `gnome-control-center`, que é dependência do `gnome-shell`. A remoção derrubaria o GNOME. Como o dnf5 protege o `gnome-shell`, ele recusa a transação, e assim nenhum outro pacote da lista era removido. Remova apenas a interface (`malcontent-control`).

Passe ao `dnf remove` somente os pacotes de fato instalados (`rpm -qa --qf '%{NAME}\n' <padroes>`) e não use `|| true`.

## 4. Repositórios
- **RPM Fusion**: instale os pacotes `rpmfusion-free-release`/`rpmfusion-nonfree-release` apenas se `rpm -q` indicar que estão ausentes. Codecs, conforme o guia oficial do RPM Fusion: `dnf install -y --allowerasing ffmpeg` (troca o `ffmpeg-free` e as bibliotecas `libav*-free`) e `dnf install -y @multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin`.
- **Google Chrome**: o repositório vem desabilitado no pacote `fedora-workstation-repositories`; habilite com `setopt`.
- **MongoDB**: não há repositório para Fedora; usa-se o de RHEL 9 (`repo.mongodb.org/yum/redhat/9`).
- **Docker CE**: use o `docker-ce.repo` oficial com `addrepo`. Antes de uma nova versão do Fedora, confira em docs.docker.com se ela já é suportada.
- **Claude Code**: não usa repositório. Por decisão do usuário, segue o método recomendado no site oficial (instalador nativo, módulo 09), sem `sudo`.
- **Flathub**: remoto de sistema, garantido pelo `ensure_flathub` (adiciona, habilita e remove filtros).
- **Extensões do GNOME**: várias existem como pacote `gnome-shell-extension-*`. Para descobrir o pacote de uma extensão: `dnf repoquery --whatprovides "/usr/share/gnome-shell/extensions/<UUID>/metadata.json"` (o exportador faz isso sozinho).

## 5. Boot (GRUB e Plymouth)
- No Fedora 34+ com UEFI, `/boot/efi/EFI/fedora/grub.cfg` é um stub que encadeia `/boot/grub2/grub.cfg`. Gere a configuração **somente** com `grub2-mkconfig -o /boot/grub2/grub.cfg`; nunca escreva por cima do stub.
- O `/etc/default/grub` do Fedora não tem a chave `GRUB_TIMEOUT_STYLE`. Um `sed` sozinho não faz nada: adicione a chave quando estiver ausente.
- O `/boot` é uma partição separada. Temas do GRUB devem ser instalados em `/boot/grub2/themes` (opção `-b` do instalador do tema).
- Faça backup de arquivos de boot apenas uma vez, preservando o original.

## 6. Shell e Usuário
- O `chsh` pede a própria senha e trava o modo headless; use `sudo usermod --shell <caminho> "$USER"`.
- O pacote `util-linux-user` não existe mais: o `chsh` faz parte do `util-linux`.
- O `wget` do Fedora é fornecido pelo `wget2-wget`; o nome `wget` funciona via "provides".
