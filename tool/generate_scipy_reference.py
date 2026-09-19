"""Generates test/fixtures/scipy_reference.json.

Reference outputs of the Sphygma backend's SciPy-based signal processing, used
by test/signal/dsp_scipy_parity_test.dart to prove the Dart port matches.

Run (needs numpy + scipy):  python tool/generate_scipy_reference.py
"""

import json
from pathlib import Path

import numpy as np
from scipy.signal import butter, filtfilt, lfilter_zi, savgol_filter, welch


def synthetic(n, fs):
    t = np.arange(n) / fs
    i = np.arange(n)
    return (
        150.0
        + 0.02 * i
        + 3.0 * np.sin(2 * np.pi * 1.2 * t)
        + 0.8 * np.sin(2 * np.pi * 2.4 * t + 0.5)
        + 0.5 * np.sin(2 * np.pi * 7.0 * t)
        + 0.3 * np.sin(i * i * 0.37)
    )


def robust_detrend(signal, window_size=45):
    # Copied from sphygma_backend/app/services/signal_processing.py
    if window_size % 2 == 0:
        window_size += 1
    baseline = savgol_filter(signal, window_size, 1)
    return signal - baseline


def preprocess_hr_signal(signal, fs):
    # Copied from sphygma_backend/app/services/signal_processing.py
    signal = robust_detrend(signal)
    signal = (signal - np.mean(signal)) / np.std(signal)
    nyq = fs / 2.0
    b, a = butter(4, [0.7 / nyq, 3.0 / nyq], btype="band")
    signal = filtfilt(b, a, signal)
    return savgol_filter(signal, 11, 3)


cases = []
for fs, n in ((30.0, 300), (29.5, 400)):
    x = synthetic(n, fs)
    nyq = fs / 2.0
    b, a = butter(4, [0.7 / nyq, 3.0 / nyq], btype="band")
    f, p = welch(x, fs=fs, nperseg=240)
    cases.append(
        {
            "fs": fs,
            "x": x.tolist(),
            "b": b.tolist(),
            "a": a.tolist(),
            "zi": lfilter_zi(b, a).tolist(),
            "filtfilt": filtfilt(b, a, x).tolist(),
            "savgol_45_1": savgol_filter(x, 45, 1).tolist(),
            "savgol_11_3": savgol_filter(x, 11, 3).tolist(),
            "welch_f": f.tolist(),
            "welch_p": p.tolist(),
            "preprocess_hr": preprocess_hr_signal(x, fs).tolist(),
        }
    )

out = Path(__file__).resolve().parent.parent / "test" / "fixtures" / "scipy_reference.json"
out.write_text(json.dumps({"cases": cases}))
print(f"Wrote {out}")
