from gen_music import *   # Seq, groove, lead, offset_mel, shift_oct, to_prog, to_mel, nf, ...

# ==========================================================================
# FIELD — alternate variants of the overworld / travel loop.
# Current version (for contrast): D major, 118 BPM, french-horn lead + brass
# stabs + pizzicato + backbeat. All three below stay adventurous/travel but
# pull in different directions: pastoral / heroic / playful.
# ==========================================================================


# --------------------------------------------------------------------------
# field2 — "Open Road": pastoral recorder wander. G major, 106 BPM.
# Light & folksy: recorder lead over nylon-guitar broken comp + harp pad,
# loping half bass, soft shaker. Breezy, unhurried, friendly.
# --------------------------------------------------------------------------
def track_field2():
    s = Seq(106)
    s.swing = 0.10
    prog = [
        (['G3', 'B3', 'D4'],  'G2'), (['C4', 'E4', 'G4'],  'C3'),
        (['D4', 'F#4', 'A4'], 'D3'), (['G3', 'B3', 'D4'],  'G2'),
        (['E3', 'G3', 'B3'],  'E2'), (['C4', 'E4', 'G4'],  'C3'),
        (['A3', 'C4', 'E4'],  'A2'), (['D4', 'F#4', 'A4'], 'D3'),
    ] * 2
    prog = prog + to_prog([
        {"chord": ["C4", "E4", "G4"], "bass": "C3"}, {"chord": ["G3", "B3", "D4"], "bass": "G2"},
        {"chord": ["A3", "C4", "E4"], "bass": "A2"}, {"chord": ["D4", "F#4", "A4"], "bass": "D3"},
        {"chord": ["E3", "G3", "B3"], "bass": "E2"}, {"chord": ["C4", "E4", "G4"], "bass": "C3"},
        {"chord": ["D4", "F#4", "A4"], "bass": "D3"}, {"chord": ["G3", "B3", "D4"], "bass": "G2"},
    ])
    groove(s, prog, bpb=4, bass='half', comp='broken', perc='shaker',
           pad_vel=0.6, comp_instr='pluck', comp_vel=0.4, comp_lift=0,
           pad_instr='pad', pad_mode='low')
    mel = [
        (0, 1, 'G4'), (1, 1, 'B4'), (2, 1, 'D5'), (3, 1, 'B4'),
        (4, 1, 'C5'), (5, 1, 'E5'), (6, 2, 'D5'),
        (8, 1, 'B4'), (9, .5, 'C5'), (9.5, .5, 'D5'), (10, 1, 'E5'), (11, 1, 'D5'),
        (12, 1, 'B4'), (13, 1, 'A4'), (14, 2, 'G4'),
        (16, 1, 'E5'), (17, 1, 'D5'), (18, 1, 'B4'), (19, 1, 'G4'),
        (20, 1, 'A4'), (21, 1, 'C5'), (22, 2, 'E5'),
        (24, 1, 'D5'), (25, .5, 'C5'), (25.5, .5, 'B4'), (26, 1, 'A4'), (27, 1, 'B4'),
        (28, 1, 'D5'), (29, 1, 'C5'), (30, 2, 'B4'),
    ]
    mel = mel + offset_mel(to_mel([
        {"beat": 0, "dur": 1, "note": "D5"}, {"beat": 1, "dur": 1, "note": "B4"},
        {"beat": 2, "dur": 1, "note": "G5"}, {"beat": 3, "dur": 1, "note": "E5"},
        {"beat": 4, "dur": 1.5, "note": "D5"}, {"beat": 5.5, "dur": 0.5, "note": "B4"},
        {"beat": 6, "dur": 2, "note": "C5"},
        {"beat": 8, "dur": 1, "note": "E5"}, {"beat": 9, "dur": 1, "note": "G5"},
        {"beat": 10, "dur": 1, "note": "F#5"}, {"beat": 11, "dur": 1, "note": "D5"},
        {"beat": 12, "dur": 1, "note": "B4"}, {"beat": 13, "dur": 1, "note": "C5"},
        {"beat": 14, "dur": 2, "note": "A4"},
        {"beat": 16, "dur": 1, "note": "G4"}, {"beat": 17, "dur": 1, "note": "B4"},
        {"beat": 18, "dur": 1, "note": "C5"}, {"beat": 19, "dur": 1, "note": "E5"},
        {"beat": 20, "dur": 1.5, "note": "D5"}, {"beat": 21.5, "dur": 0.5, "note": "C5"},
        {"beat": 22, "dur": 2, "note": "B4"},
        {"beat": 24, "dur": 1, "note": "A4"}, {"beat": 25, "dur": 1, "note": "C5"},
        {"beat": 26, "dur": 1, "note": "E5"}, {"beat": 27, "dur": 1, "note": "D5"},
        {"beat": 28, "dur": 1, "note": "B4"}, {"beat": 29, "dur": 1, "note": "A4"},
        {"beat": 30, "dur": 2, "note": "G4"},
    ]), 32)
    lead(s, mel, instr='hollow', vel=0.6, bell_long=False)
    return s


# --------------------------------------------------------------------------
# field3 — "Banner & Road": heroic brass + strings march. Bb major, 120 BPM.
# Bigger, prouder: brass-section lead, strings pad, a walking bass that pushes
# forward, full drive drums. The "setting out, chin up" version.
# --------------------------------------------------------------------------
def track_field3():
    s = Seq(120)
    s.swing = 0.0
    prog = [
        (['Bb3', 'D4', 'F4'],  'Bb2'), (['F3', 'A3', 'C4'],  'F2'),
        (['G3', 'Bb3', 'D4'],  'G2'),  (['Eb4', 'G4', 'Bb4'], 'Eb3'),
        (['Bb3', 'D4', 'F4'],  'Bb2'), (['F3', 'A3', 'C4'],  'F2'),
        (['Eb4', 'G4', 'Bb4'], 'Eb3'), (['F3', 'A3', 'C4'],  'F2'),
    ] * 2
    prog = prog + to_prog([
        {"chord": ["G3", "Bb3", "D4"], "bass": "G2"}, {"chord": ["Eb4", "G4", "Bb4"], "bass": "Eb3"},
        {"chord": ["Bb3", "D4", "F4"], "bass": "Bb2"}, {"chord": ["F3", "A3", "C4"], "bass": "F2"},
        {"chord": ["C4", "Eb4", "G4"], "bass": "C3"}, {"chord": ["F3", "A3", "C4"], "bass": "F2"},
        {"chord": ["G3", "Bb3", "D4"], "bass": "G2"}, {"chord": ["F3", "A3", "C4"], "bass": "F2"},
        {"chord": ["Eb4", "G4", "Bb4"], "bass": "Eb3"}, {"chord": ["Bb3", "D4", "F4"], "bass": "Bb2"},
        {"chord": ["F3", "A3", "C4"], "bass": "F2"}, {"chord": ["Bb3", "D4", "F4", "A4"], "bass": "Bb2"},
    ])
    groove(s, prog, bpb=4, bass='walk', comp='stab', perc='drive',
           pad_vel=0.66, comp_instr='soft', comp_vel=0.4, comp_lift=0,
           pad_instr='pad', pad_mode='half')
    mel = [
        (0, 1, 'Bb4'), (1, 1, 'D5'), (2, 1.5, 'F5'), (3.5, .5, 'D5'),
        (4, 1, 'C5'), (5, 1, 'A4'), (6, 2, 'F4'),
        (8, 1, 'D5'), (9, 1, 'F5'), (10, 1.5, 'G5'), (11.5, .5, 'F5'),
        (12, 1, 'Eb5'), (13, 1, 'D5'), (14, 2, 'Bb4'),
        (16, 1, 'F5'), (17, 1, 'D5'), (18, 1, 'Bb4'), (19, 1, 'D5'),
        (20, 1, 'C5'), (21, 1, 'Eb5'), (22, 2, 'D5'),
        (24, 1, 'C5'), (25, 1, 'A4'), (26, 1, 'F4'), (27, 1, 'A4'),
        (28, 1, 'C5'), (29, 1, 'D5'), (30, 2, 'C5'),
        (32, 1, 'Bb4'), (33, 1, 'D5'), (34, 1, 'F5'), (35, 1, 'Bb5'),
        (36, 1.5, 'A5'), (37.5, .5, 'F5'), (38, 2, 'G5'),
        (40, 1, 'F5'), (41, 1, 'D5'), (42, 1, 'Eb5'), (43, 1, 'G5'),
        (44, 1, 'F5'), (45, 1, 'D5'), (46, 2, 'Bb4'),
        (48, 1, 'D5'), (49, 1, 'F5'), (50, 1.5, 'Bb5'), (51.5, .5, 'A5'),
        (52, 1, 'G5'), (53, 1, 'F5'), (54, 2, 'D5'),
        (56, 1, 'Eb5'), (57, 1, 'G5'), (58, 1, 'F5'), (59, 1, 'D5'),
        (60, 1, 'C5'), (61, 1, 'D5'), (62, 2, 'Bb4'),
    ]
    mel = mel + offset_mel(to_mel([
        {"beat": 0, "dur": 1, "note": "F4"}, {"beat": 1, "dur": 1, "note": "Bb4"},
        {"beat": 2, "dur": 1.5, "note": "D5"}, {"beat": 3.5, "dur": 0.5, "note": "C5"},
        {"beat": 4, "dur": 1, "note": "Bb4"}, {"beat": 5, "dur": 1, "note": "D5"},
        {"beat": 6, "dur": 2, "note": "F5"},
        {"beat": 8, "dur": 1, "note": "Eb5"}, {"beat": 9, "dur": 1, "note": "C5"},
        {"beat": 10, "dur": 1.5, "note": "G4"}, {"beat": 11.5, "dur": 0.5, "note": "Bb4"},
        {"beat": 12, "dur": 1, "note": "D5"}, {"beat": 13, "dur": 1, "note": "C5"},
        {"beat": 14, "dur": 2, "note": "Bb4"},
        {"beat": 16, "dur": 1, "note": "G4"}, {"beat": 17, "dur": 1, "note": "Bb4"},
        {"beat": 18, "dur": 1.5, "note": "Eb5"}, {"beat": 19.5, "dur": 0.5, "note": "D5"},
        {"beat": 20, "dur": 1, "note": "C5"}, {"beat": 21, "dur": 1, "note": "D5"},
        {"beat": 22, "dur": 2, "note": "F5"},
        {"beat": 24, "dur": 1, "note": "Eb5"}, {"beat": 25, "dur": 1, "note": "C5"},
        {"beat": 26, "dur": 1, "note": "A4"}, {"beat": 27, "dur": 1, "note": "C5"},
        {"beat": 28, "dur": 1, "note": "D5"}, {"beat": 29, "dur": 1, "note": "F5"},
        {"beat": 30, "dur": 2, "note": "Bb4"},
    ]), 64)
    lead(s, mel, instr='lead', vel=0.66, bell_long=False)
    return s


# --------------------------------------------------------------------------
# field4 — "Skip & Stride": bouncy plucky romp. A major, 126 BPM.
# Playful and light-footed: marimba lead over pizzicato comp, springy synced
# bass, busy shaker groove. The cheeky, almost-jaunty travel version.
# --------------------------------------------------------------------------
def track_field4():
    s = Seq(126)
    s.swing = 0.12
    prog = [
        (['A3', 'C#4', 'E4'], 'A2'), (['E3', 'G#3', 'B3'], 'E2'),
        (['F#3', 'A3', 'C#4'], 'F#2'), (['D4', 'F#4', 'A4'], 'D3'),
        (['A3', 'C#4', 'E4'], 'A2'), (['D4', 'F#4', 'A4'], 'D3'),
        (['E3', 'G#3', 'B3'], 'E2'), (['A3', 'C#4', 'E4'], 'A2'),
    ] * 2
    prog = prog + to_prog([
        {"chord": ["F#3", "A3", "C#4"], "bass": "F#2"}, {"chord": ["D4", "F#4", "A4"], "bass": "D3"},
        {"chord": ["E3", "G#3", "B3"], "bass": "E2"}, {"chord": ["A3", "C#4", "E4"], "bass": "A2"},
        {"chord": ["B3", "D4", "F#4"], "bass": "B2"}, {"chord": ["E3", "G#3", "B3"], "bass": "E2"},
        {"chord": ["D4", "F#4", "A4"], "bass": "D3"}, {"chord": ["A3", "C#4", "E4"], "bass": "A2"},
    ])
    groove(s, prog, bpb=4, bass='sync', comp='broken', perc='shaker',
           pad_vel=0.5, comp_instr='pluck', comp_vel=0.46, comp_lift=1,
           pad_instr='pad', pad_mode='stab')
    mel = [
        (0, .5, 'A4'), (.5, .5, 'C#5'), (1, 1, 'E5'), (2, .5, 'C#5'), (2.5, .5, 'A4'), (3, 1, 'E5'),
        (4, .5, 'G#4'), (4.5, .5, 'B4'), (5, 1, 'E5'), (6, 2, 'D5'),
        (8, .5, 'F#4'), (8.5, .5, 'A4'), (9, 1, 'C#5'), (10, .5, 'A4'), (10.5, .5, 'F#4'), (11, 1, 'C#5'),
        (12, .5, 'D5'), (12.5, .5, 'E5'), (13, 1, 'F#5'), (14, 2, 'E5'),
        (16, .5, 'A4'), (16.5, .5, 'C#5'), (17, 1, 'E5'), (18, .5, 'F#5'), (18.5, .5, 'E5'), (19, 1, 'C#5'),
        (20, .5, 'D5'), (20.5, .5, 'F#5'), (21, 1, 'A5'), (22, 2, 'F#5'),
        (24, .5, 'E5'), (24.5, .5, 'D5'), (25, 1, 'C#5'), (26, .5, 'B4'), (26.5, .5, 'C#5'), (27, 1, 'D5'),
        (28, .5, 'C#5'), (28.5, .5, 'B4'), (29, 1, 'A4'), (30, 2, 'A4'),
    ]
    mel = mel + offset_mel(to_mel([
        {"beat": 0, "dur": 0.5, "note": "E5"}, {"beat": 0.5, "dur": 0.5, "note": "C#5"},
        {"beat": 1, "dur": 1, "note": "A4"}, {"beat": 2, "dur": 0.5, "note": "C#5"},
        {"beat": 2.5, "dur": 0.5, "note": "E5"}, {"beat": 3, "dur": 1, "note": "A5"},
        {"beat": 4, "dur": 0.5, "note": "G#5"}, {"beat": 4.5, "dur": 0.5, "note": "E5"},
        {"beat": 5, "dur": 1, "note": "B4"}, {"beat": 6, "dur": 2, "note": "E5"},
        {"beat": 8, "dur": 0.5, "note": "F#5"}, {"beat": 8.5, "dur": 0.5, "note": "A5"},
        {"beat": 9, "dur": 1, "note": "C#5"}, {"beat": 10, "dur": 0.5, "note": "A5"},
        {"beat": 10.5, "dur": 0.5, "note": "F#5"}, {"beat": 11, "dur": 1, "note": "D5"},
        {"beat": 12, "dur": 0.5, "note": "E5"}, {"beat": 12.5, "dur": 0.5, "note": "F#5"},
        {"beat": 13, "dur": 1, "note": "G#5"}, {"beat": 14, "dur": 2, "note": "A5"},
        {"beat": 16, "dur": 0.5, "note": "E5"}, {"beat": 16.5, "dur": 0.5, "note": "C#5"},
        {"beat": 17, "dur": 1, "note": "A4"}, {"beat": 18, "dur": 0.5, "note": "B4"},
        {"beat": 18.5, "dur": 0.5, "note": "C#5"}, {"beat": 19, "dur": 1, "note": "D5"},
        {"beat": 20, "dur": 0.5, "note": "C#5"}, {"beat": 20.5, "dur": 0.5, "note": "B4"},
        {"beat": 21, "dur": 1, "note": "E5"}, {"beat": 22, "dur": 2, "note": "A4"},
    ]), 32)
    lead(s, mel, instr='pluck', vel=0.62, bell_long=False)
    return s


META = {
    'field2': {
        'name': 'Open Road',
        'track_gm': {'hollow': 74, 'pad': 89, 'bass': 32, 'pluck': 24},
        'reverb': [0.5, 0.3, 0.9, 0.5], 'gain': 0.78,
        'blurb': 'pastoral recorder wander over nylon guitar — light, folksy, breezy travel',
    },
    'field3': {
        'name': 'Banner & Road',
        'track_gm': {'lead': 61, 'pad': 48, 'bass': 43, 'soft': 49},
        'reverb': [0.6, 0.25, 0.95, 0.6], 'gain': 0.82,
        'blurb': 'heroic brass + strings march, walking bass — bigger, chin-up, setting out',
    },
    'field4': {
        'name': 'Skip & Stride',
        'track_gm': {'lead': 12, 'pad': 49, 'bass': 39, 'pluck': 45},
        'reverb': [0.4, 0.35, 0.85, 0.45], 'gain': 0.8,
        'blurb': 'bouncy marimba + pizzicato romp — playful, springy, light-footed',
    },
}
