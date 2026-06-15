from gen_music import *   # Seq, groove, lead, offset_mel, shift_oct, to_prog, to_mel, nf, ...

# ==========================================================================
# EMBER-MEADOWS — warm, sunlit rolling meadows with an autumn / ember glow.
# Golden-hour, pretty, peaceful pastoral. A little slower and cozier than a
# plains field, with a gentle sway. Flute lead over harp + a soft strings pad.
# F major, 86 BPM. Should feel content and golden.
# ==========================================================================


def track_ember_meadows():
    s = Seq(86)
    s.swing = 0.09                      # gentle lilt, a sway not a bounce
    # F major. Warm, settled progression: I - IV - vi - V, with a ii/IV lift.
    prog = [
        (['F3', 'A3', 'C4'],  'F2'),  (['Bb3', 'D4', 'F4'], 'Bb2'),
        (['D4', 'F4', 'A4'],  'D3'),  (['C4', 'E4', 'G4'],  'C3'),
        (['G3', 'Bb3', 'D4'], 'G2'),  (['Bb3', 'D4', 'F4'], 'Bb2'),
        (['F3', 'A3', 'C4'],  'F2'),  (['C4', 'E4', 'G4'],  'C3'),
    ] * 2
    prog = prog + to_prog([
        {"chord": ["Bb3", "D4", "F4"], "bass": "Bb2"}, {"chord": ["F3", "A3", "C4"], "bass": "F2"},
        {"chord": ["G3", "Bb3", "D4"], "bass": "G2"},  {"chord": ["C4", "E4", "G4"], "bass": "C3"},
    ])
    groove(s, prog, bpb=4, bass='half', comp='broken', perc='soft',
           pad_vel=0.6, comp_instr='pluck', comp_vel=0.36, comp_lift=0,
           pad_instr='pad', pad_mode='swell')

    # --- main phrase: bars 1-8 (beats 0-31). Flute, octave 4-5, brief 5 peaks.
    mel = [
        (0, 1.5, 'F4'), (1.5, .5, 'G4'), (2, 1, 'A4'), (3, 1, 'C5'),
        (4, 1.5, 'D5'), (5.5, .5, 'C5'), (6, 2, 'A4'),
        (8, 1, 'A4'), (9, 1, 'D5'), (10, 1.5, 'F5'), (11.5, .5, 'D5'),
        (12, 1, 'C5'), (13, 1, 'A4'), (14, 2, 'G4'),
        (16, 1, 'Bb4'), (17, 1, 'D5'), (18, 1.5, 'C5'), (19.5, .5, 'A4'),
        (20, 1, 'G4'), (21, 1, 'A4'), (22, 2, 'F4'),
        (24, 1, 'A4'), (25, 1, 'G4'), (26, 1, 'F4'), (27, 1, 'A4'),
        (28, 1.5, 'C5'), (29.5, .5, 'D5'), (30, 2, 'C5'),
    ]
    # --- bars 9-16 (beats 32-63): a lifted answering phrase, reaches a brief F5.
    mel = mel + offset_mel(to_mel([
        {"beat": 0, "dur": 1, "note": "C5"}, {"beat": 1, "dur": 1, "note": "A4"},
        {"beat": 2, "dur": 1.5, "note": "F4"}, {"beat": 3.5, "dur": 0.5, "note": "A4"},
        {"beat": 4, "dur": 1, "note": "C5"}, {"beat": 5, "dur": 1, "note": "D5"},
        {"beat": 6, "dur": 2, "note": "C5"},
        {"beat": 8, "dur": 1, "note": "D5"}, {"beat": 9, "dur": 1, "note": "F5"},
        {"beat": 10, "dur": 1.5, "note": "E5"}, {"beat": 11.5, "dur": 0.5, "note": "C5"},
        {"beat": 12, "dur": 1, "note": "D5"}, {"beat": 13, "dur": 1, "note": "C5"},
        {"beat": 14, "dur": 2, "note": "A4"},
        {"beat": 16, "dur": 1, "note": "Bb4"}, {"beat": 17, "dur": 1, "note": "D5"},
        {"beat": 18, "dur": 1.5, "note": "F5"}, {"beat": 19.5, "dur": 0.5, "note": "D5"},
        {"beat": 20, "dur": 1, "note": "C5"}, {"beat": 21, "dur": 1, "note": "Bb4"},
        {"beat": 22, "dur": 2, "note": "A4"},
        {"beat": 24, "dur": 1, "note": "G4"}, {"beat": 25, "dur": 1, "note": "Bb4"},
        {"beat": 26, "dur": 1, "note": "A4"}, {"beat": 27, "dur": 1, "note": "G4"},
        {"beat": 28, "dur": 1.5, "note": "F4"}, {"beat": 29.5, "dur": 0.5, "note": "G4"},
        {"beat": 30, "dur": 2, "note": "A4"},
    ]), 32)
    # --- bars 17-20 (beats 64-79): a settling tag to close the loop home to F.
    mel = mel + offset_mel(to_mel([
        {"beat": 0, "dur": 1, "note": "C5"}, {"beat": 1, "dur": 1, "note": "A4"},
        {"beat": 2, "dur": 1.5, "note": "D5"}, {"beat": 3.5, "dur": 0.5, "note": "C5"},
        {"beat": 4, "dur": 1, "note": "A4"}, {"beat": 5, "dur": 1, "note": "G4"},
        {"beat": 6, "dur": 2, "note": "F4"},
        {"beat": 8, "dur": 1, "note": "A4"}, {"beat": 9, "dur": 1, "note": "C5"},
        {"beat": 10, "dur": 1, "note": "G4"}, {"beat": 11, "dur": 1, "note": "Bb4"},
        {"beat": 12, "dur": 1.5, "note": "A4"}, {"beat": 13.5, "dur": 0.5, "note": "G4"},
        {"beat": 14, "dur": 2, "note": "F4"},
    ]), 64)
    lead(s, mel, instr='lead', vel=0.6, bell_long=False)
    return s


META = {
    'ember_meadows': {
        'name': 'Ember-Meadows',
        'track_gm': {'lead': 73, 'pad': 48, 'bass': 32, 'pluck': 46},
        'reverb': [0.5, 0.3, 0.9, 0.5], 'gain': 0.76,
        'blurb': 'warm flute over harp + soft strings pad, gentle sway — golden-hour pastoral meadow',
    },
}
