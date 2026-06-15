from gen_music import *   # Seq, groove, lead, offset_mel, shift_oct, to_prog, nf, ...

# Three alternate FOREST variants — woodland / nature exploration themes.
# Current version (for contrast): D major, 100 BPM, airy pan-flute + flowing harp +
# warm strings, NO drums. All three below stay woodland but differ in key, tempo,
# lead instrument, groove and whether there's light percussion.


def track_forest2():
    # "Hollow Pines" — a deeper, older, mysterious wood. E DORIAN (minor-leaning but
    # with the raised 6th, C#, so it glows rather than mourns), slow 88 BPM. A low
    # clarinet wanders over a flowing harp and a warm string wash. No drums — the
    # space between the tall trunks IS the rhythm. Lower and sparser than the bright
    # original; the forest at dusk.
    s = Seq(88)
    s.swing = 0.0
    A = [
        (['E3', 'G3', 'B3'],  'E2'), (['D3', 'F#3', 'A3'], 'D2'),
        (['A3', 'C#4', 'E4'], 'A2'), (['G3', 'B3', 'D4'],  'G2'),
        (['E3', 'G3', 'B3'],  'E2'), (['C#3', 'E3', 'A3'], 'A2'),
        (['B2', 'D3', 'F#3'], 'B1'), (['E3', 'G3', 'B3'],  'E2'),
    ]
    B = [
        (['G3', 'B3', 'D4'],  'G2'), (['D3', 'F#3', 'A3'], 'D2'),
        (['A3', 'C#4', 'E4'], 'A2'), (['E3', 'G3', 'B3'],  'E2'),
        (['C#3', 'E3', 'A3'], 'A2'), (['B2', 'D3', 'F#3'], 'B1'),
        (['G3', 'B3', 'D4'],  'G2'), (['E3', 'G3', 'B3'],  'E2'),
    ]
    prog = A + B
    groove(s, prog, bpb=4, bass='half', comp='arp_slow', perc='none',
           pad_vel=0.6, comp_instr='bell', comp_vel=0.3, pad_spread=0.2, pad_mode='low')
    mel = [
        (0, 3, 'E5'), (3, 1, 'D5'), (4, 2, 'B4'), (6, 2, 'C#5'),
        (8, 2, 'A4'), (10, 1, 'B4'), (11, 1, 'D5'), (12, 3, 'E5'), (15, 1, 'D5'),
        (16, 2, 'C#5'), (18, 2, 'B4'), (20, 2, 'A4'), (22, 2, 'G4'),
        (24, 2, 'A4'), (26, 1, 'B4'), (27, 1, 'A4'), (28, 4, 'E4'),
    ]
    mel = mel + offset_mel([
        (0, 2, 'B4'), (2, 2, 'D5'), (4, 2, 'E5'), (6, 2, 'D5'),
        (8, 2, 'C#5'), (10, 1, 'B4'), (11, 1, 'A4'), (12, 4, 'E4'),
        (16, 2, 'A4'), (18, 2, 'B4'), (20, 2, 'D5'), (22, 2, 'E5'),
        (24, 1, 'C#5'), (25, 1, 'B4'), (26, 2, 'A4'), (28, 4, 'E5'),
    ], 32)
    lead(s, mel, instr='hollow', vel=0.5, bell_long=False)
    return s


def track_forest3():
    # "Sunlit Glade" — a bright, airy clearing where the light pours through. G MAJOR,
    # a touch faster at 112 BPM, with a chirpy recorder/ocarina lead, a music-box
    # sparkle, and a LIGHT shaker so it skips along. Major-pentatonic-leaning melody —
    # open, happy, the sunny counterpart to the dusky pines.
    s = Seq(112)
    s.swing = 0.04
    A = [
        (['G3', 'B3', 'D4'],  'G2'), (['D4', 'F#4', 'A4'], 'D3'),
        (['C4', 'E4', 'G4'],  'C3'), (['G3', 'B3', 'D4'],  'G2'),
        (['E3', 'G3', 'B3'],  'E2'), (['C4', 'E4', 'G4'],  'C3'),
        (['A3', 'C4', 'E4'],  'A2'), (['D4', 'F#4', 'A4'], 'D3'),
    ]
    B = [
        (['C4', 'E4', 'G4'],  'C3'), (['D4', 'F#4', 'A4'], 'D3'),
        (['B3', 'D4', 'G4'],  'G2'), (['E3', 'G3', 'B3'],  'E2'),
        (['A3', 'C4', 'E4'],  'A2'), (['D4', 'F#4', 'A4'], 'D3'),
        (['C4', 'E4', 'G4'],  'C3'), (['G3', 'B3', 'D4'],  'G2'),
    ]
    prog = A + A + B
    groove(s, prog, bpb=4, bass='quarter', comp='arp', perc='shaker',
           pad_vel=0.55, comp_instr='bell', comp_vel=0.34, pad_spread=0.2, pad_mode='stab')
    mel = [
        (0, 1, 'D5'), (1, 1, 'G5'), (2, 1, 'B5'), (3, 1, 'A5'),
        (4, 1, 'G5'), (5, 1, 'E5'), (6, 2, 'D5'),
        (8, 1, 'E5'), (9, 1, 'G5'), (10, 1, 'A5'), (11, 1, 'G5'),
        (12, 1, 'E5'), (13, 1, 'D5'), (14, 2, 'B4'),
        (16, 1, 'E5'), (17, 1, 'D5'), (18, 1, 'E5'), (19, 1, 'G5'),
        (20, 1, 'A5'), (21, 1, 'B5'), (22, 2, 'A5'),
        (24, 1, 'G5'), (25, 1, 'E5'), (26, 1, 'D5'), (27, 1, 'E5'),
        (28, 1, 'D5'), (29, 1, 'B4'), (30, 2, 'A4'),
        (32, 1, 'B5'), (33, 1, 'A5'), (34, 1, 'G5'), (35, 1, 'B5'),
        (36, 1, 'D6'), (37, 1, 'B5'), (38, 2, 'A5'),
        (40, 1, 'E5'), (41, 1, 'G5'), (42, 1, 'A5'), (43, 1, 'B5'),
        (44, 1, 'A5'), (45, 1, 'G5'), (46, 2, 'E5'),
        (48, 1, 'D5'), (49, 1, 'E5'), (50, 1, 'G5'), (51, 1, 'A5'),
        (52, 1, 'G5'), (53, 1, 'E5'), (54, 2, 'D5'),
        (56, 1, 'B4'), (57, 1, 'D5'), (58, 1, 'E5'), (59, 1, 'G5'),
        (60, 1, 'E5'), (61, 1, 'D5'), (62, 2, 'G5'),
    ]
    mel = mel + offset_mel([
        (0, 1, 'G5'), (1, 1, 'A5'), (2, 1, 'B5'), (3, 1, 'D6'),
        (4, 1, 'B5'), (5, 1, 'A5'), (6, 2, 'G5'),
        (8, 1, 'E5'), (9, 1, 'G5'), (10, 1, 'B5'), (11, 1, 'A5'),
        (12, 1, 'G5'), (13, 1, 'E5'), (14, 2, 'D5'),
        (16, 1, 'C5'), (17, 1, 'E5'), (18, 1, 'G5'), (19, 1, 'E5'),
        (20, 1, 'A5'), (21, 1, 'G5'), (22, 2, 'E5'),
        (24, 1, 'D5'), (25, 1, 'B4'), (26, 1, 'D5'), (27, 1, 'E5'),
        (28, 1, 'D5'), (29, 1, 'B4'), (30, 2, 'G4'),
    ], 64)
    lead(s, mel, instr='soft', vel=0.6, bell_long=False)
    return s


def track_forest4():
    # "Brookside" — a flowing, playful piece beside a woodland stream. A MAJOR, an
    # easy 104 BPM with a gentle swung lilt. A warm oboe sings over a constantly
    # flowing harp (broken arpeggio = the water), with the softest brushed perc.
    # Lots of gentle motion, never shrill — the babble of a brook under the canopy.
    s = Seq(104)
    s.swing = 0.10
    A = [
        (['A3', 'C#4', 'E4'], 'A2'), (['E3', 'G#3', 'B3'], 'E2'),
        (['F#3', 'A3', 'C#4'], 'F#2'), (['D4', 'F#4', 'A4'], 'D3'),
        (['A3', 'C#4', 'E4'], 'A2'), (['D4', 'F#4', 'A4'], 'D3'),
        (['B3', 'D4', 'F#4'], 'B2'), (['E3', 'G#3', 'B3'], 'E2'),
    ]
    B = [
        (['D4', 'F#4', 'A4'], 'D3'), (['A3', 'C#4', 'E4'], 'A2'),
        (['B3', 'D4', 'F#4'], 'B2'), (['E3', 'G#3', 'B3'], 'E2'),
        (['F#3', 'A3', 'C#4'], 'F#2'), (['D4', 'F#4', 'A4'], 'D3'),
        (['E3', 'G#3', 'B3'], 'E2'), (['A3', 'C#4', 'E4'], 'A2'),
    ]
    prog = A + A + B
    groove(s, prog, bpb=4, bass='walk', comp='broken', perc='soft',
           pad_vel=0.52, comp_instr='pluck', comp_vel=0.4, pad_spread=0.22, pad_mode='low')
    mel = [
        (0, 1.5, 'E5'), (1.5, .5, 'F#5'), (2, 1, 'A5'), (3, 1, 'F#5'),
        (4, 1, 'E5'), (5, 1, 'C#5'), (6, 2, 'B4'),
        (8, 1, 'C#5'), (9, 1, 'E5'), (10, 1.5, 'F#5'), (11.5, .5, 'E5'),
        (12, 1, 'D5'), (13, 1, 'C#5'), (14, 2, 'D5'),
        (16, 1.5, 'A5'), (17.5, .5, 'B5'), (18, 1, 'C#6'), (19, 1, 'A5'),
        (20, 1, 'F#5'), (21, 1, 'E5'), (22, 2, 'F#5'),
        (24, 1, 'E5'), (25, 1, 'D5'), (26, 1, 'C#5'), (27, 1, 'B4'),
        (28, 1, 'C#5'), (29, 1, 'E5'), (30, 2, 'A4'),
        (32, 1.5, 'F#5'), (33.5, .5, 'A5'), (34, 1, 'B5'), (35, 1, 'A5'),
        (36, 1, 'F#5'), (37, 1, 'E5'), (38, 2, 'D5'),
        (40, 1, 'E5'), (41, 1, 'F#5'), (42, 1.5, 'A5'), (43.5, .5, 'B5'),
        (44, 1, 'A5'), (45, 1, 'F#5'), (46, 2, 'E5'),
        (48, 1, 'D5'), (49, 1, 'F#5'), (50, 1.5, 'A5'), (51.5, .5, 'F#5'),
        (52, 1, 'E5'), (53, 1, 'D5'), (54, 2, 'C#5'),
        (56, 1, 'B4'), (57, 1, 'C#5'), (58, 1, 'E5'), (59, 1, 'F#5'),
        (60, 1, 'E5'), (61, 1, 'C#5'), (62, 2, 'A4'),
    ]
    mel = mel + offset_mel([
        (0, 1, 'A5'), (1, 1, 'F#5'), (2, 1.5, 'E5'), (3.5, .5, 'F#5'),
        (4, 1, 'D5'), (5, 1, 'C#5'), (6, 2, 'B4'),
        (8, 1, 'C#5'), (9, 1, 'E5'), (10, 1, 'F#5'), (11, 1, 'A5'),
        (12, 1, 'B5'), (13, 1, 'A5'), (14, 2, 'F#5'),
        (16, 1, 'E5'), (17, 1, 'F#5'), (18, 1.5, 'A5'), (19.5, .5, 'C#6'),
        (20, 1, 'B5'), (21, 1, 'A5'), (22, 2, 'F#5'),
        (24, 1, 'E5'), (25, 1, 'C#5'), (26, 1, 'B4'), (27, 1, 'C#5'),
        (28, 1, 'E5'), (29, 1, 'F#5'), (30, 2, 'A5'),
    ], 64)
    lead(s, mel, instr='soft', vel=0.6, bell_long=False)
    return s


META = {
    'forest2': {'name': 'Hollow Pines',
                'track_gm': {'hollow': 71, 'pad': 48, 'bass': 33, 'bell': 46},
                'reverb': [0.55, 0.3, 0.92, 0.5], 'gain': 0.74,
                'blurb': 'dusky E-dorian deep wood; low clarinet wanders over harp and warm strings, no drums'},
    'forest3': {'name': 'Sunlit Glade',
                'track_gm': {'soft': 74, 'pad': 49, 'bass': 33, 'bell': 10},
                'reverb': [0.45, 0.3, 0.88, 0.45], 'gain': 0.8,
                'blurb': 'bright G-major clearing; chirpy recorder + music-box sparkle with a light skipping shaker'},
    'forest4': {'name': 'Brookside',
                'track_gm': {'soft': 68, 'pad': 48, 'bass': 32, 'pluck': 46},
                'reverb': [0.5, 0.32, 0.9, 0.45], 'gain': 0.78,
                'blurb': 'flowing A-major brook; warm oboe over a babbling broken-harp current, gentle swung lilt'},
}
