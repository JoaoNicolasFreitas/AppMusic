import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import 'models/audio_track.dart';
import 'providers/app_controller.dart';
import 'screens/download_screen.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/player_screen.dart';
import 'screens/playlists_screen.dart';
import 'screens/settings_screen.dart';
import 'services/music_audio_handler.dart';
import 'widgets/artwork_tile.dart';

class AppMusicApp extends StatefulWidget {
  const AppMusicApp({
    required this.audioHandler,
    this.startupWarning,
    super.key,
  });

  final MusicAudioHandler audioHandler;
  final String? startupWarning;

  @override
  State<AppMusicApp> createState() => _AppMusicAppState();
}

class _AppMusicAppState extends State<AppMusicApp> {
  late final AppController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AppController(audioHandler: widget.audioHandler);
    if (widget.startupWarning != null) {
      _controller.reportError(widget.startupWarning!);
    }
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AppMusic',
    debugShowCheckedModeBanner: false,
    theme: _buildTheme(true),
    home: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Theme(
        data: _buildTheme(_controller.isDarkTheme),
        child: _HomeShell(controller: _controller),
      ),
    ),
  );
}

class _HomeShell extends StatefulWidget {
  const _HomeShell({required this.controller});

  final AppController controller;

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(controller: widget.controller),
      LibraryScreen(controller: widget.controller),
      PlaylistsScreen(controller: widget.controller),
      DownloadScreen(controller: widget.controller),
      SettingsScreen(controller: widget.controller),
    ];
    const titles = [
      'Início',
      'Músicas',
      'Playlists',
      'Downloads',
      'Configurações',
    ];

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 62,
        leading: Padding(
          padding: const EdgeInsets.only(left: 14, top: 8, bottom: 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFB69AFF), Color(0xFF7954E8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.graphic_eq_rounded, color: Colors.white),
          ),
        ),
        title: Text(titles[_tabIndex]),
        actions: [
          if (_tabIndex != 4)
            IconButton(
              tooltip: 'Atualizar biblioteca',
              onPressed: widget.controller.refreshLibrary,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: Column(
        children: [
          if (widget.controller.errorMessage != null)
            MaterialBanner(
              content: Text(widget.controller.errorMessage!),
              leading: const Icon(Icons.error_outline_rounded),
              actions: [
                TextButton(
                  onPressed: widget.controller.clearError,
                  child: const Text('Fechar'),
                ),
              ],
            ),
          Expanded(
            child: IndexedStack(index: _tabIndex, children: pages),
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MiniPlayer(controller: widget.controller),
          NavigationBar(
            selectedIndex: _tabIndex,
            onDestinationSelected: (index) => setState(() => _tabIndex = index),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Início',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music_rounded),
                label: 'Músicas',
              ),
              NavigationDestination(
                icon: Icon(Icons.queue_music_outlined),
                selectedIcon: Icon(Icons.queue_music_rounded),
                label: 'Playlists',
              ),
              NavigationDestination(
                icon: Icon(Icons.download_outlined),
                selectedIcon: Icon(Icons.download_rounded),
                label: 'Downloads',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded),
                label: 'Ajustes',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => StreamBuilder<MediaItem?>(
    stream: controller.audioHandler.mediaItem,
    builder: (context, itemSnapshot) {
      final item = itemSnapshot.data;
      if (item == null) return const SizedBox.shrink();
      final id = int.tryParse(item.id);
      AudioTrack? track;
      for (final candidate in controller.tracks) {
        if (candidate.id == id) {
          track = candidate;
          break;
        }
      }
      if (track == null) return const SizedBox.shrink();

      return Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PlayerScreen(controller: controller),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: ArtworkTile(track: track, size: 44),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        item.artist ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Música anterior',
                  onPressed: () => _runAudioAction(
                    controller,
                    controller.audioHandler.skipToPrevious(),
                  ),
                  icon: const Icon(Icons.skip_previous_rounded),
                ),
                StreamBuilder<PlaybackState>(
                  stream: controller.audioHandler.playbackState,
                  builder: (context, stateSnapshot) {
                    final isPlaying = stateSnapshot.data?.playing ?? false;
                    return IconButton(
                      tooltip: isPlaying ? 'Pausar' : 'Reproduzir',
                      onPressed: () => _playPause(controller, isPlaying),
                      icon: Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Próxima música',
                  onPressed: () => _runAudioAction(
                    controller,
                    controller.audioHandler.skipToNext(),
                  ),
                  icon: const Icon(Icons.skip_next_rounded),
                ),
                IconButton(
                  tooltip: 'Abrir reprodutor',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlayerScreen(controller: controller),
                    ),
                  ),
                  icon: const Icon(Icons.open_in_full_rounded),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Future<void> _playPause(AppController controller, bool isPlaying) async {
    await _runAudioAction(
      controller,
      isPlaying
          ? controller.audioHandler.pause()
          : controller.audioHandler.play(),
    );
  }

  Future<void> _runAudioAction(
    AppController controller,
    Future<void> action,
  ) async {
    try {
      await action;
    } catch (error) {
      controller.reportError(error);
    }
  }
}

ThemeData _buildTheme(bool dark) {
  const accent = Color(0xFF9B7BFF);
  final brightness = dark ? Brightness.dark : Brightness.light;
  final colorScheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: brightness,
    surface: dark ? const Color(0xFF17171F) : const Color(0xFFF6F4FA),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: dark
        ? const Color(0xFF0B0B0F)
        : const Color(0xFFF6F4FA),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: dark ? const Color(0xFF17171F) : Colors.white,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colorScheme.surface,
      indicatorColor: accent.withValues(alpha: .18),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
        ),
      ),
    ),
  );
}
