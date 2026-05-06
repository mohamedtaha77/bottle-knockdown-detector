// Shows the final results: score, annotated video, and save/reset buttons.
// Plays victory music on arrival.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:video_player/video_player.dart';
import '../providers/video_processor_provider.dart';
import '../services/music_service.dart';
import '../services/sfx_service.dart';

class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({super.key});
  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  VideoPlayerController? _player;
  bool _savedToGallery = false;

  @override
  void initState() {
    super.initState();
    // Switch to victory/results music.
    MusicService.instance.playResults();

    final result = ref.read(videoProcessorProvider).result;
    if (result != null) {
      _player = VideoPlayerController.file(File(result.outputVideoPath))
        ..initialize().then((_) {
          if (mounted) {
            setState(() {});
            _player!.setLooping(true);
            _player!.play();
          }
        });
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _saveToGallery(String path) async {
    SfxService.instance.playClick();
    try {
      await Gal.putVideo(path);
      if (mounted) setState(() => _savedToGallery = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')));
    }
  }

  void _processAnother() {
    SfxService.instance.playClick();
    // Return home and restart home music.
    MusicService.instance.playHome();
    ref.read(videoProcessorProvider.notifier).reset();
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(videoProcessorProvider).result;
    if (result == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final score = result.totalBottlesDetected == 0
        ? 0.0
        : result.bottlesKnockedDown / result.totalBottlesDetected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Results'),
        centerTitle: true,
        actions: [
          StatefulBuilder(
            builder: (ctx, setSt) => IconButton(
              icon: Icon(MusicService.instance.isMuted
                  ? Icons.music_off
                  : Icons.music_note),
              onPressed: () async {
                SfxService.instance.playClick();
                await MusicService.instance.toggleMute();
                setSt(() {});
              },
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Score card.
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  CircularPercentIndicator(
                    radius: 80,
                    lineWidth: 12,
                    percent: score.clamp(0.0, 1.0),
                    center: Text(
                      '${result.scorePercentage.toStringAsFixed(0)}%',
                      style: const TextStyle(
                          fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                    progressColor: Colors.green,
                    backgroundColor: Colors.red.shade100,
                    circularStrokeCap: CircularStrokeCap.round,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${result.bottlesKnockedDown} / ${result.totalBottlesDetected} '
                    'bottles knocked down',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Processed in ${result.processingTimeSeconds}s',
                    style:
                        TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),

            // Video player.
            if (_player != null && _player!.value.isInitialized) ...[
              GestureDetector(
                onTap: () => _player!.value.isPlaying
                    ? _player!.pause()
                    : _player!.play(),
                child: AspectRatio(
                  aspectRatio: _player!.value.aspectRatio,
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      VideoPlayer(_player!),
                      VideoProgressIndicator(_player!,
                          allowScrubbing: true,
                          padding:
                              const EdgeInsets.symmetric(vertical: 4)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Save to Gallery button.
            FilledButton.icon(
              onPressed: _savedToGallery
                  ? null
                  : () => _saveToGallery(result.outputVideoPath),
              icon: Icon(
                  _savedToGallery ? Icons.check : Icons.save_alt),
              label: Text(_savedToGallery
                  ? 'Saved to Gallery'
                  : 'Save to Gallery'),
              style: FilledButton.styleFrom(
                  backgroundColor:
                      _savedToGallery ? Colors.green.shade400 : null),
            ),
            const SizedBox(height: 8),

            // Process another video.
            OutlinedButton.icon(
              onPressed: _processAnother,
              icon: const Icon(Icons.refresh),
              label: const Text('Process Another Video'),
            ),
          ],
        ),
      ),
    );
  }
}
