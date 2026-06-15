from gen_music import *   # Seq, groove, lead, offset_mel, shift_oct, to_prog, nf, ...

# NEAR-WILDS — "The Near-Wilds". The first frontier just beyond the safe starting
# town: open grassland at the edge of the known world. Mostly bright and inviting
# (you're exploring!), but a faint thread of wariness because you've left safety.
#
# G MAJOR, medium 104 BPM, gentle forward motion (a walking pace, not a march).
# A flute lead (track_gm soft->73) sings over a warm string pad (pad->48), a light
# broken HARP (comp bell->46) that flows like wind over grass, and a soft WALKING
# BASS (32) that keeps stepping forward. Soft brushed perc only — never martial.
# The wariness comes from leaning on vi (Em) and ii (Am) inside the major: it glows,
# but it glances over its shoulder. Lead stays octave 4-5, brief 5 peaks, never shrill.
#
# Loop = 24 bars * 4 beats = 96 beats @ 104 BPM ~= 55.4s. Three 8-bar sections
# (A, A', B) and the flute melody covers every bar.


def track_near_wilds():
    s = Seq(104)
    s.swing = 0.05                     # the faintest lilt so the walk isn't stiff

    # A — open and inviting: I - V - vi - IV motion, the classic "setting out" arc,
    # but resolving through Em (vi) so there's a wistful glance back at the town.
    A = [
        (['G3', 'B3', 'D4'],  'G2'), (['D4', 'F#4', 'A4'], 'D3'),
        (['E3', 'G3', 'B3'],  'E2'), (['C4', 'E4', 'G4'],  'C3'),
        (['G3', 'B3', 'D4'],  'G2'), (['D4', 'F#4', 'A4'], 'D3'),
        (['A3', 'C4', 'E4'],  'A2'), (['D4', 'F#4', 'A4'], 'D3'),
    ]
    # B — the "thread of wariness" lifts a little: pivots to Em/Am (the frontier feels
    # bigger and less certain here) before walking home to G. Still hopeful, not dark.
    B = [
        (['E3', 'G3', 'B3'],  'E2'), (['C4', 'E4', 'G4'],  'C3'),
        (['A3', 'C4', 'E4'],  'A2'), (['B3', 'D4', 'F#4'], 'B2'),
        (['C4', 'E4', 'G4'],  'C3'), (['G3', 'B3', 'D4'],  'G2'),
        (['A3', 'C4', 'E4'],  'A2'), (['D4', 'F#4', 'A4'], 'D3'),
    ]
    prog = A + A + B
    groove(s, prog, bpb=4, bass='walk', comp='broken', perc='soft',
           pad_vel=0.6, comp_instr='bell', comp_vel=0.34, pad_spread=0.2, pad_mode='low')

    # A-section flute (bars 0-7). Long inviting phrases, stepwise with gentle leaps;
    # tops out at D5/E5, never higher — bright but soft.
    mel = [
        (0, 1.5, 'D5'), (1.5, .5, 'B4'), (2, 1, 'D5'), (3, 1, 'E5'),
        (4, 1, 'D5'), (5, 1, 'B4'), (6, 2, 'G4'),
        (8, 1, 'A4'), (9, 1, 'B4'), (10, 1.5, 'D5'), (11.5, .5, 'C5'),
        (12, 1, 'B4'), (13, 1, 'A4'), (14, 2, 'B4'),
        (16, 1, 'D5'), (17, 1, 'E5'), (18, 1.5, 'D5'), (19.5, .5, 'B4'),
        (20, 1, 'C5'), (21, 1, 'A4'), (22, 2, 'G4'),
        (24, 1, 'A4'), (25, 1, 'C5'), (26, 1, 'B4'), (27, 1, 'A4'),
        (28, 1, 'F#4'), (29, 1, 'A4'), (30, 2, 'D5'),
    ]
    # A' — reuse the phrase a step higher in places, with a small variation lift so the
    # second pass feels like walking further out (offset to bars 8-15 of the 96-beat loop).
    mel = mel + offset_mel([
        (0, 1.5, 'G5'), (1.5, .5, 'E5'), (2, 1, 'D5'), (3, 1, 'B4'),
        (4, 1, 'D5'), (5, 1, 'E5'), (6, 2, 'D5'),
        (8, 1, 'B4'), (9, 1, 'D5'), (10, 1.5, 'E5'), (11.5, .5, 'D5'),
        (12, 1, 'B4'), (13, 1, 'A4'), (14, 2, 'G4'),
        (16, 1, 'A4'), (17, 1, 'B4'), (18, 1.5, 'D5'), (19.5, .5, 'E5'),
        (20, 1, 'D5'), (21, 1, 'B4'), (22, 2, 'C5'),
        (24, 1, 'B4'), (25, 1, 'A4'), (26, 1, 'G4'), (27, 1, 'A4'),
        (28, 1, 'B4'), (29, 1, 'D5'), (30, 2, 'A4'),
    ], 32)
    # B — the wary, wider phrase (bars 16-23). More minor color (E/A roots), a single
    # brief E5 peak as the horizon opens, then walks back down to a settled G.
    mel = mel + offset_mel([
        (0, 1, 'E5'), (1, 1, 'D5'), (2, 1.5, 'B4'), (3.5, .5, 'D5'),
        (4, 1, 'E5'), (5, 1, 'D5'), (6, 2, 'B4'),
        (8, 1, 'A4'), (9, 1, 'C5'), (10, 1.5, 'B4'), (11.5, .5, 'A4'),
        (12, 1, 'F#4'), (13, 1, 'A4'), (14, 2, 'B4'),
        (16, 1, 'C5'), (17, 1, 'E5'), (18, 1.5, 'D5'), (19.5, .5, 'B4'),
        (20, 1, 'G4'), (21, 1, 'D5'), (22, 2, 'B4'),
        (24, 1, 'A4'), (25, 1, 'B4'), (26, 1, 'C5'), (27, 1, 'A4'),
        (28, 1, 'B4'), (29, 1, 'A4'), (30, 2, 'G4'),
    ], 64)
    lead(s, mel, instr='soft', vel=0.6, bell_long=False)
    return s


META = {
    'near_wilds': {'name': 'The Near-Wilds',
                   'track_gm': {'soft': 73, 'pad': 48, 'bass': 32, 'bell': 46},
                   'reverb': [0.5, 0.3, 0.9, 0.5], 'gain': 0.78,
                   'blurb': 'bright-but-wary G-major frontier; a gentle flute walks over warm strings, light harp and a soft walking bass'},
}
