import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app.dart';
import 'services/music_audio_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AppMusicBootstrap());
}

class AppMusicBootstrap extends StatefulWidget {
  const AppMusicBootstrap({super.key});

  @override
  State<AppMusicBootstrap> createState() => _AppMusicBootstrapState();
}

class _AppMusicBootstrapState extends State<AppMusicBootstrap> {
  MusicAudioHandler? _handler;
  String? _startupWarning;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeAudioService());
  }

  Future<void> _initializeAudioService() async {
    try {
      final handler = await AudioService.init<MusicAudioHandler>(
        builder: MusicAudioHandler.new,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.example.appmusic.audio',
          androidNotificationChannelName: 'Reprodução de música',
          androidNotificationChannelDescription:
              'Controles de reprodução para a música atual.',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
          androidNotificationClickStartsActivity: true,
        ),
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() => _handler = handler);
      if (Platform.isAndroid) {
        unawaited(
          Permission.notification.request().onError((error, stackTrace) {
            debugPrint('Falha ao solicitar notificação: $error');
            return PermissionStatus.denied;
          }),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Falha ao iniciar o serviço de áudio: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _handler = MusicAudioHandler();
        _startupWarning =
            'O serviço de áudio em segundo plano não iniciou. '
            'A interface continua disponível; reinicie o app se necessário.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final handler = _handler;
    if (handler != null) {
      return AppMusicApp(
        audioHandler: handler,
        startupWarning: _startupWarning,
      );
    }
    return const _StartupScreen();
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0B0B0F),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF9B7BFF),
        brightness: Brightness.dark,
      ),
    ),
    home: Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFB69AFF), Color(0xFF7954E8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF9B7BFF).withValues(alpha: .28),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.graphic_eq_rounded,
                size: 44,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'AppMusic',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.5),
            ),
            const SizedBox(height: 8),
            Text(
              'Preparando sua biblioteca',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: Colors.white60),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    ),
  );
}
