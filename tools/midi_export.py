#!/usr/bin/env python3
"""Export a gen_music Seq to a Standard MIDI File so it can be rendered through a
soundfont (real instrument samples) instead of the raw-oscillator synth.

Reuses every composition in gen_music.py (chords/bass/comp/drums/melody); only the
SOUND changes — each voice is mapped to a General-MIDI program, per-track-overridable
so each track plays genuinely different real instruments.

    python tools/midi_export.py <track>|all   ->  ../../_music_tools/emberwilds_<track>.mid
Then render with: fluidsynth -ni -F out.wav soundfont.sf2 emberwilds_<track>.mid
"""
import sys, struct, math, os
import gen_music as G

PPQ = 480

# my voice name -> default General-MIDI program (0-indexed)
VOICE_GM = {
    'pad': 48,      # String Ensemble 1
    'bass': 32,     # Acoustic Bass
    'pluck': 24,    # Nylon Guitar
    'lead': 80,     # Lead 1 (square)
    'soft': 73,     # Flute
    'bell': 10,     # Music Box
    'glass': 8,     # Celesta
    'viol': 40,     # Violin
    'hollow': 75,   # Pan Flute
    'choir': 52,    # Choir Aahs
    'organ': 19,    # Church Organ
    'darkpad': 89,  # Pad 2 (warm)
    'subdrone': 95, # Pad 8 (sweep) — deep ominous drone
}

# per-track overrides so the same voice can be a different real instrument per track
TRACK_GM = {
    'title':    {'lead': 0,  'pad': 48, 'pluck': 25, 'bass': 32, 'bell': 9},   # piano, strings, steel guitar, glockenspiel
    'mainmenu': {'soft': 11, 'pad': 89, 'bell': 46,  'bass': 32},              # vibraphone, WARM pad, harp (low/mellow, not religious)
    'field':    {'lead': 60, 'pad': 61, 'pluck': 45, 'bass': 33, 'bell': 9},   # french horn, BRASS stabs, pizzicato, fingered bass
    'town':     {'soft': 73, 'pad': 88, 'bell': 24,  'bass': 32},              # flute, new-age pad, nylon -> the cozy settlement tune
    'ruins':    {'viol': 42, 'darkpad': 92, 'glass': 46, 'bass': 43},          # solo CELLO, bowed pad, harp glints, contrabass toll
    'boss':     {'lead': 29, 'pad': 50, 'pluck': 61, 'bass': 38, 'bell': 9},   # overdriven guitar, synth strings, brass, synth bass
    'cave':     {'hollow': 79,'glass': 98,'bass': 43, 'subdrone': 95, 'darkpad': 92},  # ocarina, crystal glints, contrabass, sweep drone, dark bowed pad
    'forest':   {'soft': 75, 'pad': 48, 'bell': 46, 'bass': 32},               # pan flute, strings, harp -> open-air woodland
    # --- alternate boss themes ---
    'boss2':    {'lead': 30, 'pad': 62, 'pluck': 61, 'bass': 39},               # distortion guitar march, synth-brass pad, brass stabs, synth bass2
    'boss3':    {'viol': 48, 'organ': 19, 'bass': 43},                          # sweeping strings over church organ, contrabass (gothic waltz)
    'boss4':    {'lead': 62, 'pad': 50, 'bass': 38},                            # low synth-brass riff, pulsing synth strings, synth bass1 (doom)
    'boss5':    {'lead': 81, 'pad': 50, 'pluck': 80, 'bass': 38},               # saw lead, synth strings, square arp, synth bass1 (synthwave)
    'boss6':    {'lead': 61, 'pad': 49, 'pluck': 52, 'bass': 43},               # brass section lead, strings, choir stabs, contrabass (epic)
}

PERC_GM = {'kick': 36, 'snare': 38, 'hat': 42, 'shaker': 82, 'tom': 41}


def freq_to_midi(f):
    return max(0, min(127, int(round(69 + 12 * math.log2(f / 440.0)))))


def _vlq(n):
    out = [n & 0x7F]
    n >>= 7
    while n:
        out.insert(0, (n & 0x7F) | 0x80)
        n >>= 7
    return bytes(out)


def write_midi(seq, path, gm):
    bpm = 60.0 / seq.spb
    voices = []
    for (_, _, _, instr, _, _) in seq.notes:
        if instr not in voices:
            voices.append(instr)
    chans = [c for c in range(16) if c != 9]
    vmap = {v: chans[i] for i, v in enumerate(voices)}

    ev = []  # (tick, order, bytes) — order keeps note-offs before note-ons at a tick
    mpqn = int(round(60000000.0 / bpm))
    ev.append((0, 0, b'\xFF\x51\x03' + struct.pack('>I', mpqn)[1:]))
    for v, ch in vmap.items():
        ev.append((0, 1, bytes([0xC0 | ch, gm.get(v, VOICE_GM.get(v, 0)) & 0x7F])))
    ev.append((0, 1, bytes([0xC0 | 9, 0])))

    for (s, d, f, instr, vel, pan) in seq.notes:
        ch = vmap[instr]
        on = int(round((s / seq.spb) * PPQ))
        off = max(on + 1, int(round(((s + d) / seq.spb) * PPQ)))
        note = freq_to_midi(f)
        mv = max(1, min(127, int(round(vel * 118))))
        ev.append((on, 3, bytes([0x90 | ch, note, mv])))
        ev.append((off, 2, bytes([0x80 | ch, note, 0])))

    for (s, kind, vel, pan) in seq.perc:
        on = int(round((s / seq.spb) * PPQ))
        off = on + PPQ // 8
        note = PERC_GM.get(kind, 38)
        mv = max(1, min(127, int(round(vel * 118))))
        ev.append((on, 3, bytes([0x99, note, mv])))
        ev.append((off, 2, bytes([0x89, note, 0])))

    ev.sort(key=lambda e: (e[0], e[1]))
    track = b''
    last = 0
    for tick, _, data in ev:
        track += _vlq(tick - last) + data
        last = tick
    track += b'\x00\xFF\x2F\x00'
    header = b'MThd' + struct.pack('>IHHH', 6, 0, 1, PPQ)
    trk = b'MTrk' + struct.pack('>I', len(track)) + track
    with open(path, 'wb') as fh:
        fh.write(header + trk)


def main():
    which = sys.argv[1] if len(sys.argv) > 1 else 'mainmenu'
    out_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '_music_tools'))
    os.makedirs(out_dir, exist_ok=True)
    names = list(G.TRACKS) if which == 'all' else [which]
    for n in names:
        seq = G.TRACKS[n]()
        gm = dict(VOICE_GM)
        gm.update(TRACK_GM.get(n, {}))
        p = os.path.join(out_dir, 'emberwilds_%s.mid' % n)
        write_midi(seq, p, gm)
        print('wrote', p)


if __name__ == '__main__':
    main()
