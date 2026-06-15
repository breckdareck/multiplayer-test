from gen_music import *   # Seq, groove, lead, offset_mel, shift_oct, to_prog, nf, ...

# ==========================================================================
# WEAVE — "The Weave's Edge". The frayed edge of reality where magic comes
# undone: ethereal, shimmering, otherworldly, uncanny and BEAUTIFUL. Floating
# and dreamlike with little/no strong beat. Shimmering bell/celesta/crystal +
# an airy pad + a soft voice-like recorder lead. Strange, magical harmony —
# whole-tone / lydian / augmented colors and unresolved suspensions, so it
# sounds not-quite-of-this-world. Big airy reverb. Mysterious, not dark.
# ==========================================================================


# --------------------------------------------------------------------------
# weave — DREAMING AT THE FRAYED EDGE.
# D lydian leaning whole-tone, 66 BPM (no steady beat — drone bass, no perc).
# An airy warm pad floats while a celesta/crystal "drip" shimmers under a soft
# recorder voice. Harmony drifts by whole steps with raised-4th (G#) lydian
# color and augmented suspensions that never quite resolve. 16 bars / ~58s.
# --------------------------------------------------------------------------
def track_weave():
    s = Seq(66)
    s.swing = 0.0
    # D lydian: D E F# G# A B C#. Triads kept open/airy (oct 3) and slid by
    # whole steps so adjacent bars share a shimmering, unresolved quality.
    # Dadd9-ish / Emaj(lydian) / F#m floating / G#dim-aug glow — never a V-I.
    prog = [
        (['D3', 'F#3', 'A3', 'E4'], 'D2'),     # D add9 (open)
        (['E3', 'G#3', 'B3', 'F#4'], 'E2'),    # E (whole step up, bright)
        (['F#3', 'A3', 'C#4', 'G#4'], 'F#2'),  # F#m add9 (drifting)
        (['G#3', 'C4', 'E4'], 'G#2'),          # G# augmented (uncanny glow)
        (['A3', 'C#4', 'E4', 'B4'], 'A2'),     # A add9 (lift)
        (['B3', 'D#4', 'F#4'], 'B2'),          # B (whole-tone color, raised 3rd)
        (['G3', 'B3', 'D4', 'A4'], 'G2'),      # G add9 (softens, no resolve)
        (['E3', 'A3', 'B3', 'F#4'], 'E2'),     # Esus2/sus4 suspension (unresolved)
    ] * 2
    groove(s, prog, bpb=4, bass='drone', comp='drip', perc='none',
           pad=True, pad_mode='swell', pad_vel=0.42, pad_spread=0.20,
           pad_instr='pad', comp_instr='bell', comp_vel=0.32, bass_vel=0.55)
    n = len(prog) * 4  # 64 beats

    # soft sub-octave under each bar — a barely-there floor so it floats, not sinks
    for _b, (_ch, _rt) in enumerate(prog):
        s.n(_b * 4, 4.0, shift_oct(_rt, -1), 'bass', 0.18)

    # shimmering CRYSTAL/celesta glints — bright, brief, panned, far apart so they
    # read as magic catching the light rather than a melody. Whole-tone-ish pitches.
    for (_b, _nt, _v, _p) in [
        (1.5, 'A5', 0.16, -0.32), (6.5, 'C#6', 0.13, 0.30),
        (11.0, 'B5', 0.15, -0.26), (14.5, 'E6', 0.12, 0.34),
        (19.5, 'G#5', 0.15, 0.22), (23.0, 'D6', 0.13, -0.30),
        (27.5, 'F#6', 0.11, 0.28), (30.5, 'B5', 0.14, -0.24),
        (35.5, 'C#6', 0.15, -0.30), (39.0, 'A5', 0.13, 0.32),
        (43.5, 'E6', 0.12, -0.22), (47.0, 'G#5', 0.14, 0.26),
        (51.5, 'D6', 0.13, 0.30), (55.5, 'F#6', 0.11, -0.28),
        (59.0, 'B5', 0.14, 0.24), (62.5, 'C#6', 0.12, -0.30),
    ]:
        s.n(_b, 2.4, _nt, 'glass', _v, pan=_p)

    # the soft VOICE-LIKE lead (recorder) — a long, drifting dreamlike melody that
    # covers the whole loop. Lydian raised-4th (G#) + whole-step leaps + held
    # suspensions; octave 4-5 (one brief 5 peak), never shrill, never resolving hard.
    # Phrase A (bars 1-4), Phrase B (bars 5-8); reuse A then a varied B over the loop.
    weaveA = [
        (1, 3, 'A4'),          # open on the 5th — airy
        (4.5, 2.5, 'B4'),
        (8, 3, 'C#5'),         # lydian climb
        (12, 2, 'G#4'),        # raised-4th color (uncanny)
        (14.5, 1.5, 'A4'),
    ]
    weaveB = [
        (1, 3, 'B4'),
        (4.5, 2.5, 'C#5'),
        (8, 2, 'E5'),          # brief gentle peak, oct 5
        (10.5, 2, 'D5'),
        (13, 3, 'A4'),         # settles back, unresolved
    ]
    weaveB2 = [
        (1, 2.5, 'F#5'),       # one shimmering high entrance (brief)
        (4, 2, 'E5'),
        (7, 3, 'C#5'),
        (11, 2, 'B4'),
        (13.5, 2.5, 'A4'),     # drifts down to a suspended close
    ]
    mel = weaveA + offset_mel(weaveB, 16) + offset_mel(weaveA, 32) + offset_mel(weaveB2, 48)
    lead(s, mel, instr='soft', vel=0.50, bell_long=False)

    # a faint distant choir swell once per half-loop — breath of the unraveling
    # weave behind the recorder, very low velocity so it's atmosphere not melody.
    for (_b, _nt, _v) in [(16, 'A4', 0.16), (48, 'F#4', 0.15)]:
        s.n(_b, 6.0, _nt, 'choir', _v, pan=0.0)

    return s


META = {
    'weave': {'name': "The Weave's Edge",
              'track_gm': {'pad': 89, 'bass': 38, 'bell': 98, 'glass': 98,
                           'soft': 74, 'choir': 52},
              'reverb': [0.92, 0.20, 1.0, 0.78], 'gain': 0.70,
              'blurb': 'shimmering celesta and a soft recorder voice drifting through unraveling lydian magic'},
}
