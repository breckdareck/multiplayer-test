from gen_music import *   # Seq, shift_oct, nf, ...

# A "cave" reads as a cave through ECHO + water + organic low instruments and big
# empty space — not synth pads. These three take that approach (the earlier
# cave2/3/4 were rejected for sounding like ambient pad music, not a cavern).

def _drip(s, beat, note, voice, vel, pan=0.0):
    """A single water-drip: an attack note plus two decaying echoes."""
    s.n(beat, 1.4, note, voice, vel, pan)
    s.n(beat + 0.6, 1.1, note, voice, vel * 0.5, -pan * 0.6)
    s.n(beat + 1.3, 0.9, note, voice, vel * 0.25, pan * 0.4)


def track_cave5():
    # "Dripwater Hollow" — a near-static low string/contrabass drone with irregular
    # echoing water drips (celesta) falling far apart. The silence between is the song.
    s = Seq(66)
    s.loop_beats = 64
    drone = [('D2', 'D3', 'A3'), ('Bb1', 'Bb2', 'F3'),
             ('A1', 'A2', 'E3'), ('D2', 'D3', 'F3')]
    for i, (lo, mid, hi) in enumerate(drone):
        b = i * 16
        s.n(b, 16.5, lo, 'bass', 0.46)
        s.n(b, 16.5, mid, 'viol', 0.34, pan=-0.2)
        s.n(b, 16.5, hi, 'viol', 0.30, pan=0.2)
    drips = [(2, 'A5'), (7.5, 'D5'), (11, 'F5'), (15.5, 'E5'), (20, 'A5'),
             (25.5, 'Bb5'), (30, 'D6'), (34.5, 'F5'), (39, 'A5'), (44.5, 'E5'),
             (49, 'D5'), (54.5, 'F5'), (59, 'A5'), (62, 'C6')]
    for (b, nm) in drips:
        _drip(s, b, nm, 'glass', 0.30, pan=(-0.25 if int(b) % 2 else 0.25))
    for b in (0, 24, 48):
        s.p(b, 'tom', 0.55)
    return s


def track_cave6():
    # "The Deep Below" — oppressive and sub-heavy. A near-subliminal sweep-pad sub
    # drone, a low cello that slowly "breathes" between the tonic and its b2 (dread),
    # and a few distant, echoing booms. Maximum emptiness.
    s = Seq(58)
    s.loop_beats = 64
    for b in range(0, 64, 16):
        s.n(b, 16.5, 'C1', 'subdrone', 0.6)
        s.n(b, 16.5, 'G1', 'subdrone', 0.32)
    breaths = [(0, 'C3'), (12, 'Db3'), (20, 'C3'), (30, 'Eb3'),
               (40, 'C3'), (50, 'Db3'), (58, 'C3')]
    for k, (b, nm) in enumerate(breaths):
        s.n(b, 7.0, nm, 'viol', 0.26, pan=(-0.15 if k % 2 else 0.15))
    for b in (4, 28, 52):
        s.p(b, 'tom', 0.5)
        s.p(b + 1.5, 'tom', 0.22)
    return s


def track_cave7():
    # "Lost Passage" — a faint, lonely bassoon melody wandering in long notes with
    # big gaps and a soft echo on each phrase (calling into the dark), over an open
    # low drone and a few sparse drips. A sense of being lost underground.
    s = Seq(70)
    s.loop_beats = 64
    for (b, d, nm) in [(0, 24.5, 'A1'), (24, 16.5, 'F1'), (40, 16.5, 'A1'), (56, 8.5, 'E1')]:
        s.n(b, d, nm, 'bass', 0.28)
        s.n(b, d, shift_oct(nm, 1), 'viol', 0.15, pan=-0.15)
    mel = [(3, 5, 'A4'), (14, 4, 'Bb4'), (22, 6, 'C5'), (33, 4, 'A4'),
           (41, 5, 'E4'), (52, 4, 'F4'), (60, 3, 'A4')]
    for (b, d, nm) in mel:
        s.n(b, d, nm, 'hollow', 0.34)
        s.n(b + d * 0.5, d * 0.6, nm, 'hollow', 0.13, pan=0.25)
    for (b, nm) in [(9, 'E5'), (28, 'A5'), (47, 'C5')]:
        _drip(s, b, nm, 'glass', 0.13)
    return s


META = {
    'cave5': {'name': 'Dripwater Hollow', 'track_gm': {'bass': 43, 'viol': 49, 'glass': 8},
              'reverb': [0.95, 0.10, 1.0, 0.92], 'gain': 0.92,
              'blurb': 'low drone + echoing water drips, vast and still'},
    'cave6': {'name': 'The Deep Below', 'track_gm': {'subdrone': 95, 'viol': 42},
              'reverb': [0.97, 0.10, 1.0, 0.95], 'gain': 0.84,
              'blurb': 'sub-heavy dread, a breathing low cello, distant booms'},
    'cave7': {'name': 'Lost Passage', 'track_gm': {'bass': 43, 'viol': 49, 'hollow': 70, 'glass': 8},
              'reverb': [0.93, 0.12, 1.0, 0.90], 'gain': 0.80,
              'blurb': 'a lonely echoing bassoon wandering an open drone'},
}
