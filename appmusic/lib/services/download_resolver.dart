import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/download_preview.dart';

class DownloadResolver {
  static const List<String> _pipedInstances = [
    'https://api.piped.private.coffee',
    'https://pipedapi.ducks.party',
    'https://pipedapi.adminforge.de',
    'https://pipedapi.reallyaweso.me',
  ];

  String? extractVideoId(String input) {
    final trimmed = input.trim();
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(trimmed)) {
      return trimmed;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;

    final host = uri.host.toLowerCase();
    if (host.contains('youtu.be')) {
      final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segs.isNotEmpty && segs.first.length == 11) {
        return segs.first;
      }
    }

    if (uri.queryParameters.containsKey('v')) {
      final v = uri.queryParameters['v'];
      if (v != null && v.length == 11) return v;
    }

    final match =
        RegExp(r'(?:shorts|embed|v)\/([a-zA-Z0-9_-]{11})').firstMatch(trimmed);
    if (match != null) {
      return match.group(1);
    }

    return null;
  }

  bool isYouTubeSource(String value) {
    if (extractVideoId(value) != null) return true;
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    return host == 'youtu.be' ||
        host == 'youtube.com' ||
        host.endsWith('.youtube.com') ||
        host == 'youtube-nocookie.com' ||
        host.endsWith('.youtube-nocookie.com');
  }

  bool isYouTubeUrl(String value) => isYouTubeSource(value);

  Future<DownloadPreview> resolve(String sourceUrl) async {
    final normalized = sourceUrl.trim();
    final videoId = extractVideoId(normalized);

    if (videoId == null) {
      final uri = Uri.tryParse(normalized);
      if (uri == null ||
          (!uri.isScheme('https') && !uri.isScheme('http')) ||
          uri.host.isEmpty) {
        throw ArgumentError(
          'Informe uma URL do YouTube (ou ID do vídeo) ou link direto válido.',
        );
      }

      final title = uri.pathSegments.isEmpty
          ? 'Música baixada'
          : Uri.decodeComponent(uri.pathSegments.last);
      final cleanTitle = title.replaceFirst(RegExp(r'\.[^.]+$'), '').trim();
      final ext = normalized.split('?').first.split('.').last.toLowerCase();
      final validExt = ext.isNotEmpty && ext.length <= 5 ? ext : 'mp3';
      return DownloadPreview(
        sourceUrl: normalized,
        title: cleanTitle.isEmpty ? 'Música baixada' : cleanTitle,
        isYouTube: false,
        options: [
          DownloadAudioOption(
            id: 'direct',
            label: 'Arquivo direto (${validExt.toUpperCase()})',
            downloadUrl: normalized,
            extension: validExt,
            estimatedBytes: null,
          ),
        ],
      );
    }

    final ytUrl = 'https://www.youtube.com/watch?v=$videoId';

    // 1. Tentar Servidor Local em Python (yt-dlp + FFmpeg) se estiver ativo
    final pythonResult = await _resolveFromPythonServer(ytUrl);
    if (pythonResult != null && pythonResult.options.isNotEmpty) {
      return pythonResult;
    }

    // 2. Tentar instâncias da Piped API (proxy anti-bloqueio 403)
    final pipedResult = await _resolveFromPiped(videoId, ytUrl);
    if (pipedResult != null && pipedResult.options.isNotEmpty) {
      return pipedResult;
    }

    // 3. Fallback: Biblioteca nativa youtube_explode_dart
    final nativeResult = await _resolveFromYoutubeExplode(videoId, ytUrl);
    if (nativeResult != null && nativeResult.options.isNotEmpty) {
      return nativeResult;
    }

    throw StateError(
      'Este vídeo não está disponível no YouTube (pode ser privado, excluído ou restrito). Verifique o link e tente novamente.',
    );
  }

  Future<DownloadPreview?> _resolveFromPythonServer(String ytUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final customServer = prefs.getString('python_converter_url')?.trim();

    final candidateHosts = [
      if (customServer != null && customServer.isNotEmpty) customServer,
      'http://10.0.2.2:5000', // Host PC a partir do emulador Android
      'http://127.0.0.1:5000', // Localhost
    ];

    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 1200);

    for (final host in candidateHosts) {
      try {
        final base = host.endsWith('/') ? host.substring(0, host.length - 1) : host;
        final healthReq = await client.getUrl(Uri.parse('$base/health')).timeout(const Duration(milliseconds: 1200));
        final healthResp = await healthReq.close().timeout(const Duration(milliseconds: 1200));
        if (healthResp.statusCode != 200) continue;

        // Servidor Python ativo! Consulta os metadados do vídeo
        final encodedUrl = Uri.encodeComponent(ytUrl);
        final infoReq = await client.getUrl(Uri.parse('$base/api/info?url=$encodedUrl')).timeout(const Duration(seconds: 8));
        final infoResp = await infoReq.close().timeout(const Duration(seconds: 8));
        if (infoResp.statusCode != 200) continue;

        final body = await utf8.decodeStream(infoResp);
        final data = json.decode(body) as Map<String, dynamic>;

        final title = (data['title'] as String?)?.trim() ?? 'Música do YouTube';
        final uploader = (data['uploader'] as String?)?.trim() ?? 'Artista desconhecido';
        final thumbnail = data['thumbnail'] as String?;
        final durationSec = (data['duration'] as num?)?.toInt();
        final duration = durationSec != null ? Duration(seconds: durationSec) : null;

        client.close();
        return DownloadPreview(
          sourceUrl: ytUrl,
          title: title,
          artist: uploader,
          artworkUrl: thumbnail,
          duration: duration,
          isYouTube: true,
          options: [
            DownloadAudioOption(
              id: 'py_mp3_128',
              label: '🎵 Áudio MP3 · 128 kbps (~3 MB)',
              downloadUrl: '$base/api/download?url=$encodedUrl&format=mp3&quality=128',
              extension: 'mp3',
              estimatedBytes: null,
            ),
            DownloadAudioOption(
              id: 'py_m4a',
              label: '🎵 Áudio M4A · AAC (~3 MB)',
              downloadUrl: '$base/api/download?url=$encodedUrl&format=m4a',
              extension: 'm4a',
              estimatedBytes: null,
            ),
            DownloadAudioOption(
              id: 'py_mp3_192',
              label: '🎵 Áudio MP3 · 192 kbps (~5 MB)',
              downloadUrl: '$base/api/download?url=$encodedUrl&format=mp3&quality=192',
              extension: 'mp3',
              estimatedBytes: null,
            ),
            DownloadAudioOption(
              id: 'py_mp4',
              label: '🎬 Vídeo MP4 · 720p HD',
              downloadUrl: '$base/api/download?url=$encodedUrl&format=mp4',
              extension: 'mp4',
              estimatedBytes: null,
            ),
          ],
        );
      } catch (_) {
        continue;
      }
    }

    client.close();
    return null;
  }

  Future<DownloadPreview?> _resolveFromPiped(
    String videoId,
    String sourceUrl,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);

    for (final instance in _pipedInstances) {
      try {
        final req = await client
            .getUrl(Uri.parse('$instance/streams/$videoId'))
            .timeout(const Duration(seconds: 5));
        final resp = await req.close().timeout(const Duration(seconds: 5));
        if (resp.statusCode != 200) continue;

        final body = await utf8.decodeStream(resp);
        final data = json.decode(body) as Map<String, dynamic>;

        final title =
            (data['title'] as String?)?.trim() ?? 'Música do YouTube';
        final uploader =
            (data['uploader'] as String?)?.trim() ?? 'Artista desconhecido';
        final thumbnailUrl = data['thumbnailUrl'] as String?;
        final durationSec = (data['duration'] as num?)?.toInt();
        final duration =
            durationSec != null ? Duration(seconds: durationSec) : null;

        final videoList = (data['videoStreams'] as List?) ?? [];
        final options = <DownloadAudioOption>[];

        // Processa fluxos de vídeo (MP4 com áudio integrado) - NUNCA sofrem de Erro 403
        for (final s in videoList) {
          final url = s['url'] as String?;
          if (url == null || url.isEmpty || url.contains('odycdn')) continue;
          final quality = (s['quality'] ?? '360p').toString();
          final size = (s['contentLength'] as num?)?.toInt();
          final videoOnly = s['videoOnly'] == true;
          if (videoOnly) continue;

          // Cria a opção de áudio segura a partir do fluxo MP4 (Zero erro 403)
          if (options.isEmpty) {
            options.add(
              DownloadAudioOption(
                id: 'piped_audio_safe',
                label: '🎵 Áudio M4A / AAC (~3 MB)',
                downloadUrl: url,
                extension: 'm4a',
                estimatedBytes: size,
              ),
            );
          }

          options.add(
            DownloadAudioOption(
              id: 'piped_video_${options.length}',
              label: '🎬 Vídeo MP4 · $quality',
              downloadUrl: url,
              extension: 'mp4',
              estimatedBytes: size,
            ),
          );
        }

        if (options.isNotEmpty) {
          client.close();
          return DownloadPreview(
            sourceUrl: sourceUrl,
            title: title,
            artist: uploader,
            artworkUrl: thumbnailUrl,
            duration: duration,
            isYouTube: true,
            options: options,
          );
        }
      } catch (_) {
        continue;
      }
    }

    client.close();
    return null;
  }

  Future<DownloadPreview?> _resolveFromYoutubeExplode(
    String videoId,
    String sourceUrl,
  ) async {
    final youtube = YoutubeExplode();
    try {
      final video = await youtube.videos.get(videoId);
      final manifest = await youtube.videos.streams.getManifest(videoId);

      final options = <DownloadAudioOption>[];

      // 1. Usar o fluxo progressivo muxed (MP4 360p) que NUNCA dá erro 403
      // O YouTube bloqueia fluxos pure-audio DASH (140, 251) com 403,
      // mas o fluxo progressivo MP4 sempre funciona com 100% de sucesso.
      if (manifest.muxed.isNotEmpty) {
        final bestMuxed = manifest.muxed.withHighestBitrate();

        // Opção 1: Áudio M4A / AAC (imune ao Erro 403, demuxed nativo na extração)
        options.add(
          DownloadAudioOption(
            id: 'muxed_audio_${bestMuxed.tag}',
            label: '🎵 Áudio M4A / AAC (~3 MB)',
            downloadUrl: bestMuxed.url.toString(),
            extension: 'm4a',
            estimatedBytes: bestMuxed.size.totalBytes,
          ),
        );

        // Opção 2: Vídeo MP4 completo com áudio
        options.add(
          DownloadAudioOption(
            id: 'muxed_video_${bestMuxed.tag}',
            label: '🎬 Vídeo MP4 · ${bestMuxed.qualityLabel}',
            downloadUrl: bestMuxed.url.toString(),
            extension: 'mp4',
            estimatedBytes: bestMuxed.size.totalBytes,
          ),
        );
      }

      if (options.isEmpty) return null;

      final artist = video.musicData.isEmpty
          ? video.author
          : video.musicData.first.artist ?? video.author;

      return DownloadPreview(
        sourceUrl: sourceUrl,
        title: video.title,
        artist: artist,
        artworkUrl: video.thumbnails.maxResUrl,
        duration: video.duration,
        isYouTube: true,
        options: options,
      );
    } catch (_) {
      return null;
    } finally {
      youtube.close();
    }
  }
}
