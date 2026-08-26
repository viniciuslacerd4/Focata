#!/usr/bin/env bash
# Builda em Release e empacota o Focata num .dmg pronto para baixar.
# Uso: ./scripts/dmg.sh            → dist/Focata-<versão>.dmg
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

VERSION="$(awk -F'"' '/MARKETING_VERSION/ {print $2; exit}' project.yml)"
VOLNAME="Focata"
DMG="$ROOT/dist/Focata-$VERSION.dmg"
APP="$ROOT/build/Build/Products/Release/Focata.app"

# Layout da janela, em pontos. O fundo é desenhado nessa medida, e a altura
# da janela ganha a barra de título por cima do fundo.
WIN_W=660 WIN_H=400 TITLEBAR=28
APP_X=165 APPLICATIONS_X=495 ICON_Y=200
# Canto para onde vão os arquivos ocultos: fora da janela, mas ainda dentro da
# tela do fundo, para não aparecerem sobre o branco se a janela abrir maior.
HIDDEN_X=1180 HIDDEN_Y=980

# 1. Build ------------------------------------------------------------------
"$ROOT/scripts/build.sh" release

[ -d "$APP" ] || { echo "Focata.app não saiu do build: $APP" >&2; exit 1; }

# As licenças precisam estar dentro do bundle antes de empacotar.
for arquivo in LICENSE THIRD-PARTY-LICENSES; do
    [ -f "$APP/Contents/Resources/$arquivo" ] || {
        echo "$arquivo não entrou no bundle; confira as sources em project.yml" >&2
        exit 1
    }
done

# A assinatura ad-hoc sela os recursos: qualquer arquivo acrescentado ao bundle
# depois do build a invalida, e o macOS passa a dizer que o app está corrompido.
codesign --verify --strict "$APP" || {
    echo "a assinatura do app não confere; não vale distribuir assim" >&2
    exit 1
}

# 2. Palco ------------------------------------------------------------------
STAGE="$(mktemp -d)"
SCRATCH="$(mktemp -d)"
MOUNT=""
# Sair no meio do caminho sem desmontar deixa um volume "Focata" pendurado, e
# é ele que faz a execução seguinte montar como "Focata 1" e arrumar a janela
# do volume errado. Por isso o trap desmonta antes de apagar os diretórios.
limpar() {
    [ -n "$MOUNT" ] && hdiutil detach "$MOUNT" >/dev/null 2>&1
    rm -rf "$STAGE" "$SCRATCH"
    return 0
}
trap limpar EXIT

cp -R "$APP" "$STAGE/Focata.app"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$STAGE/.background"
swift "$ROOT/scripts/dmg-background.swift" "$STAGE/.background/background.tiff"

# Ícone do volume, a partir do mestre do app.
ICONSET="$SCRATCH/Focata.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size design/focata-icon-master.png \
        --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) design/focata-icon-master.png \
        --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$SCRATCH/VolumeIcon.icns"
# Uma cópia já no palco: o Finder só reserva uma posição para o arquivo se
# ele existir na hora de arrumar a janela. Depois ele apaga, e a gente
# devolve — a posição fica guardada pelo nome, não pelo conteúdo.
cp "$SCRATCH/VolumeIcon.icns" "$STAGE/.VolumeIcon.icns"

# 3. Imagem gravável --------------------------------------------------------
# Folga de 20 MB: o Finder ainda vai gravar .DS_Store e afins na imagem.
SIZE=$(( $(du -sk "$STAGE" | cut -f1) + 20480 ))
# O fundo é um TIFF grande (1x e 2x de uma tela de 1440x1120), mas é degradê
# liso: no UDZO ele encolhe para quase nada.
RW="$SCRATCH/rw.dmg"
hdiutil create -srcfolder "$STAGE" -volname "$VOLNAME" -fs HFS+ \
    -size "${SIZE}k" -format UDRW -ov "$RW" >/dev/null

montar() {
    hdiutil attach "$RW" -readwrite -noverify -noautoopen |
        awk -F'\t' '/Apple_HFS/ {print $NF}' | tail -1
}
desmontar() {
    sync
    hdiutil detach "$1" >/dev/null 2>&1 || hdiutil detach "$1" -force >/dev/null 2>&1
    [ "$1" = "$MOUNT" ] && MOUNT=""
    return 0
}

# Um volume com o mesmo nome já aberto no Finder, tipicamente o .dmg da versão
# anterior, rouba o ponto de montagem: a imagem nova vira "/Volumes/Focata 1" e
# o AppleScript abaixo, que fala com o volume pelo nome, arruma a janela da
# imagem antiga. Desmontar antes é o que faz o resultado sair igual em qualquer
# Mac, inclusive no de quem acabou de instalar a versão passada.
for dev in $(hdiutil info | awk -F'\t' -v vol="/Volumes/$VOLNAME" '$NF == vol {print $1}'); do
    echo "um volume $VOLNAME já estava montado, desmontando: $dev"
    hdiutil detach "$dev" >/dev/null 2>&1 || hdiutil detach "$dev" -force >/dev/null 2>&1
done
if [ -e "/Volumes/$VOLNAME" ]; then
    echo "ainda há algo montado em /Volumes/$VOLNAME; ejete e rode de novo" >&2
    exit 1
fi

MOUNT="$(montar)"
[ -n "$MOUNT" ] || { echo "não consegui montar a imagem" >&2; exit 1; }

# 4. Layout da janela -------------------------------------------------------
# Depende da permissão de automação do Finder; se faltar, o .dmg sai igual,
# só sem a janela arrumada.
osascript <<APPLESCRIPT >/dev/null 2>&1 || echo "aviso: não deu para arrumar a janela (permissão de automação do Finder)" >&2
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, $((200 + WIN_W)), $((120 + WIN_H))}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 128
        set text size of opts to 13
        set background picture of opts to file ".background:background.tiff"
        set position of item "Focata.app" of container window to {$APP_X, $ICON_Y}
        set position of item "Applications" of container window to {$APPLICATIONS_X, $ICON_Y}
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

# 5. Acabamento sem o Finder por perto ---------------------------------------
# Desmontar e montar de novo: enquanto o volume está aberto no Finder, ele
# reescreve o .DS_Store e apaga o ícone do volume por baixo da gente.
desmontar "$MOUNT"
MOUNT="$(montar)"
[ -n "$MOUNT" ] || { echo "não consegui remontar a imagem" >&2; exit 1; }

# O Finder guarda o tamanho que ele quis, não o que pedimos — num Mac com
# janelas lado a lado ele ignora o AppleScript. E os três arquivos ocultos
# ficam empilhados em cima do título para quem liga "mostrar ocultos". As duas
# coisas se resolvem escrevendo direto no .DS_Store.
# Sem permissão de automação o Finder não grava .DS_Store nenhum, e aí não há
# layout para ajustar. O .dmg continua válido, só abre com a janela padrão, que
# é o que o aviso lá em cima promete.
if [ -f "$MOUNT/.DS_Store" ]; then
    python3 "$ROOT/scripts/dmg-layout.py" "$MOUNT/.DS_Store" \
        --bounds 200 200 "$WIN_W" $((WIN_H + TITLEBAR)) \
        --mover "$HIDDEN_X" "$HIDDEN_Y" .background .fseventsd .VolumeIcon.icns
else
    echo "aviso: o Finder não gravou o layout; o .dmg sai com a janela padrão" >&2
fi

# O ícone do volume precisa do tipo de arquivo `icnC` e do bit de ícone
# personalizado na raiz; hdiutil não leva nada disso do palco.
cp "$SCRATCH/VolumeIcon.icns" "$MOUNT/.VolumeIcon.icns"
SetFile -c icnC "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT"

desmontar "$MOUNT"

# 6. Comprimir --------------------------------------------------------------
mkdir -p "$ROOT/dist"
rm -f "$DMG"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null

echo
echo "Pronto: $DMG"
echo "$(du -h "$DMG" | cut -f1) · SHA-256 $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
