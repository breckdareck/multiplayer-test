#!/usr/bin/env python3
"""Render the alternate track variants in tools/_variants/<song>.py through
FluidSynth + the soundfont, same pipeline as render_sf.py but pulling the
per-variant instrument map / reverb / gain from each module's META dict.

    python tools/render_variants.py [all|<variant-id>]   ->  ../../_music_tools/emberwilds_<id>.wav
"""
import sys, os, subprocess, importlib

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '_variants'))
import gen_music as G
import midi_export

SONGS = ['title', 'mainmenu', 'field', 'town', 'forest', 'ruins', 'cave', 'cave_new',
         # per-map themes
         'near_wilds', 'ember_meadows', 'three_terraces', 'thornroot',
         'dust_warren', 'keep', 'emberscar', 'weave']
_TOOLS = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '_music_tools'))
FS = os.path.join(_TOOLS, 'fluidsynth', 'bin', 'fluidsynth.exe')
SF = os.path.join(_TOOLS, 'gusgs.sf2')


def collect():
    out = {}  # id -> (func, meta)
    for song in SONGS:
        m = importlib.import_module(song)
        for vid, meta in m.META.items():
            out[vid] = (getattr(m, 'track_' + vid), meta)
    return out


def check(variants):
    ok = True
    for vid, (func, meta) in variants.items():
        try:
            seq = func()
        except Exception as e:
            print('  CONSTRUCT FAIL %-10s %s' % (vid, e)); ok = False; continue
        lb = seq.loop_beats if seq.loop_beats is not None else seq.total_beats()
        voices = {i[3] for i in seq.notes}
        gm = dict(midi_export.VOICE_GM); gm.update(meta.get('track_gm', {}))
        miss = [v for v in voices if v not in gm and v not in meta.get('track_gm', {})]
        flag = ' MISSING-GM:' + str(miss) if miss else ''
        print('  %-10s %4.1fs notes=%4d perc=%3d voices=%s%s' %
              (vid, lb * seq.spb, len(seq.notes), len(seq.perc), sorted(voices), flag))
    return ok


def render(vid, func, meta):
    os.makedirs(_TOOLS, exist_ok=True)
    seq = func()
    gm = dict(midi_export.VOICE_GM); gm.update(meta.get('track_gm', {}))
    mid = os.path.join(_TOOLS, 'emberwilds_%s.mid' % vid)
    midi_export.write_midi(seq, mid, gm)
    rs, dp, wd, lv = meta.get('reverb', [0.5, 0.3, 0.9, 0.5])
    wav = os.path.join(_TOOLS, 'emberwilds_%s.wav' % vid)
    cmd = [FS, '-ni', '-g', str(meta.get('gain', 0.8)), '-r', '44100',
           '-o', 'synth.reverb.room-size=%s' % rs, '-o', 'synth.reverb.damp=%s' % dp,
           '-o', 'synth.reverb.width=%s' % wd, '-o', 'synth.reverb.level=%s' % lv,
           '-F', wav, SF, mid]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print('rendered', vid)


def main():
    which = sys.argv[1] if len(sys.argv) > 1 else 'all'
    variants = collect()
    if which == 'check':
        check(variants); return
    ids = list(variants) if which == 'all' else [which]
    for vid in ids:
        f, meta = variants[vid]
        render(vid, f, meta)


if __name__ == '__main__':
    main()
