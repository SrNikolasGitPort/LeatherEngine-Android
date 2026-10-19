#!/usr/bin/env bash
set -euo pipefail

# install_github_copilot.sh
# Uso: ./scripts/install_github_copilot.sh
# Este script abre a página de instalação do GitHub Copilot já apontando para
# o repositório SrNikolasGitPort/LeatherEngine-Android. Você precisa confirmar a
# instalação no navegador (fluxo interativo do GitHub).

OWNER="SrNikolasGitPort"
REPO="LeatherEngine-Android"

echo "Preparando instalação do GitHub Copilot para $OWNER/$REPO"

if ! command -v gh >/dev/null 2>&1; then
  echo "Erro: GitHub CLI (gh) não encontrado. Instale-o: https://cli.github.com/"
  exit 1
fi

REPO_ID=$(gh api repos/$OWNER/$REPO --jq .id 2>/dev/null || true)
if [ -z "$REPO_ID" ]; then
  echo "Não foi possível obter o ID do repositório via gh. Verifique se você tem acesso e se o repositório existe."
  echo "Alternativa: abra manualmente https://github.com/marketplace/github-copilot e instale o app neste repositório."
  exit 1
fi

echo "ID do repositório: $REPO_ID"

# URL de instalação do GitHub App que direciona para instalação no repositório
INSTALL_URL="https://github.com/apps/github-copilot/installations/new?target_id=$REPO_ID&target_type=Repository"

echo "Abrindo URL de instalação no navegador:\n$INSTALL_URL"

# abrir no browser - compatível com Linux (xdg-open), macOS (open) e Windows (start)
if command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$INSTALL_URL" >/dev/null 2>&1 || true
elif command -v open >/dev/null 2>&1; then
  open "$INSTALL_URL" >/dev/null 2>&1 || true
elif command -v start >/dev/null 2>&1; then
  start "$INSTALL_URL" >/dev/null 2>&1 || true
else
  echo "Nenhum comando para abrir o navegador encontrado. Abra a URL acima manualmente."
fi

echo "No navegador: selecione 'Only select repositories' (somente repositórios específicos), marque $OWNER/$REPO e confirme a instalação/autorizações."

echo "Observação: este script não instala automaticamente o app sem sua confirmação — o GitHub exige autorização interativa no navegador." 
