import 'package:flutter_soloud/flutter_soloud.dart';

/// One place that starts the shared SoLoud engine (used by the Studio player,
/// the count-in click and the stem player) and switches on its live
/// frequency feed for the visualisers.
class AudioEngine {
  AudioEngine._();

  static bool _visualizationOn = false;

  static Future<void> ensure() async {
    if (!SoLoud.instance.isInitialized) {
      await SoLoud.instance.init();
    }
    if (!_visualizationOn) {
      try {
        SoLoud.instance.setVisualizationEnabled(
          true,
          windowSize: 256,
          kind: VisualizationKind.fft,
        );
        _visualizationOn = true;
      } catch (_) {
        // Visualisation is cosmetic; playback works without it.
      }
    }
  }
}
