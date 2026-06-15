"""Alternate variants for the MAIN MENU (character-select) track.

ROLE: low, mellow, unobtrusive wallpaper music that plays under the menu for a
long time. It must NOT be busy, loud, dramatic, or churchy. Calm, gentle,
spacious, easy to ignore.

Current/shipped version (for contrast — these are deliberately DIFFERENT):
    G major, 88 BPM, vibraphone + warm pad + harp.

Three variants, all kept low-energy and soft, differing in key / tempo / timbre:
  mainmenu2 — soft electric-piano (Rhodes-ish) over a warm pad. D major, 80 BPM.
  mainmenu3 — warm pad + soft flute, very slow and airy. Eb major, 72 BPM.
  mainmenu4 — gentle nylon guitar, sparse notes. A major, 92 BPM.
"""
from gen_music import *   # Seq, groove, lead, offset_mel, shift_oct, to_prog, to_mel, nf, ...


# ==========================================================================
# mainmenu2 — "Amber Keys": a soft Rhodes-ish electric piano (Vibraphone GM)
# laying down lazy broken chords over a warm pad, with a few harp-bell glints.
# D major, 80 BPM. Rounded, cozy, never busy.
# ==========================================================================
def track_mainmenu2():
    s = Seq(80)
    s.swing = 0.06   # a touch of lazy shuffle in the e-piano figures
    prog = [
        (['D4', 'F#4', 'A4'], 'D2'), (['B3', 'D4', 'F#4'], 'B2'),
        (['G3', 'B3', 'D4'],  'G2'), (['A3', 'C#4', 'E4'], 'A2'),
        (['F#3', 'A3', 'C#4'], 'F#2'), (['B3', 'D4', 'F#4'], 'B2'),
        (['E3', 'G3', 'B3'],  'E2'), (['A3', 'C#4', 'E4'], 'A2'),
        (['D4', 'F#4', 'A4'], 'D2'), (['G3', 'B3', 'D4'],  'G2'),
        (['A3', 'C#4', 'E4'], 'A2'), (['D4', 'F#4', 'A4'], 'D2'),
    ]
    # soft, slow broken-chord e-piano comp over a low held pad + simple drone bass
    groove(s, prog, bpb=4, bass='drone', comp='broken', perc='heartbeat',
           pad_vel=0.55, pad_instr='pad', pad_mode='low', pad_spread=0.18,
           comp_instr='soft', comp_vel=0.34, comp_lift=0)
    # melody — gentle, sits in oct 4-5, lots of air between phrases
    mel = [
        (0, 2, 'A4'), (2, 1.5, 'D5'), (3.5, .5, 'C#5'), (4, 2, 'B4'), (6, 2, 'A4'),
        (8, 2, 'B4'), (10, 1, 'A4'), (11, 1, 'G4'), (12, 3, 'A4'), (15, 1, 'F#4'),
        (16, 2, 'A4'), (18, 1, 'C#5'), (19, 1, 'D5'), (20, 2, 'E5'), (22, 2, 'C#5'),
        (24, 2, 'B4'), (26, 1, 'A4'), (27, 1, 'B4'), (28, 4, 'A4'),
        (32, 2, 'D5'), (34, 1.5, 'F#5'), (35.5, .5, 'E5'), (36, 2, 'D5'), (38, 2, 'B4'),
        (40, 2, 'A4'), (42, 1, 'B4'), (43, 1, 'C#5'), (44, 3, 'D5'), (47, 1, 'B4'),
    ]
    mel = mel + offset_mel(to_mel([
        {"beat": 0, "dur": 1.5, "note": "F#4"}, {"beat": 1.5, "dur": 0.5, "note": "A4"},
        {"beat": 2, "dur": 2, "note": "B4"}, {"beat": 4, "dur": 1, "note": "A4"},
        {"beat": 5, "dur": 1, "note": "G4"}, {"beat": 6, "dur": 2, "note": "E4"},
        {"beat": 8, "dur": 2, "note": "G4"}, {"beat": 10, "dur": 1, "note": "A4"},
        {"beat": 11, "dur": 1, "note": "B4"}, {"beat": 12, "dur": 3, "note": "D5"},
        {"beat": 15, "dur": 1, "note": "C#5"},
        {"beat": 16, "dur": 2, "note": "B4"}, {"beat": 18, "dur": 1, "note": "A4"},
        {"beat": 19, "dur": 1, "note": "F#4"}, {"beat": 20, "dur": 4, "note": "D4"},
    ]), 48)
    lead(s, mel, instr='soft', vel=0.5, bell_long=False)
    return s


# ==========================================================================
# mainmenu3 — "Distant Light": just a warm pad + a soft flute drifting over it,
# very slow and airy. No comp, no real percussion. Eb major, 72 BPM. The most
# spacious / ambient of the three — almost no rhythmic motion.
# ==========================================================================
def track_mainmenu3():
    s = Seq(72)
    prog = [
        (['Eb3', 'G3', 'Bb3'], 'Eb2'), (['C3', 'Eb3', 'G3'], 'C2'),
        (['Ab3', 'C4', 'Eb4'], 'Ab2'), (['Bb3', 'D4', 'F4'], 'Bb2'),
        (['Eb3', 'G3', 'Bb3'], 'Eb2'), (['Ab3', 'C4', 'Eb4'], 'Ab2'),
        (['F3', 'Ab3', 'C4'],  'F2'),  (['Bb3', 'D4', 'F4'], 'Bb2'),
        (['G3', 'Bb3', 'Eb4'], 'Eb2'), (['C3', 'Eb3', 'G3'], 'C2'),
        (['Ab3', 'C4', 'Eb4'], 'Ab2'), (['Bb3', 'D4', 'F4'], 'Bb2'),
    ]
    # swelling pad + a low drone bass only — the flute carries everything else
    groove(s, prog, bpb=4, bass='drone', comp='none', perc='none',
           pad_vel=0.6, pad_instr='pad', pad_mode='swell', pad_spread=0.22,
           bass_vel=0.6)
    # long, breathy flute lines with plenty of rest — never hurried
    mel = [
        (0, 3, 'Bb4'), (3, 1, 'G4'), (4, 4, 'Eb4'),
        (8, 2, 'G4'), (10, 2, 'C5'), (12, 3, 'Bb4'), (15, 1, 'Ab4'),
        (16, 4, 'Bb4'), (20, 2, 'D5'), (22, 2, 'C5'),
        (24, 3, 'Ab4'), (27, 1, 'G4'), (28, 4, 'F4'),
        (32, 2, 'Eb5'), (34, 2, 'Bb4'), (36, 4, 'C5'),
        (40, 2, 'Ab4'), (42, 2, 'Bb4'), (44, 3, 'G4'), (47, 1, 'F4'),
    ]
    mel = mel + offset_mel(to_mel([
        {"beat": 0, "dur": 4, "note": "Eb5"}, {"beat": 4, "dur": 2, "note": "C5"},
        {"beat": 6, "dur": 2, "note": "Bb4"},
        {"beat": 8, "dur": 3, "note": "G4"}, {"beat": 11, "dur": 1, "note": "Ab4"},
        {"beat": 12, "dur": 4, "note": "Bb4"},
        {"beat": 16, "dur": 2, "note": "C5"}, {"beat": 18, "dur": 2, "note": "Bb4"},
        {"beat": 20, "dur": 4, "note": "G4"},
        {"beat": 24, "dur": 3, "note": "F4"}, {"beat": 27, "dur": 1, "note": "G4"},
        {"beat": 28, "dur": 4, "note": "Eb4"},
    ]), 48)
    lead(s, mel, instr='hollow', vel=0.5, bell_long=False)
    return s


# ==========================================================================
# mainmenu4 — "Nylon Hush": a gentle fingerpicked nylon guitar with sparse,
# unhurried notes over a soft pad. A major, 92 BPM. Intimate and warm —
# slightly more pulse than mainmenu3 but still calm.
# ==========================================================================
def track_mainmenu4():
    s = Seq(92)
    s.swing = 0.05
    prog = [
        (['A3', 'C#4', 'E4'], 'A2'), (['F#3', 'A3', 'C#4'], 'F#2'),
        (['D4', 'F#4', 'A4'], 'D3'), (['E4', 'G#4', 'B4'], 'E3'),
        (['A3', 'C#4', 'E4'], 'A2'), (['D4', 'F#4', 'A4'], 'D3'),
        (['B3', 'D4', 'F#4'], 'B2'), (['E4', 'G#4', 'B4'], 'E3'),
        (['F#3', 'A3', 'C#4'], 'F#2'), (['D4', 'F#4', 'A4'], 'D3'),
        (['E4', 'G#4', 'B4'], 'E3'), (['A3', 'C#4', 'E4'], 'A2'),
    ]
    # soft broken-chord nylon comp (sparse) + held low pad + a quiet heartbeat pulse
    groove(s, prog, bpb=4, bass='half', comp='broken', perc='soft',
           pad_vel=0.42, pad_instr='pad', pad_mode='low', pad_spread=0.16,
           comp_instr='pluck', comp_vel=0.3, comp_lift=0, bass_vel=0.6)
    # sparse, lyrical guitar melody — leaves space, oct 4-5
    mel = [
        (0, 2, 'E5'), (2, 1, 'C#5'), (3, 1, 'B4'), (4, 3, 'A4'), (7, 1, 'C#5'),
        (8, 2, 'D5'), (10, 1, 'E5'), (11, 1, 'F#5'), (12, 3, 'E5'), (15, 1, 'C#5'),
        (16, 2, 'A4'), (18, 1, 'B4'), (19, 1, 'C#5'), (20, 2, 'E5'), (22, 2, 'D5'),
        (24, 2, 'C#5'), (26, 1, 'B4'), (27, 1, 'A4'), (28, 4, 'B4'),
        (32, 2, 'A4'), (34, 1, 'C#5'), (35, 1, 'E5'), (36, 3, 'F#5'), (39, 1, 'E5'),
        (40, 2, 'D5'), (42, 1, 'B4'), (43, 1, 'C#5'), (44, 3, 'A4'), (47, 1, 'E4'),
    ]
    mel = mel + offset_mel(to_mel([
        {"beat": 0, "dur": 1.5, "note": "C#5"}, {"beat": 1.5, "dur": 0.5, "note": "E5"},
        {"beat": 2, "dur": 2, "note": "A4"}, {"beat": 4, "dur": 1, "note": "B4"},
        {"beat": 5, "dur": 1, "note": "C#5"}, {"beat": 6, "dur": 2, "note": "F#4"},
        {"beat": 8, "dur": 2, "note": "D5"}, {"beat": 10, "dur": 1, "note": "C#5"},
        {"beat": 11, "dur": 1, "note": "B4"}, {"beat": 12, "dur": 3, "note": "A4"},
        {"beat": 15, "dur": 1, "note": "G#4"},
        {"beat": 16, "dur": 2, "note": "B4"}, {"beat": 18, "dur": 1, "note": "C#5"},
        {"beat": 19, "dur": 1, "note": "D5"}, {"beat": 20, "dur": 4, "note": "E5"},
        {"beat": 24, "dur": 2, "note": "C#5"}, {"beat": 26, "dur": 1, "note": "B4"},
        {"beat": 27, "dur": 1, "note": "G#4"}, {"beat": 28, "dur": 4, "note": "A4"},
    ]), 48)
    lead(s, mel, instr='pluck', vel=0.5, bell_long=False)
    return s


META = {
    'mainmenu2': {
        'name': 'Amber Keys',
        'track_gm': {'lead': 11, 'soft': 11, 'pad': 89, 'bass': 33, 'pluck': 24, 'bell': 46},
        'reverb': [0.5, 0.35, 0.9, 0.45], 'gain': 0.72,
        'blurb': 'soft Rhodes-ish e-piano drifting over a warm pad, cozy and rounded',
    },
    'mainmenu3': {
        'name': 'Distant Light',
        'track_gm': {'lead': 73, 'hollow': 73, 'pad': 89, 'bass': 32},
        'reverb': [0.6, 0.25, 0.95, 0.6], 'gain': 0.68,
        'blurb': 'a soft flute drifting over a warm pad, very slow and airy',
    },
    'mainmenu4': {
        'name': 'Nylon Hush',
        'track_gm': {'lead': 24, 'pluck': 24, 'pad': 89, 'bass': 32, 'bell': 46},
        'reverb': [0.45, 0.35, 0.85, 0.45], 'gain': 0.7,
        'blurb': 'gentle fingerpicked nylon guitar with sparse notes, intimate and warm',
    },
}
