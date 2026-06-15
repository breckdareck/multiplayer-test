from gen_music import *   # Seq, groove, lead, offset_mel, shift_oct, to_prog, nf, ...

# ==========================================================================
# TITLE variants — the start-screen theme. ROLE: warm, welcoming, inviting,
# a touch wistful/hopeful; makes the player want to press Start. The CURRENT
# version is F major / 100 BPM, piano+strings+steel+glock. These three each
# differ in key, tempo, lead instrument, groove and mood — but all stay warm.
# ==========================================================================


# --------------------------------------------------------------------------
# title2 — "Lullaby Music-Box": tender twinkling music box over a soft glass
# pad. D major, slow 84 BPM. Wistful, intimate, like a wind-up keepsake.
# --------------------------------------------------------------------------
def track_title2():
    s = Seq(84)
    s.swing = 0.04
    prog = [
        (['D3', 'F#3', 'A3'], 'D2'), (['B2', 'D3', 'F#3'], 'B1'),
        (['G3', 'B3', 'D4'],  'G2'), (['A2', 'C#3', 'E3'], 'A1'),
        (['D3', 'F#3', 'A3'], 'D2'), (['G3', 'B3', 'D4'],  'G2'),
        (['E3', 'G3', 'B3'],  'E2'), (['A2', 'C#3', 'E3'], 'A1'),
    ]
    prog = prog + to_prog([
        {"chord": ["B2", "D3", "F#3"], "bass": "B1"},
        {"chord": ["G3", "B3", "D4"],  "bass": "G2"},
        {"chord": ["D3", "F#3", "A3"], "bass": "D2"},
        {"chord": ["A2", "C#3", "E3"], "bass": "A1"},
        {"chord": ["G3", "B3", "D4"],  "bass": "G2"},
        {"chord": ["E3", "G3", "B3"],  "bass": "E2"},
        {"chord": ["A2", "C#3", "E3"], "bass": "A1"},
        {"chord": ["D3", "F#3", "A3"], "bass": "D2"},
    ])
    groove(s, prog, bpb=4, bass='drone', comp='arp_slow', perc='heartbeat',
           pad_vel=0.6, comp_instr='glass', comp_vel=0.34, comp_lift=1,
           pad_instr='pad', pad_mode='low', pad_spread=0.22)
    # A-section: gentle rising music-box phrase, lands on long held tones.
    mel = [
        (0, 1, 'A4'), (1, 1, 'D5'), (2, 1.5, 'F#5'), (3.5, .5, 'E5'),
        (4, 1, 'D5'), (5, 1, 'B4'), (6, 2, 'D5'),
        (8, 1, 'G4'), (9, 1, 'B4'), (10, 1.5, 'D5'), (11.5, .5, 'C#5'),
        (12, 1, 'B4'), (13, 1, 'A4'), (14, 2, 'A4'),
        (16, 1, 'D5'), (17, 1, 'F#5'), (18, 1.5, 'A5'), (19.5, .5, 'G5'),
        (20, 1, 'F#5'), (21, 1, 'D5'), (22, 2, 'E5'),
        (24, 1, 'B4'), (25, 1, 'D5'), (26, 1, 'C#5'), (27, 1, 'B4'),
        (28, 1, 'A4'), (29, 1, 'B4'), (30, 2, 'D5'),
    ]
    # B-section: a softer answer, mostly mid-register, ends settled on D.
    mel = mel + offset_mel(to_mel([
        {"beat": 0, "dur": 1, "note": "F#5"}, {"beat": 1, "dur": 1, "note": "E5"},
        {"beat": 2, "dur": 2, "note": "D5"},
        {"beat": 4, "dur": 1, "note": "B4"}, {"beat": 5, "dur": 1, "note": "D5"},
        {"beat": 6, "dur": 2, "note": "A4"},
        {"beat": 8, "dur": 1, "note": "G4"}, {"beat": 9, "dur": 1, "note": "B4"},
        {"beat": 10, "dur": 1.5, "note": "D5"}, {"beat": 11.5, "dur": .5, "note": "E5"},
        {"beat": 12, "dur": 1, "note": "F#5"}, {"beat": 13, "dur": 1, "note": "E5"},
        {"beat": 14, "dur": 2, "note": "D5"},
        {"beat": 16, "dur": 1, "note": "E5"}, {"beat": 17, "dur": 1, "note": "G5"},
        {"beat": 18, "dur": 1.5, "note": "F#5"}, {"beat": 19.5, "dur": .5, "note": "E5"},
        {"beat": 20, "dur": 1, "note": "D5"}, {"beat": 21, "dur": 1, "note": "B4"},
        {"beat": 22, "dur": 2, "note": "A4"},
        {"beat": 24, "dur": 1, "note": "A4"}, {"beat": 25, "dur": 1, "note": "B4"},
        {"beat": 26, "dur": 1, "note": "C#5"}, {"beat": 27, "dur": 1, "note": "D5"},
        {"beat": 28, "dur": 1, "note": "F#5"}, {"beat": 29, "dur": 1, "note": "E5"},
        {"beat": 30, "dur": 2, "note": "D5"},
    ]), 32)
    lead(s, mel, instr='bell', vel=0.6, bell_long=False)
    return s


# --------------------------------------------------------------------------
# title3 — "Dawn Overture": a soft orchestral swell. French horn carries the
# melody over a strings pad. Bb major, broad 72 BPM. Hopeful, cinematic, the
# curtain rising on a new adventure.
# --------------------------------------------------------------------------
def track_title3():
    s = Seq(76)
    s.swing = 0.0
    prog = [
        (['Bb3', 'D4', 'F4'],  'Bb2'), (['F3', 'A3', 'C4'],  'F2'),
        (['Eb3', 'G3', 'Bb3'], 'Eb2'), (['Bb3', 'D4', 'F4'], 'Bb2'),
        (['G3', 'Bb3', 'D4'],  'G2'),  (['Eb3', 'G3', 'Bb3'], 'Eb2'),
        (['F3', 'A3', 'C4'],   'F2'),  (['Bb3', 'D4', 'F4'], 'Bb2'),
    ]
    prog = prog + to_prog([
        {"chord": ["Eb3", "G3", "Bb3"], "bass": "Eb2"},
        {"chord": ["Bb3", "D4", "F4"],  "bass": "Bb2"},
        {"chord": ["C4", "Eb4", "G4"],  "bass": "C3"},
        {"chord": ["F3", "A3", "C4"],   "bass": "F2"},
        {"chord": ["G3", "Bb3", "D4"],  "bass": "G2"},
        {"chord": ["Eb3", "G3", "Bb3"], "bass": "Eb2"},
        {"chord": ["F3", "A3", "C4"],   "bass": "F2"},
        {"chord": ["Bb3", "D4", "F4"],  "bass": "Bb2"},
    ])
    groove(s, prog, bpb=4, bass='toll', comp='roll', perc='none',
           pad_vel=0.85, comp_instr='soft', comp_vel=0.3, comp_lift=0,
           pad_instr='pad', pad_mode='swell', pad_spread=0.24)
    # Long, singing horn lines — broad note values, gentle arc upward then home.
    mel = [
        (0, 2, 'F4'), (2, 2, 'Bb4'),
        (4, 1.5, 'C5'), (5.5, .5, 'Bb4'), (6, 2, 'D5'),
        (8, 2, 'Bb4'), (10, 1, 'C5'), (11, 1, 'D5'),
        (12, 3, 'Eb5'), (15, 1, 'D5'),
        (16, 2, 'D5'), (18, 1, 'C5'), (19, 1, 'Bb4'),
        (20, 2, 'C5'), (22, 2, 'A4'),
        (24, 1, 'Bb4'), (25, 1, 'D5'), (26, 2, 'F5'),
        (28, 1.5, 'D5'), (29.5, .5, 'C5'), (30, 2, 'Bb4'),
    ]
    mel = mel + offset_mel(to_mel([
        {"beat": 0, "dur": 2, "note": "G4"}, {"beat": 2, "dur": 2, "note": "Eb5"},
        {"beat": 4, "dur": 1.5, "note": "D5"}, {"beat": 5.5, "dur": .5, "note": "C5"},
        {"beat": 6, "dur": 2, "note": "Bb4"},
        {"beat": 8, "dur": 2, "note": "C5"}, {"beat": 10, "dur": 1, "note": "D5"},
        {"beat": 11, "dur": 1, "note": "Eb5"},
        {"beat": 12, "dur": 3, "note": "F5"}, {"beat": 15, "dur": 1, "note": "Eb5"},
        {"beat": 16, "dur": 2, "note": "D5"}, {"beat": 18, "dur": 2, "note": "G4"},
        {"beat": 20, "dur": 1.5, "note": "Bb4"}, {"beat": 21.5, "dur": .5, "note": "C5"},
        {"beat": 22, "dur": 2, "note": "A4"},
        {"beat": 24, "dur": 1, "note": "Bb4"}, {"beat": 25, "dur": 1, "note": "C5"},
        {"beat": 26, "dur": 1, "note": "D5"}, {"beat": 27, "dur": 1, "note": "C5"},
        {"beat": 28, "dur": 2, "note": "Bb4"}, {"beat": 30, "dur": 2, "note": "F4"},
    ]), 32)
    lead(s, mel, instr='lead', vel=0.66, bell_long=False)
    return s


# --------------------------------------------------------------------------
# title4 — "Nylon Morning": a gentle acoustic folk piece. Warm nylon guitar
# melody, fingerpicked feel, light shaker. A major, easygoing 96 BPM. Cozy,
# personal, sun-through-the-window inviting.
# --------------------------------------------------------------------------
def track_title4():
    s = Seq(96)
    s.swing = 0.08
    prog = [
        (['A3', 'C#4', 'E4'], 'A2'), (['E3', 'G#3', 'B3'], 'E2'),
        (['F#3', 'A3', 'C#4'], 'F#2'), (['D3', 'F#3', 'A3'], 'D2'),
        (['A3', 'C#4', 'E4'], 'A2'), (['D3', 'F#3', 'A3'], 'D2'),
        (['E3', 'G#3', 'B3'], 'E2'), (['A3', 'C#4', 'E4'], 'A2'),
    ]
    prog = prog + to_prog([
        {"chord": ["F#3", "A3", "C#4"], "bass": "F#2"},
        {"chord": ["D3", "F#3", "A3"],  "bass": "D2"},
        {"chord": ["E3", "G#3", "B3"],  "bass": "E2"},
        {"chord": ["C#3", "E3", "G#3"], "bass": "C#2"},
        {"chord": ["D3", "F#3", "A3"],  "bass": "D2"},
        {"chord": ["E3", "G#3", "B3"],  "bass": "E2"},
        {"chord": ["F#3", "A3", "C#4"], "bass": "F#2"},
        {"chord": ["E3", "G#3", "B3"],  "bass": "E2"},
    ])
    groove(s, prog, bpb=4, bass='walk', comp='broken', perc='shaker',
           pad_vel=0.5, comp_instr='pluck', comp_vel=0.5, comp_lift=1,
           pad=True, pad_instr='pad', pad_mode='low', pad_spread=0.18)
    # Lilting, dance-like guitar tune — stepwise with little turns, sits mid-range.
    mel = [
        (0, 1, 'E5'), (1, 1, 'C#5'), (2, 1, 'A4'), (3, 1, 'B4'),
        (4, 1, 'C#5'), (5, 1, 'B4'), (6, 2, 'A4'),
        (8, 1, 'C#5'), (9, 1, 'E5'), (10, 1, 'F#5'), (11, 1, 'E5'),
        (12, 1, 'D5'), (13, 1, 'C#5'), (14, 2, 'D5'),
        (16, 1, 'E5'), (17, 1, 'C#5'), (18, 1, 'A4'), (19, 1, 'C#5'),
        (20, 1, 'B4'), (21, 1, 'G#4'), (22, 2, 'E4'),
        (24, 1, 'A4'), (25, 1, 'B4'), (26, 1, 'C#5'), (27, 1, 'E5'),
        (28, 1, 'D5'), (29, 1, 'C#5'), (30, 2, 'A4'),
    ]
    mel = mel + offset_mel(to_mel([
        {"beat": 0, "dur": 1, "note": "F#5"}, {"beat": 1, "dur": 1, "note": "E5"},
        {"beat": 2, "dur": 1, "note": "C#5"}, {"beat": 3, "dur": 1, "note": "D5"},
        {"beat": 4, "dur": 1, "note": "E5"}, {"beat": 5, "dur": 1, "note": "D5"},
        {"beat": 6, "dur": 2, "note": "C#5"},
        {"beat": 8, "dur": 1, "note": "B4"}, {"beat": 9, "dur": 1, "note": "D5"},
        {"beat": 10, "dur": 1, "note": "F#5"}, {"beat": 11, "dur": 1, "note": "E5"},
        {"beat": 12, "dur": 1, "note": "B4"}, {"beat": 13, "dur": 1, "note": "C#5"},
        {"beat": 14, "dur": 2, "note": "G#4"},
        {"beat": 16, "dur": 1, "note": "A4"}, {"beat": 17, "dur": 1, "note": "C#5"},
        {"beat": 18, "dur": 1, "note": "E5"}, {"beat": 19, "dur": 1, "note": "D5"},
        {"beat": 20, "dur": 1, "note": "C#5"}, {"beat": 21, "dur": 1, "note": "B4"},
        {"beat": 22, "dur": 2, "note": "A4"},
        {"beat": 24, "dur": 1, "note": "G#4"}, {"beat": 25, "dur": 1, "note": "B4"},
        {"beat": 26, "dur": 1, "note": "D5"}, {"beat": 27, "dur": 1, "note": "C#5"},
        {"beat": 28, "dur": 1, "note": "B4"}, {"beat": 29, "dur": 1, "note": "G#4"},
        {"beat": 30, "dur": 2, "note": "A4"},
    ]), 32)
    lead(s, mel, instr='soft', vel=0.64, bell_long=False)
    return s


META = {
    'title2': {
        'name': 'Lullaby Music-Box',
        'track_gm': {'lead': 10, 'bell': 10, 'glass': 11, 'pad': 89, 'bass': 46},
        'reverb': [0.6, 0.25, 0.95, 0.6], 'gain': 0.72,
        'blurb': 'tender wind-up music box over a soft pad — wistful and intimate',
    },
    'title3': {
        'name': 'Dawn Overture',
        'track_gm': {'lead': 60, 'soft': 48, 'pad': 48, 'bass': 43},
        'reverb': [0.6, 0.25, 0.95, 0.6], 'gain': 0.8,
        'blurb': 'hopeful French-horn melody over a swelling strings pad — cinematic sunrise',
    },
    'title4': {
        'name': 'Nylon Morning',
        'track_gm': {'lead': 24, 'soft': 24, 'pluck': 24, 'pad': 89, 'bass': 32},
        'reverb': [0.4, 0.35, 0.85, 0.45], 'gain': 0.78,
        'blurb': 'gentle fingerpicked nylon-guitar folk — cozy, sun-through-the-window warm',
    },
}
