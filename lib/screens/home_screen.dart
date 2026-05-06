// Landing screen — lets the user pick a video and start processing.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/video_processor_provider.dart';
import '../services/music_service.dart';
import '../services/sfx_service.dart';
import 'processing_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _videoPath;
  String? _videoName;

  @override
  void initState() {
    super.initState();
    // Start home background music when this screen is first shown.
    MusicService.instance.playHome();
  }

  Future<void> _pickVideo() async {
    // UI click sound.
    SfxService.instance.playClick();

    final pick = await FilePicker.platform
        .pickFiles(type: FileType.video, allowMultiple: false);
    if (pick == null || pick.files.isEmpty) return;
    setState(() {
      _videoPath = pick.files.first.path;
      _videoName = pick.files.first.name;
    });
  }

  void _startProcessing() {
    if (_videoPath == null) return;
    // Upward two-tone for launch.
    SfxService.instance.playStart();
    ref.read(videoProcessorProvider.notifier).startProcessing(_videoPath!);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProcessingScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bottle Knockdown Detector'),
        centerTitle: true,
        // Mute button in the top-right corner.
        actions: [
          StatefulBuilder(
            builder: (ctx, setSt) => IconButton(
              icon: Icon(MusicService.instance.isMuted
                  ? Icons.music_off
                  : Icons.music_note),
              tooltip: 'Toggle music',
              onPressed: () async {
                SfxService.instance.playClick();
                await MusicService.instance.toggleMute();
                setSt(() {});
              },
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.sports_bar,
                  size: 96, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                'Detect & score bottle knockdowns from a toy-car video.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 40),
              OutlinedButton.icon(
                onPressed: _pickVideo,
                icon: const Icon(Icons.video_library_outlined),
                label: const Text('Pick Video'),
              ),
              if (_videoName != null) ...[
                const SizedBox(height: 8),
                Text(
                  _videoName!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.grey[600]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _videoPath != null ? _startProcessing : null,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start Processing'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
