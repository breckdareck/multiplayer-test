#!/usr/bin/env python3
"""Render gen_music tracks through FluidSynth + a soundfont (real instruments).

Centralizes the soundfont render: MIDI export (instrument map in midi_export.py)
+ a DISTINCT reverb space per track (so each track sounds like its own room/place)
+ per-track gain. Reusable for the final in-game integration.

    python tools/render_sf.py <track>|all   ->  ../../_music_tools/emberwilds_<track>.wav
"""
import sys, os, subprocess
import gen_music as G
import midi_export

_TOOLS = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '_music_tools'))
FS = os.path.join(_TOOLS, 'fluidsynth', 'bin', 'fluidsynth.exe')
SF = os.path.join(_TOOLS, 'gusgs.sf2')

# per-track reverb: (room-size, damp, width, level) — deliberately spread wide so
# every track occupies a different acoustic space.
TRACK_REVERB = {
    'title':    (0.60, 0.35, 0.85, 0.55),   # warm hall
    'mainmenu': (0.82, 0.15, 1.00, 0.78),   # big airy hall
    'field':    (0.18, 0.50, 0.60, 0.28),   # tight / dry / outdoor
    'town':     (0.30, 0.68, 0.55, 0.38),   # small cozy room (dark, dry)
    'ruins':    (0.55, 0.32, 0.85, 0.50),   # weathered stone, spacious but intimate
    'boss':     (0.10, 0.78, 0.70, 0.20),   # very dry, punchy, in-your-face
    'cave':     (0.97, 0.12, 1.00, 0.98),   # huge dark cavern
    'forest':   (0.50, 0.10, 1.00, 0.55),   # bright open air
    'boss2':    (0.14, 0.60, 0.70, 0.22),   # dry, punchy march
    'boss3':    (0.55, 0.30, 0.95, 0.55),   # gothic hall (waltz)
    'boss4':    (0.16, 0.55, 0.70, 0.24),   # heavy, close, dry (doom)
    'boss5':    (0.26, 0.40, 0.85, 0.36),   # synth space
    'boss6':    (0.55, 0.25, 1.00, 0.60),   # epic hall
}
GAIN = {'field': 0.72, 'boss': 0.70, 'ruins': 0.82, 'cave': 0.80,
        'boss2': 0.70, 'boss3': 0.74, 'boss4': 0.70, 'boss5': 0.70, 'boss6': 0.72}  # default 0.8


def render(track):
    os.makedirs(_TOOLS, exist_ok=True)
    seq = G.TRACKS[track]()
    gm = dict(midi_export.VOICE_GM)
    gm.update(midi_export.TRACK_GM.get(track, {}))
    mid = os.path.join(_TOOLS, 'emberwilds_%s.mid' % track)
    midi_export.write_midi(seq, mid, gm)
    rs, dp, wd, lv = TRACK_REVERB.get(track, (0.5, 0.3, 0.9, 0.5))
    wav = os.path.join(_TOOLS, 'emberwilds_%s.wav' % track)
    cmd = [FS, '-ni', '-g', str(GAIN.get(track, 0.8)), '-r', '44100',
           '-o', 'synth.reverb.room-size=%s' % rs, '-o', 'synth.reverb.damp=%s' % dp,
           '-o', 'synth.reverb.width=%s' % wd, '-o', 'synth.reverb.level=%s' % lv,
           '-F', wav, SF, mid]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print('rendered', track)


def main():
    which = sys.argv[1] if len(sys.argv) > 1 else 'all'
    names = list(G.TRACKS) if which == 'all' else [which]
    for n in names:
        render(n)


if __name__ == '__main__':
    main()
