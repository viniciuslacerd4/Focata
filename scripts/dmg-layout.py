#!/usr/bin/env python3
"""Acerta o .DS_Store do .dmg no que o Finder não deixa a gente acertar.

Duas coisas:

1. **O tamanho da janela.** O caminho normal é pedir via AppleScript, mas num
   Mac rodando um gerenciador de janelas em tiling (AeroSpace, yabai) o Finder
   ignora o pedido e grava o tamanho dele — e o fundo fica boiando num canto.

2. **Os arquivos ocultos.** `.background`, `.fseventsd` e `.VolumeIcon.icns`
   precisam existir no volume, e quem liga "mostrar arquivos ocultos" no Finder
   vê os três empilhados em cima do título. Aqui a gente empurra cada um para
   fora da área visível — quando o Finder tiver deixado uma posição gravada.

O .DS_Store é um B-tree com blocos de tamanho fixo, então nada pode mudar de
comprimento. O registro `Iloc` é sempre 16 bytes (x, y e um rabicho), então
trocar as coordenadas é direto. Já o `bwsp` é um plist binário: a string de
bounds sai completada com espaços até bater o tamanho original, e o
`NSRectFromString` ignora o que sobra.

Uso:
    dmg-layout.py <.DS_Store> --bounds x y largura altura
                              [--mover x y nome [nome ...]]
"""
import argparse
import plistlib
import sys

avisos = []


def _registros(data, tipo):
    """Cada registro é <u32 tam do nome><nome UTF-16BE><id 4><tipo 4><dados>."""
    at = data.find(tipo)
    while at != -1:
        for tamanho in range(1, 129):
            inicio = at - 2 * tamanho
            if inicio - 4 < 0:
                break
            if int.from_bytes(data[inicio - 4 : inicio], "big") != tamanho:
                continue
            try:
                nome = bytes(data[inicio:at]).decode("utf-16-be")
            except UnicodeDecodeError:
                continue
            yield nome, at
            break
        at = data.find(tipo, at + 1)


def bounds(data, x, y, largura, altura):
    for _, at in _registros(data, b"bwsp"):
        if bytes(data[at + 4 : at + 8]) != b"blob":
            continue
        tamanho = int.from_bytes(data[at + 8 : at + 12], "big")
        inicio = at + 12
        try:
            plist = plistlib.loads(bytes(data[inicio : inicio + tamanho]))
        except Exception as erro:
            return avisos.append(f"bwsp ilegível ({erro})")

        texto = "{{%d, %d}, {%d, %d}}" % (x, y, largura, altura)
        espacos = 0
        for _ in range(64):
            plist["WindowBounds"] = texto + " " * espacos
            novo = plistlib.dumps(plist, fmt=plistlib.FMT_BINARY)
            folga = tamanho - len(novo)
            if folga == 0:
                data[inicio : inicio + tamanho] = novo
                return
            espacos += folga
            if espacos < 0:
                return avisos.append("os bounds novos não cabem no registro")
        return avisos.append("não consegui casar o tamanho do registro bwsp")
    avisos.append("registro bwsp não encontrado")


def mover(data, x, y, nomes):
    # Sem posição gravada não há o que mover: o Finder só reserva uma para
    # arquivo oculto se quem buildou estiver com "mostrar ocultos" ligado. É o
    # caso comum, e aí não tem problema nenhum — ninguém vai ver os arquivos.
    for nome, at in _registros(data, b"Iloc"):
        if nome not in nomes or bytes(data[at + 4 : at + 8]) != b"blob":
            continue
        inicio = at + 12
        data[inicio : inicio + 4] = x.to_bytes(4, "big")
        data[inicio + 4 : inicio + 8] = y.to_bytes(4, "big")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("ds_store")
    p.add_argument("--bounds", nargs=4, type=int, metavar=("X", "Y", "L", "A"), required=True)
    p.add_argument("--mover", nargs="+", metavar="X Y NOME", default=None)
    args = p.parse_args()

    data = bytearray(open(args.ds_store, "rb").read())
    bounds(data, *args.bounds)
    if args.mover:
        mover(data, int(args.mover[0]), int(args.mover[1]), args.mover[2:])
    open(args.ds_store, "wb").write(data)

    for aviso in avisos:
        print(f"aviso: layout do .dmg — {aviso}", file=sys.stderr)
