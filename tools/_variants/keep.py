from gen_music import *   # Seq, groove, lead, offset_mel, shift_oct, to_prog, nf, ...

# ==========================================================================
# TRACK: The Warded Keep — a fortified stone stronghold held under a protective
# ward. Tense, watchful, martial — but EXPLORATION music, not an active fight.
# Cold halls, a guarded sense of dread, old power. Slightly gothic: this keep
# houses a Dracula/Castlevania-style boss later, so the grandeur is foreshadowed
# (church organ comp + low brass lead) without going full combat.
#
# D harmonic minor / 63 BPM, 4/4. Slow deliberate pulse: a soft tom on the
# downbeats (ritual perc) + a tolling contrabass. French-horn lead (low brass,
# kept oct 4-5, dignified — never shrill) over a cold bowed-pad wash with sparse
# church-organ swells underneath. 16 bars -> ~61s loop, melody across the whole.
# ==========================================================================
def track_keep():
    s = Seq(63)
    # i  -  bVI  -  iv  -  V(harm.min., C# leading tone) ... weathered, watchful
    prog = [
        (['D3', 'F3', 'A3'],  'D2'), (['Bb2', 'D3', 'F3'], 'Bb1'),
        (['G2', 'Bb2', 'D3'], 'G1'), (['A2', 'C#3', 'E3'], 'A1'),
        (['D3', 'F3', 'A3'],  'D2'), (['F3', 'A3', 'C4'],  'F2'),
        (['Bb2', 'D3', 'F3'], 'Bb1'), (['A2', 'C#3', 'E3'], 'A1'),
        (['D3', 'F3', 'A3'],  'D2'), (['G2', 'Bb2', 'D3'], 'G1'),
        (['C3', 'E3', 'G3'],  'C2'), (['F3', 'A3', 'C4'],  'F2'),
        (['Bb2', 'D3', 'F3'], 'Bb1'), (['G2', 'Bb2', 'D3'], 'G1'),
        (['A2', 'C#3', 'E3'], 'A1'), (['D3', 'F3', 'A3'],  'D2'),
    ]
    # tolling low strings (contrabass), cold organ swells underneath the pad
    # (a slow staggered chord 'roll' = a churchy swell), and a soft tom on the
    # downbeats for the deliberate martial pulse.
    groove(s, prog, bpb=4, bass='toll', comp='roll', perc='ritual',
           pad_vel=0.40, pad_spread=0.14, comp_instr='organ', comp_vel=0.20,
           pad=True, pad_instr='darkpad', pad_mode='low')
    # Low-brass processional. Octave 4-5, long dignified phrases that rise and
    # settle — watchful, never frantic. Harmonic-minor C# over the A (dominant)
    # bars gives the slightly gothic lift toward the keep's hidden grandeur.
    mel = [
        (0, 3, 'D5'), (3, 1, 'A4'), (4, 2, 'Bb4'), (6, 2, 'A4'),
        (8, 2, 'D5'), (10, 2, 'F5'), (12, 3, 'E5'), (15, 1, 'C#5'),
        (16, 4, 'D5'), (20, 2, 'A4'), (22, 2, 'C5'),
        (24, 2, 'D5'), (26, 2, 'F5'), (28, 3, 'E5'), (31, 1, 'D5'),
        (32, 3, 'A4'), (35, 1, 'D5'), (36, 2, 'Bb4'), (38, 2, 'G4'),
        (40, 2, 'C5'), (42, 2, 'E5'), (44, 3, 'F5'), (47, 1, 'A5'),
        (48, 4, 'G5'), (52, 2, 'F5'), (54, 2, 'D5'),
        (56, 2, 'E5'), (58, 2, 'C#5'), (60, 4, 'D5'),
    ]
    lead(s, mel, instr='lead', vel=0.54, bell_long=False)
    return s


META = {
    'keep': {
        'name': 'The Warded Keep',
        # lead = French Horn (low brass, dignified); darkpad = cold bowed strings
        # wash; organ = Church Organ swells (gothic foreshadow); bass = Contrabass
        # toll.
        'track_gm': {'lead': 60, 'darkpad': 48, 'organ': 19, 'bass': 43},
        'reverb': [0.6, 0.25, 0.95, 0.6],   # big cold stone hall
        'gain': 0.78,
        'blurb': 'Cold warded stronghold: tolling low strings + church-organ swells under a dignified, watchful low-brass processional — gothic grandeur held in check.',
    },
}
