import os
import re
import glob
import math
import numpy as np

try:
    import librosa  # type: ignore
except Exception as e:  # pragma: no cover
    raise SystemExit(
        "Missing dependency 'librosa'. Create a venv and install with:\n"
        "  python3 -m venv .venv && source .venv/bin/activate && pip install librosa soundfile numpy\n"
        f"Error: {e}"
    )

SR = 44100
FPS = 30.0
TOL_MS = 6.0
WIN_MS = 150.0  # search window half-width
FIRST_WIN_MS = 250.0  # range to locate the very first onset near start
FIRST_CENTER_MS = 35.0  # initial guess for first onset (~lead-in)

fname_re = re.compile(r"_(\d+)_(\d+)\.wav$")


def expected_deltas_ms(path: str) -> tuple[int, int]:
    m = fname_re.search(path)
    if not m:
        raise ValueError(f"Unrecognized filename: {path}")
    b = int(m.group(1))
    d = int(m.group(2))
    total_ms = round(((b + d) / FPS) * 1000.0)
    t1_ms = round((b / (b + d)) * total_ms)
    return t1_ms, total_ms - t1_ms


def percussive_onset_envelope_ms(y: np.ndarray, sr: int) -> tuple[np.ndarray, np.ndarray]:
    # Emphasize percussive components to sharpen onsets (helps with piano crossfades)
    y_h, y_p = librosa.effects.hpss(y)
    oenv = librosa.onset.onset_strength(y=y_p, sr=sr, aggregate=np.mean)
    t = librosa.times_like(oenv, sr=sr)
    # Light smoothing to stabilize local argmax
    win = 3
    if win > 1:
        k = np.ones(win, dtype=float) / float(win)
        oenv = np.convolve(oenv, k, mode="same")
    return oenv, t * 1000.0


def find_onset_near(env: np.ndarray, t_ms: np.ndarray, center_ms: float, half_win_ms: float) -> float:
    # Use the steepest rise (derivative peak) within the window for robust onset timing
    deriv = np.gradient(env)
    # Smooth derivative lightly
    k = np.array([0.25, 0.5, 0.25])
    deriv = np.convolve(deriv, k, mode="same")
    mask = np.abs(t_ms - center_ms) <= half_win_ms
    if not np.any(mask):
        idx = int(np.argmax(deriv))
        return float(t_ms[idx])
    idx_local = np.argmax(deriv[mask])
    idx_global = np.flatnonzero(mask)[idx_local]
    return float(t_ms[idx_global])


def measure_onsets_ms_windowed(path: str) -> tuple[float, float, float]:
    y, sr = librosa.load(path, sr=SR, mono=True)
    env, t_ms = percussive_onset_envelope_ms(y, sr)
    # First onset near the beginning
    o1 = find_onset_near(env, t_ms, FIRST_CENTER_MS, FIRST_WIN_MS)
    exp12, exp23 = expected_deltas_ms(path)
    # Second and third centered around expected offsets from first
    o2 = find_onset_near(env, t_ms, o1 + exp12, WIN_MS)
    o3 = find_onset_near(env, t_ms, o2 + exp23, WIN_MS)
    return o1, o2, o3


def check_dir(root: str) -> None:
    files = sorted(glob.glob(os.path.join(root, "*.wav")))
    if not files:
        print(f"No files in {root}")
        return
    print(f"Checking {root}")
    worst = 0.0
    for f in files:
        exp12, exp23 = expected_deltas_ms(f)
        o1, o2, o3 = measure_onsets_ms_windowed(f)
        m12 = o2 - o1
        m23 = o3 - o2
        e12 = abs(m12 - exp12)
        e23 = abs(m23 - exp23)
        worst = max(worst, e12, e23)
        ok = e12 <= TOL_MS and e23 <= TOL_MS
        status = "OK " if ok else "ERR"
        print(
            f"{status} {os.path.basename(f):>18}  "
            f"Δ12 {m12:6.1f}ms (exp {exp12:4d})  "
            f"Δ23 {m23:6.1f}ms (exp {exp23:4d})  "
            f"err {max(e12, e23):4.1f}ms"
        )
    print(f"Worst absolute error: {worst:.1f} ms")


def main() -> None:
    for setname in ("piano", "woodblock", "tones"):
        d = os.path.join("assets", "audio", "cycles", setname)
        if os.path.isdir(d):
            check_dir(d)


if __name__ == "__main__":
    main()
