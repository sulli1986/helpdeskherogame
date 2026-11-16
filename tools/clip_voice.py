#!/usr/bin/env python3
"""Voiceover for the daily clip: speak each narration line with Piper (free, offline neural TTS).

Usage: clip_voice.py OUT_DIR
Reads OUT_DIR/narration.json ({"lines": [{"text", "at"?}], "outro": str}) from clip_text.py.
Writes OUT_DIR/voice.wav (mono 22.05 kHz, the whole clip's voice track) and OUT_DIR/voice.json
({"lines": [{"text", "start", "end"}], "outro": {...}, "spoken": bool}) used for captions and ducking.

Voice: Piper's en_US "ljspeech" (trained on the public-domain LJ Speech dataset). The model is
downloaded at render time into ~/.cache/piper and is never part of the game. Before using it we
check its model card still says Public Domain; if anything fails, the clip renders without a voice
(captions are then timed at a normal speaking rate) rather than failing the job.
"""
import json
import os
import sys
import urllib.request
import wave
from pathlib import Path

import numpy as np

out = Path(sys.argv[1])
SR = 22050
VOICE = "en_US-ljspeech-high"
BASE = "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/ljspeech/high/"
CACHE = Path(os.environ.get("PIPER_CACHE", Path.home() / ".cache" / "piper"))
GAP = 0.35          # silence between lines
START = 0.25        # first line starts almost at once: the hook must land in the first second
WPS = 2.9           # words per second when there's no voice (captions only)

nar = json.loads((out / "narration.json").read_text(encoding="utf-8"))


def fetch(name: str) -> Path:
    p = CACHE / name
    if not p.exists() or p.stat().st_size == 0:
        CACHE.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(BASE + name, p)
    return p


def load_voice():
    if os.environ.get("CLIP_VOICE", "piper") == "off":
        return None
    try:
        from piper import PiperVoice
        card = fetch("MODEL_CARD").read_text(encoding="utf-8", errors="replace")
        if "public domain" not in card.lower():
            print("::warning::Piper voice licence changed (no 'Public Domain' in its model card): no voiceover")
            return None
        fetch(f"{VOICE}.onnx.json")
        return PiperVoice.load(str(fetch(f"{VOICE}.onnx")))
    except Exception as e:  # no network, no package: render without a voice
        print(f"::warning::No voiceover ({e.__class__.__name__}: {e})")
        return None


def speak(voice, text: str) -> np.ndarray:
    if voice is None:
        return np.zeros(int(SR * max(1.2, len(text.split()) / WPS)), dtype=np.float32)
    from piper import SynthesisConfig
    tmp = out / "_line.wav"
    with wave.open(str(tmp), "wb") as w:
        voice.synthesize_wav(text, w, syn_config=SynthesisConfig(length_scale=0.92))  # a touch brisker
    with wave.open(str(tmp), "rb") as r:
        sr = r.getframerate()
        pcm = np.frombuffer(r.readframes(r.getnframes()), dtype="<i2").astype(np.float32) / 32768
    tmp.unlink()
    if sr != SR:  # resample (linear) to the track rate
        pcm = np.interp(np.arange(int(len(pcm) * SR / sr)) * sr / SR, np.arange(len(pcm)), pcm).astype(np.float32)
    # trim leading/trailing silence so the lines butt up nicely
    loud = np.nonzero(np.abs(pcm) > 0.01)[0]
    return pcm[max(0, loud[0] - 400):loud[-1] + 1200] if len(loud) else pcm


voice = load_voice()
clips, t = [], START
for ln in nar["lines"]:
    pcm = speak(voice, ln["text"])
    start = max(t, float(ln.get("at", 0.0)))
    clips.append({"text": ln["text"], "start": round(start, 2), "end": round(start + len(pcm) / SR, 2), "pcm": pcm})
    t = start + len(pcm) / SR + GAP
outro_pcm = speak(voice, nar["outro"])

# The outro is placed by the composer (it knows where the end card goes); keep it separate.
total = clips[-1]["end"] + 0.2 if clips else 0.0
track = np.zeros(int(total * SR) + 1, dtype=np.float32)
for c in clips:
    i = int(c["start"] * SR)
    track[i:i + len(c["pcm"])] += c["pcm"][: len(track) - i]


def write(path: Path, pcm: np.ndarray) -> None:
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(pcm, -1, 1) * 32767).astype("<i2").tobytes())


write(out / "voice.wav", track)
write(out / "outro.wav", outro_pcm)
info = {
    "spoken": voice is not None,
    "lines": [{k: c[k] for k in ("text", "start", "end")} for c in clips],
    "outro": {"text": nar["outro"], "length": round(len(outro_pcm) / SR, 2)},
}
(out / "voice.json").write_text(json.dumps(info, indent=1), encoding="utf-8")
print(f"voice: {'piper ' + VOICE if voice else 'none (captions only)'}, {len(clips)} lines, ends {total:.1f}s")
