#!/usr/bin/env python3
"""Original game-music synthesizer (pure stdlib, no numpy).

Sibling to tools/gen_ability_sfx.py — same "compose it in code, synthesize to a
.wav" approach, but for looping background music. Every track here is an ORIGINAL
composition (my own melodies + chord progressions) written to fill a ROLE/MOOD
(title, field, town, …). Nothing is transcribed from any copyrighted track — the
goal is to REPLACE licensed music with copyright-clean originals.

Usage:
    python tools/gen_music.py title          # render one track
    python tools/gen_music.py all            # render every track
Outputs <name>.wav into assets/music/ (convert to .ogg with ffmpeg for the repo).

Engine: wavetable oscillators (sine/saw/tri/square) with LINEAR INTERPOLATION
(anti-alias) + detune, ADSR envelopes, per-voice one-pole lowpass, instrument
timbres (pluck/bell/pad/bass/perc), stereo panning, a Schroeder reverb, and a
master 2-pole lowpass to keep the top end mellow (no screech). Render is per-note
into float buffers, then a master chain (soft-clip + normalize) to 16-bit PCM.
"""
import math, sys, wave, struct, os

SR = 44100

# --------------------------------------------------------------------------
# Notes
# --------------------------------------------------------------------------
_BASE = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}

def nf(name):
    """Note name -> frequency. 'A4', 'F#5', 'Bb3'."""
    n = _BASE[name[0].upper()]
    i = 1
    while i < len(name) and name[i] in '#b':
        n += 1 if name[i] == '#' else -1
        i += 1
    midi = 12 * (int(name[i:]) + 1) + n
    return 440.0 * 2 ** ((midi - 69) / 12.0)

def shift_oct(name, d):
    """Bump a note name up/down d octaves: shift_oct('D2', 1) -> 'D3'."""
    i = 1
    while i < len(name) and name[i] in '#b':
        i += 1
    return name[:i] + str(int(name[i:]) + d)

# --------------------------------------------------------------------------
# Wavetables
# --------------------------------------------------------------------------
T = 2048
SINE = [math.sin(2 * math.pi * i / T) for i in range(T)]
SAW = [(i / T) * 2.0 - 1.0 for i in range(T)]
TRI = [4.0 * abs((i / T) - 0.5) - 1.0 for i in range(T)]
SQR = [1.0 if i < T // 2 else -1.0 for i in range(T)]
TABLES = {'sine': SINE, 'saw': SAW, 'tri': TRI, 'sqr': SQR}

# --------------------------------------------------------------------------
# Instruments. Mellowed: lower lowpass coefficients + softer bell partials so
# high notes don't screech. lp0/lp1 = one-pole cutoff at note start / end.
# --------------------------------------------------------------------------
INSTR = {
    'pluck':  dict(wave='saw',  detune=4,  a=0.005, d=0.18, s=0.40, r=0.22, lp0=0.40, lp1=0.09, gain=0.50, h=None),
    'lead':   dict(wave='saw',  detune=5,  a=0.025, d=0.10, s=0.80, r=0.28, lp0=0.26, lp1=0.16, gain=0.52, h=None),
    'bell':   dict(wave='sine', detune=0,  a=0.003, d=0.55, s=0.0,  r=0.35, lp0=1.0,  lp1=1.0,  gain=0.26, h=[1.0, 0.42, 0.18, 0.07]),
    'pad':    dict(wave='saw',  detune=11, a=0.40,  d=0.4,  s=0.7,  r=1.1,  lp0=0.13, lp1=0.09, gain=0.24, h=None),
    'bass':   dict(wave='tri',  detune=0,  a=0.006, d=0.12, s=0.85, r=0.16, lp0=0.40, lp1=0.26, gain=0.70, h=None),
    'soft':   dict(wave='tri',  detune=3,  a=0.02,  d=0.20, s=0.70, r=0.40, lp0=0.55, lp1=0.30, gain=0.50, h=None),
    # bowed-strings (ruins): saw + vibrato, slow swell, reedy and mournful.
    'viol':   dict(wave='saw',  detune=6,  a=0.11,  d=0.15, s=0.88, r=0.50, lp0=0.30, lp1=0.20, gain=0.46, h=None, vib=0.007, vibr=5.5),
    # hollow flute/ocarina (cave): sine + odd partials + vibrata, breathy and eerie.
    'hollow': dict(wave='sine', detune=0,  a=0.05,  d=0.10, s=0.85, r=0.45, lp0=1.0,  lp1=1.0,  gain=0.54, h=[1.0, 0.0, 0.22, 0.0, 0.08], vib=0.006, vibr=4.6),
    # glassy celesta (ruins comp): brighter, more partials than the plain bell.
    'glass':  dict(wave='sine', detune=0,  a=0.002, d=0.6,  s=0.0,  r=0.4,  lp0=1.0,  lp1=1.0,  gain=0.30, h=[1.0, 0.6, 0.35, 0.22, 0.14, 0.09]),
    # pipe-organ chord wash (ruins): drawbar sine harmonics, churchy, steady.
    'organ':  dict(wave='sine', detune=2,  a=0.25,  d=0.30, s=0.90, r=0.80, lp0=0.9,  lp1=0.8,  gain=0.26, h=[1.0, 0.5, 0.0, 0.42, 0.0, 0.25]),
    # vocal 'aah' choir lead (ruins melody): vowel-shaped sine + vibrato + swell.
    'choir':  dict(wave='sine', detune=5,  a=0.14,  d=0.20, s=0.85, r=0.60, lp0=0.7,  lp1=0.55, gain=0.42, h=[1.0, 0.55, 0.80, 0.45, 0.25, 0.12], vib=0.008, vibr=5.0),
    # dark hollow drone-wash (cave): detuned low sines, very filtered, no buzz.
    'darkpad':dict(wave='sine', detune=9,  a=0.50,  d=0.40, s=0.70, r=1.20, lp0=0.40, lp1=0.30, gain=0.34, h=None),
}

def adsr(i, n, a, d, s, r):
    ai, di, ri = a * SR, d * SR, r * SR
    if i < ai:
        return i / ai if ai > 0 else 1.0
    if i < ai + di:
        return 1.0 - (1.0 - s) * ((i - ai) / di if di > 0 else 1.0)
    if i < n:
        return s
    t = (i - n) / ri if ri > 0 else 1.0
    return s * max(0.0, 1.0 - t)

def render_note(L, R, start, dur, freq, instr, vel=1.0, pan=0.0):
    p = INSTR[instr]
    body = int(dur * SR)
    tail = int(p['r'] * SR)
    n = body + tail
    tbl = TABLES[p['wave']]
    cents = p['detune']
    freqs = [freq] if cents == 0 else [freq * 2 ** (-cents / 1200.0), freq * 2 ** (cents / 1200.0)]
    harm = p['h']
    hg = harm if harm else [1.0]
    incs = [[f * h_i * T / SR for f in freqs] for h_i in hg]
    phases = [[0.0 for _ in freqs] for _ in hg]
    lp_state = 0.0
    a, d, s, r = p['a'], p['d'], p['s'], p['r']
    gain = p['gain'] * vel
    lp0, lp1 = p['lp0'], p['lp1']
    gl = math.cos((pan + 1) * math.pi / 4)
    gr = math.sin((pan + 1) * math.pi / 4)
    base = int(start * SR)
    inv_body = 1.0 / max(1, body)
    sum_hg = sum(hg)
    nvoice = len(freqs)
    vib = p.get('vib', 0.0)
    vstep = 2.0 * math.pi * p.get('vibr', 5.0) / SR
    for i in range(n):
        vmul = 1.0 + vib * math.sin(vstep * i) if vib > 0.0 else 1.0
        smp = 0.0
        for hi in range(len(hg)):
            ph = phases[hi]
            inc = incs[hi]
            g = hg[hi]
            for v in range(nvoice):
                ph[v] += inc[v] * vmul
                if ph[v] >= T:
                    ph[v] -= T
                i0 = int(ph[v])
                i1 = i0 + 1
                if i1 >= T:
                    i1 = 0
                # linear interpolation — kills the integer-index aliasing "screech"
                smp += (tbl[i0] + (tbl[i1] - tbl[i0]) * (ph[v] - i0)) * g
        smp /= (nvoice * sum_hg)
        env = adsr(i, body, a, d, s, r)
        frac = i * inv_body
        if frac > 1.0:
            frac = 1.0
        coef = lp0 + (lp1 - lp0) * frac
        lp_state += coef * (smp - lp_state)
        out = lp_state * env * gain
        idx = base + i
        if 0 <= idx < len(L):
            L[idx] += out * gl
            R[idx] += out * gr

def render_perc(L, R, start, kind, vel=1.0, pan=0.0):
    base = int(start * SR)
    gl = math.cos((pan + 1) * math.pi / 4)
    gr = math.sin((pan + 1) * math.pi / 4)
    if kind == 'kick':
        n = int(0.18 * SR)
        ph = 0.0
        for i in range(n):
            t = i / n
            f = 115.0 * (1.0 - t) + 45.0
            ph += f * T / SR
            if ph >= T:
                ph -= T
            env = (1.0 - t) ** 2
            out = SINE[int(ph)] * env * 1.05 * vel
            idx = base + i
            if 0 <= idx < len(L):
                L[idx] += out * gl
                R[idx] += out * gr
    elif kind == 'snare':
        n = int(0.13 * SR)
        seed = 0x71f3 + base
        ph = 0.0
        for i in range(n):
            t = i / n
            seed = (1103515245 * seed + 12345) & 0x7FFFFFFF
            noise = (seed / 0x3FFFFFFF) - 1.0
            ph += 190.0 * T / SR
            if ph >= T:
                ph -= T
            body = SINE[int(ph)] * 0.35
            env = (1.0 - t) ** 1.6
            out = (noise * 0.7 + body) * env * 0.78 * vel
            idx = base + i
            if 0 <= idx < len(L):
                L[idx] += out * gl
                R[idx] += out * gr
    elif kind == 'tom':
        n = int(0.32 * SR)
        ph = 0.0
        for i in range(n):
            t = i / n
            f = 100.0 * (1.0 - t * 0.45) + 52.0
            ph += f * T / SR
            if ph >= T:
                ph -= T
            env = (1.0 - t) ** 1.7
            out = SINE[int(ph)] * env * 0.9 * vel
            idx = base + i
            if 0 <= idx < len(L):
                L[idx] += out * gl
                R[idx] += out * gr
    else:  # 'shaker' / 'hat' — softened, low-level noise so it reads as air, not hiss
        n = int((0.05 if kind == 'hat' else 0.08) * SR)
        seed = 0x2545F4 + base
        lp = 0.0
        g = (0.30 if kind == 'hat' else 0.20) * vel
        for i in range(n):
            seed = (1103515245 * seed + 12345) & 0x7FFFFFFF
            noise = (seed / 0x3FFFFFFF) - 1.0
            lp += 0.30 * (noise - lp)   # heavier smoothing => darker, less screechy
            hp = noise - lp
            env = (1.0 - i / n) ** 2
            out = hp * env * g
            idx = base + i
            if 0 <= idx < len(L):
                L[idx] += out * gl
                R[idx] += out * gr

# --------------------------------------------------------------------------
# Master FX
# --------------------------------------------------------------------------
def _comb(buf, delay, fb, mix):
    out = list(buf)
    d = [0.0] * delay
    di = 0
    for i in range(len(buf)):
        y = d[di]
        d[di] = buf[i] + y * fb
        di = (di + 1) % delay
        out[i] = buf[i] + mix * y
    return out

def _allpass(buf, delay, fb):
    out = list(buf)
    d = [0.0] * delay
    di = 0
    for i in range(len(buf)):
        bufout = d[di]
        d[di] = buf[i] + bufout * fb
        out[i] = -buf[i] * fb + bufout
        di = (di + 1) % delay
    return out

def reverb(buf, amount=0.20, size=1.0):
    def _sz(d): return max(1, int(d * size))
    def _fb(fb): return min(0.93, 1.0 - (1.0 - fb) / size)
    wet = _comb(buf, _sz(1557), _fb(0.76), 1.0)
    wet = _comb(wet, _sz(1617), _fb(0.78), 1.0)
    wet = _comb(wet, _sz(1491), _fb(0.74), 1.0)
    wet = _allpass(wet, _sz(225), 0.5)
    wet = _allpass(wet, _sz(556), 0.5)
    return [buf[i] * (1 - amount) + wet[i] * amount * 0.30 for i in range(len(buf))]

def lowpass(buf, fc):
    """One-pole lowpass; cascade for steeper roll-off."""
    a = 1.0 - math.exp(-2.0 * math.pi * fc / SR)
    y = 0.0
    out = [0.0] * len(buf)
    for i in range(len(buf)):
        y += a * (buf[i] - y)
        out[i] = y
    return out

def finalize(L, R, loop_len, rev_amount=0.20, rev_size=1.0, tone=5200):
    L = reverb(L, rev_amount, rev_size); R = reverb(R, rev_amount, rev_size)
    # Per-track 2-pole lowpass = the master 'tone'/brightness of this track.
    L = lowpass(lowpass(L, tone), tone)
    R = lowpass(lowpass(R, tone), tone)
    # Seamless loop: the music body is exactly loop_len samples, but note releases +
    # reverb decay spill PAST it. Fold that overhang back onto the start (wrap-add) so
    # the last bar's tail continues into the first bar — exactly what happens on the
    # next iteration — then cut to loop_len. End now flows into start with no gap.
    n = len(L)
    for j in range(loop_len, n):
        k = (j - loop_len) % loop_len
        L[k] += L[j]; R[k] += R[j]
    del L[loop_len:]; del R[loop_len:]
    peak = max(1e-6, max(max(abs(x) for x in L), max(abs(x) for x in R)))
    norm = 0.84 / peak
    out = bytearray()
    for i in range(len(L)):
        for ch in (L[i], R[i]):
            v = math.tanh(ch * norm * 1.1)
            out += struct.pack('<h', int(max(-1.0, min(1.0, v)) * 32767))
    return bytes(out)

def write_wav(path, pcm):
    with wave.open(path, 'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(pcm)

# --------------------------------------------------------------------------
# Sequencer
# --------------------------------------------------------------------------
class Seq:
    def __init__(self, bpm):
        self.spb = 60.0 / bpm
        self.notes = []
        self.perc = []
        # The musical loop length in beats (bar grid). Set by auto_backing / the
        # track. Notes/ornaments that ring PAST this fold back to the start, so the
        # loop point lands exactly on the downbeat — never on a trailing ornament.
        self.loop_beats = None
        self.swing = 0.0  # 0=straight; ~0.12 pushes off-beat 8ths later (shuffle)
        self.rev_amount = 0.20   # reverb WET mix
        self.rev_size = 1.0      # reverb room size / decay (1=small room, ~2=cathedral)
        self.tone = 5200         # master lowpass cutoff Hz = brightness of the whole mix
    def _w(self, beat):
        # Swing warp: keep down-beats fixed, push the off-beat (x.5) later.
        if self.swing <= 0.0:
            return beat
        w = math.floor(beat); f = beat - w; a = self.swing
        if f <= 0.5:
            f = f * (0.5 + a) / 0.5
        else:
            f = (0.5 + a) + (f - 0.5) * (0.5 - a) / 0.5
        return w + f
    def n(self, beat, dur, note, instr, vel=1.0, pan=0.0):
        self.notes.append((self._w(beat) * self.spb, dur * self.spb, nf(note), instr, vel, pan))
    def chord(self, beat, dur, notes, instr, vel=1.0, pan=0.0, spread=0.0):
        for k, nt in enumerate(notes):
            pp = pan + (k - (len(notes) - 1) / 2.0) * spread
            self.n(beat, dur, nt, instr, vel, max(-1, min(1, pp)))
    def arp(self, beat, notes, instr, step=0.5, dur=0.45, vel=0.8, pan=0.0):
        for k, nt in enumerate(notes):
            self.n(beat + k * step, dur, nt, instr, vel, pan)
    def p(self, beat, kind, vel=1.0, pan=0.0):
        self.perc.append((self._w(beat) * self.spb, kind, vel, pan))
    def total_beats(self):
        return max((s / self.spb + d / self.spb for s, d, *_ in self.notes), default=0.0)
    def render(self):
        # The loop is exactly loop_beats long (bar grid); render that PLUS tail room
        # for the final notes' releases + reverb decay, which finalize() folds back.
        loop_beats = self.loop_beats if self.loop_beats is not None else self.total_beats()
        loop = int(round(loop_beats * self.spb * SR))
        length = loop + int((3.0 + (self.rev_size - 1.0) * 2.0) * SR)
        L = [0.0] * length; R = [0.0] * length
        for s, d, f, instr, vel, pan in self.notes:
            render_note(L, R, s, d, f, instr, vel, pan)
        for s, kind, vel, pan in self.perc:
            render_perc(L, R, s, kind, vel, pan)
        return finalize(L, R, loop, self.rev_amount, self.rev_size, self.tone)

def auto_backing(s, prog, bpb=4, pad_vel=0.78, arp_instr='pluck', arp_step=0.5,
                 arp_vel=0.5, arp_lift=0, perc='light', pad_spread=0.16):
    """Fill pad (sustained chord) + bass (root) + arpeggio (+ optional perc) for a
    list of (chord_notes, bass_root) bars. The track adds its own lead on top."""
    s.loop_beats = len(prog) * bpb   # loop point = end of the last bar, on the downbeat
    for bar, (chord, root) in enumerate(prog):
        b0 = bar * bpb
        s.chord(b0, bpb, chord, 'pad', vel=pad_vel, spread=pad_spread)
        s.n(b0, bpb * 0.5, root, 'bass', 0.85)
        s.n(b0 + bpb * 0.5, bpb * 0.5, shift_oct(root, 1), 'bass', 0.62)
        if arp_step > 0:
            cell = [shift_oct(c, arp_lift) for c in chord]
            k = 0
            t = b0
            while t < b0 + bpb - 1e-6:
                s.n(t, arp_step * 0.9, cell[k % len(cell)], arp_instr, arp_vel,
                    pan=(-0.22 if k % 2 == 0 else 0.22))
                t += arp_step
                k += 1
        if perc == 'light':
            s.p(b0, 'kick', 0.55)
            for off in (1, 2, 3):
                s.p(b0 + off, 'shaker', 0.45)
        elif perc == 'drive':
            s.p(b0, 'kick', 0.7); s.p(b0 + 2, 'kick', 0.6)
            for off in (0.5, 1.5, 2.5, 3.5):
                s.p(b0 + off, 'hat', 0.4)
        elif perc == 'soft':
            s.p(b0, 'kick', 0.4)
            s.p(b0 + 2, 'shaker', 0.4)

def _gpad(s, b0, bpb, chord, instr, vel, spread, mode):
    if mode == 'none':
        return
    if mode == 'low':            # open root+fifth, held — no full-chord up/down move
        s.n(b0, bpb, chord[0], instr, vel, pan=-0.12)
        s.n(b0, bpb, chord[-1], instr, vel * 0.85, pan=0.12)
    elif mode == 'stab':         # one short chord hit on the downbeat (off the wash)
        s.chord(b0, 0.5, chord, instr, vel, spread=spread)
    elif mode == 'half':         # chord on beats 1 and 3 (oom-pah)
        s.chord(b0, bpb * 0.5, chord, instr, vel, spread=spread)
        s.chord(b0 + bpb * 0.5, bpb * 0.5, chord, instr, vel * 0.9, spread=spread)
    elif mode == 'pulse':        # chord re-struck every beat (driving)
        for k in range(bpb):
            s.chord(b0 + k, 0.9, chord, instr, vel * 0.82, spread=spread)
    elif mode == 'swell':        # staggered entry — root first, upper notes ramp in
        for j, c in enumerate(chord):
            s.n(b0 + j * 0.3, bpb - j * 0.3, c, instr, vel * (0.78 + 0.06 * j),
                pan=(j - (len(chord) - 1) / 2.0) * spread)
    else:                        # 'block' — full chord held the whole bar
        s.chord(b0, bpb, chord, instr, vel, spread=spread)


def groove(s, prog, bpb=4, bass='half', comp='arp', perc='backbeat',
           pad_vel=0.7, pad_spread=0.16, comp_instr='pluck', comp_vel=0.5,
           comp_lift=1, bass_vel=0.8, pad=True, pad_instr='pad', pad_mode='block'):
    """Realize a (chord, root) progression with a configurable GROOVE so each track
    gets its own rhythmic identity (bass pattern + chord-comp rhythm + drum groove)
    instead of the one-size sustained-pad + bass-1-3 + even-arp of auto_backing."""
    s.loop_beats = len(prog) * bpb
    m = len(prog)
    for bar, (chord, root) in enumerate(prog):
        b0 = bar * bpb
        nxt = prog[(bar + 1) % m][1]
        if pad:
            _gpad(s, b0, bpb, chord, pad_instr, pad_vel, pad_spread, pad_mode)
        _gbass(s, b0, bpb, chord, root, nxt, bass, bass_vel)
        _gcomp(s, b0, bpb, chord, comp, comp_instr, comp_vel, comp_lift)
        _gperc(s, b0, bpb, perc)

def _gbass(s, b0, bpb, chord, root, nxt, pat, vel):
    if pat == 'drone':
        s.n(b0, bpb, root, 'bass', vel)
    elif pat == 'half':
        s.n(b0, bpb * 0.5, root, 'bass', vel)
        s.n(b0 + bpb * 0.5, bpb * 0.5, shift_oct(root, 1), 'bass', vel * 0.8)
    elif pat == 'quarter':
        for k in range(bpb):
            s.n(b0 + k, 0.9, root if k % 2 == 0 else shift_oct(root, 1), 'bass', vel * (0.95 if k % 2 == 0 else 0.78))
    elif pat == 'eighth':
        for k in range(bpb * 2):
            s.n(b0 + k * 0.5, 0.45, root if k % 2 == 0 else shift_oct(root, 1), 'bass', vel * 0.8)
    elif pat == 'sync':
        for off, v, hi in [(0, 1.0, False), (1.5, 0.8, True), (2, 0.9, False), (3.5, 0.75, True)]:
            s.n(b0 + off, 0.5, shift_oct(root, 1) if hi else root, 'bass', vel * v)
    elif pat == 'walk':
        seq = [root, shift_oct(chord[1], -1), shift_oct(chord[-1], -1), nxt]
        for k in range(bpb):
            s.n(b0 + k, 0.9, seq[k % len(seq)], 'bass', vel * (0.92 if k % 2 == 0 else 0.78))
    elif pat == 'toll':
        s.n(b0, bpb * 0.55, root, 'bass', vel)
        s.n(b0 + bpb * 0.5, bpb * 0.5, shift_oct(root, -1), 'bass', vel * 0.85)
    elif pat == 'creep':
        s.n(b0, 1.5, root, 'bass', vel)
        s.n(b0 + 2.5, 0.7, root, 'bass', vel * 0.7)
        s.n(b0 + 3.5, 0.5, shift_oct(root, 1), 'bass', vel * 0.6)

def _gcomp(s, b0, bpb, chord, pat, instr, vel, lift):
    cell = [shift_oct(c, lift) for c in chord]
    nc = len(cell)
    if pat in ('none', 'pad'):
        return
    if pat == 'arp':
        k = 0; t = b0
        while t < b0 + bpb - 1e-6:
            s.n(t, 0.45, cell[k % nc], instr, vel, pan=(-0.22 if k % 2 == 0 else 0.22)); t += 0.5; k += 1
    elif pat == 'arp_slow':
        k = 0; t = b0
        while t < b0 + bpb - 1e-6:
            s.n(t, 0.9, cell[k % nc], instr, vel, pan=(-0.2 if k % 2 == 0 else 0.2)); t += 1.0; k += 1
    elif pat == 'stab':
        for off in [x + 0.5 for x in range(bpb)]:
            for j, c in enumerate(cell):
                s.n(b0 + off, 0.22, c, instr, vel, pan=(j - (nc - 1) / 2.0) * 0.12)
    elif pat == 'roll':
        for base in (0.0, bpb * 0.5):
            for j, c in enumerate(cell):
                s.n(b0 + base + j * 0.07, 1.3, c, instr, vel * 0.8, pan=(j - (nc - 1) / 2.0) * 0.14)
    elif pat == 'broken':
        patt = [0, nc - 1, 1, nc - 1]
        k = 0; t = b0
        while t < b0 + bpb - 1e-6:
            s.n(t, 0.45, cell[patt[k % len(patt)] % nc], instr, vel, pan=(-0.18 if k % 2 == 0 else 0.18)); t += 0.5; k += 1
    elif pat == 'drip':
        s.n(b0 + 1, 1.4, cell[1 % nc], 'bell', vel, pan=-0.3)
        s.n(b0 + 3, 1.4, cell[2 % nc], 'bell', vel * 0.85, pan=0.3)

def _gperc(s, b0, bpb, pat):
    if pat == 'none':
        return
    if pat == 'heartbeat':
        s.p(b0, 'kick', 0.35); s.p(b0 + 2, 'kick', 0.28)
    elif pat == 'soft':
        s.p(b0, 'kick', 0.42); s.p(b0 + 2, 'shaker', 0.4)
    elif pat == 'backbeat':
        s.p(b0, 'kick', 0.6); s.p(b0 + 2, 'kick', 0.5)
        s.p(b0 + 1, 'snare', 0.5); s.p(b0 + 3, 'snare', 0.5)
        for k in (0.5, 1.5, 2.5, 3.5):
            s.p(b0 + k, 'hat', 0.3)
    elif pat == 'shaker':
        s.p(b0, 'kick', 0.4)
        for k in (0.5, 1.5, 2.5, 3.5):
            s.p(b0 + k, 'shaker', 0.42)
        for k in (1, 3):
            s.p(b0 + k, 'shaker', 0.3)
    elif pat == 'ritual':
        s.p(b0, 'tom', 0.5)
    elif pat == 'drive':
        s.p(b0, 'kick', 0.7); s.p(b0 + 0.75, 'kick', 0.5); s.p(b0 + 2, 'kick', 0.6); s.p(b0 + 2.75, 'kick', 0.45)
        s.p(b0 + 2, 'snare', 0.55)
        for k in [x * 0.25 for x in range(bpb * 4)]:
            s.p(b0 + k, 'hat', 0.22)

def lead(s, mel, instr='lead', vel=0.7, bell_long=True):
    for (beat, dur, note) in mel:
        s.n(beat, dur, note, instr, vel=vel)
        if bell_long and dur >= 1.5:
            s.n(beat, 0.6, note, 'bell', vel=0.32)

def offset_mel(mel, beats):
    """Shift a melody's beats so an A/B section can be reused later in the loop."""
    return [(b + beats, d, n) for (b, d, n) in mel]

def to_prog(bars):
    """Convert structured B-section bars [{'chord':[...],'bass':'X2'}] -> [(chord, root)]."""
    return [(b['chord'], b['bass']) for b in bars]

def to_mel(items):
    """Convert structured melody [{'beat','dur','note'}] -> [(beat, dur, note)]."""
    return [(m['beat'], m['dur'], m['note']) for m in items]

# ==========================================================================
# TRACK: Title — warm, welcoming, a touch wistful. F major / 100 BPM.
# ==========================================================================
def track_title():
    s = Seq(100)
    prog = [
        (['F3', 'A3', 'C4', 'E4'],  'F2'), (['A3', 'C4', 'E4', 'G4'],  'A2'),
        (['Bb3', 'D4', 'F4', 'A4'], 'Bb2'), (['C4', 'E4', 'G4', 'Bb4'], 'C3'),
        (['D4', 'F4', 'A4', 'C5'],  'D3'), (['Bb3', 'D4', 'F4', 'A4'], 'Bb2'),
        (['G3', 'Bb3', 'D4', 'F4'], 'G2'), (['C4', 'E4', 'G4', 'Bb4'], 'C3'),
    ] * 2
    prog = prog + to_prog([{"chord": ["Bb3", "D4", "F4"], "bass": "Bb2"}, {"chord": ["A3", "C4", "F4"], "bass": "A2"}, {"chord": ["G3", "Bb3", "D4"], "bass": "G2"}, {"chord": ["D4", "F4", "A4"], "bass": "D3"}, {"chord": ["Bb3", "D4", "F4"], "bass": "Bb2"}, {"chord": ["C4", "E4", "G4"], "bass": "C3"}, {"chord": ["G3", "Bb3", "D4", "F4"], "bass": "G2"}, {"chord": ["C4", "E4", "G4", "Bb4"], "bass": "C3"}])
    groove(s, prog, bpb=4, bass='half', comp='broken', perc='soft', pad_vel=0.78, comp_instr='pluck', comp_vel=0.5, pad_mode='swell')
    mel = [
        (0, 1, 'C5'), (1, 1, 'F5'), (2, 1.5, 'A5'), (3.5, .5, 'G5'), (4, 1, 'E5'), (5, 1, 'C5'), (6, 2, 'E5'),
        (8, 1, 'D5'), (9, 1, 'F5'), (10, 1.5, 'A5'), (11.5, .5, 'C6'), (12, 1, 'Bb5'), (13, 1, 'A5'), (14, 2, 'G5'),
        (16, 1, 'F5'), (17, 1, 'A5'), (18, 1.5, 'C6'), (19.5, .5, 'Bb5'), (20, 1, 'A5'), (21, 1, 'G5'), (22, 2, 'F5'),
        (24, 1, 'A5'), (25, 1, 'G5'), (26, 1, 'F5'), (27, 1, 'D5'), (28, 1, 'E5'), (29, 1, 'G5'), (30, 2, 'F5'),
        (32, 1, 'A5'), (33, 1, 'C6'), (34, 1.5, 'D6'), (35.5, .5, 'C6'), (36, 1, 'A5'), (37, 1, 'F5'), (38, 2, 'A5'),
        (40, 1, 'G5'), (41, 1, 'Bb5'), (42, 1.5, 'D6'), (43.5, .5, 'C6'), (44, 1, 'Bb5'), (45, 1, 'A5'), (46, 2, 'G5'),
        (48, 1, 'F5'), (49, 1, 'A5'), (50, 1.5, 'C6'), (51.5, .5, 'A5'), (52, 1, 'G5'), (53, 1, 'E5'), (54, 2, 'F5'),
        (56, 1, 'G5'), (57, 1, 'A5'), (58, 1, 'Bb5'), (59, 1, 'A5'), (60, 1, 'G5'), (61, 1, 'E5'), (62, 2, 'F5'),
    ]
    mel = mel + offset_mel(to_mel([{"beat": 0, "dur": 1, "note": "F4"}, {"beat": 1, "dur": 1, "note": "A4"}, {"beat": 2, "dur": 1.5, "note": "Bb4"}, {"beat": 3.5, "dur": 0.5, "note": "C5"}, {"beat": 4, "dur": 1.5, "note": "D5"}, {"beat": 5.5, "dur": 0.5, "note": "C5"}, {"beat": 6, "dur": 2, "note": "A4"}, {"beat": 8, "dur": 1, "note": "Bb4"}, {"beat": 9, "dur": 1, "note": "D5"}, {"beat": 10, "dur": 2, "note": "G4"}, {"beat": 12, "dur": 1, "note": "A4"}, {"beat": 13, "dur": 1, "note": "D5"}, {"beat": 14, "dur": 1.5, "note": "F5"}, {"beat": 15.5, "dur": 0.5, "note": "E5"}, {"beat": 16, "dur": 1.5, "note": "D5"}, {"beat": 17.5, "dur": 0.5, "note": "C5"}, {"beat": 18, "dur": 1, "note": "Bb4"}, {"beat": 19, "dur": 1, "note": "D5"}, {"beat": 20, "dur": 1.5, "note": "C5"}, {"beat": 21.5, "dur": 0.5, "note": "E5"}, {"beat": 22, "dur": 2, "note": "G5"}, {"beat": 24, "dur": 1, "note": "F5"}, {"beat": 25, "dur": 1, "note": "D5"}, {"beat": 26, "dur": 1, "note": "Bb4"}, {"beat": 27, "dur": 1, "note": "G4"}, {"beat": 28, "dur": 1, "note": "A4"}, {"beat": 29, "dur": 1, "note": "Bb4"}, {"beat": 30, "dur": 2, "note": "C5"}]), 64)
    lead(s, mel, vel=0.7)
    return s

# ==========================================================================
# TRACK: Main menu — calmer, spacious, "choose your hero". G major / 88 BPM.
# Pad-forward, slow bell arpeggio, gentle.
# ==========================================================================
def track_mainmenu():
    s = Seq(88)
    prog = [
        (['G3', 'B3', 'D4'], 'G2'), (['E3', 'G3', 'B3'], 'E2'),
        (['C4', 'E4', 'G4'], 'C3'), (['D4', 'F#4', 'A4'], 'D3'),
        (['G3', 'B3', 'D4'], 'G2'), (['C4', 'E4', 'G4'], 'C3'),
        (['A3', 'C4', 'E4'], 'A2'), (['D4', 'F#4', 'A4'], 'D3'),
        (['B3', 'D4', 'G4'], 'G2'), (['E3', 'G3', 'B3'], 'E2'),
        (['C4', 'E4', 'G4'], 'C3'), (['D4', 'F#4', 'A4'], 'D3'),
    ]
    prog = prog + to_prog([{"chord": ["E3", "G3", "B3"], "bass": "E2"}, {"chord": ["B3", "D4", "F#4"], "bass": "B2"}, {"chord": ["C4", "E4", "G4"], "bass": "C3"}, {"chord": ["B3", "D4", "G4"], "bass": "B2"}, {"chord": ["A3", "C4", "E4"], "bass": "A2"}, {"chord": ["E3", "G3", "B3"], "bass": "E2"}, {"chord": ["C4", "E4", "G4"], "bass": "C3"}, {"chord": ["A3", "D4", "F#4"], "bass": "D3"}, {"chord": ["G3", "B3", "D4"], "bass": "G2"}, {"chord": ["A3", "D4", "F#4"], "bass": "D3"}])
    groove(s, prog, bpb=4, bass='drone', comp='arp_slow', perc='soft', pad_vel=0.85, comp_instr='bell', comp_vel=0.4, pad_spread=0.2, pad_mode='low')
    mel = [
        (0, 2, 'D5'), (2, 2, 'B4'), (4, 2, 'C5'), (6, 1, 'E5'), (7, 1, 'D5'),
        (8, 2, 'G4'), (10, 1, 'A4'), (11, 1, 'B4'), (12, 3, 'D5'), (15, 1, 'C5'),
        (16, 2, 'B4'), (18, 2, 'D5'), (20, 2, 'E5'), (22, 2, 'D5'),
        (24, 2, 'C5'), (26, 1, 'B4'), (27, 1, 'A4'), (28, 4, 'G4'),
        (32, 2, 'G5'), (34, 2, 'D5'), (36, 2, 'E5'), (38, 1, 'F#5'), (39, 1, 'G5'),
        (40, 2, 'C5'), (42, 2, 'E5'), (44, 3, 'D5'), (47, 1, 'B4'),
    ]
    mel = mel + offset_mel(to_mel([{"beat": 0, "dur": 1.5, "note": "B4"}, {"beat": 1.5, "dur": 0.5, "note": "G4"}, {"beat": 2, "dur": 2, "note": "E4"}, {"beat": 4, "dur": 1, "note": "F#4"}, {"beat": 5, "dur": 1, "note": "A4"}, {"beat": 6, "dur": 2, "note": "B4"}, {"beat": 8, "dur": 1.5, "note": "G4"}, {"beat": 9.5, "dur": 0.5, "note": "E4"}, {"beat": 10, "dur": 2, "note": "C5"}, {"beat": 12, "dur": 1, "note": "B4"}, {"beat": 13, "dur": 1, "note": "A4"}, {"beat": 14, "dur": 2, "note": "G4"}, {"beat": 16, "dur": 1, "note": "A4"}, {"beat": 17, "dur": 1, "note": "C5"}, {"beat": 18, "dur": 2, "note": "E5"}, {"beat": 20, "dur": 1.5, "note": "B4"}, {"beat": 21.5, "dur": 0.5, "note": "G4"}, {"beat": 22, "dur": 2, "note": "E4"}, {"beat": 24, "dur": 1, "note": "G4"}, {"beat": 25, "dur": 1, "note": "C5"}, {"beat": 26, "dur": 1, "note": "E5"}, {"beat": 27, "dur": 1, "note": "D5"}, {"beat": 28, "dur": 1.5, "note": "C5"}, {"beat": 29.5, "dur": 0.5, "note": "A4"}, {"beat": 30, "dur": 2, "note": "F#4"}, {"beat": 32, "dur": 1, "note": "G4"}, {"beat": 33, "dur": 1, "note": "B4"}, {"beat": 34, "dur": 2, "note": "D5"}, {"beat": 36, "dur": 1.5, "note": "B4"}, {"beat": 37.5, "dur": 0.5, "note": "A4"}, {"beat": 38, "dur": 2, "note": "G4"}]), 48)
    lead(s, mel, instr='soft', vel=0.62)
    return s

# ==========================================================================
# TRACK: Field — adventurous, driving, the workhorse loop. D major / 118 BPM.
# ==========================================================================
def track_field():
    s = Seq(118)
    prog = [
        (['D4', 'F#4', 'A4'], 'D2'), (['A3', 'C#4', 'E4'], 'A2'),
        (['B3', 'D4', 'F#4'], 'B2'), (['G3', 'B3', 'D4'], 'G2'),
        (['D4', 'F#4', 'A4'], 'D2'), (['A3', 'C#4', 'E4'], 'A2'),
        (['G3', 'B3', 'D4'], 'G2'), (['A3', 'C#4', 'E4'], 'A2'),
    ] * 2
    prog = prog + to_prog([{"chord": ["B3", "D4", "F#4"], "bass": "B2"}, {"chord": ["G3", "B3", "D4"], "bass": "G2"}, {"chord": ["D4", "F#4", "A4"], "bass": "D3"}, {"chord": ["A3", "C#4", "E4"], "bass": "A2"}, {"chord": ["G3", "B3", "D4"], "bass": "G2"}, {"chord": ["D4", "F#4", "A4"], "bass": "D3"}, {"chord": ["E4", "G4", "B4"], "bass": "E3"}, {"chord": ["A3", "C#4", "E4"], "bass": "A2"}, {"chord": ["B3", "D4", "F#4"], "bass": "B2"}, {"chord": ["G3", "B3", "D4"], "bass": "G2"}, {"chord": ["A3", "C#4", "E4"], "bass": "A2"}, {"chord": ["A3", "C#4", "E4", "G4"], "bass": "A2"}])
    groove(s, prog, bpb=4, bass='sync', comp='stab', perc='backbeat', pad_vel=0.7, comp_instr='pluck', comp_vel=0.42, pad_mode='stab')
    mel = [
        (0, 1, 'D5'), (1, .5, 'E5'), (1.5, .5, 'F#5'), (2, 1, 'A5'), (3, 1, 'F#5'),
        (4, 1, 'E5'), (5, 1, 'C#5'), (6, 2, 'E5'),
        (8, 1, 'F#5'), (9, .5, 'G5'), (9.5, .5, 'A5'), (10, 1, 'B5'), (11, 1, 'A5'),
        (12, 1, 'G5'), (13, 1, 'B5'), (14, 2, 'A5'),
        (16, 1, 'D5'), (17, .5, 'E5'), (17.5, .5, 'F#5'), (18, 1, 'A5'), (19, 1, 'D6'),
        (20, 1, 'C#6'), (21, 1, 'A5'), (22, 2, 'B5'),
        (24, 1, 'G5'), (25, 1, 'A5'), (26, 1, 'B5'), (27, 1, 'A5'),
        (28, 1, 'F#5'), (29, 1, 'E5'), (30, 2, 'D5'),
        (32, 1, 'A5'), (33, 1, 'F#5'), (34, 1, 'D5'), (35, 1, 'F#5'), (36, 1, 'A5'), (37, 1, 'B5'), (38, 2, 'A5'),
        (40, 1, 'B5'), (41, 1, 'A5'), (42, 1, 'G5'), (43, 1, 'F#5'), (44, 1, 'E5'), (45, 1, 'F#5'), (46, 2, 'D5'),
        (48, 1, 'D5'), (49, .5, 'E5'), (49.5, .5, 'F#5'), (50, 1, 'A5'), (51, 1, 'D6'), (52, 1, 'B5'), (53, 1, 'A5'), (54, 2, 'F#5'),
        (56, 1, 'G5'), (57, 1, 'E5'), (58, 1, 'A5'), (59, 1, 'G5'), (60, 1, 'F#5'), (61, 1, 'E5'), (62, 2, 'D5'),
    ]
    mel = mel + offset_mel(to_mel([{"beat": 0, "dur": 1, "note": "F#4"}, {"beat": 1, "dur": 1, "note": "A4"}, {"beat": 2, "dur": 1.5, "note": "B4"}, {"beat": 3.5, "dur": 0.5, "note": "A4"}, {"beat": 4, "dur": 1, "note": "G4"}, {"beat": 5, "dur": 1, "note": "B4"}, {"beat": 6, "dur": 2, "note": "D5"}, {"beat": 8, "dur": 1, "note": "A4"}, {"beat": 9, "dur": 1, "note": "D5"}, {"beat": 10, "dur": 1.5, "note": "F#5"}, {"beat": 11.5, "dur": 0.5, "note": "E5"}, {"beat": 12, "dur": 1, "note": "E5"}, {"beat": 13, "dur": 1, "note": "C#5"}, {"beat": 14, "dur": 2, "note": "A4"}, {"beat": 16, "dur": 1, "note": "B4"}, {"beat": 17, "dur": 1, "note": "D5"}, {"beat": 18, "dur": 1.5, "note": "G5"}, {"beat": 19.5, "dur": 0.5, "note": "F#5"}, {"beat": 20, "dur": 1, "note": "E5"}, {"beat": 21, "dur": 1, "note": "F#5"}, {"beat": 22, "dur": 2, "note": "A5"}, {"beat": 24, "dur": 1, "note": "G5"}, {"beat": 25, "dur": 1, "note": "E5"}, {"beat": 26, "dur": 1.5, "note": "B4"}, {"beat": 27.5, "dur": 0.5, "note": "C#5"}, {"beat": 28, "dur": 1, "note": "E5"}, {"beat": 29, "dur": 1, "note": "C#5"}, {"beat": 30, "dur": 2, "note": "E5"}, {"beat": 32, "dur": 1, "note": "F#5"}, {"beat": 33, "dur": 1, "note": "D5"}, {"beat": 34, "dur": 1.5, "note": "B4"}, {"beat": 35.5, "dur": 0.5, "note": "D5"}, {"beat": 36, "dur": 1, "note": "G4"}, {"beat": 37, "dur": 1, "note": "B4"}, {"beat": 38, "dur": 2, "note": "D5"}, {"beat": 40, "dur": 1, "note": "C#5"}, {"beat": 41, "dur": 1, "note": "E5"}, {"beat": 42, "dur": 1, "note": "D5"}, {"beat": 43, "dur": 1, "note": "C#5"}, {"beat": 44, "dur": 1, "note": "B4"}, {"beat": 45, "dur": 1, "note": "C#5"}, {"beat": 46, "dur": 2, "note": "A4"}]), 64)
    lead(s, mel, vel=0.66)
    return s

# ==========================================================================
# TRACK: Town — cozy, welcoming settlement. G major / 108 BPM. Soft flute + music-box.
# ==========================================================================
def track_town():
    s = Seq(108)
    prog = [
        (['G3', 'B3', 'D4'], 'G2'), (['D4', 'F#4', 'A4'], 'D3'),
        (['E3', 'G3', 'B3'], 'E2'), (['C4', 'E4', 'G4'], 'C3'),
        (['G3', 'B3', 'D4'], 'G2'), (['C4', 'E4', 'G4'], 'C3'),
        (['A3', 'C4', 'E4'], 'A2'), (['D4', 'F#4', 'A4'], 'D3'),
    ] * 2
    prog = prog + to_prog([{"chord": ["E3", "G3", "B3"], "bass": "E2"}, {"chord": ["C4", "E4", "G4"], "bass": "C3"}, {"chord": ["A3", "C4", "E4"], "bass": "A2"}, {"chord": ["D4", "F#4", "A4"], "bass": "D3"}, {"chord": ["E3", "G3", "B3"], "bass": "E2"}, {"chord": ["C4", "E4", "G4"], "bass": "C3"}, {"chord": ["G3", "B3", "D4"], "bass": "G2"}, {"chord": ["A3", "C4", "E4"], "bass": "A2"}, {"chord": ["C4", "E4", "G4"], "bass": "C3"}, {"chord": ["D4", "F#4", "A4", "C5"], "bass": "D3"}, {"chord": ["G3", "B3", "D4"], "bass": "G2"}])
    s.swing = 0.08
    groove(s, prog, bpb=4, bass='quarter', comp='arp', perc='soft', pad_vel=0.62, comp_instr='bell', comp_vel=0.4)
    # G major pentatonic-leaning melody (G A B D E) — open, folk wander
    mel = [
        (0, 1, 'D5'), (1, 1, 'E5'), (2, 1, 'G5'), (3, 1, 'E5'), (4, 1, 'D5'), (5, 1, 'B4'), (6, 2, 'A4'),
        (8, 1, 'B4'), (9, 1, 'D5'), (10, 1, 'E5'), (11, 1, 'D5'), (12, 1, 'B4'), (13, 1, 'A4'), (14, 2, 'G4'),
        (16, 1, 'E5'), (17, 1, 'G5'), (18, 1, 'A5'), (19, 1, 'G5'), (20, 1, 'E5'), (21, 1, 'D5'), (22, 2, 'E5'),
        (24, 1, 'D5'), (25, 1, 'B4'), (26, 1, 'D5'), (27, 1, 'E5'), (28, 1, 'D5'), (29, 1, 'B4'), (30, 2, 'A4'),
        (32, 1, 'G5'), (33, 1, 'A5'), (34, 1, 'B5'), (35, 1, 'A5'), (36, 1, 'G5'), (37, 1, 'E5'), (38, 2, 'D5'),
        (40, 1, 'E5'), (41, 1, 'G5'), (42, 1, 'E5'), (43, 1, 'D5'), (44, 1, 'E5'), (45, 1, 'A5'), (46, 2, 'G5'),
        (48, 1, 'B4'), (49, 1, 'D5'), (50, 1, 'E5'), (51, 1, 'G5'), (52, 1, 'E5'), (53, 1, 'D5'), (54, 2, 'B4'),
        (56, 1, 'A4'), (57, 1, 'B4'), (58, 1, 'D5'), (59, 1, 'E5'), (60, 1, 'D5'), (61, 1, 'B4'), (62, 2, 'G4'),
    ]
    mel = mel + offset_mel(to_mel([{"beat": 0, "dur": 1, "note": "B4"}, {"beat": 1, "dur": 1, "note": "D5"}, {"beat": 2, "dur": 1.5, "note": "E5"}, {"beat": 3.5, "dur": 0.5, "note": "D5"}, {"beat": 4, "dur": 1, "note": "E5"}, {"beat": 5, "dur": 1, "note": "G5"}, {"beat": 6, "dur": 2, "note": "E5"}, {"beat": 8, "dur": 1, "note": "A4"}, {"beat": 9, "dur": 1, "note": "C5"}, {"beat": 10, "dur": 1.5, "note": "E5"}, {"beat": 11.5, "dur": 0.5, "note": "D5"}, {"beat": 12, "dur": 1, "note": "D5"}, {"beat": 13, "dur": 1, "note": "B4"}, {"beat": 14, "dur": 2, "note": "A4"}, {"beat": 16, "dur": 1, "note": "B4"}, {"beat": 17, "dur": 1, "note": "E5"}, {"beat": 18, "dur": 1, "note": "G5"}, {"beat": 19, "dur": 1, "note": "E5"}, {"beat": 20, "dur": 1, "note": "D5"}, {"beat": 21, "dur": 1, "note": "E5"}, {"beat": 22, "dur": 2, "note": "G5"}, {"beat": 24, "dur": 1, "note": "D5"}, {"beat": 25, "dur": 1, "note": "B4"}, {"beat": 26, "dur": 1, "note": "G4"}, {"beat": 27, "dur": 1, "note": "B4"}, {"beat": 28, "dur": 1, "note": "C5"}, {"beat": 29, "dur": 1, "note": "E5"}, {"beat": 30, "dur": 1.5, "note": "A4"}, {"beat": 31.5, "dur": 0.5, "note": "C5"}, {"beat": 32, "dur": 1, "note": "E5"}, {"beat": 33, "dur": 1, "note": "D5"}, {"beat": 34, "dur": 1, "note": "C5"}, {"beat": 35, "dur": 1, "note": "B4"}, {"beat": 36, "dur": 1, "note": "C5"}, {"beat": 37, "dur": 1, "note": "A4"}, {"beat": 38, "dur": 1, "note": "D5"}, {"beat": 39, "dur": 1, "note": "C5"}, {"beat": 40, "dur": 1, "note": "B4"}, {"beat": 41, "dur": 1, "note": "A4"}, {"beat": 42, "dur": 1, "note": "B4"}, {"beat": 43, "dur": 1, "note": "G4"}]), 64)
    lead(s, mel, instr='soft', vel=0.56)
    return s

# ==========================================================================
# TRACK: Ruins — ancient, lonely, brooding (not a cathedral). D minor / 68 BPM.
# Solo cello over a low bowed-pad drone, deep toll, cold harp glints.
# ==========================================================================
def track_ruins():
    # Ancient ruins: lonely and brooding, NOT a cathedral. A solo cello over a low
    # bowed-pad drone with a deep contrabass toll and a few cold harp glints.
    # D natural minor (with a harmonic-minor C# tension) in a slow 4/4 — weathered.
    s = Seq(68)
    s.rev_amount = 0.32; s.rev_size = 1.5; s.tone = 5000
    prog = [
        (['D3', 'F3', 'A3'], 'D2'), (['Bb2', 'D3', 'F3'], 'Bb1'),
        (['F3', 'A3', 'C4'], 'F2'), (['C3', 'E3', 'G3'], 'C2'),
        (['D3', 'F3', 'A3'], 'D2'), (['G2', 'Bb2', 'D3'], 'G1'),
        (['A2', 'C#3', 'E3'], 'A1'), (['D3', 'F3', 'A3'], 'D2'),
        (['F3', 'A3', 'C4'], 'F2'), (['C3', 'E3', 'G3'], 'C2'),
        (['G2', 'Bb2', 'D3'], 'G1'), (['D3', 'F3', 'A3'], 'D2'),
        (['Bb2', 'D3', 'F3'], 'Bb1'), (['A2', 'C#3', 'E3'], 'A1'),
        (['D3', 'F3', 'A3'], 'D2'), (['A2', 'C#3', 'E3', 'G3'], 'A1'),
    ]
    groove(s, prog, bpb=4, bass='toll', comp='none', perc='none',
           pad=True, pad_mode='low', pad_vel=0.42, pad_instr='darkpad', pad_spread=0.14)
    # cold harp glints — irregular, off the grid (no rolling arpeggio wash)
    for (_b, _n, _p) in [(2.5, 'A4', -0.25), (7.0, 'D5', 0.25), (13.5, 'F4', -0.2),
                         (20.0, 'A4', 0.2), (26.5, 'C5', -0.25), (34.0, 'D5', 0.25),
                         (43.5, 'A4', -0.2), (52.0, 'F4', 0.25), (58.5, 'E4', -0.2)]:
        s.n(_b, 1.6, _n, 'glass', 0.17, pan=_p)
    mel = [
        (0, 3, 'D4'), (3, 1, 'F4'), (4, 4, 'E4'),
        (8, 2, 'F4'), (10, 2, 'A4'), (12, 3, 'G4'), (15, 1, 'F4'),
        (16, 4, 'D4'), (20, 2, 'C4'), (22, 2, 'D4'),
        (24, 3, 'A4'), (27, 1, 'G4'), (28, 4, 'F4'),
        (32, 2, 'A4'), (34, 2, 'Bb4'), (36, 4, 'A4'),
        (40, 2, 'G4'), (42, 2, 'F4'), (44, 3, 'E4'), (47, 1, 'D4'),
        (48, 4, 'F4'), (52, 2, 'E4'), (54, 2, 'D4'),
        (56, 3, 'C4'), (59, 1, 'D4'), (60, 4, 'D4'),
    ]
    lead(s, mel, instr='viol', vel=0.5, bell_long=False)
    return s

# ==========================================================================
# TRACK: Boss — urgent, driving, dramatic. D minor / 132 BPM. Pumping bass,
# 16th arps, harmonic-minor tension (C# over the A chord).
# ==========================================================================
def track_boss():
    s = Seq(132)
    prog = [
        (['D4', 'F4', 'A4'], 'D2'), (['Bb3', 'D4', 'F4'], 'Bb2'),
        (['C4', 'E4', 'G4'], 'C3'), (['A3', 'C#4', 'E4'], 'A2'),
        (['D4', 'F4', 'A4'], 'D2'), (['Bb3', 'D4', 'F4'], 'Bb2'),
        (['G3', 'Bb3', 'D4'], 'G2'), (['A3', 'C#4', 'E4'], 'A2'),
    ] * 2
    prog = prog + to_prog([{"chord": ["G3", "Bb3", "D4"], "bass": "G2"}, {"chord": ["A3", "C#4", "E4"], "bass": "A2"}, {"chord": ["Bb3", "D4", "F4"], "bass": "Bb2"}, {"chord": ["C4", "E4", "G4"], "bass": "C3"}, {"chord": ["D4", "F4", "A4"], "bass": "D2"}, {"chord": ["Bb3", "D4", "F4"], "bass": "Bb2"}, {"chord": ["F3", "A3", "C4"], "bass": "F2"}, {"chord": ["C4", "E4", "G4"], "bass": "C3"}, {"chord": ["Bb3", "D4", "F4"], "bass": "Bb2"}, {"chord": ["C4", "E4", "G4"], "bass": "C3"}, {"chord": ["D4", "F4", "A4"], "bass": "D2"}, {"chord": ["A3", "C#4", "E4"], "bass": "A2"}, {"chord": ["G3", "Bb3", "D4"], "bass": "G2"}, {"chord": ["Bb3", "D4", "F4"], "bass": "Bb2"}, {"chord": ["D4", "F4", "A4"], "bass": "D2"}, {"chord": ["A3", "C#4", "E4", "G4"], "bass": "A2"}])
    groove(s, prog, bpb=4, bass='eighth', comp='stab', perc='drive', pad_vel=0.66, comp_instr='pluck', comp_vel=0.36, pad_mode='pulse')
    mel = [
        (0, .5, 'A5'), (.5, .5, 'D6'), (1, 1, 'C6'), (2, 1, 'A5'), (3, 1, 'F5'),
        (4, .5, 'G5'), (4.5, .5, 'A5'), (5, 1, 'Bb5'), (6, 2, 'A5'),
        (8, .5, 'F5'), (8.5, .5, 'G5'), (9, 1, 'A5'), (10, 1, 'D5'), (11, 1, 'F5'),
        (12, .5, 'E5'), (12.5, .5, 'F5'), (13, 1, 'G5'), (14, 2, 'E5'),
        (16, .5, 'A5'), (16.5, .5, 'D6'), (17, 1, 'C6'), (18, 1, 'A5'), (19, 1, 'Bb5'),
        (20, 1, 'A5'), (21, 1, 'G5'), (22, 2, 'F5'),
        (24, .5, 'D5'), (24.5, .5, 'F5'), (25, .5, 'A5'), (25.5, .5, 'C6'), (26, 1, 'D6'), (27, 1, 'C#6'),
        (28, 1, 'D6'), (29, 1, 'A5'), (30, 2, 'D6'),
        (32, .5, 'D6'), (32.5, .5, 'C6'), (33, 1, 'A5'), (34, 1, 'D6'), (35, 1, 'C6'),
        (36, .5, 'A5'), (36.5, .5, 'F5'), (37, 1, 'A5'), (38, 2, 'D6'),
        (40, .5, 'Bb5'), (40.5, .5, 'A5'), (41, 1, 'G5'), (42, 1, 'F5'), (43, 1, 'D5'),
        (44, 1, 'F5'), (45, 1, 'G5'), (46, 2, 'A5'),
        (48, .5, 'A5'), (48.5, .5, 'D6'), (49, 1, 'C6'), (50, 1, 'A5'), (51, 1, 'Bb5'),
        (52, 1, 'C6'), (53, 1, 'D6'), (54, 2, 'C#6'),
        (56, .5, 'D6'), (56.5, .5, 'A5'), (57, .5, 'F5'), (57.5, .5, 'A5'), (58, 1, 'D6'), (59, 1, 'C#6'),
        (60, 1, 'D6'), (61, 1, 'A5'), (62, 2, 'D6'),
    ]
    mel = mel + offset_mel(to_mel([{"beat": 0, "dur": 0.5, "note": "D5"}, {"beat": 0.5, "dur": 0.5, "note": "D5"}, {"beat": 1, "dur": 0.5, "note": "Bb4"}, {"beat": 1.5, "dur": 0.5, "note": "D5"}, {"beat": 2, "dur": 1, "note": "G5"}, {"beat": 3, "dur": 0.5, "note": "F5"}, {"beat": 3.5, "dur": 0.5, "note": "D5"}, {"beat": 4, "dur": 0.5, "note": "E5"}, {"beat": 4.5, "dur": 0.5, "note": "E5"}, {"beat": 5, "dur": 0.5, "note": "C#5"}, {"beat": 5.5, "dur": 0.5, "note": "E5"}, {"beat": 6, "dur": 1.5, "note": "A5"}, {"beat": 7.5, "dur": 0.5, "note": "G5"}, {"beat": 8, "dur": 0.5, "note": "F5"}, {"beat": 8.5, "dur": 0.5, "note": "Bb4"}, {"beat": 9, "dur": 0.5, "note": "D5"}, {"beat": 9.5, "dur": 0.5, "note": "F5"}, {"beat": 10, "dur": 1, "note": "Bb5"}, {"beat": 11, "dur": 0.5, "note": "A5"}, {"beat": 11.5, "dur": 0.5, "note": "F5"}, {"beat": 12, "dur": 0.5, "note": "E5"}, {"beat": 12.5, "dur": 0.5, "note": "G5"}, {"beat": 13, "dur": 0.5, "note": "C5"}, {"beat": 13.5, "dur": 0.5, "note": "E5"}, {"beat": 14, "dur": 1.5, "note": "C6"}, {"beat": 15.5, "dur": 0.5, "note": "G5"}, {"beat": 16, "dur": 2, "note": "A5"}, {"beat": 18, "dur": 1, "note": "F5"}, {"beat": 19, "dur": 1, "note": "D5"}, {"beat": 20, "dur": 1, "note": "F5"}, {"beat": 21, "dur": 1, "note": "A5"}, {"beat": 22, "dur": 2, "note": "D5"}, {"beat": 24, "dur": 1.5, "note": "C5"}, {"beat": 25.5, "dur": 0.5, "note": "F5"}, {"beat": 26, "dur": 1, "note": "A5"}, {"beat": 27, "dur": 1, "note": "C6"}, {"beat": 28, "dur": 2, "note": "G5"}, {"beat": 30, "dur": 1, "note": "E5"}, {"beat": 31, "dur": 1, "note": "C5"}, {"beat": 32, "dur": 0.5, "note": "D5"}, {"beat": 32.5, "dur": 0.5, "note": "F5"}, {"beat": 33, "dur": 0.5, "note": "Bb5"}, {"beat": 33.5, "dur": 0.5, "note": "A5"}, {"beat": 34, "dur": 1, "note": "F5"}, {"beat": 35, "dur": 0.5, "note": "D5"}, {"beat": 35.5, "dur": 0.5, "note": "F5"}, {"beat": 36, "dur": 0.5, "note": "E5"}, {"beat": 36.5, "dur": 0.5, "note": "G5"}, {"beat": 37, "dur": 0.5, "note": "C6"}, {"beat": 37.5, "dur": 0.5, "note": "Bb5"}, {"beat": 38, "dur": 1, "note": "G5"}, {"beat": 39, "dur": 0.5, "note": "E5"}, {"beat": 39.5, "dur": 0.5, "note": "G5"}, {"beat": 40, "dur": 1, "note": "A5"}, {"beat": 41, "dur": 0.5, "note": "F5"}, {"beat": 41.5, "dur": 0.5, "note": "D5"}, {"beat": 42, "dur": 1, "note": "F5"}, {"beat": 43, "dur": 0.5, "note": "E5"}, {"beat": 43.5, "dur": 0.5, "note": "C#5"}, {"beat": 44, "dur": 0.5, "note": "D5"}, {"beat": 44.5, "dur": 0.5, "note": "E5"}, {"beat": 45, "dur": 0.5, "note": "F5"}, {"beat": 45.5, "dur": 0.5, "note": "G5"}, {"beat": 46, "dur": 1.5, "note": "A5"}, {"beat": 47.5, "dur": 0.5, "note": "G5"}, {"beat": 48, "dur": 0.5, "note": "D5"}, {"beat": 48.5, "dur": 0.5, "note": "D5"}, {"beat": 49, "dur": 0.5, "note": "Bb4"}, {"beat": 49.5, "dur": 0.5, "note": "D5"}, {"beat": 50, "dur": 1, "note": "G5"}, {"beat": 51, "dur": 0.5, "note": "Bb5"}, {"beat": 51.5, "dur": 0.5, "note": "G5"}, {"beat": 52, "dur": 0.5, "note": "F5"}, {"beat": 52.5, "dur": 0.5, "note": "D5"}, {"beat": 53, "dur": 0.5, "note": "Bb4"}, {"beat": 53.5, "dur": 0.5, "note": "D5"}, {"beat": 54, "dur": 1, "note": "F5"}, {"beat": 55, "dur": 1, "note": "D5"}, {"beat": 56, "dur": 0.5, "note": "A5"}, {"beat": 56.5, "dur": 0.5, "note": "A5"}, {"beat": 57, "dur": 0.5, "note": "F5"}, {"beat": 57.5, "dur": 0.5, "note": "A5"}, {"beat": 58, "dur": 1, "note": "D6"}, {"beat": 59, "dur": 0.5, "note": "C6"}, {"beat": 59.5, "dur": 0.5, "note": "A5"}, {"beat": 60, "dur": 0.5, "note": "G5"}, {"beat": 60.5, "dur": 0.5, "note": "E5"}, {"beat": 61, "dur": 0.5, "note": "C#5"}, {"beat": 61.5, "dur": 0.5, "note": "E5"}, {"beat": 62, "dur": 1, "note": "G5"}, {"beat": 63, "dur": 1, "note": "A5"}]), 64)
    mel = [(b, d, shift_oct(nt, -1)) for (b, d, nt) in mel]
    lead(s, mel, vel=0.66)
    return s

# ==========================================================================
# TRACK: Cave — dark, deep, very open and quiet. E phrygian / 80 BPM. Low pad
# drone + sub-bass sweep + a few long lonely notes; almost no motion.
# ==========================================================================
def track_cave():
    # Deep cave: quiet, eerie, very open. A low pad drone + sub-bass + a sweep pedal
    # with only a handful of long, lonely notes and a few cold glints. E phrygian
    # (the F-natural b2) for dread. No steady arpeggio, almost no motion.
    s = Seq(80)
    s.rev_amount = 0.50; s.rev_size = 2.1; s.tone = 2900
    prog = [
        (['E3', 'G3', 'B3'], 'E2'), (['F3', 'A3', 'C4'], 'F2'),
        (['E3', 'G3', 'B3'], 'E2'), (['C3', 'E3', 'G3'], 'C2'),
        (['E3', 'G3', 'B3'], 'E2'), (['D3', 'F3', 'A3'], 'D2'),
        (['B2', 'D3', 'F3'], 'B1'), (['E3', 'G3', 'B3'], 'E2'),
    ] * 2
    groove(s, prog, bpb=4, bass='drone', comp='none', perc='none',
           pad=True, pad_mode='low', pad_vel=0.32, pad_instr='darkpad', pad_spread=0.1)
    n = len(prog) * 4
    # deep tonic sweep pedal — the cave's underground rumble
    for _pb in range(0, n, 4):
        s.n(_pb, 4.3, 'E1', 'subdrone', 0.5)
    # sub-bass octave under each bar
    for _b, (_ch, _rt) in enumerate(prog):
        s.n(_b * 4, 4.0, shift_oct(_rt, -1), 'bass', 0.24)
    # rare, irregular cold glints — a few only, far apart
    for (_pb, _pn, _p) in [(6, 'F5', -0.2), (21, 'B4', 0.25), (38, 'C5', -0.25), (55, 'F5', 0.2)]:
        s.n(_pb, 2.4, _pn, 'glass', 0.11, pan=_p)
    # distant, soft boom — slow, every 4 bars
    for _bm in range(0, n, 16):
        s.p(_bm, 'tom', 0.5)
    # very sparse, long, low eerie line — fewer notes, lots of empty air
    mel = [
        (3, 6, 'B4'),
        (14, 5, 'E4'),
        (26, 7, 'G4'),
        (39, 5, 'F4'),
        (50, 6, 'E4'),
        (60, 4, 'B4'),
    ]
    lead(s, mel, instr='hollow', vel=0.44, bell_long=False)
    return s

# ==========================================================================
# TRACK: Forest — open-air woodland, bright and spacious. D major / 100 BPM.
# Airy pan-flute over a flowing harp + warm strings, no drums.
# ==========================================================================
def track_forest():
    # Open-air woodland wander: bright, spacious D major. Airy pan-flute lead over a
    # flowing harp and a warm string wash, NO drums (the space is the rhythm).
    # Deliberately distinct from the cozy town tune: higher, opener, longer notes.
    s = Seq(100)
    s.rev_amount = 0.30; s.rev_size = 1.4; s.tone = 6200
    A = [
        (['D4', 'F#4', 'A4'], 'D2'), (['A3', 'C#4', 'E4'], 'A2'),
        (['B3', 'D4', 'F#4'], 'B2'), (['G3', 'B3', 'D4'], 'G2'),
        (['D4', 'F#4', 'A4'], 'D2'), (['G3', 'B3', 'D4'], 'G2'),
        (['E3', 'G3', 'B3'], 'E2'), (['A3', 'C#4', 'E4'], 'A2'),
    ]
    B = [
        (['B3', 'D4', 'F#4'], 'B2'), (['G3', 'B3', 'D4'], 'G2'),
        (['D4', 'F#4', 'A4'], 'D3'), (['A3', 'C#4', 'E4'], 'A2'),
        (['E3', 'G3', 'B3'], 'E2'), (['A3', 'C#4', 'E4'], 'A2'),
        (['B3', 'D4', 'F#4'], 'B2'), (['A3', 'C#4', 'E4', 'G4'], 'A2'),
    ]
    prog = A + A + B
    groove(s, prog, bpb=4, bass='half', comp='arp', perc='none',
           pad_vel=0.58, comp_instr='bell', comp_vel=0.36, pad_spread=0.22)
    mel = [
        (0, 2, 'A5'), (2, 1, 'B5'), (3, 1, 'A5'),
        (4, 2, 'F#5'), (6, 2, 'E5'),
        (8, 1.5, 'D5'), (9.5, .5, 'E5'), (10, 2, 'F#5'), (12, 1, 'E5'), (13, 1, 'D5'), (14, 2, 'B4'),
        (16, 2, 'D5'), (18, 1, 'F#5'), (19, 1, 'A5'), (20, 2, 'B5'), (22, 2, 'A5'),
        (24, 1, 'F#5'), (25, 1, 'E5'), (26, 2, 'D5'), (28, 2, 'E5'), (30, 2, 'F#5'),
        (32, 2, 'A5'), (34, 2, 'B5'), (36, 1.5, 'D6'), (37.5, .5, 'B5'), (38, 2, 'A5'),
        (40, 2, 'F#5'), (42, 1, 'E5'), (43, 1, 'F#5'), (44, 2, 'E5'), (46, 2, 'D5'),
        (48, 2, 'F#5'), (50, 1, 'A5'), (51, 1, 'B5'), (52, 2, 'A5'), (54, 2, 'F#5'),
        (56, 1, 'E5'), (57, 1, 'D5'), (58, 2, 'E5'), (60, 1, 'D5'), (61, 1, 'B4'), (62, 2, 'A4'),
    ]
    mel = mel + offset_mel([
        (0, 2, 'D5'), (2, 2, 'F#5'), (4, 2, 'E5'), (6, 2, 'D5'),
        (8, 1, 'B4'), (9, 1, 'D5'), (10, 2, 'E5'), (12, 2, 'F#5'), (14, 2, 'A5'),
        (16, 2, 'B5'), (18, 2, 'A5'), (20, 2, 'F#5'), (22, 2, 'E5'),
        (24, 1, 'D5'), (25, 1, 'E5'), (26, 2, 'F#5'), (28, 2, 'E5'), (30, 2, 'D5'),
    ], 64)
    lead(s, mel, instr='soft', vel=0.6, bell_long=False)
    return s

# ==========================================================================
# BOSS VARIANTS — five alternate boss themes to pick from. Distinct tempo,
# mode, meter, groove and lead instrument each.
# ==========================================================================
def track_boss2():
    # "Iron Onslaught" — militaristic E-minor march. Relentless distortion-guitar
    # riff over synth-brass stabs and a driving synth bass. 138 BPM.
    s = Seq(138)
    s.rev_amount = 0.16; s.rev_size = 1.0; s.tone = 5200
    Em=(['E3','G3','B3'],'E2'); C=(['C3','E3','G3'],'C2'); G=(['G3','B3','D4'],'G2')
    D=(['D3','F#3','A3'],'D2'); Am=(['A3','C4','E4'],'A2'); B=(['B2','D#3','F#3'],'B1')
    A8=[Em,C,G,D,Em,Am,B,Em]; B8=[C,G,Am,Em,C,D,B,Em]
    prog=A8+B8+A8
    groove(s, prog, bpb=4, bass='eighth', comp='stab', perc='drive',
           pad_vel=0.62, comp_instr='pluck', comp_vel=0.4, pad_mode='pulse')
    main=[
        (0,.5,'E5'),(0.5,.5,'B4'),(1,1,'E5'),(2,1,'G5'),(3,1,'F#5'),
        (4,.5,'E5'),(4.5,.5,'G5'),(5,1,'C6'),(6,1,'B5'),(7,1,'G5'),
        (8,1,'D5'),(9,1,'G5'),(10,1,'B5'),(11,1,'A5'),
        (12,.5,'F#5'),(12.5,.5,'A5'),(13,1,'D5'),(14,2,'E5'),
        (16,.5,'E5'),(16.5,.5,'B4'),(17,1,'G5'),(18,1,'E5'),(19,1,'B5'),
        (20,1,'A5'),(21,1,'C6'),(22,1,'A5'),(23,1,'E5'),
        (24,.5,'D#5'),(24.5,.5,'F#5'),(25,1,'B5'),(26,1,'A5'),(27,1,'F#5'),
        (28,1,'G5'),(29,1,'F#5'),(30,2,'E5'),
        (32,.5,'B5'),(32.5,.5,'E5'),(33,1,'G5'),(34,1,'B5'),(35,1,'C6'),
        (36,1,'B5'),(37,1,'A5'),(38,2,'G5'),
        (40,.5,'A5'),(40.5,.5,'C6'),(41,1,'B5'),(42,1,'G5'),(43,1,'E5'),
        (44,1,'F#5'),(45,1,'A5'),(46,2,'B5'),
        (48,1,'C6'),(49,1,'B5'),(50,1,'G5'),(51,1,'A5'),
        (52,.5,'F#5'),(52.5,.5,'D#5'),(53,1,'F#5'),(54,2,'B5'),
        (56,1,'E5'),(57,1,'G5'),(58,1,'B5'),(59,1,'A5'),(60,1,'G5'),(61,1,'F#5'),(62,2,'E5'),
    ]
    mel=main+offset_mel([(b,d,n) for (b,d,n) in main if b<32],64)
    lead(s, mel, vel=0.64, bell_long=False)
    return s

def track_boss3():
    # "Vertigo Waltz" — a fast, spinning dark waltz in C minor. Sweeping strings
    # over a gothic church-organ, 3/4 at 162 BPM. Dramatic and vertiginous.
    s = Seq(162)
    s.rev_amount = 0.30; s.rev_size = 1.5; s.tone = 5600
    Cm=(['C3','Eb3','G3'],'C2'); Ab=(['Ab2','C3','Eb3'],'Ab1'); Eb=(['Eb3','G3','Bb3'],'Eb2')
    G=(['G2','B2','D3'],'G1'); Fm=(['F3','Ab3','C4'],'F2'); Bb=(['Bb2','D3','F3'],'Bb1')
    A8=[Cm,Ab,Fm,G,Cm,Ab,G,Cm]; B8=[Eb,Bb,Fm,Cm,Ab,Fm,G,Cm]
    prog=A8+B8+A8
    groove(s, prog, bpb=3, bass='quarter', comp='arp', perc='ritual',
           pad_vel=0.5, comp_instr='organ', comp_vel=0.32, pad_instr='organ', pad_mode='block')
    for _bar in range(len(prog)):
        b0=_bar*3
        s.p(b0+1,'shaker',0.3); s.p(b0+2,'shaker',0.28)
    main=[
        (0,1,'G5'),(1,1,'Eb5'),(2,1,'C5'),
        (3,1.5,'D5'),(4.5,.5,'Eb5'),(5,1,'G5'),
        (6,1,'Ab5'),(7,1,'G5'),(8,1,'F5'),
        (9,1,'Eb5'),(10,1,'D5'),(11,1,'C5'),
        (12,1,'C5'),(13,1,'Eb5'),(14,1,'G5'),
        (15,1.5,'Ab5'),(16.5,.5,'G5'),(17,1,'F5'),
        (18,1,'D5'),(19,1,'F5'),(20,1,'Ab5'),
        (21,2,'G5'),(23,1,'D5'),
        (24,1,'Eb5'),(25,1,'G5'),(26,1,'Bb5'),
        (27,1.5,'C6'),(28.5,.5,'Bb5'),(29,1,'G5'),
        (30,1,'F5'),(31,1,'Ab5'),(32,1,'C6'),
        (33,1,'Bb5'),(34,1,'G5'),(35,1,'F5'),
        (36,1,'Ab5'),(37,1,'G5'),(38,1,'F5'),
        (39,1,'Eb5'),(40,1,'D5'),(41,1,'Eb5'),
        (42,1,'F5'),(43,1,'D5'),(44,1,'B4'),
        (45,2,'C5'),(47,1,'G4'),
    ]
    mel=main+offset_mel([(b,d,n) for (b,d,n) in main if b<24],48)
    lead(s, mel, instr='viol', vel=0.56, bell_long=False)
    return s

def track_boss4():
    # "Doomcrusher" — slow, heavy, crushing. Half-time D-minor groove, a low
    # synth-brass riff over pulsing strings. 120 BPM, all weight, no rush.
    s = Seq(120)
    s.rev_amount = 0.18; s.rev_size = 1.1; s.tone = 4600
    Dm=(['D3','F3','A3'],'D2'); Bb=(['Bb2','D3','F3'],'Bb1'); F=(['F3','A3','C4'],'F2')
    C=(['C3','E3','G3'],'C2'); Gm=(['G2','Bb2','D3'],'G1'); A=(['A2','C#3','E3'],'A1')
    A8=[Dm,Dm,Bb,C,Dm,Dm,Gm,A]; B8=[F,C,Dm,Bb,Gm,A,Dm,A]
    prog=A8+B8+A8
    groove(s, prog, bpb=4, bass='quarter', comp='none', perc='drive',
           pad_vel=0.55, pad_mode='pulse')
    main=[
        (0,1,'D4'),(1,1,'D4'),(2,.5,'F4'),(2.5,.5,'D4'),(3,1,'A4'),
        (4,1,'Bb4'),(5,1,'A4'),(6,2,'F4'),
        (8,1,'D4'),(9,1,'D4'),(10,.5,'C5'),(10.5,.5,'A4'),(11,1,'F4'),
        (12,1,'G4'),(13,1,'A4'),(14,2,'D5'),
        (16,1,'D4'),(17,1,'D4'),(18,.5,'F4'),(18.5,.5,'D4'),(19,1,'A4'),
        (20,1,'Bb4'),(21,1,'C5'),(22,2,'D5'),
        (24,1,'A4'),(25,1,'F4'),(26,1,'G4'),(27,1,'A4'),
        (28,.5,'C#5'),(28.5,.5,'E5'),(29,1,'A4'),(30,2,'D5'),
        (32,1,'F4'),(33,1,'A4'),(34,1,'C5'),(35,1,'A4'),
        (36,1,'G4'),(37,1,'F4'),(38,2,'A4'),
        (40,1,'D4'),(41,.5,'F4'),(41.5,.5,'A4'),(42,1,'D5'),(43,1,'C5'),
        (44,1,'Bb4'),(45,1,'A4'),(46,2,'F4'),
        (48,1,'G4'),(49,1,'Bb4'),(50,1,'D5'),(51,1,'Bb4'),
        (52,1,'A4'),(53,.5,'C#5'),(53.5,.5,'E5'),(54,2,'A4'),
        (56,1,'D5'),(57,1,'C5'),(58,1,'A4'),(59,1,'F4'),(60,1,'E4'),(61,1,'D4'),(62,2,'D4'),
    ]
    mel=main+offset_mel([(b,d,n) for (b,d,n) in main if b<32],64)
    lead(s, mel, vel=0.7, bell_long=False)
    return s

def track_boss5():
    # "Frenzy" — fast synthwave boss. Busy 16th saw-lead lines over a square-synth
    # arp and a pumping synth bass. A harmonic minor (G# bite). 160 BPM.
    s = Seq(160)
    s.rev_amount = 0.22; s.rev_size = 1.0; s.tone = 6000
    Am=(['A3','C4','E4'],'A2'); F=(['F3','A3','C4'],'F2'); Dm=(['D3','F3','A3'],'D2')
    E=(['E3','G#3','B3'],'E2'); G=(['G3','B3','D4'],'G2'); C=(['C3','E3','G3'],'C2')
    A8=[Am,F,Dm,E,Am,F,E,Am]; B8=[C,G,Dm,Am,F,E,Am,E]
    prog=A8+B8+A8
    groove(s, prog, bpb=4, bass='eighth', comp='arp', perc='drive',
           pad_vel=0.48, comp_instr='pluck', comp_vel=0.38, pad_mode='pulse')
    main=[
        (0,.5,'A5'),(0.5,.5,'C6'),(1,.5,'B5'),(1.5,.5,'A5'),(2,1,'E5'),(3,1,'A5'),
        (4,.5,'F5'),(4.5,.5,'A5'),(5,1,'C6'),(6,1,'A5'),(7,1,'F5'),
        (8,.5,'D5'),(8.5,.5,'F5'),(9,.5,'A5'),(9.5,.5,'D6'),(10,1,'C6'),(11,1,'A5'),
        (12,.5,'G#5'),(12.5,.5,'B5'),(13,1,'E5'),(14,2,'A5'),
        (16,.5,'A5'),(16.5,.5,'C6'),(17,.5,'B5'),(17.5,.5,'A5'),(18,1,'E5'),(19,1,'A5'),
        (20,.5,'F5'),(20.5,.5,'A5'),(21,1,'C6'),(22,1,'B5'),(23,1,'A5'),
        (24,.5,'G#5'),(24.5,.5,'B5'),(25,1,'D6'),(26,1,'C6'),(27,1,'B5'),
        (28,.5,'A5'),(28.5,.5,'G#5'),(29,1,'B5'),(30,2,'A5'),
        (32,.5,'C6'),(32.5,.5,'E6'),(33,1,'D6'),(34,1,'C6'),(35,1,'A5'),
        (36,.5,'G5'),(36.5,.5,'B5'),(37,1,'D6'),(38,2,'C6'),
        (40,.5,'A5'),(40.5,.5,'C6'),(41,1,'B5'),(42,1,'A5'),(43,1,'F5'),
        (44,.5,'E5'),(44.5,.5,'G#5'),(45,1,'B5'),(46,2,'E6'),
        (48,1,'A5'),(49,.5,'G#5'),(49.5,.5,'A5'),(50,1,'B5'),(51,1,'C6'),
        (52,.5,'D6'),(52.5,.5,'C6'),(53,1,'B5'),(54,2,'A5'),
        (56,.5,'E5'),(56.5,.5,'A5'),(57,.5,'C6'),(57.5,.5,'B5'),(58,1,'A5'),(59,1,'G#5'),(60,1,'A5'),(61,1,'E5'),(62,2,'A5'),
    ]
    mel=main+offset_mel([(b,d,n) for (b,d,n) in main if b<32],64)
    lead(s, mel, vel=0.6, bell_long=False)
    return s

def track_boss6():
    # "Last Stand" — epic orchestral finale. Heroic brass lead over swelling strings
    # and choir stabs with timpani booms. D harmonic minor, 146 BPM. Grand.
    s = Seq(146)
    s.rev_amount = 0.32; s.rev_size = 1.6; s.tone = 5800
    Dm=(['D3','F3','A3'],'D2'); Bb=(['Bb2','D3','F3'],'Bb1'); Gm=(['G2','Bb2','D3'],'G1')
    A=(['A2','C#3','E3'],'A1'); F=(['F3','A3','C4'],'F2'); C=(['C3','E3','G3'],'C2')
    A8=[Dm,Bb,Gm,A,Dm,Gm,A,Dm]; B8=[F,C,Bb,Gm,Dm,A,Dm,A]
    prog=A8+B8+A8
    groove(s, prog, bpb=4, bass='quarter', comp='stab', perc='drive',
           pad_vel=0.6, comp_instr='pluck', comp_vel=0.4, pad_mode='swell')
    for _bar in range(len(prog)):
        s.p(_bar*4,'tom',0.6)
    main=[
        (0,1,'D5'),(1,1,'A5'),(2,2,'D6'),
        (4,1,'C#6'),(5,1,'A5'),(6,2,'D6'),
        (8,1,'Bb5'),(9,1,'A5'),(10,1,'G5'),(11,1,'F5'),
        (12,1,'A5'),(13,1,'C#6'),(14,2,'D6'),
        (16,1,'D5'),(17,1,'F5'),(18,2,'A5'),
        (20,1,'G5'),(21,1,'Bb5'),(22,2,'A5'),
        (24,1,'A5'),(25,1,'C#6'),(26,1,'E6'),(27,1,'D6'),
        (28,1,'C#6'),(29,1,'A5'),(30,2,'D6'),
        (32,1,'F5'),(33,1,'A5'),(34,2,'C6'),
        (36,1,'Bb5'),(37,1,'G5'),(38,2,'Bb5'),
        (40,1,'C6'),(41,1,'Bb5'),(42,1,'A5'),(43,1,'G5'),
        (44,1,'A5'),(45,1,'C#6'),(46,2,'D6'),
        (48,1,'D6'),(49,1,'C#6'),(50,1,'Bb5'),(51,1,'A5'),
        (52,1,'G5'),(53,1,'A5'),(54,2,'Bb5'),
        (56,1,'A5'),(57,1,'G5'),(58,1,'F5'),(59,1,'E5'),(60,1,'F5'),(61,1,'A5'),(62,2,'D6'),
    ]
    mel=main+offset_mel([(b,d,n) for (b,d,n) in main if b<32],64)
    lead(s, mel, vel=0.62, bell_long=False)
    return s


TRACKS = {
    'title': track_title,
    'mainmenu': track_mainmenu,
    'field': track_field,
    'town': track_town,
    'ruins': track_ruins,
    'boss': track_boss,
    'cave': track_cave,
    'forest': track_forest,
    'boss2': track_boss2,
    'boss3': track_boss3,
    'boss4': track_boss4,
    'boss5': track_boss5,
    'boss6': track_boss6,
}

def main():
    which = sys.argv[1] if len(sys.argv) > 1 else 'title'
    out_dir = os.path.join(os.path.dirname(__file__), '..', 'assets', 'music')
    names = list(TRACKS) if which == 'all' else [which]
    for name in names:
        if name not in TRACKS:
            print('unknown track:', name); continue
        print('rendering', name, '...')
        pcm = TRACKS[name]().render()
        path = os.path.abspath(os.path.join(out_dir, 'emberwilds_%s.wav' % name))
        write_wav(path, pcm)
        print('  ->', path, '(%.1f MB)' % (len(pcm) / 1e6))

if __name__ == '__main__':
    main()
