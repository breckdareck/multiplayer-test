from gen_music import *   # Seq, groove, lead, offset_mel, shift_oct, to_prog, nf, ...

# ==========================================================================
# TRACK: The Dust Warren — arid underground desert burrow. DRY, not a wet cave.
# Parched, hollow, lonely, a touch exotic. A reedy double-reed lead (english
# horn) winds an eastern line over a sparse drone and a soft hand-drum (quiet
# tom + shaker, no full kit). Spacious but DRY — modest reverb, sand & silence.
#
# Key: D Phrygian-dominant (D Eb F# G A Bb C) — the b2 (Eb) + raised 3rd (F#)
# give the harmonic-minor / desert color. 80 BPM, 16 bars ~= 48 s loop.
# Lead stays octave 4-5 (reedy, not shrill); brief 5 peaks only.
# ==========================================================================
def track_dust_warren():
    s = Seq(80)
    s.swing = 0.06                     # a faint, dragging lilt — like heat haze
    # Sparse harmony: open root-fifth shells colored by the b2/b6 so the mode
    # reads. Held drone underneath; the chords barely move (parched stillness).
    prog = [
        (['D3', 'A3', 'D4'],  'D2'),  (['Eb3', 'A3', 'C4'], 'D2'),   # i  -> bII shimmer over D pedal
        (['D3', 'F#3', 'A3'], 'D2'),  (['Bb2', 'D3', 'F3'], 'Bb2'),  # I(maj3) -> bVI
        (['D3', 'A3', 'D4'],  'D2'),  (['G3', 'Bb3', 'D4'], 'G2'),   # i -> iv
        (['Eb3', 'G3', 'C4'], 'C2'),  (['D3', 'A3', 'D4'],  'D2'),   # bII/C -> i
        (['D3', 'A3', 'D4'],  'D2'),  (['Eb3', 'A3', 'C4'], 'D2'),
        (['D3', 'F#3', 'A3'], 'D2'),  (['Bb2', 'D3', 'F3'], 'Bb2'),
        (['G3', 'Bb3', 'D4'], 'G2'),  (['A2', 'C#3', 'E3'], 'A2'),   # iv -> V(maj3) tension
        (['Bb2', 'D3', 'F3'], 'Bb2'), (['D3', 'A3', 'D4'],  'D2'),   # bVI -> home
    ]
    # Drone bass + held low pad wash + NO comp arpeggio + soft ritual hand-drum.
    # darkpad/hollow give the dry, breathy, hollow body. perc='ritual' = one tom
    # per bar; we lay extra shaker/tom by hand below for the hand-drum feel.
    groove(s, prog, bpb=4, bass='drone', comp='none', perc='ritual',
           pad=True, pad_mode='low', pad_vel=0.30, pad_instr='darkpad', pad_spread=0.10,
           bass_vel=0.55)

    n = len(prog) * 4   # 64 beats

    # Soft hand-drum bed: a quiet tom on 1, a hand-shaken pulse on the off-beats,
    # an answering tom on the "and" of 3. Loose and low — sand, not a kit.
    for b0 in range(0, n, 4):
        s.p(b0 + 0.0, 'tom', 0.34, pan=-0.10)
        s.p(b0 + 1.5, 'shaker', 0.22, pan=0.18)
        s.p(b0 + 2.5, 'tom', 0.24, pan=0.12)
        s.p(b0 + 3.5, 'shaker', 0.20, pan=-0.16)

    # A low sustained tonic pedal under it all — the warren's dry underground hum.
    for b0 in range(0, n, 8):
        s.n(b0, 8.3, 'D2', 'bass', 0.20, pan=0.0)

    # The reedy double-reed line (english horn via track_gm). Stays in octave 4,
    # touches 5 only at phrase peaks. Lots of breath/silence between phrases.
    # A-phrase (bars 1-8 / beats 0-31).
    mel = [
        (0,   1.5, 'D4'),  (1.5, 0.5, 'Eb4'), (2,   2,  'F#4'),            # rise off the b2
        (4,   1,   'A4'),  (5,   1,   'G4'),  (6,   2,  'F#4'),            # settle on the maj3
        (8,   1,   'A4'),  (9,   1,   'Bb4'), (10,  1.5,'A4'),  (11.5,.5,'G4'),
        (12,  1.5, 'F#4'), (13.5,.5,  'Eb4'), (14,  2,  'D4'),            # fall home (b2 lean)
        (16,  1,   'F4'),  (17,  1,   'G4'),  (18,  2,  'Bb4'),           # bVI color, breathy
        (20,  1,   'A4'),  (21,  1,   'G4'),  (22,  2,  'F#4'),
        (24,  1.5, 'G4'),  (25.5,.5,  'A4'),  (26,  1.5,'C5'),  (27.5,.5,'Bb4'),  # brief oct-5 reach
        (28,  1,   'A4'),  (29,  1,   'G4'),  (30,  2,  'D4'),            # come to rest
    ]
    # B-phrase (bars 9-16 / beats 32-63) — same shape, lifted and elaborated,
    # then a long lonely descent so the late bars are never empty.
    mel = mel + offset_mel([
        (0,   1.5, 'A4'),  (1.5, 0.5, 'Bb4'), (2,   2,  'C5'),            # higher answer, brief 5
        (4,   1,   'Bb4'), (5,   1,   'A4'),  (6,   2,  'F#4'),
        (8,   1,   'A4'),  (9,   1,   'G4'),  (10,  1.5,'F#4'), (11.5,.5,'Eb4'),
        (12,  1.5, 'D4'),  (13.5,.5,  'F4'),  (14,  2,  'G4'),            # wandering
        (16,  1,   'Bb4'), (17,  1,   'A4'),  (18,  2,  'G4'),            # bVI -> down
        (20,  1.5, 'F#4'), (21.5,.5,  'G4'),  (22,  2,  'A4'),            # V tension (C#3/E3 under)
        (24,  1,   'G4'),  (25,  1,   'F4'),  (26,  1.5,'Eb4'), (27.5,.5,'F4'),  # bVI / b2 sigh
        (28,  1,   'D4'),  (29,  1,   'Eb4'), (30,  2,  'D4'),            # exhale to the tonic
    ], 32)

    lead(s, mel, instr='hollow', vel=0.50, bell_long=False)
    return s


META = {
    'dust_warren': {
        'name': 'The Dust Warren',
        # english horn lead (69), warm pad (89), acoustic bass (32) drone, soft
        # tom/shaker handled by the perc engine.
        'track_gm': {'lead': 69, 'hollow': 69, 'pad': 89, 'darkpad': 89, 'bass': 32},
        # modest, DRY room — spacious but NOT a cavern.
        'reverb': [0.34, 0.42, 0.78, 0.34],
        'gain': 0.74,
        'blurb': 'A lonely reed winds through a dry, sand-hushed desert burrow.',
    },
}
