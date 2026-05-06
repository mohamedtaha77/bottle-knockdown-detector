// Shows live progress while the video is being processed.
// Plays processing music and fires a crash SFX each time a new bottle falls.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/video_processor_provider.dart';
import '../services/music_service.dart';
import '../services/sfx_service.dart';
import 'result_screen.dart';

class ProcessingScreen extends ConsumerStatefulWidget {
  const ProcessingScreen({super.key});
  @override
  ConsumerState<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends ConsumerState<ProcessingScreen> {
  final _stopwatch = Stopwatch();
  Timer? _timer;
  String _elapsed = '0:00';

  // Track fallen count so we know when a NEW bottle falls.
  int _lastFallenCount = 0;

  @override
  void initState() {
    super.initState();

    // Switch to processing background music.
    MusicService.instance.playProcessing();

    // Tick the elapsed timer every second.
    _stopwatch.start();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final secs = _stopwatch.elapsed.inSeconds;
      setState(() {
        _elapsed =
            '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
      });
    });

    // Listen for terminal states and for new fallen bottles.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.listenManual<ProcessingState>(videoProcessorProvider,
          (prev, next) {
        if (!mounted) return;

        // Fire crash SFX whenever fallen count increases.
        final fallen = next.progress?.bottlesFallen ?? 0;
        if (fallen > _lastFallenCount) {
          _lastFallenCount = fallen;
          SfxService.instance.playBottleFallen();
        }

        switch (next.status) {
          case ProcessingStatus.done:
            _stop();
            SfxService.instance.playComplete();
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const ResultScreen()));
          case ProcessingStatus.idle:
            _stop();
            Navigator.of(context).pop();
          case ProcessingStatus.error:
            _stop();
            SfxService.instance.playCancel();
            showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Processing failed'),
                content: Text(next.errorMessage ?? 'Unknown error'),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).pop();
                    },
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          case ProcessingStatus.running:
            break;
        }
      });
    });
  }

  void _stop() {
    _stopwatch.stop();
    _timer?.cancel();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(videoProcessorProvider);
    final progress = state.progress;
    final pct = progress?.percentage ?? 0.0;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Processing…'),
          automaticallyImplyLeading: false,
          actions: [
            // Mute toggle — affects both music and SFX.
            StatefulBuilder(
              builder: (ctx, setSt) => IconButton(
                icon: Icon(MusicService.instance.isMuted
                    ? Icons.music_off
                    : Icons.music_note),
                onPressed: () async {
                  await MusicService.instance.toggleMute();
                  setSt(() {});
                },
              ),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Live stopwatch.
              Text(
                _elapsed,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    fontWeight: FontWeight.w300,
                    color: Colors.grey.shade400),
              ),
              const SizedBox(height: 24),
              Text('${pct.toStringAsFixed(1)}%',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayMedium),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: pct / 100, minHeight: 8),
              const SizedBox(height: 8),
              if (progress != null)
                Text(
                  'Frame ${progress.currentFrame} / ${progress.totalFrames}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
              const SizedBox(height: 32),
              if (progress != null) ...[
                _StatTile(
                    label: 'Bottles detected',
                    value: '${progress.bottlesDetected}'),
                const SizedBox(height: 8),
                _StatTile(
                    label: 'Knocked down so far',
                    value: '${progress.bottlesFallen}',
                    highlight: progress.bottlesFallen > 0),
              ],
              const SizedBox(height: 48),
              OutlinedButton(
                onPressed: () {
                  SfxService.instance.playCancel();
                  ref.read(videoProcessorProvider.notifier).cancel();
                },
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label, value;
  final bool highlight;
  const _StatTile(
      {required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyLarge),
          Text(value,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: highlight ? Colors.green : null)),
        ],
      );
}
