// lib/core/utils/sound_helper_web.dart
// Flutter Web implementation using the Web Audio API.
// Plays a two-tone chime when the queue token changes.

import 'package:web/web.dart';
import 'package:flutter/foundation.dart';

void playTokenChangeSound() {
  try {
    // Create a fresh AudioContext each time to avoid state issues
    final ctx = AudioContext();

    void _tone(double freq, double startAt, double duration, double peak) {
      final osc  = ctx.createOscillator();
      final gain = ctx.createGain();

      osc.connect(gain);
      gain.connect(ctx.destination);

      osc.type = 'sine';
      osc.frequency.value = freq;

      final now = ctx.currentTime;
      gain.gain
        ..setValueAtTime(0, now + startAt)
        ..linearRampToValueAtTime(peak, now + startAt + 0.04)
        ..exponentialRampToValueAtTime(0.001, now + startAt + duration);

      osc
        ..start(now + startAt)
        ..stop(now + startAt + duration + 0.05);
    }

    // Two ascending tones: D5 → A5 (pleasant notification chime)
    _tone(587.3, 0.00, 0.45, 0.28); // D5
    _tone(880.0, 0.20, 0.55, 0.22); // A5

    // Close context after sounds finish to free resources
    Future.delayed(const Duration(milliseconds: 900), () {
      try { ctx.close(); } catch (_) {}
    });
  } catch (e) {
    debugPrint('[Sound] Web Audio error: $e');
  }
}