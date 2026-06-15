#!/usr/bin/env python3
"""Turn the single-pass soundfont renders into SEAMLESS loops.

fluidsynth renders the MIDI once, leaving a reverb/release tail after the musical
loop point (the "dead space") and a start that doesn't match the end. This is the
same fix gen_music.finalize() did for the old synth path: take the exact musical
loop length L (= loop_beats * spb), wrap every sample PAST L back onto the start
(so the previous iteration's tail continues into bar 1 — exactly what happens on
the next loop), then cut to L. End now flows into start with no gap.

    python tools/seamless_loop.py [all|<name>]
    reads  ../../_music_tools/emberwilds_<name>.wav
    writes ../../_music_tools/emberwilds_<name>_loop.wav
"""
import os, sys, wave, array

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '_variants'))
sys.path.insert(0, os.path.dirname(__file__))
import gen_music as G
import render_variants as RV

SR = 44100
_TOOLS = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '_music_tools'))


def loop_lengths():
    """name -> musical loop length in samples, for every track we render."""
    out = {}
    seqs = {}
    for name, f in G.TRACKS.items():          # base tracks + boss2..boss6
        seqs[name] = f()
    for vid, (f, _meta) in RV.collect().items():  # the 21 song variants + cave5..7
        seqs[vid] = f()
    for name, s in seqs.items():
        lb = s.loop_beats if s.loop_beats is not None else s.total_beats()
        out[name] = max(1, int(round(lb * s.spb * SR)))
    out['cave5_drips'] = out.get('cave5', out.get('cave', 0))  # drip mix shares cave5's grid
    return out


def fold(name, L):
    src = os.path.join(_TOOLS, 'emberwilds_%s.wav' % name)
    if not os.path.exists(src):
        return None
    w = wave.open(src, 'rb')
    n, ch = w.getnframes(), w.getnchannels()
    a = array.array('h'); a.frombytes(w.readframes(n)); w.close()
    if ch == 1:                                # mono -> interleave to stereo
        st = array.array('h', [0]) * (n * 2)
        for i in range(n):
            st[2 * i] = a[i]; st[2 * i + 1] = a[i]
        a = st; ch = 2
    if n <= L:                                 # no tail to fold; just (try to) trim
        L = min(L, n)
    else:
        for j in range(L, n):                  # tail is shorter than L -> k = j-L, no mod
            k = j - L
            for c in (0, 1):
                v = a[2 * k + c] + a[2 * j + c]
                a[2 * k + c] = -32768 if v < -32768 else (32767 if v > 32767 else v)
    body = a[:2 * L]
    dst = os.path.join(_TOOLS, 'emberwilds_%s_loop.wav' % name)
    o = wave.open(dst, 'wb')
    o.setnchannels(2); o.setsampwidth(2); o.setframerate(SR)
    o.writeframes(body.tobytes()); o.close()
    return L


def main():
    which = sys.argv[1] if len(sys.argv) > 1 else 'all'
    Ls = loop_lengths()
    names = sorted(Ls) if which == 'all' else [which]
    done = 0
    for name in names:
        r = fold(name, Ls.get(name, 0))
        if r:
            print('  looped %-14s %.1fs' % (name, r / SR)); done += 1
    print('=== %d tracks looped ===' % done)


if __name__ == '__main__':
    main()
