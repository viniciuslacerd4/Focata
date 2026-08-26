#!/usr/bin/env bash
# Gera o projeto e builda o Focata.
# Uso: ./scripts/build.sh [debug|release|test]   (padrão: debug)
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null; then
    echo "xcodegen não encontrado. Instale com: brew install xcodegen" >&2
    exit 1
fi

MODE="${1:-debug}"
xcodegen generate

case "$MODE" in
    debug|release)
        CONFIG="$([ "$MODE" = "release" ] && echo Release || echo Debug)"
        xcodebuild -project Focata.xcodeproj -scheme Focata \
            -configuration "$CONFIG" -derivedDataPath build build
        echo
        echo "Pronto: build/Build/Products/$CONFIG/Focata.app"
        ;;
    test)
        xcodebuild -project Focata.xcodeproj -scheme Focata \
            -configuration Debug -derivedDataPath build test
        ;;
    *)
        echo "Modo desconhecido: $MODE (use debug, release ou test)" >&2
        exit 1
        ;;
esac
