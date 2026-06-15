#!/usr/bin/env python3
"""Synthesize realistic leaking-faucet water drips and mix them into a cave track.

The physics of a water drop: when it strikes the pool it traps a bubble that
oscillates and SHRINKS, so the pitch CHIRPS UPWARD over a very short, fast-decaying
"plink". That's it — a single clean sine sweeping up, ~120 ms, no noise, no second
partial (those read as sci-fi blips). A leaking faucet is a STEADY, evenly-spaced
drip at a near-constant pitch. We give the whole drip layer one light shared cave
reverb so it sits in the space, then mix it under the music.

    python tools/cave_drips.py [cave5]   reads ../../_music_tools/emberwilds_<name>.wav
                                         -> ../../_music_tools/emberwilds_<name>_drips.wav
"""
import wave, struct, math, os, sys, random
sys.path.insert(0, os.path.dirname(__file__))
import gen_music as G   # reuse its Schroeder reverb for the shared cave space

SR = 44100
_TOOLS = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '_music_tools'))

# --- tunable feel ---------------------------------------------------------
MIN_GAP  = 8.0      # a slow, occasional leak: gaps wander between MIN and MAX seconds
MAX_GAP  = 15.0
LONG_P   = 0.0      # (no extra pause — keep gaps inside the 8-15s band)
START_MIN = 3.0     # first drip lands a few seconds in (clean intro, no drip at t=0)
START_MAX = 7.0
END_PAD  = 5.0      # no drips within this many seconds of the loop end, so a drip (or
                    # its reverb tail) never wraps across the seam onto the intro —
                    # that wrap was the "double drip at the start" artifact
F0       = 820      # base pitch (Hz) of the drop
F_JIT    = 0.07     # +/- per-drip pitch wobble
RATIO    = 2.3      # how far the pitch chirps UP over the drop
DUR      = 0.16     # length of one drop (s)
DTAU     = 0.040    # amplitude decay time-constant (s)
PAN_VAR  = 0.22     # stereo wander
MIX      = 0.18     # drip layer level under the music (quiet, just a hint)
REV_AMT  = 0.14     # cave reverb wet on the drips (drier)
REV_SIZE = 1.5


def read_wav(path):
    w = wave.open(path, 'rb')
    n, ch = w.getnframes(), w.getnchannels()
    data = w.readframes(n); w.close()
    ints = struct.unpack('<%dh' % (n * ch), data)
    if ch == 2:
        L = [ints[i * 2] / 32768.0 for i in range(n)]
        R = [ints[i * 2 + 1] / 32768.0 for i in range(n)]
    else:
        L = [v / 32768.0 for v in ints]; R = list(L)
    return L, R


def drop(f0):
    """One clean water drop: a short sine chirping up f0 -> f0*RATIO, fast decay."""
    n = int(DUR * SR)
    out = [0.0] * n
    ph = 0.0
    atk = int(0.0018 * SR)            # ~2 ms soft attack = impact without a click
    for i in range(n):
        t = i / SR
        f = f0 * (RATIO ** (t / DUR))
        ph += 2.0 * math.pi * f / SR
        env = math.exp(-t / DTAU)
        a = 1.0 if i >= atk else i / atk
        out[i] = math.sin(ph) * env * a
    return out


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else 'cave5'
    # Mix onto the already-seamless music LOOP (length = the musical loop L) and keep
    # every drip inside [START, L-END_PAD] so no drip or its reverb tail crosses the
    # loop seam. The result is already loop-ready with a clean single-drip intro.
    L, R = read_wav(os.path.join(_TOOLS, 'emberwilds_%s_loop.wav' % name))
    N = len(L)
    dl = [0.0] * N
    dr = [0.0] * N
    random.seed(11)
    t = random.uniform(START_MIN, START_MAX)
    count = 0
    while t < (N / SR) - END_PAD:
        buf = drop(F0 * random.uniform(1 - F_JIT, 1 + F_JIT))
        pan = random.uniform(-PAN_VAR, PAN_VAR)
        gl = math.cos((pan + 1) * math.pi / 4)
        gr = math.sin((pan + 1) * math.pi / 4)
        base = int(t * SR)
        for i, v in enumerate(buf):
            idx = base + i
            if idx < N:
                dl[idx] += v * gl
                dr[idx] += v * gr
        count += 1
        gap = random.uniform(MIN_GAP, MAX_GAP)
        if random.random() < LONG_P:
            gap += random.uniform(1.0, 3.5)     # occasional long pause = natural leak
        t += gap
    # one shared cave space on the whole drip layer (natural tail, not echo cascade)
    dl = G.reverb(dl, REV_AMT, REV_SIZE)
    dr = G.reverb(dr, REV_AMT, REV_SIZE)
    for i in range(N):
        L[i] += dl[i] * MIX
        R[i] += dr[i] * MIX
    peak = max(1e-6, max(max(abs(x) for x in L), max(abs(x) for x in R)))
    norm = 0.95 / peak
    out = bytearray()
    for i in range(N):
        for ch in (L[i], R[i]):
            v = math.tanh(ch * norm)
            out += struct.pack('<h', int(max(-1.0, min(1.0, v)) * 32767))
    op = os.path.join(_TOOLS, 'emberwilds_%s_drips.wav' % name)
    w = wave.open(op, 'wb')
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(bytes(out)); w.close()
    print('wrote', op, '(%d drips)' % count)


if __name__ == '__main__':
    main()
