from gen_music import *   # Seq, groove, lead, offset_mel, shift_oct, to_prog, nf, ...

# Windmill Terraces (map: three_terraces) — breezy pastoral hill-terraces dotted
# with windmills. Light, lilting, airy; a sense of wind and turning sails. D MAJOR,
# 118 BPM with a strong swung lilt (s.swing high) so the 8ths skip like a 6/8 jig —
# the "turning sail" feel. A bright recorder sings the tune over a plucked nylon-
# guitar folk backing, a walking acoustic bass, a warm pad wash and the softest
# brushed shaker. Cheerful and rustic, bouncy but never frantic; lead stays in
# octave 4-5 (only brief 6th-octave touches) so it reads airy, not shrill.


def track_three_terraces():
    s = Seq(118)
    s.swing = 0.12   # strong lilt — off-beat 8ths pushed late = the swung, turning bounce

    # I–V–vi–IV-ish pastoral motion in D, with a flatter, brighter B section that
    # lifts to the relative-leaning G/A before settling home.
    A = [
        (['D4', 'F#4', 'A4'], 'D2'), (['A3', 'C#4', 'E4'], 'A2'),
        (['B3', 'D4', 'F#4'], 'B2'), (['G3', 'B3', 'D4'],  'G2'),
        (['D4', 'F#4', 'A4'], 'D2'), (['G3', 'B3', 'D4'],  'G2'),
        (['A3', 'C#4', 'E4'], 'A2'), (['D4', 'F#4', 'A4'], 'D2'),
    ]
    B = [
        (['G3', 'B3', 'D4'],  'G2'), (['D4', 'F#4', 'A4'], 'D3'),
        (['E3', 'G3', 'B3'],  'E2'), (['A3', 'C#4', 'E4'], 'A2'),
        (['B3', 'D4', 'F#4'], 'B2'), (['G3', 'B3', 'D4'],  'G2'),
        (['A3', 'C#4', 'E4'], 'A2'), (['D4', 'F#4', 'A4'], 'D2'),
    ]
    prog = A + A + B   # 24 bars * 4 = 96 beats @ 118 BPM ~= 48.8s loop

    groove(s, prog, bpb=4, bass='walk', comp='broken', perc='shaker',
           pad_vel=0.5, comp_instr='pluck', comp_vel=0.42, pad_spread=0.22, pad_mode='low')

    # A-section tune: a chirpy, lilting figure that hops up to the sail-turn peak then
    # eases home. Dotted/8th motion rides the swing. Octave 4-5, one quick D6 lift.
    A_mel = [
        (0, 1, 'D5'), (1, .5, 'F#5'), (1.5, .5, 'E5'), (2, 1, 'A5'), (3, 1, 'F#5'),
        (4, 1, 'E5'), (5, 1, 'C#5'), (6, 2, 'D5'),
        (8, 1, 'F#5'), (9, .5, 'A5'), (9.5, .5, 'G5'), (10, 1, 'B5'), (11, 1, 'A5'),
        (12, 1, 'G5'), (13, 1, 'E5'), (14, 2, 'D5'),
        (16, 1, 'D5'), (17, .5, 'E5'), (17.5, .5, 'F#5'), (18, 1, 'A5'), (19, 1, 'B5'),
        (20, 1, 'A5'), (21, 1, 'F#5'), (22, 2, 'E5'),
        (24, 1, 'A5'), (25, 1, 'G5'), (26, 1, 'F#5'), (27, 1, 'E5'),
        (28, 1, 'F#5'), (29, 1, 'D5'), (30, 2, 'D5'),
    ]
    # A repeat: same shape lifted with a brief D6 sail-peak, then resolves down.
    A2_mel = offset_mel([
        (0, 1, 'A5'), (1, .5, 'B5'), (1.5, .5, 'A5'), (2, 1, 'F#5'), (3, 1, 'E5'),
        (4, 1, 'F#5'), (5, 1, 'A5'), (6, 2, 'D6'),
        (8, 1, 'B5'), (9, 1, 'A5'), (10, 1, 'G5'), (11, 1, 'F#5'),
        (12, 1, 'E5'), (13, 1, 'F#5'), (14, 2, 'G5'),
        (16, 1, 'F#5'), (17, .5, 'E5'), (17.5, .5, 'D5'), (18, 1, 'E5'), (19, 1, 'F#5'),
        (20, 1, 'A5'), (21, 1, 'G5'), (22, 2, 'F#5'),
        (24, 1, 'E5'), (25, 1, 'D5'), (26, 1, 'C#5'), (27, 1, 'E5'),
        (28, 1, 'D5'), (29, 1, 'A4'), (30, 2, 'D5'),
    ], 32)
    # B-section tune: a flatter, breezier answer (steps + held notes) that opens the
    # space then walks back home. Stays octave 4-5.
    B_mel = offset_mel([
        (0, 1, 'B4'), (1, 1, 'D5'), (2, 1, 'G5'), (3, 1, 'F#5'),
        (4, 1, 'E5'), (5, 1, 'D5'), (6, 2, 'B4'),
        (8, 1, 'C#5'), (9, 1, 'E5'), (10, 1, 'A5'), (11, 1, 'G5'),
        (12, 1, 'F#5'), (13, 1, 'E5'), (14, 2, 'D5'),
        (16, 1, 'E5'), (17, .5, 'F#5'), (17.5, .5, 'G5'), (18, 1, 'A5'), (19, 1, 'B5'),
        (20, 1, 'A5'), (21, 1, 'F#5'), (22, 2, 'E5'),
        (24, 1, 'D5'), (25, 1, 'F#5'), (26, 1, 'A5'), (27, 1, 'F#5'),
        (28, 1, 'E5'), (29, 1, 'C#5'), (30, 2, 'D5'),
    ], 64)

    mel = A_mel + A2_mel + B_mel
    lead(s, mel, instr='lead', vel=0.62, bell_long=False)
    return s


META = {
    'three_terraces': {
        'name': 'Windmill Terraces',
        'track_gm': {'lead': 74, 'pad': 89, 'bass': 32, 'pluck': 24},
        'reverb': [0.45, 0.3, 0.9, 0.45],
        'gain': 0.8,
        'blurb': 'breezy D-major hill-terraces; a chirpy recorder lilts over a plucked nylon-guitar folk backing, swung and bouncy',
    },
}
