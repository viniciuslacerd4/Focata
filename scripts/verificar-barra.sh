#!/usr/bin/env bash
# Verifica se o item do Focata realmente ganhou um slot na barra de menu.
#
# Sintoma de item sem slot: ele existe e se diz visível, mas o sistema não
# reserva espaço e ele nunca é desenhado. O tell é a posição vertical — um item
# de verdade fica logo abaixo do topo (y ≈ 7); um sem slot vai parar em y ≈ -1
# ou no rodapé da tela.
set -uo pipefail

cd "$(dirname "$0")/.."

APP="build/Build/Products/Release/Focata.app"
if [ ! -d "$APP" ]; then
    echo "Build de Release não encontrada. Rodando ./scripts/build.sh release…"
    ./scripts/build.sh release >/dev/null || { echo "Build falhou."; exit 1; }
fi

pkill -x Focata 2>/dev/null
sleep 1
open "$APP"
sleep 4

if ! pgrep -x Focata >/dev/null; then
    echo "✗ O Focata não está rodando."
    exit 1
fi

GEO=$(osascript -e 'tell application "System Events" to tell process "Focata" to get {position, size} of menu bar item 1 of menu bar 1' 2>/dev/null)
if [ -z "$GEO" ]; then
    echo "✗ Nenhum item de barra encontrado."
    exit 1
fi

Y=$(echo "$GEO" | awk -F', *' '{print $2}')
echo "Geometria do item: $GEO"

if [ "${Y:-999}" -ge 0 ] && [ "${Y:-999}" -le 20 ]; then
    echo "✓ O item ganhou slot na barra (y=$Y). Deve estar visível."
else
    echo "✗ y=$Y — o item está fora da barra, sem slot."
    exit 1
fi

cat <<'CHECKLIST'

Agora o que só o seu clique confirma:

  1. Clique no TEXTO          → abre o editor; digite e pressione return
  2. Clique no ANEL           → inicia o foco (o anel começa a preencher)
  3. Shift+clique             → limpa a tarefa
  4. Clique direito           → menu com Concluir, Pular, Modo privado, Histórico
  5. Arraste um item do Lembretes sobre o ícone
  6. Configurações › Atalhos  → grave um atalho e teste de outro app
  7. Notificações             → conceda a permissão no primeiro início de foco

Dica para não esperar 25 minutos: em Configurações › Pomodoro use o preset
Sprint 15/3, ou rode isto para um foco de 12 segundos:

  defaults write dev.vinicius.focata focusMinutes -float 0.2 && pkill -x Focata && open build/Build/Products/Release/Focata.app

Para voltar ao padrão:

  defaults write dev.vinicius.focata focusMinutes -float 25
CHECKLIST
