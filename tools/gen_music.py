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
    'pad':    dict(wave='saw',  detune=11, a=0.40,  d=0.4,  s=0.7,  r=1.1,  lp0=0.13, lp1=0.09, gain=0.30, h=None),
    'bass':   dict(wave='tri',  detune=0,  a=0.006, d=0.12, s=0.85, r=0.16, lp0=0.40, lp1=0.26, gain=0.70, h=None),
    'soft':   dict(wave='tri',  detune=3,  a=0.02,  d=0.20, s=0.70, r=0.40, lp0=0.55, lp1=0.30, gain=0.50, h=None),
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
    for i in range(n):
        smp = 0.0
        for hi in range(len(hg)):
            ph = phases[hi]
            inc = incs[hi]
            g = hg[hi]
            for v in range(nvoice):
                ph[v] += inc[v]
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
            out = SINE[int(ph)] * env * 0.85 * vel
            idx = base + i
            if 0 <= idx < len(L):
                L[idx] += out * gl
                R[idx] += out * gr
    else:  # 'shaker' / 'hat' — softened, low-level noise so it reads as air, not hiss
        n = int((0.05 if kind == 'hat' else 0.08) * SR)
        seed = 0x2545F4 + base
        lp = 0.0
        g = (0.09 if kind == 'hat' else 0.055) * vel
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

def reverb(buf, amount=0.20):
    wet = _comb(buf, 1557, 0.76, 1.0)
    wet = _comb(wet, 1617, 0.78, 1.0)
    wet = _comb(wet, 1491, 0.74, 1.0)
    wet = _allpass(wet, 225, 0.5)
    wet = _allpass(wet, 556, 0.5)
    return [buf[i] * (1 - amount) + wet[i] * amount * 0.25 for i in range(len(buf))]

def lowpass(buf, fc):
    """One-pole lowpass; cascade for steeper roll-off."""
    a = 1.0 - math.exp(-2.0 * math.pi * fc / SR)
    y = 0.0
    out = [0.0] * len(buf)
    for i in range(len(buf)):
        y += a * (buf[i] - y)
        out[i] = y
    return out

def finalize(L, R):
    L = reverb(L); R = reverb(R)
    # Mellow: 2-pole ~5.2 kHz lowpass tames osc/bell harshness + reverb fizz.
    L = lowpass(lowpass(L, 5200), 5200)
    R = lowpass(lowpass(R, 5200), 5200)
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
    def n(self, beat, dur, note, instr, vel=1.0, pan=0.0):
        self.notes.append((beat * self.spb, dur * self.spb, nf(note), instr, vel, pan))
    def chord(self, beat, dur, notes, instr, vel=1.0, pan=0.0, spread=0.0):
        for k, nt in enumerate(notes):
            pp = pan + (k - (len(notes) - 1) / 2.0) * spread
            self.n(beat, dur, nt, instr, vel, max(-1, min(1, pp)))
    def arp(self, beat, notes, instr, step=0.5, dur=0.45, vel=0.8, pan=0.0):
        for k, nt in enumerate(notes):
            self.n(beat + k * step, dur, nt, instr, vel, pan)
    def p(self, beat, kind, vel=1.0, pan=0.0):
        self.perc.append((beat * self.spb, kind, vel, pan))
    def total_beats(self):
        return max((s / self.spb + d / self.spb for s, d, *_ in self.notes), default=0.0)
    def render(self):
        length = int((self.total_beats() * self.spb + 1.4) * SR)
        L = [0.0] * length; R = [0.0] * length
        for s, d, f, instr, vel, pan in self.notes:
            render_note(L, R, s, d, f, instr, vel, pan)
        for s, kind, vel, pan in self.perc:
            render_perc(L, R, s, kind, vel, pan)
        return finalize(L, R)

def auto_backing(s, prog, bpb=4, pad_vel=0.78, arp_instr='pluck', arp_step=0.5,
                 arp_vel=0.5, arp_lift=0, perc='light', pad_spread=0.16):
    """Fill pad (sustained chord) + bass (root) + arpeggio (+ optional perc) for a
    list of (chord_notes, bass_root) bars. The track adds its own lead on top."""
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

def lead(s, mel, instr='lead', vel=0.7, bell_long=True):
    for (beat, dur, note) in mel:
        s.n(beat, dur, note, instr, vel=vel)
        if bell_long and dur >= 1.5:
            s.n(beat, 0.6, note, 'bell', vel=0.32)

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
    auto_backing(s, prog, bpb=4, perc='light')
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
    auto_backing(s, prog, bpb=4, pad_vel=0.85, arp_instr='bell', arp_step=1.0,
                 arp_vel=0.4, arp_lift=1, perc='soft', pad_spread=0.2)
    mel = [
        (0, 2, 'D5'), (2, 2, 'B4'), (4, 2, 'C5'), (6, 1, 'E5'), (7, 1, 'D5'),
        (8, 2, 'G4'), (10, 1, 'A4'), (11, 1, 'B4'), (12, 3, 'D5'), (15, 1, 'C5'),
        (16, 2, 'B4'), (18, 2, 'D5'), (20, 2, 'E5'), (22, 2, 'D5'),
        (24, 2, 'C5'), (26, 1, 'B4'), (27, 1, 'A4'), (28, 4, 'G4'),
        (32, 2, 'G5'), (34, 2, 'D5'), (36, 2, 'E5'), (38, 1, 'F#5'), (39, 1, 'G5'),
        (40, 2, 'C5'), (42, 2, 'E5'), (44, 3, 'D5'), (47, 1, 'B4'),
    ]
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
    auto_backing(s, prog, bpb=4, pad_vel=0.7, arp_instr='pluck', arp_step=0.5,
                 arp_vel=0.5, arp_lift=1, perc='drive')
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
    lead(s, mel, vel=0.66)
    return s

# ==========================================================================
# TRACK: Town (meadows) — cozy, light, pastoral. C major / 104 BPM. Music-box.
# ==========================================================================
def track_town():
    s = Seq(104)
    prog = [
        (['C4', 'E4', 'G4'], 'C3'), (['G3', 'B3', 'D4'], 'G2'),
        (['A3', 'C4', 'E4'], 'A2'), (['F3', 'A3', 'C4'], 'F2'),
        (['C4', 'E4', 'G4'], 'C3'), (['G3', 'B3', 'D4'], 'G2'),
        (['F3', 'A3', 'C4'], 'F2'), (['G3', 'B3', 'D4'], 'G2'),
    ] * 2
    auto_backing(s, prog, bpb=4, pad_vel=0.66, arp_instr='bell', arp_step=0.5,
                 arp_vel=0.42, arp_lift=1, perc='soft')
    mel = [
        (0, 1, 'G4'), (1, 1, 'C5'), (2, 1, 'E5'), (3, 1, 'G5'), (4, 1, 'E5'), (5, 1, 'D5'), (6, 2, 'C5'),
        (8, 1, 'D5'), (9, 1, 'E5'), (10, 1, 'D5'), (11, 1, 'B4'), (12, 1, 'C5'), (13, 1, 'A4'), (14, 2, 'C5'),
        (16, 1, 'E5'), (17, 1, 'G5'), (18, 1, 'A5'), (19, 1, 'G5'), (20, 1, 'E5'), (21, 1, 'C5'), (22, 2, 'D5'),
        (24, 1, 'C5'), (25, 1, 'A4'), (26, 1, 'F5'), (27, 1, 'E5'), (28, 1, 'D5'), (29, 1, 'B4'), (30, 2, 'C5'),
        (32, 1, 'G4'), (33, 1, 'C5'), (34, 1, 'E5'), (35, 1, 'D5'), (36, 1, 'E5'), (37, 1, 'G5'), (38, 2, 'E5'),
        (40, 1, 'D5'), (41, 1, 'F5'), (42, 1, 'A5'), (43, 1, 'G5'), (44, 1, 'E5'), (45, 1, 'D5'), (46, 2, 'C5'),
        (48, 1, 'A4'), (49, 1, 'C5'), (50, 1, 'F5'), (51, 1, 'E5'), (52, 1, 'D5'), (53, 1, 'C5'), (54, 2, 'B4'),
        (56, 1, 'C5'), (57, 1, 'D5'), (58, 1, 'E5'), (59, 1, 'D5'), (60, 1, 'B4'), (61, 1, 'D5'), (62, 2, 'C5'),
    ]
    lead(s, mel, instr='soft', vel=0.6)
    return s

# ==========================================================================
# TRACK: Ruins — ancient, mysterious, sparse + a little mournful. A minor /
# 76 BPM. Pad + slow bass + bell, no drive. (Replaces a town/ruins theme.)
# ==========================================================================
def track_ruins():
    s = Seq(76)
    prog = [
        (['A3', 'C4', 'E4'], 'A2'), (['F3', 'A3', 'C4'], 'F2'),
        (['G3', 'B3', 'D4'], 'G2'), (['E3', 'G3', 'B3'], 'E2'),
        (['A3', 'C4', 'E4'], 'A2'), (['D3', 'F3', 'A3'], 'D2'),
        (['G3', 'B3', 'D4'], 'G2'), (['E3', 'G3', 'B3'], 'E2'),
        (['F3', 'A3', 'C4'], 'F2'), (['C4', 'E4', 'G4'], 'C3'),
        (['D3', 'F3', 'A3'], 'D2'), (['E3', 'G3', 'B3'], 'E2'),
    ]
    # sparse: pad + bass + a slow bell arp, NO kick/hat (the 'none' perc)
    for bar, (chord, root) in enumerate(prog):
        b0 = bar * 4
        s.chord(b0, 4, chord, 'pad', vel=0.85, spread=0.22)
        s.n(b0, 3.0, root, 'bass', 0.8)
        s.n(b0 + 2, 2.0, shift_oct(root, 1), 'bass', 0.5)
        # slow descending bell figure, every half-note
        cell = [shift_oct(c, 1) for c in chord]
        for k in range(2):
            s.n(b0 + k * 2, 1.6, cell[(k) % len(cell)], 'bell', 0.34, pan=(-0.2 if k == 0 else 0.2))
    mel = [
        (0, 3, 'E5'), (3, 1, 'D5'), (4, 2, 'C5'), (6, 2, 'A4'),
        (8, 3, 'D5'), (11, 1, 'C5'), (12, 2, 'B4'), (14, 2, 'G#4'),
        (16, 2, 'A4'), (18, 2, 'C5'), (20, 2, 'E5'), (22, 2, 'D5'),
        (24, 3, 'C5'), (27, 1, 'B4'), (28, 4, 'A4'),
        (32, 2, 'C5'), (34, 2, 'F5'), (36, 2, 'E5'), (38, 2, 'C5'),
        (40, 2, 'D5'), (42, 2, 'B4'), (44, 4, 'A4'),
    ]
    lead(s, mel, instr='soft', vel=0.6, bell_long=False)
    return s

# ==========================================================================
# TRACK: Boss — urgent, driving, dramatic. D minor / 140 BPM. Pumping bass,
# 16th arps, harmonic-minor tension (C# over the A chord).
# ==========================================================================
def track_boss():
    s = Seq(140)
    prog = [
        (['D4', 'F4', 'A4'], 'D2'), (['Bb3', 'D4', 'F4'], 'Bb2'),
        (['C4', 'E4', 'G4'], 'C3'), (['A3', 'C#4', 'E4'], 'A2'),
        (['D4', 'F4', 'A4'], 'D2'), (['Bb3', 'D4', 'F4'], 'Bb2'),
        (['G3', 'Bb3', 'D4'], 'G2'), (['A3', 'C#4', 'E4'], 'A2'),
    ] * 2
    auto_backing(s, prog, bpb=4, pad_vel=0.72, arp_instr='pluck', arp_step=0.25,
                 arp_vel=0.36, arp_lift=1, perc='drive')
    # pumping eighth-note bass for urgency (over the half-note bass auto_backing adds)
    for bar, (chord, root) in enumerate(prog):
        b0 = bar * 4
        for k in range(8):
            s.n(b0 + k * 0.5, 0.45, root if k % 2 == 0 else shift_oct(root, 1), 'bass', 0.5)
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
    lead(s, mel, vel=0.66)
    return s

# ==========================================================================
# TRACK: Cave — dark, deep, ominous, very sparse. E minor (phrygian-ish) /
# 84 BPM. Low pad drone + deep bass + slow bell drips + a soft heartbeat kick.
# ==========================================================================
def track_cave():
    s = Seq(84)
    prog = [
        (['E3', 'G3', 'B3'], 'E2'), (['C3', 'E3', 'G3'], 'C2'),
        (['D3', 'F3', 'A3'], 'D2'), (['E3', 'G3', 'B3'], 'E2'),
        (['F3', 'A3', 'C4'], 'F2'), (['C3', 'E3', 'G3'], 'C2'),
        (['B2', 'D3', 'F3'], 'B1'), (['E3', 'G3', 'B3'], 'E2'),
    ]
    for bar, (chord, root) in enumerate(prog):
        b0 = bar * 4
        s.chord(b0, 4, chord, 'pad', vel=0.9, spread=0.24)
        s.n(b0, 4.0, root, 'bass', 0.85)             # sustained low drone
        s.p(b0, 'kick', 0.35)                         # slow heartbeat
        s.p(b0 + 2, 'kick', 0.28)
        # sparse bell drips, panned, an octave up
        s.n(b0 + 1, 1.4, shift_oct(chord[1], 1), 'bell', 0.30, pan=-0.3)
        s.n(b0 + 3, 1.4, shift_oct(chord[2], 1), 'bell', 0.26, pan=0.3)
    mel = [
        (0, 3, 'B4'), (3, 1, 'A4'), (4, 4, 'G4'),
        (8, 2, 'A4'), (10, 2, 'C5'), (12, 4, 'B4'),
        (16, 3, 'E5'), (19, 1, 'D5'), (20, 4, 'C5'),
        (24, 2, 'B4'), (26, 2, 'G4'), (28, 4, 'E4'),
    ]
    lead(s, mel, instr='soft', vel=0.5, bell_long=False)
    return s

# ==========================================================================
# TRACK: Forest — flowing, woodland wander, gentle and folk-ish. G major /
# 108 BPM. Flute-like soft lead, pentatonic motion, light steps.
# ==========================================================================
def track_forest():
    s = Seq(108)
    prog = [
        (['G3', 'B3', 'D4'], 'G2'), (['D4', 'F#4', 'A4'], 'D3'),
        (['E3', 'G3', 'B3'], 'E2'), (['C4', 'E4', 'G4'], 'C3'),
        (['G3', 'B3', 'D4'], 'G2'), (['C4', 'E4', 'G4'], 'C3'),
        (['A3', 'C4', 'E4'], 'A2'), (['D4', 'F#4', 'A4'], 'D3'),
    ] * 2
    auto_backing(s, prog, bpb=4, pad_vel=0.62, arp_instr='bell', arp_step=0.5,
                 arp_vel=0.36, arp_lift=1, perc='soft')
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
    lead(s, mel, instr='soft', vel=0.56)
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
