#!/usr/bin/env python3
"""Generate the ability/combat SFX palette and wire it into the ability .tres.

Zero-dependency (stdlib only) procedural synthesis, mirroring the
generated-pixel-icon pipeline: deterministic output (seeded per sound name),
committed to assets/sounds/generated/, re-runnable any time.

    python tools/gen_ability_sfx.py            # synth WAVs + wire .tres
    python tools/gen_ability_sfx.py --dry-run  # print the ability->sound map only

Wiring: every ability .tres under resources/Abilities/{Sword,Bow,Staff,Dagger}
(excluding Upgrades/) that has an inline ActiveBehaviorData sub-resource gets
its `sfx_path` set (replaced if present, inserted after `script = ...` if not)
to a palette sound chosen by filename keywords. Passives have no
ActiveBehaviorData block and are skipped automatically.

NOTE: a plain HEADLESS run imports the new .wav files and writes their .import
sidecars — e.g. `godot --headless --path . --script res://test/run_tests.gd` or
any headless project load — so no editor pass is needed (the editor would also
re-serialize touched .tres). Commit the .wav AND its generated .import. Use
`--synth-only` to regenerate the palette without re-touching the ability .tres.
"""

import argparse
import math
import os
import random
import re
import struct
import wave

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "sounds", "generated")
RES_PREFIX = "res://assets/sounds/generated/"
ABILITY_DIRS = ["Sword", "Bow", "Staff", "Dagger"]

TAU = 2.0 * math.pi


# ---------------------------------------------------------------------------
# DSP helpers (pure stdlib, sample lists in [-1, 1])
# ---------------------------------------------------------------------------

def silence(dur):
    return [0.0] * int(SR * dur)


def white(rng, dur):
    n = int(SR * dur)
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def sine_sweep(f0, f1, dur, amp=1.0, curve=1.0):
    """Sine whose frequency sweeps f0 -> f1 over dur. curve > 1 biases late."""
    n = int(SR * dur)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        x = (i / max(n - 1, 1)) ** curve
        f = f0 + (f1 - f0) * x
        phase += TAU * f / SR
        out[i] = amp * math.sin(phase)
    return out


def partial(freq, dur, tau_s, amp=1.0, detune=0.0):
    """Exponentially-decaying sine partial (struck metal / glass)."""
    n = int(SR * dur)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        f = freq * (1.0 + detune * (i / max(n - 1, 1)))
        phase += TAU * f / SR
        out[i] = amp * math.exp(-i / (SR * tau_s)) * math.sin(phase)
    return out


def lowpass(x, cutoff):
    alpha = 1.0 - math.exp(-TAU * cutoff / SR)
    y, out = 0.0, [0.0] * len(x)
    for i, s in enumerate(x):
        y += alpha * (s - y)
        out[i] = y
    return out


def highpass(x, cutoff):
    lp = lowpass(x, cutoff)
    return [a - b for a, b in zip(x, lp)]


def bandpass(x, lo, hi):
    return lowpass(highpass(x, lo), hi)


def bandpass_sweep(x, lo0, hi0, lo1, hi1):
    """Bandpass whose band sweeps over the clip (two passes, crossfaded)."""
    a = bandpass(x, lo0, hi0)
    b = bandpass(x, lo1, hi1)
    n = max(len(x) - 1, 1)
    return [a[i] * (1 - i / n) + b[i] * (i / n) for i in range(len(x))]


def env_ad(x, attack_s, tail_tau_s):
    """Linear attack, exponential decay envelope applied in place."""
    n = len(x)
    a = max(int(SR * attack_s), 1)
    out = [0.0] * n
    for i in range(n):
        e = (i / a) if i < a else math.exp(-(i - a) / (SR * tail_tau_s))
        out[i] = x[i] * e
    return out


def fade_out(x, dur_s=0.02):
    n, f = len(x), max(int(SR * dur_s), 1)
    for i in range(max(n - f, 0), n):
        x[i] *= (n - i) / f
    return x


def mix(*clips):
    n = max(len(c) for c in clips)
    out = [0.0] * n
    for c in clips:
        for i, s in enumerate(c):
            out[i] += s
    return out


def delay(x, dur_s):
    return silence(dur_s) + x


def gain(x, g):
    return [s * g for s in x]


def soft_clip(x, drive=1.0):
    return [math.tanh(s * drive) for s in x]


def normalize(x, peak=0.8):
    m = max(abs(s) for s in x) or 1.0
    return [s * peak / m for s in x]


def tremolo(x, rate, depth):
    return [s * (1.0 - depth * 0.5 * (1.0 + math.sin(TAU * rate * i / SR)))
            for i, s in enumerate(x)]


def write_wav(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = b"".join(
            struct.pack("<h", max(-32767, min(32767, int(s * 32767.0))))
            for s in samples)
        w.writeframes(frames)


# ---------------------------------------------------------------------------
# The palette
# ---------------------------------------------------------------------------

def snd_sword_slash(rng):
    whoosh = env_ad(bandpass_sweep(white(rng, 0.20), 1800, 4200, 500, 1400), 0.004, 0.05)
    edge = gain(partial(3400, 0.12, 0.02, detune=-0.1), 0.25)
    return normalize(soft_clip(mix(whoosh, edge), 1.4))


def snd_sword_heavy(rng):
    thump = env_ad(sine_sweep(150, 48, 0.40), 0.002, 0.10)
    ring = mix(partial(1700, 0.45, 0.10, 0.5), partial(2310, 0.45, 0.07, 0.35),
               partial(3140, 0.45, 0.05, 0.22))
    debris = env_ad(lowpass(white(rng, 0.35), 900), 0.01, 0.07)
    return normalize(soft_clip(mix(thump, gain(ring, 0.6), gain(debris, 0.5)), 1.6))


def snd_sword_warcry(rng):
    a = tremolo(sine_sweep(196, 165, 0.34, curve=1.4), 28, 0.35)
    b = tremolo(sine_sweep(294, 248, 0.34, curve=1.4), 28, 0.35)
    breath = env_ad(bandpass(white(rng, 0.34), 600, 2400), 0.03, 0.09)
    body = env_ad(mix(a, gain(b, 0.6)), 0.025, 0.11)
    return normalize(soft_clip(mix(body, gain(breath, 0.35)), 2.2))


def snd_sword_guard(rng):
    shing = mix(partial(4100, 0.32, 0.06), partial(5350, 0.32, 0.05, 0.7),
                partial(6720, 0.32, 0.035, 0.5))
    tick = env_ad(highpass(white(rng, 0.05), 3000), 0.001, 0.012)
    return normalize(mix(gain(shing, 0.8), gain(tick, 0.6)))


def snd_bow_release(rng):
    twang = mix(partial(420, 0.22, 0.035), partial(840, 0.22, 0.02, 0.4),
                partial(1265, 0.22, 0.012, 0.25))
    air = env_ad(bandpass_sweep(white(rng, 0.22), 900, 2600, 2200, 5200), 0.008, 0.05)
    return normalize(soft_clip(mix(twang, gain(air, 0.5)), 1.3))


def snd_bow_snipe(rng):
    twang = mix(partial(300, 0.40, 0.06), partial(600, 0.40, 0.035, 0.5),
                partial(905, 0.40, 0.02, 0.3))
    crack = env_ad(highpass(white(rng, 0.06), 2500), 0.001, 0.014)
    boom = env_ad(sine_sweep(130, 60, 0.30), 0.002, 0.07)
    return normalize(soft_clip(mix(twang, gain(crack, 0.8), gain(boom, 0.7)), 1.4))


def snd_bow_volley(rng):
    shots = []
    for k in range(3):
        f = 420 * (1.0 + 0.08 * (k - 1))
        tw = mix(partial(f, 0.16, 0.03), partial(2 * f, 0.16, 0.016, 0.4))
        air = env_ad(bandpass(white(rng, 0.14), 1200, 4000), 0.006, 0.035)
        shots.append(delay(gain(mix(tw, gain(air, 0.5)), 0.9 - 0.12 * k), 0.075 * k))
    return normalize(soft_clip(mix(*shots), 1.3))


def snd_bow_trap(rng):
    click1 = env_ad(highpass(white(rng, 0.03), 2800), 0.001, 0.008)
    click2 = delay(env_ad(highpass(white(rng, 0.04), 1800), 0.001, 0.010), 0.07)
    clack = delay(env_ad(lowpass(white(rng, 0.10), 700), 0.002, 0.025), 0.10)
    snap = delay(gain(partial(1500, 0.10, 0.015), 0.6), 0.10)
    return normalize(mix(click1, gain(click2, 0.8), clack, snap))


def snd_mark_ping(rng):
    ping = env_ad(sine_sweep(1180, 1770, 0.32, curve=0.6), 0.004, 0.10)
    shimmer = delay(gain(partial(2360, 0.30, 0.08), 0.30), 0.05)
    return normalize(mix(ping, shimmer))


def snd_dash_whoosh(rng):
    woo = env_ad(bandpass_sweep(white(rng, 0.32), 1600, 3800, 240, 800), 0.030, 0.09)
    tone = gain(env_ad(sine_sweep(700, 220, 0.30), 0.03, 0.08), 0.18)
    return normalize(mix(woo, tone))


def snd_staff_fire(rng):
    roar = env_ad(lowpass(white(rng, 0.50), 1300), 0.030, 0.16)
    rumble = env_ad(sine_sweep(95, 55, 0.50), 0.02, 0.16)
    crackle = silence(0.50)
    for _ in range(26):
        p = rng.randint(0, len(crackle) - 200)
        amp = rng.uniform(0.25, 0.8)
        for j in range(rng.randint(40, 160)):
            crackle[p + j] += amp * rng.uniform(-1, 1) * math.exp(-j / 40.0)
    return normalize(soft_clip(mix(roar, gain(rumble, 0.7),
                                   gain(highpass(crackle, 1500), 0.5)), 1.5))


def snd_staff_ice(rng):
    bells = []
    for k in range(7):
        f = rng.uniform(2400, 6200)
        bells.append(delay(gain(partial(f, 0.28, 0.05, detune=-0.04),
                                rng.uniform(0.25, 0.6) * (1.0 - k * 0.08)),
                           0.045 * k))
    air = env_ad(highpass(white(rng, 0.45), 4500), 0.02, 0.10)
    return normalize(mix(gain(air, 0.25), *bells))


def snd_staff_lightning(rng):
    n = int(SR * 0.30)
    buzz, phase = [0.0] * n, 0.0
    f = 1900.0
    for i in range(n):
        if i % 90 == 0:
            f = rng.uniform(1200, 3800)
        phase += TAU * f / SR
        buzz[i] = math.copysign(1.0, math.sin(phase))  # square-ish snarl
    buzz = env_ad(bandpass(buzz, 900, 6000), 0.001, 0.06)
    crack = env_ad(highpass(white(rng, 0.08), 3000), 0.001, 0.018)
    return normalize(soft_clip(mix(gain(buzz, 0.8), crack), 1.7))


def snd_staff_arcane(rng):
    chord = mix(sine_sweep(440, 880, 0.40, 0.6, 0.8),
                sine_sweep(550, 1100, 0.40, 0.42, 0.8),
                sine_sweep(660, 1320, 0.40, 0.3, 0.8))
    chord = env_ad(tremolo(chord, 16, 0.4), 0.02, 0.12)
    sparkle = delay(gain(partial(2640, 0.25, 0.06), 0.2), 0.16)
    return normalize(mix(chord, sparkle))


def snd_staff_buff(rng):
    notes, t0 = [], 0.0
    for f in (523.25, 659.25, 783.99):  # C5 E5 G5
        tone = mix(partial(f, 0.40, 0.12), partial(2 * f, 0.40, 0.06, 0.3))
        notes.append(delay(tone, t0))
        t0 += 0.085
    pad = env_ad(lowpass(white(rng, 0.5), 500), 0.10, 0.14)
    return normalize(mix(gain(pad, 0.12), *notes))


def snd_dagger_stab(rng):
    shink = env_ad(highpass(white(rng, 0.10), 2200), 0.001, 0.022)
    tick = gain(partial(4400, 0.08, 0.012), 0.4)
    return normalize(soft_clip(mix(shink, tick), 1.4))


def snd_dagger_poison(rng):
    hiss = env_ad(bandpass(white(rng, 0.45), 800, 3200), 0.04, 0.13)
    bubbles = silence(0.45)
    for _ in range(7):
        p = rng.randint(int(0.03 * SR), len(bubbles) - int(0.06 * SR))
        f0 = rng.uniform(500, 950)
        blip = env_ad(sine_sweep(f0, f0 * 0.55, 0.05, 0.7), 0.004, 0.012)
        for j, s in enumerate(blip):
            bubbles[p + j] += s
    return normalize(mix(gain(hiss, 0.6), bubbles))


def snd_dagger_stealth(rng):
    woo = env_ad(bandpass_sweep(white(rng, 0.42), 1900, 3300, 220, 650), 0.07, 0.12)
    breath = gain(env_ad(sine_sweep(420, 170, 0.40), 0.06, 0.11), 0.12)
    return normalize(mix(woo, breath))


def snd_dagger_throw(rng):
    whistle = env_ad(sine_sweep(1850, 880, 0.18, 0.7), 0.004, 0.045)
    air = env_ad(bandpass(white(rng, 0.18), 1500, 5000), 0.004, 0.04)
    return normalize(mix(whistle, gain(air, 0.45)))


def snd_buff_cast(rng):
    notes, t0 = [], 0.0
    for f in (392.0, 587.33):  # G4 D5
        notes.append(delay(mix(partial(f, 0.42, 0.13),
                                partial(2 * f, 0.42, 0.07, 0.35)), t0))
        t0 += 0.10
    warm = env_ad(lowpass(white(rng, 0.45), 420), 0.08, 0.13)
    return normalize(mix(gain(warm, 0.15), *notes))


def snd_attack_sword(rng):
    return normalize(env_ad(bandpass_sweep(white(rng, 0.15), 1500, 3600, 450, 1200),
                            0.003, 0.04), 0.7)


def snd_attack_bow(rng):
    tw = mix(partial(430, 0.14, 0.026), partial(860, 0.14, 0.014, 0.4))
    air = env_ad(bandpass(white(rng, 0.12), 1400, 4200), 0.005, 0.03)
    return normalize(mix(tw, gain(air, 0.4)), 0.7)


def snd_attack_staff(rng):
    pop = env_ad(sine_sweep(620, 990, 0.14, curve=0.7), 0.004, 0.04)
    fizz = env_ad(highpass(white(rng, 0.12), 2600), 0.004, 0.03)
    return normalize(mix(pop, gain(fizz, 0.3)), 0.7)


def snd_attack_dagger(rng):
    return normalize(env_ad(bandpass_sweep(white(rng, 0.10), 2400, 5200, 900, 2200),
                            0.002, 0.025), 0.65)


def snd_land_soft(rng):
    thud = env_ad(sine_sweep(110, 62, 0.09), 0.002, 0.022)
    scuff = env_ad(lowpass(white(rng, 0.07), 800), 0.002, 0.016)
    return normalize(mix(thud, gain(scuff, 0.6)), 0.35)  # deliberately quiet


# --- UI palette -------------------------------------------------------------

def snd_ui_click(rng):
    blip = env_ad(sine_sweep(1250, 980, 0.05), 0.001, 0.012)
    tick = env_ad(highpass(white(rng, 0.03), 2500), 0.001, 0.006)
    return normalize(mix(blip, gain(tick, 0.35)), 0.55)


def snd_ui_hover(rng):
    return normalize(env_ad(sine_sweep(1700, 1550, 0.03), 0.002, 0.008), 0.22)


def snd_ui_open(rng):
    woo = env_ad(bandpass_sweep(white(rng, 0.16), 500, 1400, 1800, 4200), 0.01, 0.045)
    blip = gain(env_ad(sine_sweep(620, 1080, 0.14, curve=0.8), 0.008, 0.04), 0.5)
    return normalize(mix(woo, blip), 0.5)


def snd_ui_close(rng):
    woo = env_ad(bandpass_sweep(white(rng, 0.14), 1800, 4200, 450, 1200), 0.008, 0.04)
    blip = gain(env_ad(sine_sweep(1080, 580, 0.12, curve=0.8), 0.006, 0.035), 0.5)
    return normalize(mix(woo, blip), 0.45)


def snd_death_sting(rng):
    # Somber minor dyad (A2 + C3) with a slow dark swell underneath.
    low = mix(partial(110.0, 1.2, 0.40), partial(130.81, 1.2, 0.38, 0.8),
              partial(220.0, 1.2, 0.22, 0.35))
    swell = env_ad(lowpass(white(rng, 1.1), 300), 0.30, 0.30)
    return normalize(mix(low, gain(swell, 0.25)), 0.6)



# --- cross-discipline event stingers (EventJuice: escalations + synergy) ----

def snd_escalation_thermal(rng):
    """Burn+chill detonation: steam hiss + descending crack + low pop."""
    hiss = env_ad(highpass(white(rng, 0.30), 2800), 0.005, 0.08)
    crack = env_ad(sine_sweep(520, 90, 0.22, curve=1.6), 0.002, 0.07)
    pop = gain(env_ad(lowpass(white(rng, 0.08), 1200), 0.001, 0.03), 0.8)
    return normalize(mix(gain(hiss, 0.5), crack, pop))


def snd_escalation_septic(rng):
    """Poison-on-bleed: two sickly low wobbles + filtered fizz."""
    blub1 = env_ad(sine_sweep(220, 140, 0.18, curve=0.7), 0.01, 0.06)
    blub2 = delay(env_ad(sine_sweep(260, 120, 0.16, curve=0.7), 0.01, 0.05), 0.09)
    fizz = gain(env_ad(lowpass(white(rng, 0.25), 900), 0.02, 0.08), 0.3)
    return normalize(mix(blub1, blub2, fizz))


def snd_escalation_brittle(rng):
    """Mark shatter: short glass partials + a bright snap."""
    bells = []
    for k in range(4):
        f = rng.uniform(3200, 7000)
        bells.append(delay(gain(partial(f, 0.18, 0.04, detune=-0.05),
                                0.5 - k * 0.1), 0.03 * k))
    snap = env_ad(highpass(white(rng, 0.06), 5000), 0.001, 0.02)
    return normalize(mix(gain(snap, 0.7), *bells))


def snd_duo_swap(rng):
    """Duo rotation beat: two-chord rise + bright sparkle tail — bigger
    ceremony than the per-proc shimmer."""
    low = env_ad(sine_sweep(440, 660, 0.18, curve=0.5), 0.006, 0.08)
    high = delay(env_ad(sine_sweep(880, 1320, 0.20, curve=0.5), 0.006, 0.09), 0.09)
    spark1 = delay(gain(partial(2640, 0.22, 0.06), 0.30), 0.16)
    spark2 = delay(gain(partial(3520, 0.18, 0.05), 0.22), 0.22)
    return normalize(mix(low, high, spark1, spark2))


def snd_synergy_proc(rng):
    """Pair-payoff shimmer: quick two-note rise + glint."""
    a = env_ad(sine_sweep(880, 1320, 0.14, curve=0.5), 0.004, 0.05)
    b = delay(env_ad(sine_sweep(1320, 1760, 0.14, curve=0.5), 0.004, 0.06), 0.07)
    glint = delay(gain(partial(2640, 0.18, 0.05), 0.25), 0.10)
    return normalize(mix(a, b, glint))


# --- combat feedback (the most frequent moments — kept SHORT + not too loud) -

def snd_hit_impact(rng):
    """Generic landed-hit thwack: a low thud + filtered body + a touch of snap.
    Plays on every hit over the weapon swing, so deliberately quiet and brief."""
    thud = env_ad(sine_sweep(220, 90, 0.09), 0.001, 0.025)
    body = env_ad(lowpass(white(rng, 0.08), 1100), 0.001, 0.02)
    snap = gain(env_ad(highpass(white(rng, 0.03), 2200), 0.001, 0.008), 0.4)
    return normalize(soft_clip(mix(thud, gain(body, 0.7), snap), 1.3), 0.5)


def snd_hit_crit(rng):
    """Crit sting: a bright descending crack + metallic ting over the impact."""
    crack = env_ad(sine_sweep(900, 220, 0.10, curve=1.5), 0.001, 0.03)
    ting = mix(partial(3200, 0.16, 0.04), partial(4600, 0.16, 0.03, 0.5))
    snap = env_ad(highpass(white(rng, 0.04), 3000), 0.001, 0.012)
    return normalize(soft_clip(mix(crack, gain(ting, 0.6), gain(snap, 0.7)), 1.5), 0.7)


def snd_enemy_death(rng):
    """Mob defeat poof: an airy descending burst + a soft low pop (MapleStory poof)."""
    poof = env_ad(bandpass_sweep(white(rng, 0.22), 1400, 3600, 300, 900), 0.004, 0.07)
    pop = env_ad(sine_sweep(180, 70, 0.16), 0.002, 0.05)
    return normalize(soft_clip(mix(gain(poof, 0.7), pop), 1.2), 0.5)


def snd_mastery_ding(rng):
    """Mastery-up ding: a bright ascending two-note chime, celebratory but small."""
    notes, t0 = [], 0.0
    for f in (659.25, 987.77):  # E5 B5
        notes.append(delay(mix(partial(f, 0.30, 0.10), partial(2 * f, 0.30, 0.05, 0.3)), t0))
        t0 += 0.07
    return normalize(mix(*notes), 0.55)


SOUNDS = {
    "sword_slash": snd_sword_slash,
    "sword_heavy": snd_sword_heavy,
    "sword_warcry": snd_sword_warcry,
    "sword_guard": snd_sword_guard,
    "bow_release": snd_bow_release,
    "bow_snipe": snd_bow_snipe,
    "bow_volley": snd_bow_volley,
    "bow_trap": snd_bow_trap,
    "mark_ping": snd_mark_ping,
    "dash_whoosh": snd_dash_whoosh,
    "staff_fire": snd_staff_fire,
    "staff_ice": snd_staff_ice,
    "staff_lightning": snd_staff_lightning,
    "staff_arcane": snd_staff_arcane,
    "staff_buff": snd_staff_buff,
    "dagger_stab": snd_dagger_stab,
    "dagger_poison": snd_dagger_poison,
    "dagger_stealth": snd_dagger_stealth,
    "dagger_throw": snd_dagger_throw,
    "buff_cast": snd_buff_cast,
    "attack_sword": snd_attack_sword,
    "attack_bow": snd_attack_bow,
    "attack_staff": snd_attack_staff,
    "attack_dagger": snd_attack_dagger,
    "land_soft": snd_land_soft,
    "ui_click": snd_ui_click,
    "ui_hover": snd_ui_hover,
    "ui_open": snd_ui_open,
    "ui_close": snd_ui_close,
    "death_sting": snd_death_sting,
    "escalation_thermal": snd_escalation_thermal,
    "escalation_septic": snd_escalation_septic,
    "escalation_brittle": snd_escalation_brittle,
    "synergy_proc": snd_synergy_proc,
    "duo_swap": snd_duo_swap,
    "hit_impact": snd_hit_impact,
    "hit_crit": snd_hit_crit,
    "enemy_death": snd_enemy_death,
    "mastery_ding": snd_mastery_ding,
}


# ---------------------------------------------------------------------------
# Ability -> sound mapping (filename keywords, lowercased; first match wins)
# ---------------------------------------------------------------------------

RULES = {
    "Sword": [
        (r"earthsplit|sundering", "sword_heavy"),
        (r"charge|onslaught|banner|warcry", "sword_warcry"),
        (r"vow|bulwark|riposte|second_wind|stance", "sword_guard"),
        (r"sentinel|mark", "mark_ping"),
        (r"vault", "dash_whoosh"),
        (r".", "sword_slash"),
    ],
    "Bow": [
        (r"volley|hailstorm|skyfall|split", "bow_volley"),
        (r"caltrop", "bow_trap"),
        (r"snipe|sundering", "bow_snipe"),
        (r"mark", "mark_ping"),
        (r"disengage", "dash_whoosh"),
        (r"eagle|steady|keen|focus", "buff_cast"),
        (r".", "bow_release"),
    ],
    "Staff": [
        (r"immolate|pyre|fire", "staff_fire"),
        (r"glacial|frost|ice", "staff_ice"),
        (r"storm|lightning|overload", "staff_lightning"),
        (r"mana|wellspring|communion|ward|resonance", "staff_buff"),
        (r"phase", "dash_whoosh"),
        (r".", "staff_arcane"),
    ],
    "Dagger": [
        (r"envenom|toxic|poison", "dagger_poison"),
        (r"smoke|meld|shadow_partner|shadowpartner", "dagger_stealth"),
        (r"shadowstep", "dash_whoosh"),
        (r"fan_of|knives|knife", "dagger_throw"),
        (r"death|vendetta|mark", "mark_ping"),
        (r"bloodlust|spree|instinct|composure|killing_edge", "buff_cast"),
        (r".", "dagger_stab"),
    ],
}


def pick_sound(weapon, fname):
    key = fname.lower()
    for pat, snd in RULES[weapon]:
        if re.search(pat, key):
            return snd
    return None


# ---------------------------------------------------------------------------
# .tres wiring
# ---------------------------------------------------------------------------

ABD_EXT_RE = re.compile(
    r'\[ext_resource type="Script"[^\]]*?path="res://scripts/Resources/'
    r'AbilitySystem/ActiveBehaviorData\.gd"[^\]]*?id="([^"]+)"')

# Constants.AbilityType: ACTIVE = 0 (the .tres default, so the property is
# usually omitted on actives), PASSIVE = 1. Passives are never cast, so a
# cast sfx_path on them is inert — skip them entirely.
PASSIVE_RE = re.compile(r"^ability_type = 1\b", re.M)


def wire_tres(path, sound_name):
    """Set sfx_path inside the ActiveBehaviorData sub-resource. Returns
    'wired' / 'replaced' / None (no active behavior block)."""
    with open(path, encoding="utf-8") as f:
        lines = f.readlines()
    text = "".join(lines)
    if PASSIVE_RE.search(text):
        return None
    m = ABD_EXT_RE.search(text)
    if not m:
        return None
    # The ActiveBehaviorData block is the (only) one whose script property
    # references that ext_resource id; formula/data blocks use different ids.
    script_line = 'script = ExtResource("%s")' % m.group(1)
    sfx_line = 'sfx_path = "%s%s.wav"\n' % (RES_PREFIX, sound_name)

    idx = next((i for i, l in enumerate(lines) if l.strip() == script_line), None)
    if idx is None:
        return None

    # Scan the rest of the block (until the next section header) for an
    # existing sfx_path; replace it, otherwise insert right after `script =`.
    replaced = False
    j = idx + 1
    while j < len(lines) and not lines[j].startswith("["):
        if lines[j].startswith("sfx_path = "):
            lines[j] = sfx_line
            replaced = True
        j += 1
    if not replaced:
        lines.insert(idx + 1, sfx_line)

    with open(path, "w", encoding="utf-8", newline="") as f:
        f.writelines(lines)
    return "replaced" if replaced else "wired"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true",
                    help="print the ability->sound mapping without writing")
    ap.add_argument("--synth-only", action="store_true",
                    help="only synth the WAV palette; do not touch ability .tres")
    args = ap.parse_args()

    if not args.dry_run:
        os.makedirs(OUT_DIR, exist_ok=True)
        for name, builder in SOUNDS.items():
            rng = random.Random(name)  # deterministic per sound
            samples = fade_out(builder(rng))
            write_wav(os.path.join(OUT_DIR, name + ".wav"), samples)
            print("synth  %-16s %5.2fs" % (name, len(samples) / SR))

    if args.synth_only:
        return

    total = {"wired": 0, "replaced": 0, "skipped": 0}
    for weapon in ABILITY_DIRS:
        folder = os.path.join(ROOT, "resources", "Abilities", weapon)
        for fname in sorted(os.listdir(folder)):
            if not fname.endswith(".tres"):
                continue
            sound = pick_sound(weapon, fname)
            path = os.path.join(folder, fname)
            if args.dry_run:
                with open(path, encoding="utf-8") as f:
                    text = f.read()
                if PASSIVE_RE.search(text):
                    state = "(passive - skip)"
                elif not ABD_EXT_RE.search(text):
                    state = "(no active behavior - skip)"
                else:
                    state = sound
                print("%-7s %-34s -> %s" % (weapon, fname, state))
                continue
            res = wire_tres(path, sound)
            if res:
                total[res] += 1
                print("%-8s %-7s %-34s -> %s" % (res, weapon, fname, sound))
            else:
                total["skipped"] += 1
    if not args.dry_run:
        print("\n%d wired, %d replaced, %d passives skipped" %
              (total["wired"], total["replaced"], total["skipped"]))


if __name__ == "__main__":
    main()
