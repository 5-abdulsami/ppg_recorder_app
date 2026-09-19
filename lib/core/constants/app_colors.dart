import 'package:flutter/material.dart';

/// Colour palette.
abstract final class AppColors {
  /// Brand seed colour (deep crimson, evoking blood/PPG).
  static const Color primary = Color(0xFFB3261E);

  /// Screen background.
  static const Color background = Color(0xFFF7F5F4);

  /// Card / surface colour.
  static const Color surface = Colors.white;

  /// Subtle borders.
  static const Color border = Color(0xFFE4DFDD);

  /// Secondary text.
  static const Color textSecondary = Color(0xFF6B6260);

  /// Good quality.
  static const Color qualityGood = Color(0xFF2E7D32);

  /// Fair quality.
  static const Color qualityFair = Color(0xFFF9A825);

  /// Poor quality.
  static const Color qualityPoor = Color(0xFFC62828);

  /// Quality unknown / unavailable.
  static const Color qualityUnknown = Color(0xFF9E9E9E);

  /// Red-channel waveform.
  static const Color channelRed = Color(0xFFD32F2F);

  /// Green-channel waveform.
  static const Color channelGreen = Color(0xFF388E3C);

  /// Dark background of the recording screen.
  static const Color recordingBackground = Color(0xFF121212);
}
