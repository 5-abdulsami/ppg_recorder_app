import 'package:flutter/services.dart';

/// Haptic cues for recording events.
abstract interface class HapticsService {
  /// Recording has started.
  Future<void> recordingStarted();

  /// Recording has finished or been stopped.
  Future<void> recordingStopped();

  /// Something needs attention (e.g. finger removed).
  Future<void> warning();
}

/// [HapticsService] using the platform's built-in haptic feedback.
class PlatformHapticsService implements HapticsService {
  @override
  Future<void> recordingStarted() => HapticFeedback.heavyImpact();

  @override
  Future<void> recordingStopped() async {
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await HapticFeedback.heavyImpact();
  }

  @override
  Future<void> warning() => HapticFeedback.vibrate();
}
