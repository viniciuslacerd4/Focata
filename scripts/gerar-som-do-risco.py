#!/usr/bin/env python3
"""Gera o som do risco que atravessa a tarefa concluída.

São três variações do mesmo gesto — giz de cera arrastado no papel — para que
uma tarefa de várias linhas não soe como três vezes o mesmo clique.

O som é sintetizado, e não gravado: assim ele nasce do repositório, cabe em
poucos kilobytes e pode ser reajustado mudando os números daqui.

    ./scripts/gerar-som-do-risco.py

Escreve Resources/Sounds/strike-{1,2,3}.wav.
"""

import math
import os
import random
import struct
import wave

TAXA = 44100
# O mesmo tempo que o risco leva para atravessar uma linha
# (`FarewellTextView.strokeDuration`): o som acaba quando o traço acaba.
DURACAO = 0.30
# Um giz de cera é atrito: ruído de banda larga com um pico áspero na região
# média-aguda (o arrasto) e um corpo grave (a pressão do traço no papel).
ATRITO_HZ, ATRITO_Q, ATRITO_GANHO = 1700.0, 1.0, 1.0
CORPO_HZ, CORPO_Q, CORPO_GANHO = 450.0, 1.0, 0.6
# Acima disso é chiado, não atrito: sem este corte o som vira estática.
TETO_HZ = 5000.0
# O grão: a cera não desliza liso, ela engancha. A amplitude é sorteada de novo
# a cada 1,2 ms e suavizada, o que dá a textura irregular do arrasto.
GRAO_MS = 2.0
GRAO_MINIMO = 0.25
ATAQUE_MS = 6.0
QUEDA_MS = 60.0


def passa_banda(amostras, centro, q):
    """Biquad passa-banda (cookbook do RBJ), ganho unitário no pico."""
    w0 = 2 * math.pi * centro / TAXA
    alfa = math.sin(w0) / (2 * q)
    b0, b1, b2 = alfa, 0.0, -alfa
    a0, a1, a2 = 1 + alfa, -2 * math.cos(w0), 1 - alfa
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0

    saida = []
    x1 = x2 = y1 = y2 = 0.0
    for x in amostras:
        y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        saida.append(y)
        x2, x1 = x1, x
        y2, y1 = y1, y
    return saida


def passa_baixa(amostras, corte):
    """Um polo só, para tirar o chiado de cima sem endurecer o som."""
    k = math.exp(-2 * math.pi * corte / TAXA)
    saida = []
    valor = 0.0
    for x in amostras:
        valor = (1 - k) * x + k * valor
        saida.append(valor)
    return saida


def envelope_do_grao(total, rng):
    """Amplitude irregular, sorteada em degraus e suavizada."""
    passo = max(1, int(TAXA * GRAO_MS / 1000))
    valor = 1.0
    alvo = 1.0
    envelope = []
    for i in range(total):
        if i % passo == 0:
            alvo = rng.uniform(GRAO_MINIMO, 1.0)
        # Um polo só: o degrau vira rampa curta, e o grão não estala.
        valor += (alvo - valor) * 0.25
        envelope.append(valor)
    return envelope


def envelope_do_traço(total):
    """Ataque rápido (a cera encosta) e queda curta (a mão levanta)."""
    ataque = max(1, int(TAXA * ATAQUE_MS / 1000))
    queda = max(1, int(TAXA * QUEDA_MS / 1000))
    envelope = []
    for i in range(total):
        if i < ataque:
            envelope.append(i / ataque)
        elif i >= total - queda:
            restante = (total - i) / queda
            envelope.append(0.5 - 0.5 * math.cos(math.pi * restante))
        else:
            envelope.append(1.0)
    return envelope


def gerar(semente):
    rng = random.Random(semente)
    total = int(TAXA * DURACAO)
    ruido = [rng.uniform(-1.0, 1.0) for _ in range(total)]

    # A altura do arrasto varia um pouco entre as variações, como varia a mão.
    desvio = rng.uniform(-250, 250)
    # Duas passagens no mesmo filtro: uma só deixa passar chiado demais pelas
    # saias da banda.
    atrito = passa_banda(passa_banda(ruido, ATRITO_HZ + desvio, ATRITO_Q), ATRITO_HZ + desvio, ATRITO_Q)
    corpo = passa_banda(ruido, CORPO_HZ + desvio / 4, CORPO_Q)

    grao = envelope_do_grao(total, rng)
    traço = envelope_do_traço(total)

    misturado = passa_baixa(
        [ATRITO_GANHO * atrito[i] + CORPO_GANHO * corpo[i] for i in range(total)],
        TETO_HZ,
    )
    amostras = [misturado[i] * grao[i] * traço[i] for i in range(total)]

    pico = max(abs(a) for a in amostras) or 1.0
    return [0.85 * a / pico for a in amostras]


def escrever(caminho, amostras):
    with wave.open(caminho, "wb") as arquivo:
        arquivo.setnchannels(1)
        arquivo.setsampwidth(2)
        arquivo.setframerate(TAXA)
        arquivo.writeframes(
            b"".join(struct.pack("<h", int(max(-1.0, min(1.0, a)) * 32767)) for a in amostras)
        )


def main():
    raiz = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    pasta = os.path.join(raiz, "Resources", "Sounds")
    os.makedirs(pasta, exist_ok=True)
    for numero in (1, 2, 3):
        caminho = os.path.join(pasta, f"strike-{numero}.wav")
        escrever(caminho, gerar(semente=numero * 977))
        print(f"{os.path.relpath(caminho, raiz)} — {DURACAO * 1000:.0f} ms")


if __name__ == "__main__":
    main()
