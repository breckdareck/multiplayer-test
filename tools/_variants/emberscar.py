from gen_music import *   # Seq, groove, lead, offset_mel, shift_oct, to_prog, nf, ...

# ==========================================================================
# THE EMBER-SCAR (emberscar) — music for a volcanic, scorched scar burned into
# the land. Molten, oppressive, dangerous heat; a place that HURTS to be in.
# Dark C-minor with a phrygian b2 (Db) for menace, very slow (56 BPM) heavy
# smoldering pulse. A brooding low bed (contrabass drone + dark pad), a heavy
# tom heartbeat as the smolder, distant soft-tom "booms" like a far-off
# eruption, and a mournful cello lead winding low over the top (oct 4-5, never
# shrill). Menacing and grand, but the dread of a deadly zone — NOT a fast boss
# chase. Dark and weighty throughout.
# Loop = 14 bars * 4 beats @ 56 BPM = 56 beats = 60.0s.
# ==========================================================================

def track_emberscar():
    s = Seq(56)
    s.swing = 0.0
    # C natural/harmonic minor with a phrygian Db for dread. Roots stay low
    # (oct 1-2) so the bed sits deep and oppressive. Chords held in oct 2-3.
    prog = [
        (['C3', 'Eb3', 'G3'], 'C1'),   # i  — home, smoldering
        (['C3', 'Eb3', 'G3'], 'C1'),   # i  — let it sit and breathe heat
        (['Db3', 'F3', 'Ab3'], 'Db1'), # bII — phrygian dread leans in
        (['Ab2', 'C3', 'Eb3'], 'Ab1'), # bVI — heavy, sinking
        (['C3', 'Eb3', 'G3'], 'C1'),   # i
        (['G2', 'Bb2', 'D3'], 'G1'),   # v  — minor dominant, no lift
        (['Ab2', 'C3', 'Eb3'], 'Ab1'), # bVI
        (['Db3', 'F3', 'Ab3'], 'Db1'), # bII — the menace returns
        (['C3', 'Eb3', 'G3'], 'C1'),   # i
        (['F2', 'Ab2', 'C3'], 'F1'),   # iv — low and grinding
        (['Ab2', 'C3', 'Eb3'], 'Ab1'), # bVI
        (['G2', 'B2', 'D3'], 'G1'),    # V  — harmonic-minor B natural = tension
        (['Ab2', 'C3', 'Eb3'], 'Ab1'), # bVI — sink again
        (['C3', 'Eb3', 'G3', 'D3'], 'C1'),  # i(add9) — unresolved, loops back
    ]
    # Bed: a near-static low contrabass drone, a brooding dark pad held low, and
    # a slow ritual tom on each downbeat = the heavy smoldering pulse. No comp
    # arpeggio — keep it weighty and open, not busy.
    groove(s, prog, bpb=4, bass='drone', comp='none', perc='ritual',
           pad=True, pad_mode='low', pad_vel=0.40, pad_instr='darkpad', pad_spread=0.14)

    # Low brass/string "drone" reinforcement underneath — a sustained sub fifth
    # per bar that thickens the bed into something oppressive and grand.
    for bar, (_chord, root) in enumerate(prog):
        b0 = bar * 4
        s.n(b0, 4.3, shift_oct(root, 1), 'subdrone', 0.30, pan=-0.10)
        s.n(b0, 4.3, root, 'subdrone', 0.22, pan=0.10)

    # Distant eruptions — deep, soft toms far apart, plus a faint echo, like a
    # rumble rolling in from somewhere over the scar.
    for (b, v, pan) in [(3.5, 0.55, -0.2), (15.0, 0.5, 0.22), (27.5, 0.6, -0.18),
                        (39.0, 0.5, 0.2), (51.5, 0.58, -0.2)]:
        s.p(b, 'tom', v, pan)
        s.p(b + 0.9, 'tom', v * 0.4, -pan * 0.7)   # rolling echo

    # Lead: a brooding cello lament, low (oct 4-5), long held tones with heavy
    # sighing falls and big gaps of empty heat between phrases. Leans on the
    # phrygian Db and the Eb minor color. A short octave-5 peak only at the
    # climax, never shrill.
    mel = [
        # Phrase A — the smolder rises and falls back
        (1, 3, 'G4'), (4, 4, 'Eb4'),
        (9, 2, 'C4'), (11, 3, 'Db4'), (14, 1, 'C4'),
        # Phrase B — leaning into the dread
        (16, 3, 'Eb4'), (19, 1, 'F4'), (20, 4, 'G4'),
        (25, 2, 'Ab4'), (27, 3, 'G4'), (30, 1, 'F4'),
        # Phrase C — the climb, a brief lift then sinking
        (32, 2, 'G4'), (34, 2, 'Bb4'), (36, 4, 'C5'),
        (41, 2, 'Bb4'), (43, 1, 'Ab4'), (44, 3, 'G4'), (47, 1, 'F4'),
        # Phrase D — settle back down to the home dread, unresolved
        (48, 3, 'Eb4'), (51, 1, 'Db4'), (52, 4, 'C4'),
        (56 - 1.5, 1.5, 'G3'),  # final low sigh, folds into the loop
    ]
    lead(s, mel, instr='viol', vel=0.50, bell_long=False)

    # A second, even lower cello voice shadows the lead on the long tones (an
    # octave down where it stays warm) — thickens the lament into low brass-like
    # weight without adding brightness.
    for (b, d, nm) in [(4, 4, 'Eb4'), (20, 4, 'G4'), (36, 4, 'C5'), (52, 4, 'C4')]:
        s.n(b, d, shift_oct(nm, -1), 'hollow', 0.20, pan=0.15)

    return s


META = {
    'emberscar': {
        'name': 'The Ember-Scar',
        'track_gm': {'lead': 42, 'viol': 42, 'darkpad': 89, 'bass': 43,
                     'subdrone': 58, 'hollow': 42},
        'reverb': [0.7, 0.22, 0.95, 0.6], 'gain': 0.8,
        'blurb': 'oppressive volcanic dread — a brooding cello over a low brass/string drone, a heavy smoldering tom pulse, and distant eruption booms',
    },
}
