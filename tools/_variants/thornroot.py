from gen_music import *   # Seq, groove, lead, offset_mel, shift_oct, to_prog, nf, ...

# THORNROOT HOLLOW — an overgrown, thorny, shadowed forest hollow. Tangled roots,
# brambles, a woodland gone a bit wrong: mysterious, uneasy, lightly menacing
# (not a boss fight). D AEOLIAN with a creeping b2 (Eb) for the "wrong" color.
# Slow 72 BPM, a creeping low bass + a dark held pad, a sparse harp, and a lonely
# low-clarinet lead that wanders in octave 4-5 with long watchful gaps. Atmosphere
# over melody — the silence between the brambles is part of the song.


def track_thornroot():
    s = Seq(72)
    s.swing = 0.0
    # 16 bars (64 beats ~ 53s at 72 BPM). Dm tonal center; the Eb (b2) and Bb
    # chords are the brambles — they make the wood feel subtly off and watchful.
    A = [
        (['D3', 'F3', 'A3'],  'D2'),   # i
        (['D3', 'F3', 'A3'],  'D2'),   # i (held, breathing)
        (['Bb2', 'D3', 'F3'], 'Bb1'),  # bVI — shadow swells
        (['A2', 'C3', 'E3'],  'A1'),   # v (minor dominant, no leading tone)
        (['D3', 'F3', 'A3'],  'D2'),   # i
        (['Eb3', 'G3', 'Bb3'], 'Eb2'), # bII — the creeping menace (Neapolitan color)
        (['Bb2', 'D3', 'F3'], 'Bb1'),  # bVI
        (['A2', 'C3', 'E3'],  'A1'),   # v
    ]
    B = [
        (['G2', 'Bb2', 'D3'], 'G1'),   # iv
        (['D3', 'F3', 'A3'],  'D2'),   # i
        (['Eb3', 'G3', 'Bb3'], 'Eb2'), # bII
        (['A2', 'C3', 'E3'],  'A1'),   # v
        (['Bb2', 'D3', 'F3'], 'Bb1'),  # bVI
        (['G2', 'Bb2', 'D3'], 'G1'),   # iv
        (['A2', 'C3', 'E3'],  'A1'),   # v
        (['D3', 'F3', 'A3'],  'D2'),   # i — settle back into the hollow
    ]
    prog = A + B

    # creeping bass + a dark held pad (root+fifth) + a sparse, slow harp arp.
    # No drum groove — kept clear so the few manual toms below feel like footfalls.
    groove(s, prog, bpb=4, bass='creep', comp='arp_slow', perc='none',
           pad_vel=0.5, comp_instr='pluck', comp_vel=0.26, pad_spread=0.2,
           pad_instr='darkpad', pad_mode='low')

    # A few distant, irregular low toms — like something moving in the brambles.
    for b in (3.5, 18, 35.5, 50, 61):
        s.p(b, 'tom', 0.34)

    # Lonely low-clarinet lead, octave 4-5, long notes with watchful gaps.
    # First 32 beats (bars 1-8 = A section).
    mel = [
        (1, 3, 'A4'), (4, 2, 'D5'), (7, 2, 'C5'),
        (12, 3, 'Bb4'), (15, 1, 'A4'),
        (16, 4, 'F4'),
        (22, 2, 'Eb5'), (24, 2, 'D5'),
        (28, 3, 'A4'), (31, 1, 'C5'),
    ]
    # Bars 9-16 (B section) — climbs a touch higher, then sinks back to the tonic.
    mel = mel + offset_mel([
        (1, 3, 'D5'), (5, 2, 'F5'), (7, 1, 'Eb5'),
        (10, 3, 'D5'), (13, 2, 'Bb4'),
        (16, 2, 'C5'), (18, 2, 'Eb5'), (20, 2, 'D5'),
        (24, 2, 'A4'), (26, 2, 'C5'),
        (29, 3, 'D4'),
    ], 32)
    lead(s, mel, instr='hollow', vel=0.5, bell_long=False)
    return s


META = {
    'thornroot': {
        'name': 'Thornroot Hollow',
        'track_gm': {'hollow': 71, 'darkpad': 89, 'bass': 43, 'pluck': 46},
        'reverb': [0.62, 0.28, 0.95, 0.55],
        'gain': 0.72,
        'blurb': 'dusky D-minor forest gone wrong; a lonely low clarinet wanders over a creeping bass, dark pad and sparse harp',
    },
}
