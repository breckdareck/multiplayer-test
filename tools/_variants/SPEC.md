# Music variant composition spec

You are composing **alternate variants** of one background-music track for a Godot
RPG. The music engine is `tools/gen_music.py`. Tracks are rendered to real
instruments later via a soundfont, so the **General-MIDI program number** you pick
per voice is what determines the actual timbre.

Everything you write is an **ORIGINAL composition** — your own melodies and chord
progressions. Do NOT transcribe any existing/copyrighted tune.

## What to produce

Write the file `tools/_variants/<song>.py` (your song name is in your task). It must
look EXACTLY like this shape:

```python
from gen_music import *   # Seq, groove, lead, offset_mel, shift_oct, to_prog, nf, ...

def track_<song>2():
    s = Seq(<bpm>)
    s.swing = 0.0                      # 0..0.16; affects 8th-note feel
    prog = [ (<chord notes>, <root>), ... ]
    groove(s, prog, bpb=4, bass='...', comp='...', perc='...',
           pad_vel=0.7, comp_instr='...', comp_vel=0.45, pad_instr='pad', pad_mode='...')
    mel = [ (beat, dur, 'note'), ... ]
    mel = mel + offset_mel([ ... ], <beats>)   # optional, to cover later bars
    lead(s, mel, instr='...', vel=0.62, bell_long=False)
    return s

def track_<song>3():
    ...
    return s

def track_<song>4():
    ...
    return s

META = {
    '<song>2': {'name': 'Short Name', 'track_gm': {'lead': 73, 'pad': 48, 'bass': 32, ...},
                'reverb': [0.5, 0.3, 0.9, 0.5], 'gain': 0.8, 'blurb': 'one line of feel'},
    '<song>3': {...},
    '<song>4': {...},
}
```

- Function names are `track_<song>2`, `track_<song>3`, `track_<song>4` (your song name,
  suffixes 2/3/4). `META` keys are `'<song>2'` etc.
- `track_gm` MUST give a GM program (int) for **every voice slot you actually use** —
  always include `'bass'`; plus your `pad_instr`, your `comp_instr`, your `lead` instr,
  and any voice in manual `s.n(...)` calls. (If you use `comp='drip'`, also map `'bell'`.)

## The composition API (these are imported; do NOT redefine them)

- `Seq(bpm)` → sequencer. Set `s.swing` (0..~0.16). (Ignore `s.rev_amount/rev_size/tone`;
  reverb is set per-variant by your `reverb` field, not in the function.)
- `prog = [(chord, root), ...]` where `chord` is a list of note names (the held harmony,
  usually octave 2–4) and `root` is the bass note name (e.g. `'C2'`). The loop length =
  `len(prog) * bpb` beats. groove sets it automatically.
- `groove(s, prog, bpb=4, bass='half', comp='arp', perc='backbeat', pad_vel=0.7,
   pad_spread=0.16, comp_instr='pluck', comp_vel=0.5, comp_lift=1, bass_vel=0.8,
   pad=True, pad_instr='pad', pad_mode='block')` — realizes the backing.
  - `bass` ∈ `drone, half, quarter, eighth, sync, walk, toll, creep`
  - `comp` ∈ `arp, arp_slow, stab, roll, broken, drip, none`
  - `perc` ∈ `heartbeat, soft, backbeat, shaker, drive, ritual, none`
  - `pad_mode` ∈ `none, low, stab, half, pulse, swell, block`
  - set `pad=False` to omit the held pad entirely; `comp='none'`/`perc='none'` likewise.
- `lead(s, mel, instr='lead', vel=0.7, bell_long=False)` where `mel = [(beat, dur, 'note'), ...]`.
  Use `bell_long=False` unless you want long notes doubled by a bell.
- `offset_mel(mel, beats)` → shifts a melody's beats (reuse a phrase later in the loop).
- `shift_oct('A4', -1)` → `'A3'`. `s.n(beat, dur, 'note', voice, vel, pan)` for manual notes.
  `s.p(beat, kind, vel, pan)` for manual drums; `kind` ∈ `kick, snare, hat, shaker, tom`.
- Voice slots you may use (each needs a `track_gm` entry): `lead, pad, bass, pluck, bell,
  soft, glass, viol, hollow, organ, choir, darkpad, subdrone`. (They're just labels; the
  SOUND comes from `track_gm`.)
- Note names: `Letter[#/b]octave`, e.g. `'C4'`, `'F#5'`, `'Bb3'`, `'E2'`. Chords ~oct 2–4,
  melodies ~oct 4–6.

## GM program palette (0-indexed; pick to fit the mood)

Piano 0 · Glockenspiel 9 · Music Box 10 · Vibraphone 11 · Marimba 12 · Church Organ 19 ·
Accordion 21 · Nylon Guitar 24 · Steel Guitar 25 · Overdrive Gtr 29 · Distortion Gtr 30 ·
Acoustic Bass 32 · Fingered Bass 33 · Synth Bass1 38 · Synth Bass2 39 · Violin 40 ·
Cello 42 · Contrabass 43 · Pizzicato 45 · Harp 46 · Strings Ens1 48 · Strings Ens2 49 ·
Synth Strings 50 · Choir Aahs 52 · Voice Oohs 53 · French Horn 60 · Brass Section 61 ·
Synth Brass 62 · Oboe 68 · English Horn 69 · Bassoon 70 · Clarinet 71 · Flute 73 ·
Recorder 74 · Pan Flute 75 · Ocarina 79 · Square Lead 80 · Saw Lead 81 · New-age Pad 88 ·
Warm Pad 89 · Bowed Pad 92 · Sweep Pad 95 · Crystal 98.

## reverb / gain

`reverb` = `[room_size, damp, width, level]`, each 0..1.
- dry / close (combat, cozy): `[0.15, 0.6, 0.7, 0.25]`
- medium room: `[0.4, 0.35, 0.85, 0.45]`
- big hall / open: `[0.6, 0.25, 0.95, 0.6]`
- cavernous: `[0.95, 0.12, 1.0, 0.95]`
`gain` ~ 0.7–0.85 (quieter/sparser tracks lower).

## Quality bar

1. **Three DISTINCT variants** — different enough from each other AND from the current
   version (you'll be told its key/tempo/instruments). Vary key, tempo, lead instrument,
   groove, and mood — but all three must still fit the track's ROLE.
2. **Melody covers the whole loop** — don't leave late bars empty. Either write the melody
   across all bars, or write a main phrase and reuse it with `offset_mel`. Loop length in
   seconds = `len(prog) * bpb * 60 / bpm`; aim **~45–60 s** (so pick enough bars).
3. **Not shrill** — keep leads mostly octave 4–5; reach octave-6 peaks only briefly.
4. Make them sound intentional and musical, not random. Use a clear chord progression.

## Verify before you finish (REQUIRED)

From the repo's `tools` dir, run and make sure it prints `construct OK`:

```
python -c "import sys; sys.path.insert(0,'_variants'); import importlib; m=importlib.import_module('<song>'); [getattr(m,'track_'+k)() for k in m.META]; print('construct OK', list(m.META))"
```

Fix any errors (bad note name, unknown groove token, missing voice in track_gm) until it
passes. Then you're done — report the 3 variant names + one-line feels.
