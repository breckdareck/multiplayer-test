from gen_music import *   # Seq, groove, lead, offset_mel, shift_oct, to_prog, nf, ...

# ==========================================================================
# RUINS VARIANTS — three alternate "ancient ruins / forgotten places" themes.
# All lonely, somber, mysterious and SPARSE; each differs in key, tempo, lead
# voice, harmony and motion from one another AND from the current version
# (D minor, 68 BPM, solo cello over a bowed drone with harp glints).
# Deliberately NOT churchy: no choir wash, no organ hymn, modest reverb.
# ==========================================================================


def track_ruins2():
    # "Hollow Reliquary" — a mournful solo English horn winding over a sparse,
    # low bowed drone. A natural minor, 72 BPM, slow 4/4. Reedy and weathered,
    # lots of empty air between phrases; only a faint low cello pedal underneath.
    s = Seq(72)
    # Drone-led: a sustained root (drone bass) + a barely-there low pad. No comp,
    # no percussion — the reed line and the silence carry it.
    prog = [
        (['A2', 'C3', 'E3'], 'A1'), (['A2', 'C3', 'E3'], 'A1'),
        (['F2', 'A2', 'C3'], 'F1'), (['G2', 'Bb2', 'D3'], 'G1'),
        (['A2', 'C3', 'E3'], 'A1'), (['D3', 'F3', 'A3'], 'D2'),
        (['E2', 'G#2', 'B2'], 'E1'), (['A2', 'C3', 'E3'], 'A1'),
        (['F2', 'A2', 'C3'], 'F1'), (['C3', 'E3', 'G3'], 'C2'),
        (['D3', 'F3', 'A3'], 'D2'), (['A2', 'C3', 'E3'], 'A1'),
        (['G2', 'Bb2', 'D3'], 'G1'), (['E2', 'G#2', 'B2'], 'E1'),
        (['A2', 'C3', 'E3'], 'A1'), (['E2', 'G#2', 'B2', 'D3'], 'E1'),
    ]
    groove(s, prog, bpb=4, bass='drone', comp='none', perc='none',
           pad=True, pad_mode='low', pad_vel=0.34, pad_instr='darkpad', pad_spread=0.12)
    # A harmonic-minor-tinted lament (G# over the E chords). Long held tones,
    # sighing falls, frequent rests — never busy.
    mel = [
        (1, 3, 'E4'), (4, 4, 'C4'),
        (8, 2, 'A4'), (10, 2, 'G4'), (12, 3, 'F4'), (15, 1, 'E4'),
        (16, 4, 'C4'), (21, 3, 'D4'),
        (24, 2, 'E4'), (26, 2, 'G#4'), (28, 4, 'A4'),
        (32, 2, 'C5'), (34, 2, 'A4'), (36, 3, 'G4'), (39, 1, 'F4'),
        (40, 4, 'E4'), (45, 3, 'D4'),
        (48, 3, 'F4'), (51, 1, 'E4'), (52, 4, 'D4'),
        (56, 2, 'C4'), (58, 2, 'E4'), (60, 3, 'A4'), (63, 1, 'G#4'),
    ]
    lead(s, mel, instr='hollow', vel=0.5, bell_long=False)
    return s


def track_ruins3():
    # "Stonefall" — tense, hushed low strings with a creeping bass and a sense of
    # unease; occasional cold harp glints break the stillness. E minor with a
    # phrygian b2 (F natural) for dread. 64 BPM. Darker and more anxious than the
    # lonely-lament variants — the air feels watched.
    s = Seq(64)
    prog = [
        (['E3', 'G3', 'B3'], 'E2'), (['F3', 'A3', 'C4'], 'F2'),
        (['E3', 'G3', 'B3'], 'E2'), (['C3', 'E3', 'G3'], 'C2'),
        (['E3', 'G3', 'B3'], 'E2'), (['D3', 'F3', 'A3'], 'D2'),
        (['B2', 'D3', 'F3'], 'B1'), (['E3', 'G3', 'B3'], 'E2'),
        (['C3', 'E3', 'G3'], 'C2'), (['A2', 'C3', 'E3'], 'A1'),
        (['F3', 'A3', 'C4'], 'F2'), (['B2', 'D3', 'F3'], 'B1'),
        (['E3', 'G3', 'B3'], 'E2'), (['D3', 'F3', 'A3'], 'D2'),
        (['C3', 'E3', 'G3'], 'C2'), (['B2', 'D3', 'F3', 'A3'], 'B1'),
    ]
    # Hushed low strings (viol pad), a creeping bass that won't sit still, no drums
    # except a slow ritual tom marking the dread. A handful of harp glints, off-grid.
    groove(s, prog, bpb=4, bass='creep', comp='none', perc='ritual',
           pad=True, pad_mode='low', pad_vel=0.40, pad_instr='viol', pad_spread=0.16)
    # cold harp glints — sparse, irregular, unsettling intervals (b2/tritone color)
    for (_b, _n, _p) in [(3.5, 'F5', -0.25), (11.0, 'B4', 0.25), (18.5, 'C5', -0.2),
                         (27.0, 'F5', 0.22), (35.5, 'A4', -0.25), (44.0, 'B4', 0.2),
                         (52.5, 'C5', -0.2), (59.0, 'F4', 0.25)]:
        s.n(_b, 1.8, _n, 'glass', 0.16, pan=_p)
    # low, tense melody — small steps, leaning on the b2, lots of held suspense
    mel = [
        (0, 3, 'B4'), (3, 1, 'C5'), (4, 4, 'B4'),
        (8, 2, 'E4'), (10, 2, 'G4'), (12, 4, 'F4'),
        (16, 3, 'E4'), (19, 1, 'D4'), (20, 4, 'E4'),
        (24, 2, 'G4'), (26, 2, 'A4'), (28, 3, 'B4'), (31, 1, 'C5'),
        (32, 4, 'B4'), (36, 2, 'A4'), (38, 2, 'G4'),
        (40, 3, 'F4'), (43, 1, 'E4'), (44, 4, 'D4'),
        (48, 2, 'E4'), (50, 2, 'G4'), (52, 4, 'F4'),
        (56, 3, 'E4'), (59, 1, 'F4'), (60, 4, 'E4'),
    ]
    lead(s, mel, instr='viol', vel=0.46, bell_long=False)
    return s


def track_ruins4():
    # "Driftwind Halls" — an airy, hollow flute/ocarina drifting over a slow warm
    # pad; desolate and distant, like wind moving through empty colonnades. G minor
    # with a dorian-bright E natural color, 76 BPM. Open and breathy, more wistful
    # than grim — the loneliness of a vast empty place rather than dread.
    s = Seq(76)
    prog = [
        (['G3', 'Bb3', 'D4'], 'G2'), (['D3', 'F3', 'A3'], 'D2'),
        (['Eb3', 'G3', 'Bb3'], 'Eb2'), (['F3', 'A3', 'C4'], 'F2'),
        (['G3', 'Bb3', 'D4'], 'G2'), (['C3', 'E3', 'G3'], 'C2'),
        (['D3', 'F3', 'A3'], 'D2'), (['G3', 'Bb3', 'D4'], 'G2'),
        (['Eb3', 'G3', 'Bb3'], 'Eb2'), (['Bb2', 'D3', 'F3'], 'Bb1'),
        (['C3', 'E3', 'G3'], 'C2'), (['D3', 'F3', 'A3'], 'D2'),
        (['Eb3', 'G3', 'Bb3'], 'Eb2'), (['F3', 'A3', 'C4'], 'F2'),
        (['G3', 'Bb3', 'D4'], 'G2'), (['D3', 'F3', 'A3', 'C4'], 'D2'),
    ]
    # Slow held warm pad + a half-step drone bass; a few sparse harp drips for air.
    # No percussion. The flute floats far above an open, distant backing.
    groove(s, prog, bpb=4, bass='half', comp='drip', perc='none',
           pad=True, pad_mode='swell', pad_vel=0.44, pad_instr='pad', pad_spread=0.20,
           comp_instr='bell', comp_vel=0.20)
    # airy, drifting flute line — gentle arcs, dorian E natural lifts it out of grim,
    # mostly octave 4-5 with brief 5 peaks, never shrill.
    mel = [
        (0, 2, 'D5'), (2, 2, 'Bb4'), (4, 3, 'C5'), (7, 1, 'D5'),
        (8, 2, 'F5'), (10, 1, 'E5'), (11, 1, 'D5'), (12, 4, 'C5'),
        (16, 2, 'Bb4'), (18, 2, 'D5'), (20, 3, 'Eb5'), (23, 1, 'D5'),
        (24, 2, 'C5'), (26, 2, 'Bb4'), (28, 4, 'G4'),
        (32, 2, 'Bb4'), (34, 2, 'C5'), (36, 3, 'D5'), (39, 1, 'Eb5'),
        (40, 2, 'F5'), (42, 2, 'D5'), (44, 4, 'C5'),
        (48, 2, 'Bb4'), (50, 1, 'C5'), (51, 1, 'D5'), (52, 3, 'Eb5'), (55, 1, 'D5'),
        (56, 2, 'C5'), (58, 2, 'A4'), (60, 4, 'D5'),
    ]
    lead(s, mel, instr='hollow', vel=0.5, bell_long=False)
    return s


META = {
    'ruins2': {'name': 'Hollow Reliquary',
               'track_gm': {'lead': 69, 'hollow': 69, 'darkpad': 89, 'bass': 42},
               'reverb': [0.45, 0.35, 0.85, 0.45], 'gain': 0.72,
               'blurb': 'mournful solo English horn over a sparse low bowed drone'},
    'ruins3': {'name': 'Stonefall',
               'track_gm': {'lead': 48, 'viol': 48, 'glass': 46, 'bass': 43},
               'reverb': [0.5, 0.3, 0.9, 0.5], 'gain': 0.7,
               'blurb': 'tense hushed low strings + cold harp glints, a sense of unease'},
    'ruins4': {'name': 'Driftwind Halls',
               'track_gm': {'lead': 79, 'hollow': 79, 'pad': 89, 'bass': 43, 'bell': 46},
               'reverb': [0.6, 0.28, 0.92, 0.55], 'gain': 0.7,
               'blurb': 'airy hollow ocarina drifting over a slow pad, desolate and distant'},
}
