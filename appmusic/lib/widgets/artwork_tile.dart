import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/audio_track.dart';
import '../services/audio_library_service.dart';

class ArtworkTile extends StatefulWidget {
  const ArtworkTile({required this.track, required this.size, super.key});

  final AudioTrack track;
  final double size;

  @override
  State<ArtworkTile> createState() => _ArtworkTileState();
}

class _ArtworkTileState extends State<ArtworkTile> {
  static final Map<int, Uint8List?> _cache = {};
  late Future<Uint8List?> _artwork;

  @override
  void initState() {
    super.initState();
    _loadArtwork();
  }

  @override
  void didUpdateWidget(covariant ArtworkTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) _loadArtwork();
  }

  void _loadArtwork() {
    if (_cache.containsKey(widget.track.id)) {
      _artwork = Future.value(_cache[widget.track.id]);
    } else {
      _artwork = AudioLibraryService().queryArtwork(widget.track.id).then((bytes) {
        _cache[widget.track.id] = bytes;
        return bytes;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(18),
    child: SizedBox.square(
      dimension: widget.size,
      child: FutureBuilder<Uint8List?>(
        future: _artwork,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes != null) {
            return Image.memory(bytes, fit: BoxFit.cover);
          }
          return DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF41325F), Color(0xFF1F1F2C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Icon(
              Icons.music_note_rounded,
              size: widget.size * 0.42,
              color: Colors.white70,
            ),
          );
        },
      ),
    ),
  );
}
