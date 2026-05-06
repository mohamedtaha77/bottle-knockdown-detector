// Plays one-shot sound effects without interrupting background music.
//
// UI click sounds are generated as short sine-wave tones using a raw PCM
// AudioPlayer so no extra asset files are needed for them.
// The "bottle fallen" crash uses the real WAV asset.
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import '../utils/logger.dart';

class SfxService {
  // Singleton.
  SfxService._();
  static final instance = SfxService._();

  // Dedicated player for WAV assets (bottle crash).
  final AudioPlayer _assetPlayer = AudioPlayer();

  // Separate player for generated tones so they can overlap.
  final AudioPlayer _tonePlayer = AudioPlayer();

  bool _muted = false;

  // ---------------------------------------------------------------------------
  // Public sound events
  // ---------------------------------------------------------------------------

  /// Short high-pitched beep — used for button taps.
  Future<void> playClick() => _playTone(frequency: 880, durationMs: 80, volume: 0.5);

  /// Positive ascending two-tone — "Start Processing" pressed.
  Future<void> playStart() async {
    await _playTone(frequency: 660, durationMs: 80, volume: 0.5);
    await Future.delayed(const Duration(milliseconds: 60));
    await _playTone(frequency: 880, durationMs: 120, volume: 0.5);
  }

  /// Descending two-tone — Cancel pressed.
  Future<void> playCancel() async {
    await _playTone(frequency: 440, durationMs: 80, volume: 0.4);
    await Future.delayed(const Duration(milliseconds: 60));
    await _playTone(frequency: 330, durationMs: 120, volume: 0.4);
  }

  /// Success fanfare — processing complete.
  Future<void> playComplete() async {
    for (final freq in [523, 659, 784, 1047]) {
      await _playTone(frequency: freq.toDouble(), durationMs: 100, volume: 0.55);
      await Future.delayed(const Duration(milliseconds: 80));
    }
  }

  /// Bowling pin crash WAV — fired each time a new bottle is confirmed fallen.
  Future<void> playBottleFallen() async {
    if (_muted) return;
    try {
      await _assetPlayer.stop();
      await _assetPlayer.play(
        AssetSource('audio/sfx/bottle_fallen.wav'),
        volume: 0.85,
      );
    } catch (e) {
      appLogger.e('SfxService bottle_fallen error: $e');
    }
  }

  /// Mute/unmute all SFX. Returns the new muted state.
  bool toggleMute() {
    _muted = !_muted;
    return _muted;
  }

  bool get isMuted => _muted;

  Future<void> dispose() async {
    await _assetPlayer.dispose();
    await _tonePlayer.dispose();
  }

  // ---------------------------------------------------------------------------
  // Tone generator
  // ---------------------------------------------------------------------------

  /// Synthesises a sine-wave tone at [frequency] Hz for [durationMs] ms
  /// and plays it immediately as raw PCM bytes (44100 Hz, mono, 16-bit).
  Future<void> _playTone({
    required double frequency,
    required int durationMs,
    required double volume,
  }) async {
    if (_muted) return;
    try {
      const sampleRate = 44100;
      final numSamples = (sampleRate * durationMs / 1000).round();
      final buffer = Int16List(numSamples);

      for (int i = 0; i < numSamples; i++) {
        // Sine wave with a short fade-out to avoid clicks.
        final t = i / sampleRate;
        final fadeOut = (i > numSamples * 0.7)
            ? 1.0 - (i - numSamples * 0.7) / (numSamples * 0.3)
            : 1.0;
        buffer[i] = (math.sin(2 * math.pi * frequency * t) *
                32767 *
                volume *
                fadeOut)
            .round()
            .clamp(-32768, 32767);
      }

      // Build a minimal WAV header + PCM data.
      final wav = _buildWav(buffer, sampleRate);
      await _tonePlayer.stop();
      await _tonePlayer.play(BytesSource(wav));
    } catch (e) {
      appLogger.e('SfxService tone error: $e');
    }
  }

  /// Wraps raw 16-bit PCM [samples] in a WAV container.
  Uint8List _buildWav(Int16List samples, int sampleRate) {
    final dataBytes = samples.buffer.asUint8List();
    final fileSize = 36 + dataBytes.length;
    final buf = ByteData(44 + dataBytes.length);
    int o = 0;

    // RIFF chunk
    buf.buffer.asUint8List().setRange(o, o + 4, [82, 73, 70, 70]); o += 4; // "RIFF"
    buf.setUint32(o, fileSize, Endian.little); o += 4;
    buf.buffer.asUint8List().setRange(o, o + 4, [87, 65, 86, 69]); o += 4; // "WAVE"

    // fmt chunk
    buf.buffer.asUint8List().setRange(o, o + 4, [102, 109, 116, 32]); o += 4; // "fmt "
    buf.setUint32(o, 16, Endian.little); o += 4;           // chunk size
    buf.setUint16(o, 1, Endian.little); o += 2;            // PCM
    buf.setUint16(o, 1, Endian.little); o += 2;            // mono
    buf.setUint32(o, sampleRate, Endian.little); o += 4;   // sample rate
    buf.setUint32(o, sampleRate * 2, Endian.little); o += 4; // byte rate
    buf.setUint16(o, 2, Endian.little); o += 2;            // block align
    buf.setUint16(o, 16, Endian.little); o += 2;           // bits per sample

    // data chunk
    buf.buffer.asUint8List().setRange(o, o + 4, [100, 97, 116, 97]); o += 4; // "data"
    buf.setUint32(o, dataBytes.length, Endian.little); o += 4;
    buf.buffer.asUint8List().setRange(o, o + dataBytes.length, dataBytes);

    return buf.buffer.asUint8List();
  }
}
