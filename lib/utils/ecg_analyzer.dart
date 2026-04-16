// lib/utils/ecg_analyzer.dart

import 'dart:math';

class EcgAnalyzer {
  // ── R-peak detection ──────────────────────────────────────────────
  // Adaptive threshold (60% of local max) + refractory period.
  // refractoryPeriod: min samples between peaks — 20 @ 75 Hz ≈ 267 ms,
  // prevents double-counting the same QRS complex.
  static List<int> detectRPeaks(
    List<double> waveform, {
    double thresholdFraction = 0.6,
    int refractoryPeriod = 20,
  }) {
    if (waveform.length < refractoryPeriod * 2) return [];

    final maxVal = waveform.reduce((a, b) => a > b ? a : b);
    final threshold = maxVal * thresholdFraction;

    final peaks = <int>[];
    int lastPeak = -refractoryPeriod;

    for (int i = 1; i < waveform.length - 1; i++) {
      if (i - lastPeak < refractoryPeriod) continue;
      if (waveform[i] >= threshold &&
          waveform[i] >= waveform[i - 1] &&
          waveform[i] >= waveform[i + 1]) {
        peaks.add(i);
        lastPeak = i;
      }
    }
    return peaks;
  }

  // ── Heart rate ────────────────────────────────────────────────────
  // Derives BPM from mean RR interval.
  // sampleRate: effective Hz — 3 samples per 40 ms tick = 75 Hz.
  static int heartRate(List<int> peaks, {double sampleRate = 75.0}) {
    if (peaks.length < 2) return 0;
    final rr = <int>[];
    for (int i = 1; i < peaks.length; i++) {
      rr.add(peaks[i] - peaks[i - 1]);
    }
    final meanRr = rr.reduce((a, b) => a + b) / rr.length;
    return (60.0 / (meanRr / sampleRate)).round().clamp(30, 220);
  }

  // ── Arrhythmia detection ──────────────────────────────────────────
  // Uses RR coefficient of variation (SD / mean).
  // CV > 0.15 (15%) is clinically considered irregular rhythm.
  static bool isArrhythmia(List<int> peaks, {double cvThreshold = 0.15}) {
    if (peaks.length < 4) return false;
    final rr = <double>[];
    for (int i = 1; i < peaks.length; i++) {
      rr.add((peaks[i] - peaks[i - 1]).toDouble());
    }
    final mean = rr.reduce((a, b) => a + b) / rr.length;
    if (mean == 0) return false;
    final variance =
        rr.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) /
        rr.length;
    final cv = sqrt(variance) / mean;
    return cv > cvThreshold;
  }
}
