from gen_music import *   # Seq, groove, lead, offset_mel, shift_oct, to_prog, nf, ...

# ==========================================================================
# CAVE variants — dark, ominous, oppressive, deep. All three must stay quiet,
# eerie, very OPEN/spacious, with FEW notes and almost NO steady rhythm. Long
# lonely tones, lots of empty air, a deep sense of dread. No catchy arpeggio.
# Each differs from the others AND from the current version (E phrygian / 80 /
# darkpad + subdrone + glass glints + hollow lead). All cavernous-reverb.
# ==========================================================================


# --------------------------------------------------------------------------
# cave2 — DRIPPING, CRYSTALLINE + EERIE.
# D phrygian, 76 BPM. A near-still darkpad drone with rare cold Crystal/glass
# "drips" falling far apart, and a few faint glass glints. Almost no melody —
# the space between drips IS the piece. Crystal voice = GM Crystal (98).
# --------------------------------------------------------------------------
def track_cave2():
    s = Seq(76)
    s.swing = 0.0
    # D phrygian: D Eb F G A Bb C. Held triads kept low + open (oct 2-3).
    prog = [
        (['D3', 'F3', 'A3'], 'D2'), (['Eb3', 'G3', 'Bb3'], 'Eb2'),
        (['D3', 'F3', 'A3'], 'D2'), (['Bb2', 'D3', 'F3'], 'Bb1'),
        (['D3', 'F3', 'A3'], 'D2'), (['C3', 'Eb3', 'G3'], 'C2'),
        (['Bb2', 'D3', 'F3'], 'Bb1'), (['D3', 'F3', 'A3'], 'D2'),
    ] * 2
    groove(s, prog, bpb=4, bass='drone', comp='none', perc='none',
           pad=True, pad_mode='low', pad_vel=0.30, pad_instr='darkpad', pad_spread=0.12)
    n = len(prog) * 4  # 64 beats
    # sub-bass octave under each bar — the cavern floor, very quiet
    for _b, (_ch, _rt) in enumerate(prog):
        s.n(_b * 4, 4.0, shift_oct(_rt, -1), 'bass', 0.22)
    # rare cold CRYSTAL drips — single notes falling far apart, never a run.
    # high but brief + low velocity so they read as glints, not melody.
    for (_b, _nt, _v, _p) in [
        (2.5, 'A5', 0.16, -0.30), (11, 'D6', 0.13, 0.32), (18.5, 'F5', 0.15, 0.18),
        (27, 'Bb5', 0.12, -0.28), (34.5, 'A5', 0.15, 0.30), (43, 'C6', 0.13, -0.20),
        (50.5, 'D6', 0.12, 0.26), (59, 'F5', 0.14, -0.24),
    ]:
        s.n(_b, 2.2, _nt, 'glass', _v, pan=_p)
    # a couple of even-rarer deeper Crystal tones to ground the glints
    for (_b, _nt, _v, _p) in [(6, 'A4', 0.18, 0.0), (38, 'F4', 0.17, 0.0)]:
        s.n(_b, 3.0, _nt, 'bell', _v, pan=_p)
    # a sparse, very long, low eerie thread — only a handful of notes, lots of air
    mel = [
        (4, 6, 'A4'),
        (20, 7, 'F4'),
        (36, 5, 'Eb4'),
        (52, 8, 'D4'),
    ]
    lead(s, mel, instr='hollow', vel=0.34, bell_long=False)
    return s


# --------------------------------------------------------------------------
# cave3 — DEEP RUMBLING DREAD.
# C phrygian, 64 BPM (slowest, lowest). Sub-bass + low sweep darkpad heavy and
# near-subliminal; only a few low, long tones float up. A rare soft tom boom
# every several bars marks the abyss. The darkest of the three.
# --------------------------------------------------------------------------
def track_cave3():
    s = Seq(64)
    s.swing = 0.0
    # C phrygian: C Db Eb F G Ab Bb. Triads dropped LOW (oct 2) for weight.
    prog = [
        (['C3', 'Eb3', 'G3'], 'C2'), (['Db3', 'F3', 'Ab3'], 'Db2'),
        (['C3', 'Eb3', 'G3'], 'C2'), (['Ab2', 'C3', 'Eb3'], 'Ab1'),
        (['C3', 'Eb3', 'G3'], 'C2'), (['Bb2', 'D3', 'F3'], 'Bb1'),
        (['Ab2', 'C3', 'Eb3'], 'Ab1'), (['C3', 'Eb3', 'G3'], 'C2'),
    ] * 2
    groove(s, prog, bpb=4, bass='drone', comp='none', perc='none',
           pad=True, pad_mode='low', pad_vel=0.34, pad_instr='darkpad', pad_spread=0.10)
    n = len(prog) * 4  # 64 beats
    # deep tonic sweep pedal — the underground rumble, held across each bar
    for _pb in range(0, n, 4):
        s.n(_pb, 4.4, 'C1', 'subdrone', 0.52)
    # sub-bass two octaves under each bar root — near-subliminal floor
    for _b, (_ch, _rt) in enumerate(prog):
        s.n(_b * 4, 4.0, shift_oct(_rt, -1), 'bass', 0.30)
    # a VERY few low, long tones rising out of the murk — fewer than the others
    mel = [
        (5, 7, 'Eb4'),
        (22, 8, 'C4'),
        (40, 6, 'Ab3'),
        (54, 9, 'G3'),
    ]
    lead(s, mel, instr='darkpad', vel=0.30, bell_long=False)
    # one cold, distant glint per half-loop so it isn't fully featureless
    for (_b, _nt, _v, _p) in [(14, 'G4', 0.12, -0.3), (46, 'Eb4', 0.12, 0.3)]:
        s.n(_b, 3.0, _nt, 'glass', _v, pan=_p)
    # rare soft tom boom — the abyss answering, every 4 bars (8s) only
    for _bm in range(0, n, 16):
        s.p(_bm, 'tom', 0.42)
    return s


# --------------------------------------------------------------------------
# cave4 — COLD HOLLOW WIND.
# A phrygian, 72 BPM. A breathy ocarina/pan-flute drifts long, lonely notes over
# an open drone — wind moving through empty stone. More melody than the others
# but still slow + very spread out, with big silences between phrases.
# --------------------------------------------------------------------------
def track_cave4():
    s = Seq(72)
    s.swing = 0.0
    # A phrygian: A Bb C D E F G. Open low triads (oct 2-3).
    prog = [
        (['A2', 'C3', 'E3'], 'A1'), (['Bb2', 'D3', 'F3'], 'Bb1'),
        (['A2', 'C3', 'E3'], 'A1'), (['F2', 'A2', 'C3'], 'F1'),
        (['A2', 'C3', 'E3'], 'A1'), (['G2', 'Bb2', 'D3'], 'G1'),
        (['F2', 'A2', 'C3'], 'F1'), (['E3', 'G3', 'B3'], 'E2'),
    ] * 2
    groove(s, prog, bpb=4, bass='drone', comp='none', perc='none',
           pad=True, pad_mode='low', pad_vel=0.30, pad_instr='darkpad', pad_spread=0.14)
    n = len(prog) * 4  # 64 beats
    # sub-bass octave under each bar — soft cavern floor
    for _b, (_ch, _rt) in enumerate(prog):
        s.n(_b * 4, 4.0, shift_oct(_rt, -1), 'bass', 0.22)
    # the wind: long, drifting ocarina/pan-flute phrases, slow + spread out.
    # Phrase A (bars 1-4 region), then big air, then Phrase B; reuse later.
    windA = [
        (2, 5, 'E5'),
        (9, 4, 'C5'),
        (15, 6, 'A4'),
    ]
    windB = [
        (2, 5, 'F5'),
        (10, 4, 'E5'),
        (16, 6, 'D5'),
    ]
    mel = windA + offset_mel(windB, 16) + offset_mel(windA, 32) + offset_mel(windB, 48)
    lead(s, mel, instr='hollow', vel=0.40, bell_long=False)
    # one faint high gust glint per half-loop — far apart, breathy not shrill
    for (_b, _nt, _v, _p) in [(23, 'A4', 0.12, 0.3), (55, 'E4', 0.12, -0.3)]:
        s.n(_b, 3.5, _nt, 'glass', _v, pan=_p)
    return s


META = {
    'cave2': {'name': 'Cave — Crystal Drip',
              'track_gm': {'darkpad': 89, 'bass': 39, 'glass': 98, 'bell': 98, 'hollow': 79},
              'reverb': [0.95, 0.12, 1.0, 0.92], 'gain': 0.66,
              'blurb': 'rare cold crystal drips falling through still black air'},
    'cave3': {'name': 'Cave — Abyssal Dread',
              'track_gm': {'darkpad': 89, 'subdrone': 95, 'bass': 39, 'glass': 98},
              'reverb': [0.95, 0.10, 1.0, 0.95], 'gain': 0.62,
              'blurb': 'near-subliminal sub-rumble with a few low tones and a distant boom'},
    'cave4': {'name': 'Cave — Hollow Wind',
              'track_gm': {'darkpad': 89, 'bass': 39, 'hollow': 79, 'glass': 98},
              'reverb': [0.95, 0.12, 1.0, 0.90], 'gain': 0.68,
              'blurb': 'a cold ocarina drifting long lonely tones through empty stone'},
}
