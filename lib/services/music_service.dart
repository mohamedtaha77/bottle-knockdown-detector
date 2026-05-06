// Manages looping background music across screens.
//
// Usage:
//   MusicService.instance.playHome();       // home screen
//   MusicService.instance.playProcessing(); // processing screen
//   MusicService.instance.playResults();    // result screen
//   MusicService.instance.stop();           // silence
//
// Only one track plays at a time. Switching tracks fades the old one out
// before starting the new one (simple cross-fade via volume steps).
import 'package:audioplayers/audioplayers.dart';
import '../utils/logger.dart';

class MusicService {
  // Singleton — one instance shared across the whole app.
  MusicService._();
  static final instance = MusicService._();

  final AudioPlayer _player = AudioPlayer();

  // Track paths in assets.
  static const _home       = 'audio/music/home_bg.mp3';
  static const _processing = 'audio/music/processing_bg.mp3';
  static const _results    = 'audio/music/results_bg.mp3';

  String? _currentTrack;
  bool _muted = false;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  Future<void> playHome()       => _play(_home);
  Future<void> playProcessing() => _play(_processing);
  Future<void> playResults()    => _play(_results);

  /// Toggle mute on/off. Returns the new muted state.
  Future<bool> toggleMute() async {
    _muted = !_muted;
    await _player.setVolume(_muted ? 0.0 : 0.4);
    return _muted;
  }

  bool get isMuted => _muted;

  /// Stops all music immediately.
  Future<void> stop() async {
    await _player.stop();
    _currentTrack = null;
  }

  /// Release the player when the app exits.
  Future<void> dispose() => _player.dispose();

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  Future<void> _play(String assetPath) async {
    // Skip if already playing the same track.
    if (_currentTrack == assetPath) return;

    try {
      // Fade out the current track quickly (5 steps × 30 ms = 150 ms fade).
      if (_currentTrack != null) {
        for (double v = 0.4; v >= 0; v -= 0.08) {
          await _player.setVolume(v.clamp(0.0, 1.0));
          await Future.delayed(const Duration(milliseconds: 30));
        }
      }

      _currentTrack = assetPath;
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(_muted ? 0.0 : 0.0); // start silent

      await _player.play(AssetSource(assetPath));

      // Fade in the new track (5 steps × 30 ms).
      for (double v = 0.0; v <= 0.4; v += 0.08) {
        await _player.setVolume(_muted ? 0.0 : v.clamp(0.0, 0.4));
        await Future.delayed(const Duration(milliseconds: 30));
      }
      await _player.setVolume(_muted ? 0.0 : 0.4);

      appLogger.d('Music: playing $assetPath');
    } catch (e) {
      appLogger.e('MusicService error: $e');
    }
  }
}
