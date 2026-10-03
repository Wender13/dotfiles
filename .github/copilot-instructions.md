# REGRAS E DIRETRIZES DO PROJETO (COPILOT INSTRUCTIONS)

Você está auxiliando no desenvolvimento de uma ferramenta de automação de Dotfiles para Linux (Bash), com o Fedora 41+ como alvo principal. A fonte de verdade das regras é a pasta `.agents/rules/`; leia-a antes de propor mudanças. Siga estas diretrizes estritamente em todas as suas respostas e sugestões de código:

## 1. Arquitetura e Modularidade
- O arquivo `app.sh` é o menu interativo de entrada (e o modo `--all`, headless). NÃO coloque lógica de instalação nele.
- Toda nova automação deve ser um script isolado em `scripts/NN-nome.sh`, com os cabeçalhos `# MENU_DESC:` (máximo 44 caracteres) e `# CATEGORY:`. O `app.sh` descobre os módulos sozinho; não há arrays para editar.
- Use a biblioteca `scripts/lib.sh` (via `source`) para cores, detecção de distro (`detect_distro`, `is_apt`, `is_dnf`), `ensure_command`, `clone_if_missing`, `load_env` e `ensure_flathub`.

## 2. Qualidade e Resiliência (Fail-Fast)
- **Idempotência**: todos os scripts devem poder rodar infinitas vezes sem quebrar o sistema. Use `mkdir -p` e verifique a existência de arquivos, pacotes e programas antes de baixar ou instalar.
- **Set e Erros**: todo script em `scripts/` DEVE iniciar com `set -euo pipefail`. Não use `|| true` para esconder erros nem encadeie comandos críticos com `&&`.
- **Caminhos**: evite caminhos absolutos hardcoded e o diretório atual. Use `$SCRIPT_DIR`, `$DOTFILES_DIR` e `mktemp`.
- **Headless**: nenhum passo pode exigir interação quando o dado existe no `.env`.
- **Validação**: antes de entregar, rode `bash tools/check.sh` (nunca execute os módulos reais para testar).

## 3. Fedora e dnf5
- Use apenas a sintaxe do dnf5 (ex: `dnf config-manager setopt`, `addrepo --from-repofile=`, `dnf install @grupo`). Comandos do dnf4 como `groupupdate` e `--set-enabled` não existem mais.
- Um nome de pacote inválido aborta a transação inteira: valide com `dnf repoquery --available` e `dnf install --assumeno`.
- Antes de remover pacotes, cheque as dependências reversas (`dnf remove --assumeno`).
- Detalhes em `.agents/rules/06-fedora.md`.

## 4. Segurança de Dados (Zero Secrets)
- É ESTRITAMENTE PROIBIDO fazer hardcode de senhas, e-mails, nomes de usuário (usernames), tokens de API ou chaves SSH nos scripts.
- Leia dados pessoais do `.env` ignorado pelo Git (`load_env`) e use `read -r -p` apenas como alternativa. Documente novas chaves no `.env.example` só com valores de exemplo.
- Configurações do GNOME (dconf) podem conter credenciais: elas só entram no repositório pelo `style/gnome/bin/export-gnome-settings.sh`. Nunca proponha commitar um `dconf dump /` inteiro.

## 5. Padrões de Commit (Semantic Git)
Sempre que for sugerir ou criar mensagens de commit, obedeça a este formato exato:
- **Idioma**: Inglês estrito.
- **Tipo**: Conventional Commits (`feat:`, `fix:`, `chore:`, `refactor:`, `docs:`).
- **Título**: Resumo conciso da alteração.
- **Corpo**: Descrição detalhada técnica e o "porquê" da alteração.
- **Rodapé**: Proibido usar "Co-authored-by" ou assinaturas de IA.

## 6. Backlog e Ações Autônomas
- Se você acessar o arquivo `.agents/rules/04-backlog.md`, saiba que você NUNCA deve implementar itens dele por conta própria. Converse com o usuário, sugira a solução e aguarde a aprovação dele para modificar o código.

## 7. Comunicação e Estilo
- Não utilize emojis (proibido na documentação, no código e nas explicações).
- Responda em Português para conversação e documentação (exceto mensagens de commit, que são em Inglês).
