from gen_music import *   # Seq, groove, lead, offset_mel, shift_oct, to_prog, nf, ...

# ==========================================================================
# TOWN VARIANTS — three cozy settlement themes, each distinct from the other
# and from the CURRENT town (G major / 108 BPM / soft flute + music box).
#   town2  Market Square  — D major / 116 BPM, marimba + shaker, bustling.
#   town3  Evening Hamlet — A major / 96 BPM, soft strings + harp, slow & warm.
#   town4  Cobblestone Reel — F major / 112 BPM, nylon guitar + accordion, swing.
# ==========================================================================


def track_town2():
    # "Market Square" — a lively, bustling daytime tune. Bright D major with a
    # bouncy marimba lead over a busy nylon-pluck comp and light hand-percussion
    # (shaker). Quarter-note walking bass keeps it moving without getting heavy.
    s = Seq(116)
    s.swing = 0.04
    prog = [
        (['D4', 'F#4', 'A4'], 'D2'), (['G3', 'B3', 'D4'], 'G2'),
        (['A3', 'C#4', 'E4'], 'A2'), (['D4', 'F#4', 'A4'], 'D3'),
        (['B3', 'D4', 'F#4'], 'B2'), (['G3', 'B3', 'D4'], 'G2'),
        (['E3', 'G3', 'B3'], 'E2'), (['A3', 'C#4', 'E4'], 'A2'),
    ] * 2
    prog = prog + to_prog([
        {"chord": ["G3", "B3", "D4"], "bass": "G2"}, {"chord": ["D4", "F#4", "A4"], "bass": "D3"},
        {"chord": ["E3", "G3", "B3"], "bass": "E2"}, {"chord": ["A3", "C#4", "E4"], "bass": "A2"},
        {"chord": ["B3", "D4", "F#4"], "bass": "B2"}, {"chord": ["G3", "B3", "D4"], "bass": "G2"},
        {"chord": ["D4", "F#4", "A4"], "bass": "D3"}, {"chord": ["A3", "C#4", "E4", "G4"], "bass": "A2"},
    ])
    groove(s, prog, bpb=4, bass='walk', comp='broken', perc='shaker',
           pad_vel=0.5, comp_instr='pluck', comp_vel=0.42, pad_mode='stab', pad_spread=0.18)
    # bouncy marimba tune — D major, lots of stepwise skips, market chatter
    mel = [
        (0, .5, 'A4'), (.5, .5, 'D5'), (1, 1, 'F#5'), (2, 1, 'E5'), (3, 1, 'D5'),
        (4, .5, 'B4'), (4.5, .5, 'D5'), (5, 1, 'G5'), (6, 2, 'F#5'),
        (8, .5, 'E5'), (8.5, .5, 'A5'), (9, 1, 'G5'), (10, 1, 'E5'), (11, 1, 'C#5'),
        (12, 1, 'D5'), (13, 1, 'F#5'), (14, 2, 'E5'),
        (16, .5, 'F#5'), (16.5, .5, 'A5'), (17, 1, 'B5'), (18, 1, 'A5'), (19, 1, 'F#5'),
        (20, 1, 'G5'), (21, 1, 'E5'), (22, 2, 'D5'),
        (24, .5, 'B4'), (24.5, .5, 'D5'), (25, 1, 'G5'), (26, 1, 'B5'), (27, 1, 'A5'),
        (28, 1, 'G5'), (29, 1, 'E5'), (30, 2, 'A5'),
        (32, 1, 'F#5'), (33, .5, 'E5'), (33.5, .5, 'D5'), (34, 1, 'E5'), (35, 1, 'G5'),
        (36, 1, 'F#5'), (37, 1, 'D5'), (38, 2, 'A4'),
        (40, .5, 'D5'), (40.5, .5, 'E5'), (41, 1, 'F#5'), (42, 1, 'A5'), (43, 1, 'G5'),
        (44, 1, 'E5'), (45, 1, 'C#5'), (46, 2, 'E5'),
        (48, .5, 'F#5'), (48.5, .5, 'B5'), (49, 1, 'A5'), (50, 1, 'G5'), (51, 1, 'F#5'),
        (52, 1, 'E5'), (53, 1, 'G5'), (54, 2, 'F#5'),
        (56, 1, 'A5'), (57, 1, 'G5'), (58, 1, 'F#5'), (59, 1, 'E5'),
        (60, 1, 'F#5'), (61, 1, 'D5'), (62, 2, 'D5'),
    ]
    mel = mel + offset_mel(to_mel([
        {"beat": 0, "dur": 1, "note": "G5"}, {"beat": 1, "dur": 1, "note": "F#5"},
        {"beat": 2, "dur": 1, "note": "E5"}, {"beat": 3, "dur": 1, "note": "D5"},
        {"beat": 4, "dur": .5, "note": "E5"}, {"beat": 4.5, "dur": .5, "note": "F#5"},
        {"beat": 5, "dur": 1, "note": "A5"}, {"beat": 6, "dur": 2, "note": "G5"},
        {"beat": 8, "dur": 1, "note": "B5"}, {"beat": 9, "dur": 1, "note": "A5"},
        {"beat": 10, "dur": 1, "note": "F#5"}, {"beat": 11, "dur": 1, "note": "D5"},
        {"beat": 12, "dur": 1, "note": "E5"}, {"beat": 13, "dur": 1, "note": "C#5"},
        {"beat": 14, "dur": 2, "note": "A4"},
        {"beat": 16, "dur": .5, "note": "F#5"}, {"beat": 16.5, "dur": .5, "note": "G5"},
        {"beat": 17, "dur": 1, "note": "A5"}, {"beat": 18, "dur": 1, "note": "B5"},
        {"beat": 19, "dur": 1, "note": "A5"}, {"beat": 20, "dur": 1, "note": "G5"},
        {"beat": 21, "dur": 1, "note": "E5"}, {"beat": 22, "dur": 2, "note": "F#5"},
        {"beat": 24, "dur": 1, "note": "G5"}, {"beat": 25, "dur": 1, "note": "E5"},
        {"beat": 26, "dur": 1, "note": "D5"}, {"beat": 27, "dur": 1, "note": "B4"},
        {"beat": 28, "dur": 1, "note": "C#5"}, {"beat": 29, "dur": 1, "note": "E5"},
        {"beat": 30, "dur": 2, "note": "D5"},
    ]), 64)
    lead(s, mel, instr='bell', vel=0.6, bell_long=False)
    return s


def track_town3():
    # "Evening Hamlet" — quiet, warm, slower. Lamps lit, day winding down. Soft
    # strings carry a gentle A-major tune over a harp arpeggio and a low held pad.
    # No drums — just a half-note bass to breathe. The homey, restful end of town.
    s = Seq(96)
    s.rev_amount = 0.34; s.rev_size = 1.4; s.tone = 5400
    prog = [
        (['A3', 'C#4', 'E4'], 'A2'), (['F#3', 'A3', 'C#4'], 'F#2'),
        (['D4', 'F#4', 'A4'], 'D3'), (['E3', 'G#3', 'B3'], 'E2'),
        (['A3', 'C#4', 'E4'], 'A2'), (['D4', 'F#4', 'A4'], 'D3'),
        (['B3', 'D4', 'F#4'], 'B2'), (['E3', 'G#3', 'B3'], 'E2'),
    ]
    prog = prog + to_prog([
        {"chord": ["F#3", "A3", "C#4"], "bass": "F#2"}, {"chord": ["D4", "F#4", "A4"], "bass": "D3"},
        {"chord": ["B3", "D4", "F#4"], "bass": "B2"}, {"chord": ["E3", "G#3", "B3"], "bass": "E2"},
        {"chord": ["A3", "C#4", "E4"], "bass": "A2"}, {"chord": ["D4", "F#4", "A4"], "bass": "D3"},
        {"chord": ["E3", "G#3", "B3"], "bass": "E2"}, {"chord": ["A3", "C#4", "E4"], "bass": "A2"},
        {"chord": ["D4", "F#4", "A4"], "bass": "D3"}, {"chord": ["E3", "G#3", "B3"], "bass": "E2"},
        {"chord": ["A3", "C#4", "E4", "G#4"], "bass": "A2"},
    ])
    groove(s, prog, bpb=4, bass='half', comp='arp_slow', perc='none',
           pad_vel=0.6, comp_instr='bell', comp_vel=0.32, pad_spread=0.2, pad_mode='low')
    # gentle, long-breathed A-major tune for soft strings — restful, warm
    mel = [
        (0, 2, 'E5'), (2, 1, 'C#5'), (3, 1, 'E5'),
        (4, 2, 'F#5'), (6, 2, 'E5'),
        (8, 1.5, 'D5'), (9.5, .5, 'E5'), (10, 2, 'F#5'), (12, 1, 'E5'), (13, 1, 'C#5'), (14, 2, 'B4'),
        (16, 2, 'C#5'), (18, 2, 'E5'), (20, 1, 'F#5'), (21, 1, 'E5'), (22, 2, 'C#5'),
        (24, 2, 'B4'), (26, 1, 'C#5'), (27, 1, 'D5'), (28, 4, 'E5'),
        (32, 2, 'A5'), (34, 1, 'G#5'), (35, 1, 'F#5'), (36, 2, 'E5'), (38, 2, 'C#5'),
        (40, 1.5, 'D5'), (41.5, .5, 'E5'), (42, 2, 'F#5'), (44, 1, 'E5'), (45, 1, 'D5'), (46, 2, 'B4'),
        (48, 2, 'E5'), (50, 2, 'F#5'), (52, 1, 'E5'), (53, 1, 'C#5'), (54, 2, 'B4'),
        (56, 2, 'C#5'), (58, 1, 'D5'), (59, 1, 'C#5'), (60, 4, 'A4'),
    ]
    mel = mel + offset_mel(to_mel([
        {"beat": 0, "dur": 2, "note": "C#5"}, {"beat": 2, "dur": 2, "note": "A4"},
        {"beat": 4, "dur": 1, "note": "B4"}, {"beat": 5, "dur": 1, "note": "C#5"},
        {"beat": 6, "dur": 2, "note": "D5"},
        {"beat": 8, "dur": 1.5, "note": "E5"}, {"beat": 9.5, "dur": .5, "note": "D5"},
        {"beat": 10, "dur": 2, "note": "C#5"}, {"beat": 12, "dur": 1, "note": "B4"},
        {"beat": 13, "dur": 1, "note": "A4"}, {"beat": 14, "dur": 2, "note": "F#4"},
        {"beat": 16, "dur": 2, "note": "B4"}, {"beat": 18, "dur": 2, "note": "D5"},
        {"beat": 20, "dur": 1, "note": "E5"}, {"beat": 21, "dur": 1, "note": "F#5"},
        {"beat": 22, "dur": 2, "note": "E5"},
        {"beat": 24, "dur": 1, "note": "C#5"}, {"beat": 25, "dur": 1, "note": "D5"},
        {"beat": 26, "dur": 2, "note": "E5"}, {"beat": 28, "dur": 4, "note": "A4"},
    ]), 64)
    lead(s, mel, instr='soft', vel=0.56, bell_long=False)
    return s


def track_town4():
    # "Cobblestone Reel" — a warm folk dance with a gentle swing lilt. Nylon
    # guitar carries the tune over an accordion oom-pah (half-bar comp) and a
    # light shaker. F major, 112 BPM, swung 8ths — toe-tapping but still cozy.
    s = Seq(112)
    s.swing = 0.12
    prog = [
        (['F3', 'A3', 'C4'], 'F2'), (['C4', 'E4', 'G4'], 'C3'),
        (['D4', 'F4', 'A4'], 'D3'), (['Bb3', 'D4', 'F4'], 'Bb2'),
        (['F3', 'A3', 'C4'], 'F2'), (['Bb3', 'D4', 'F4'], 'Bb2'),
        (['C4', 'E4', 'G4'], 'C3'), (['F3', 'A3', 'C4'], 'F2'),
    ] * 2
    prog = prog + to_prog([
        {"chord": ["D4", "F4", "A4"], "bass": "D3"}, {"chord": ["Bb3", "D4", "F4"], "bass": "Bb2"},
        {"chord": ["G3", "Bb3", "D4"], "bass": "G2"}, {"chord": ["C4", "E4", "G4"], "bass": "C3"},
        {"chord": ["F3", "A3", "C4"], "bass": "F2"}, {"chord": ["Bb3", "D4", "F4"], "bass": "Bb2"},
        {"chord": ["C4", "E4", "G4"], "bass": "C3"}, {"chord": ["F3", "A3", "C4", "E4"], "bass": "F2"},
    ])
    groove(s, prog, bpb=4, bass='quarter', comp='arp', perc='shaker',
           pad_vel=0.5, comp_instr='organ', comp_vel=0.34, pad_mode='half', pad_spread=0.16)
    # lilting F-major dance tune — nylon guitar, dotted swing skips
    mel = [
        (0, 1, 'C5'), (1, .5, 'F5'), (1.5, .5, 'A5'), (2, 1, 'G5'), (3, 1, 'F5'),
        (4, 1, 'E5'), (5, .5, 'G5'), (5.5, .5, 'C5'), (6, 2, 'E5'),
        (8, 1, 'F5'), (9, .5, 'A5'), (9.5, .5, 'G5'), (10, 1, 'F5'), (11, 1, 'D5'),
        (12, 1, 'C5'), (13, .5, 'E5'), (13.5, .5, 'G5'), (14, 2, 'F5'),
        (16, 1, 'A5'), (17, .5, 'G5'), (17.5, .5, 'F5'), (18, 1, 'E5'), (19, 1, 'D5'),
        (20, 1, 'C5'), (21, .5, 'D5'), (21.5, .5, 'E5'), (22, 2, 'F5'),
        (24, 1, 'G5'), (25, .5, 'F5'), (25.5, .5, 'E5'), (26, 1, 'D5'), (27, 1, 'E5'),
        (28, 1, 'F5'), (29, .5, 'A5'), (29.5, .5, 'C6'), (30, 2, 'A5'),
        (32, 1, 'A5'), (33, .5, 'G5'), (33.5, .5, 'F5'), (34, 1, 'A5'), (35, 1, 'G5'),
        (36, 1, 'F5'), (37, .5, 'D5'), (37.5, .5, 'F5'), (38, 2, 'E5'),
        (40, 1, 'D5'), (41, .5, 'F5'), (41.5, .5, 'A5'), (42, 1, 'G5'), (43, 1, 'F5'),
        (44, 1, 'D5'), (45, .5, 'E5'), (45.5, .5, 'D5'), (46, 2, 'C5'),
        (48, 1, 'C5'), (49, .5, 'E5'), (49.5, .5, 'G5'), (50, 1, 'F5'), (51, 1, 'E5'),
        (52, 1, 'D5'), (53, .5, 'F5'), (53.5, .5, 'E5'), (54, 2, 'G5'),
        (56, 1, 'F5'), (57, .5, 'G5'), (57.5, .5, 'A5'), (58, 1, 'G5'), (59, 1, 'E5'),
        (60, 1, 'F5'), (61, 1, 'C5'), (62, 2, 'F5'),
    ]
    mel = mel + offset_mel(to_mel([
        {"beat": 0, "dur": 1, "note": "A5"}, {"beat": 1, "dur": .5, "note": "G5"},
        {"beat": 1.5, "dur": .5, "note": "F5"}, {"beat": 2, "dur": 1, "note": "E5"},
        {"beat": 3, "dur": 1, "note": "D5"}, {"beat": 4, "dur": 1, "note": "Bb5"},
        {"beat": 5, "dur": .5, "note": "A5"}, {"beat": 5.5, "dur": .5, "note": "G5"},
        {"beat": 6, "dur": 2, "note": "F5"},
        {"beat": 8, "dur": 1, "note": "G5"}, {"beat": 9, "dur": .5, "note": "F5"},
        {"beat": 9.5, "dur": .5, "note": "E5"}, {"beat": 10, "dur": 1, "note": "D5"},
        {"beat": 11, "dur": 1, "note": "Bb4"}, {"beat": 12, "dur": 1, "note": "C5"},
        {"beat": 13, "dur": .5, "note": "E5"}, {"beat": 13.5, "dur": .5, "note": "G5"},
        {"beat": 14, "dur": 2, "note": "C5"},
        {"beat": 16, "dur": 1, "note": "F5"}, {"beat": 17, "dur": .5, "note": "A5"},
        {"beat": 17.5, "dur": .5, "note": "C6"}, {"beat": 18, "dur": 1, "note": "Bb5"},
        {"beat": 19, "dur": 1, "note": "G5"}, {"beat": 20, "dur": 1, "note": "A5"},
        {"beat": 21, "dur": .5, "note": "G5"}, {"beat": 21.5, "dur": .5, "note": "F5"},
        {"beat": 22, "dur": 2, "note": "E5"},
        {"beat": 24, "dur": 1, "note": "D5"}, {"beat": 25, "dur": .5, "note": "E5"},
        {"beat": 25.5, "dur": .5, "note": "F5"}, {"beat": 26, "dur": 1, "note": "G5"},
        {"beat": 27, "dur": 1, "note": "E5"}, {"beat": 28, "dur": 2, "note": "F5"},
        {"beat": 30, "dur": 2, "note": "C5"},
    ]), 64)
    lead(s, mel, instr='pluck', vel=0.6, bell_long=False)
    return s


META = {
    'town2': {'name': 'Market Square',
              'track_gm': {'lead': 12, 'pad': 24, 'bass': 32, 'pluck': 24, 'bell': 12},
              'reverb': [0.3, 0.4, 0.85, 0.4], 'gain': 0.82,
              'blurb': 'Bustling daytime market — bouncy marimba over busy plucks and a shaker.'},
    'town3': {'name': 'Evening Hamlet',
              'track_gm': {'lead': 48, 'pad': 89, 'bass': 32, 'soft': 48, 'bell': 46},
              'reverb': [0.5, 0.3, 0.9, 0.5], 'gain': 0.74,
              'blurb': 'Lamps-lit evening calm — soft strings drift over a harp, slow and warm.'},
    'town4': {'name': 'Cobblestone Reel',
              'track_gm': {'lead': 24, 'pad': 21, 'bass': 32, 'pluck': 24, 'organ': 21},
              'reverb': [0.35, 0.35, 0.85, 0.4], 'gain': 0.8,
              'blurb': 'Toe-tapping folk dance — nylon guitar lilts over an accordion oom-pah.'},
}
